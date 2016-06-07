#################################################
# Meta-programming utils placed first.
#################################################
module LockUtil
	def self.included(clazz)
		super
		# add instance methods: method_locks, method_lock_get
		clazz.class_eval do
			define_method(:method_locks) { instance_variable_get :@method_locks }
			define_method(:method_lock_get) { |m| send("__get_lock4_#{m}".to_sym) }
		end
		# add feature DSL 'thread_safe'
		clazz.singleton_class.class_eval do
			define_method(:thread_safe) do |*methods|
				methods.each do |method|
					method = method.to_sym
					# method -> method_without_threadsafe
					old_method_sym = "#{method}_without_threadsafe".to_sym
					if clazz.method_defined? old_method_sym
# 					puts "#{clazz}: #{old_method_sym} alread exists, skip wrap".red
					else
						alias_method old_method_sym, method
# 					puts "#{clazz}: #{method} -> #{method}_without_threadsafe".red
					end
					clazz.class_eval do
						# add instance methods: __get_lock4_(method_name)
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
							ret = nil
# 							puts "#{clazz}\##{self.object_id} call thread_safe method #{method}".red
							method_lock_get(method).synchronize do
# 								puts "#{clazz}\##{self.object_id} call internal method #{old_method_sym}".blue
								ret = send old_method_sym, *args, &block
							end
# 							puts "#{clazz}\##{self.object_id} end thread_safe method #{method}".green
							ret
						end
					end
				end
			end
		end
	end
end

module CacheUtil
	def cache_client
		redis
	end

	# Should add a redis_db function here.
	def redis
		@@redis ||= Redis.new :host => REDIS_HOST, port:REDIS_PORT, db:redis_db, password:REDIS_PSWD, timeout:20.0, connect_timeout:20.0, reconnect_attempts:10
	end

	def clear_redis_by_prefix(prefix)
		return if prefix.nil?
		cmd = "local keys = redis.call('keys', ARGV[1]) for i=1,#keys,5000 do redis.call('del', unpack(keys, i, math.min(i+4999, #keys))) end return keys";
		Logger.debug "Clearing redis by prefix:[#{prefix}]"
		redis.eval(cmd, [], ["#{prefix}*"])
	end

	def clear_redis_by_table(table)
		clear_redis_by_prefix "SQL_BUFFER:#{table}:"
	end

	def clear_redis_by_path(prefix)
		cmd = "local keys = redis.call('keys', ARGV[1]) for i=1,#keys,5000 do redis.call('del', unpack(keys, i, math.min(i+4999, #keys))) end return keys";
		redis.eval(cmd, [], ["#{prefix}:*"])
	end
end

