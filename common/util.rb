#################################################
# Meta-programming utils placed first.
#################################################
module LockUtil
	def self.included(clazz)
		super
		# add feature DSL 'thread_safe'
		# add instance methods: method_locks, method_lock_get, __get_lock4_(method_name)
		clazz.singleton_class.class_eval do
			define_method(:thread_safe) do |*methods|
				methods.each do |method|
					method = method.to_sym
					# method -> method_without_threadsafe
					old_method_sym = "#{method}_without_threadsafe".to_sym
					alias_method old_method_sym, method
					clazz.class_eval do
						define_method(:method_locks) { instance_variable_get :@method_locks }
						define_method(:method_lock_get) { |m| send("__get_lock4_#{m}".to_sym) }
						# All target methods share one mutex.
						define_method("__get_lock4_#{method}".to_sym) do
							instance_variable_set(:@method_locks, {}) if method_locks.nil?
							return method_locks[method] unless method_locks[method].nil?
							# Init mutex for all methods.
							mutex = Mutex.new
							methods.each { |m| method_locks[m] = mutex }
							mutex
						end
						# Wrap old method with lock.
						define_method(method) do |*args, &block|
							method_lock_get(method).lock
							ret = send old_method_sym, *args, &block
							method_lock_get(method).unlock
							ret
						end
					end
				end
			end
		end
	end
end

#################################################
# Utility modules below
#################################################
module SpiderUtil
	def parse_web(url, encoding = nil, max_ct = -1)
		doc = nil
		ct = 0
		while true
			begin
				newurl = URI.escape url
				if newurl != url
					# Use java version curl
					doc = curl_javaver url
					next if doc == nil
					if encoding.nil?
						doc = Nokogiri::HTML(doc)
					else
						doc = Nokogiri::HTML(doc, nil, encoding)
					end
				else
					if encoding.nil?
						doc = Nokogiri::HTML(open(url))
					else
						doc = Nokogiri::HTML(open(url), nil, encoding)
					end
				end
				return doc
			rescue => e
				Logger.debug "error in parsing web:#{e.message}"
				ct += 1
				raise e if max_ct > 0 && ct >= max_ct
				sleep 1
			end
		end
	end
	
	def download(url, filename, max_ct = -1)
		doc = nil
		ct = 0
		while true
			begin
				open(filename, 'wb') do |file|
					file << open(url).read
				end
				return doc
			rescue => e
				Logger.debug "error in downloading #{url}: #{e.message}"
				ct += 1
				raise e if max_ct > 0 && ct >= max_ct
				sleep 1
			end
		end
	end
	
	def curl_javaver(url)
		jarpath = "#{File.dirname(__FILE__)}/curl.jar"
		tmpFile = "#{Time.now.to_i}_#{rand(10000)}.html"
		cmd = "java -jar #{jarpath} '#{url}' #{tmpFile}"
		ret = system(cmd)
		Logger.debug("#{cmd} --> #{ret}")
		result = ""
		if File.exist?(tmpFile)
			result = File.open(tmpFile, "rb").read
			File.delete(tmpFile)
		else
			result = nil
		end
		return result
	end
end

module CycleWorker
	def cycle_init(opt={})
		@cycle_roundtime = 60
		@cycle_roundtime = opt[:roundtime] unless opt[:roundtime].nil?
		@cycle_roundct = 0
	end

	def cycle_endless(opt={})
		cycle_init if @cycle_roundtime.nil?
		verbose = opt[:verbose]
		while true
			@cycle_roundct += 1
			Logger.debug "CycleWorker round##{@cycle_roundct} start." if verbose
			start_t = Time.now
			cycle_work
			end_t = Time.now
			Logger.debug "CycleWorker round##{@cycle_roundct} finished." if verbose
			sleep_time = @cycle_roundtime - (end_t - start_t)
			sleep sleep_time if sleep_time > 0
		end
	end

	def cycle_work; end
end
	
module EncodeUtil
	def encode64(data)
		data.nil? ? Base64.encode64("") : Base64.encode64(data)
	end

	def decode64(data)
		return nil if data.nil? || data.empty?
		Base64.decode64(data).force_encoding("UTF-8")
	end

	def hash_str(data)
		data.nil? ? Digest::MD5.hexdigest("") : Digest::MD5.hexdigest(data)
	end

	def md5(data)
		data.nil? ? Digest::MD5.hexdigest("") : Digest::MD5.hexdigest(data)
	end

	def snake2Camel(snake, capFirst = false)
		camel = nil
		snake.split('_').each do |w|
			if camel.nil?
				camel = w.capitalize if capFirst
				camel = w if !capFirst
			else
				camel << w.capitalize
			end
		end
		camel
	end

	def camel2Snake(camel)
		camel.gsub(/::/, '/').
		gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
		gsub(/([a-z\d])([A-Z])/,'\1_\2').
		tr("-", "_").
		downcase
	end
end

module CacheUtil
	def redis
		@redis ||= Redis.new :host => REDIS_HOST, port:REDIS_PORT, db:REDIS_DB, password:REDIS_PSWD
	end

	def clear_redis_by_table(table)
		cmd = "local keys = redis.call('keys', ARGV[1]) for i=1,#keys,5000 do redis.call('del', unpack(keys, i, math.min(i+4999, #keys))) end return keys";
		@redis.eval(cmd, [], ["SQL_BUFFER:#{table}:*"])
	end