module Cacheable
	include CacheUtil

	def self.included(clazz)
		super
		# add feature DSL 'cache_by'
		clazz.singleton_class.class_eval do
			define_method(:cache_by) do |*args|
				raise "cache_by need a basename and a key array." if args.size <= 1
				raise "cache_by need a basename and a key array." unless args[1].is_a?(Array)
				opt = args[2] || {}
				type_sorted_set = opt[:type] == :sorted_set
				value_method = opt[:value] || :to_json
				# Find an avaiable method name slot.
				cache_method_key,	cache_method, decache_method = '@__cacheable_key', '__cacheable_cache', '__cacheable_decache'
				index = 0
				while true
					break unless clazz.method_defined?("#{cache_method}_#{index}".to_sym)
					index += 1
				end
				# Define method (de)cacheable_cache_method_#NUM
				target_cache_method_sym = "#{cache_method}_#{index}".to_sym
				target_decache_method_sym = "#{decache_method}_#{index}".to_sym
				clazz.class_eval do
					define_method(target_cache_method_sym) do
						# Compute K and V.
						cache_key = args[0].to_s
						keys = args[1]
						middle_keys, score = keys, 0
						if type_sorted_set
							# Last key is score of sorted set.
							last_key, middle_keys = keys[-1], keys[0..-2]
							score = send(last_key).to_i
						end
						middle_keys.each { |k| cache_key = "#{cache_key}:#{send(k).to_s}" }
						# Remove old data if key changed.
						old_kv = instance_variable_get "#{cache_method_key}_#{index}".to_sym
						if old_kv != nil && old_kv[0] != cache_key
							if type_sorted_set
								cache_client.zrem old_kv[0], old_kv[1]
							else
								cache_client.del old_kv[0]
							end
						end
						value = send value_method
						instance_variable_set "#{cache_method_key}_#{index}".to_sym, [cache_key, value]
						# Put data.
						if type_sorted_set
							cache_client.zadd cache_key, score, value
						else
							cache_client.set cache_key, value
						end
					end
					define_method(target_decache_method_sym) do
						# ZREM old data.
						old_kv = instance_variable_get "#{cache_method_key}_#{index}".to_sym
						if old_kv != nil
							if type_sorted_set
								cache_client.zrem old_kv[0], old_kv[1]
							else
								cache_client.del old_kv[0]
							end
						end
					end
					define_method(:cache) do
						index = 0
						# Combine all cache methods.
						while true
							method_sym = "#{cache_method}_#{index}".to_sym
							break unless clazz.method_defined?(method_sym)
							send method_sym
							index += 1
						end
					end
					define_method(:decache) do
						index = 0
						# Combine all decache methods.
						while true
							method_sym = "#{decache_method}_#{index}".to_sym
							break unless clazz.method_defined?(method_sym)
							send method_sym
							index += 1
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
module EncodeUtil
	def encode64(data)
		Base64.encode64(data.nil? ? '':data).strip.gsub("\n", '')
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

	def to_camel(snake, capFirst = false)
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

	def to_snake(camel)
		camel.gsub(/::/, '/').
		gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
		gsub(/([a-z\d])([A-Z])/,'\1_\2').
		tr("-", "_").
		downcase
	end
end

module SleepUtil
	def graphic_sleep(time)
		maxSleepCount = time
		sleepCount = 0
		statusBarLength = 70
		step = 1
		step = 0.1 if time < 60
		while sleepCount < maxSleepCount
			elapsedLength = statusBarLength * sleepCount / maxSleepCount
			remainedLength = statusBarLength - elapsedLength
			statusStr = "|#{'=' * elapsedLength}>#{'.' * remainedLength}"
			print "\rSleep #{(maxSleepCount - sleepCount).to_i.to_s.ljust(10)}#{statusStr}"
			sleep step
			sleepCount += step
		end
		print "\r#{' '.ljust('Sleep '.length + 10 + statusBarLength + 2)}\r"
	end
end

module SpiderUtil
	include EncodeUtil

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
				Logger.debug "error in parsing [#{url}]:\n#{e.message}"
				ct += 1
				raise e if max_ct > 0 && ct >= max_ct
				sleep 1
			end
		end
	end
	
	def curl_native(url, opt={})
		filename = opt[:file]
		max_ct = opt[:retry] || -1
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

	def curl(url, opt={})
		file = opt[:file]
		agent = opt[:agent]
		tmp_file_use = false
		if file.nil?
			file = "curl_#{hash_str(url)}.html"
			tmp_file_use = true
		end
		cmd = "curl --silent --output '#{file}'"
		cmd += " -A '#{agent}'" unless agent.nil?
		cmd += " --retry #{opt[:retry]}" unless opt[:retry].nil?
		cmd += " --max-time #{opt[:max_time]}" unless opt[:max_time].nil?
		cmd += " '#{url}'"
		ret = system(cmd)
		Logger.debug("#{cmd} --> #{ret}") if opt[:verbose] == true
		if File.exist?(file)
			result = File.open(file, "rb").read
			File.delete(file) if tmp_file_use
		else
			result = nil
		end
		result
	end
	
	def curl_javaver(url, opt={})
		file = opt[:file]
		tmp_file_use = false
		if file.nil?
			file = "curl_#{hash_str(url)}.html"
			tmp_file_use = true
		end
		jarpath = "#{APD_COMMON_PATH}/res/curl.jar"
		cmd = "java -jar #{jarpath} '#{url}' #{file}"
		ret = system(cmd)
		Logger.debug("#{cmd} --> #{ret}")
		result = ""
		if File.exist?(file)
			result = File.open(file, "rb").read
			File.delete(file) if tmp_file_use
		else
			result = nil
		end
		result
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

module LZString
	def lz_context
		@lz_context ||= ExecJS.compile(File.read("#{APD_COMMON_PATH}/../res/lz-string.min.js"))
	end

	def lz_compressToBase64(string)
		lz_context.call("LZString.compressToBase64", string)
	end

	def lz_decompressFromBase64(string)
		lz_context.call("LZString.decompressFromBase64", string)
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
	thread_safe :mq_createq

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
	thread_safe :mq_exists?, :mq_push

	def mq_redirect(from_queue, to_queue)
		unless mq_exists? from_queue
			Logger.highlight "MQ[#{from_queue}] not exist, abort."
			return -1
		end
		q = mq_createq from_queue
		q2 = mq_createq to_queue
		remain_ct = q.message_count
		processedCount = 0
		Logger.debug "Subscribe MQ:#{from_queue} count:[#{remain_ct}]"
		return 0 if remain_ct == 0
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
				Logger.info "MQ Redirect: #{q.name} -> #{q2.name}: #{processedCount}/#{remain_ct}"
				data = body
				# Redirect to other queue.
				@mq_channel.default_exchange.publish(body, :routing_key => q2.name)
				# Send ACK.
				@mq_channel.ack delivery_tag
			rescue => e
				Logger.highlight "--> [#{q.name}]: #{body}"
				Logger.error e
				exit!
			end
			if processedCount == remain_ct
				if mq_march_hare?
					break
				else
					consumer.cancel
				end
			end
		end
		processedCount
	end

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
		db_table = options[:table]
		dao = options[:dao]
		clazz = nil
		if db_table != nil
			raise 'mq_consume: dao must provided along to db_table.' if dao.nil?
			clazz = dao.get_class db_table unless db_table.nil?
		end
		debug = options[:debug] == true
		show_full_body = options[:show_full_body] == true
		silent = options[:silent] == true
		noack_on_err = options[:noack_on_err] == true
		noerr = options[:noerr] == true
		format = options[:format]
		prefetch_num = options[:prefetch_num]
		allow_dup_entry = options[:allow_dup_entry] == true
		exitOnEmpty = options[:exitOnEmpty] == true
		mqc_name = (options[:header] || '')
	
		options[:dao] = 'given' unless dao.nil?
		Logger.info "Connecting to MQ:#{queue}, options:#{options.to_json}"
	
		unless mq_exists? queue
			Logger.highlight "MQ[#{queue}] not exist, abort."
			return -1
		end
		@mq_channel.basic_qos(prefetch_num) unless prefetch_num.nil?
		q = mq_createq queue
		err_q = mq_createq "#{queue}_err" unless noerr
		remain_ct = q.message_count
		processedCount = 0
		Logger.debug "Subscribe MQ:#{queue} count:[#{remain_ct}]"
		return 0 if remain_ct == 0 && exitOnEmpty
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
				Logger.info "MQC: #{mqc_name}[#{q.name}:#{processedCount}/#{remain_ct}]: #{show_full_body ? body : body[0..40]}" unless silent
				data = nil
				format = :json if format.nil?
				if format == :json
					data = JSON.parse body
				elsif format == :raw
					data = body
				else
					raise "Unknown format: #{format}"
				end
				# Process json in yield, save if needed.
				success = yield(data, dao) if block_given?
				# Redirect to err queue.
				@mq_channel.default_exchange.publish(body, :routing_key => err_q.name) if success == false && noerr == false
				# Save to DB only if success != FALSE
				dao.save(clazz.new(data), allow_dup_entry) if format == :json && success != false && clazz != nil
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
				@mq_channel.default_exchange.publish(body, :routing_key => err_q.name) unless noerr
				exit!
			end
			if processedCount == remain_ct && exitOnEmpty
				if mq_march_hare?
					break
				else
					consumer.cancel
				end
			end
		end
		processedCount
	end
end