end

module MQUtil
	include LockUtil

	def mq_march_hare?
		@mq_march_hare
	end

	def mq_connect(opt={})
		return @mq_conn unless @mq_conn.nil?
		# Use Bunny, otherwise March-hare
		if defined? Bunny
			Logger.warn "Bunny found, use it instead of march_hare." if opt[:march_hare] == true
			@mq_march_hare = false
			mq_conn_int = Bunny.new(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
		else
			Logger.warn "Use march_hare instead of bunny." if opt[:march_hare] == false
			@mq_march_hare = true
			mq_conn_int = MarchHare.connect(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
		end
		@mysql2_enabled = opt[:mysql2] == true
		mq_conn_int.start
		@mq_qlist = {}
		@mq_channel = mq_conn_int.create_channel
		@mq_conn = mq_conn_int
	end

	def mq_close
		@mq_channel.close
		@mq_conn.close
		@mq_conn = nil
	end
	thread_safe :mq_connect, :mq_close

	def mq_createq(route_key)
		mq_connect
		q = @mq_channel.queue(route_key, :durable => true)
		@mq_qlist[route_key] = true
		q
	end

	def mq_exists?(queue)
		return true if mq_march_hare?
		mq_connect
		@mq_conn.queue_exists? queue
	end

	def mq_push(route_key, content, opt={})
		mq_connect
		verbose = opt[:verbose]
		mq_createq route_key if @mq_qlist[route_key].nil?
		content = [*content]
		content.each do |piece|
			next if piece.nil?
			payload = piece
			payload = payload.to_json unless payload.is_a? String
			@mq_channel.default_exchange.publish payload, routing_key:route_key
			Logger.debug "MQUtil: msg #{payload}" if verbose
		end
		Logger.debug "MQUtil: pushed #{content.size} msg to mq[#{route_key}]" if verbose
	end
	thread_safe :mq_createq, :mq_exists?, :mq_push

	def mq_consume(queue, options={})
		mq_connect
		if options[:thread]
			options[:thread] = false
			return Thread.new do
				mq_consume(queue, options) do |o, dao|
					if block_given?
						yield o, dao
					end
				end
			end
		end
		tableName = options[:table]
		dao = DynamicMysqlDao.new mysql2_enabled: @mysql2_enabled
		clazz = nil
		clazz = dao.getClass tableName unless tableName.nil?
		debug = options[:debug] == true
		show_full_body = options[:show_full_body] == true
		silent = options[:silent] == true
		noack_on_err = options[:noack_on_err] == true
		noerr = options[:noerr] == true
		prefetch_num = options[:prefetch_num]
		allow_dup_entry = options[:allow_dup_entry] == true
		exitOnEmpty = options[:exitOnEmpty] == true
		mqc_name = (options[:header] || '')
	
		Logger.info "Connecting to MQ:#{queue}, options:#{options.to_json}"
	
		unless mq_exists? queue
			Logger.highlight "MQ[#{queue}] not exist, abort."
			return -1
		end
		@mq_channel.basic_qos(prefetch_num) unless prefetch_num.nil?
		q = mq_createq queue
		err_q = mq_createq "#{queue}_err"
		remain_ct = q.message_count
		processedCount = 0
		Logger.debug "Subscribe MQ:#{queue} count:[#{remain_ct}]"
		return 0 if remain_ct == 0 and exitOnEmpty
		consumer = q.subscribe(:manual_ack => true, :block => true) do |a, b, c|
			# Compatibility variables for both march_hare and bunny.
			delivery_tag, consumer, body = nil, nil, nil
			if mq_march_hare?
				metadata, body = a, b
				delivery_tag = metadata.delivery_tag
			else
				delivery_info, properties, body = a, b, c
				delivery_tag = delivery_info.delivery_tag
				consumer = delivery_info.consumer
			end
			processedCount += 1
			success = true
			begin
				Logger.info "#{mqc_name}[#{q.name}:#{processedCount}/#{remain_ct}]: #{show_full_body ? body : body[0..40]}" unless silent
				json = JSON.parse body
				# Process json in yield, save if needed.
				success = yield(json, dao) if block_given?
				# Redirect to err queue.
				@mq_channel.default_exchange.publish(body, :routing_key => err_q.name) if success == false && noerr == false
				# Save to DB only if success != FALSE
				dao.saveObj(clazz.new(json), allow_dup_entry) if success != false && clazz != nil
				# Debug only onetime.
				exit! if debug
				# Send ACK.
				if success == false && noack_on_err
					Logger.debug "noack_on_err is ON, this msg will not ACK."
				else
					@mq_channel.ack delivery_tag
				end
			rescue => e
				Logger.highlight "--> [#{q.name}]: #{body}"
				Logger.error e
				# Redirect to err queue only if exception occurred.
				@mq_channel.default_exchange.publish(body, :routing_key => err_q.name)
				exit!
			end
			if processedCount == remain_ct and exitOnEmpty
				if mq_march_hare?
					break
				else
					consumer.cancel
				end
			end
		end
		begin
			Logger.debug "Closing connection."
			dao.close
		rescue
		end
		processedCount
	end
end
