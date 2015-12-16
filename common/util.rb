module SpiderUtil
	def parseWebWithRetry(url, encoding = nil)
		doc = nil
		while true
			begin
				newurl = URI.escape(url)
				if newurl != url
					# Use java version curl
					doc = curlJAVA(url)
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
				break
			rescue SystemExit, Interrupt
				puts "SignalException caught, exit!"
				exit!
			rescue Exception => e
				puts "parseWebWithRetry:#{e.message}"
			end
		end
		return doc
	end
	
	def downloadWithRetry(url, filename)
		doc = nil
		while true
			begin
				open(filename, 'wb') do |file|
					LOGGER.debug(url)
					file << open(url).read
				end
				break
			rescue Exception => e
				puts e.message
				sleep 1
			end
		end
		return doc
	end
	
	def curlJAVA(url)
		jarpath = "#{File.dirname(__FILE__)}/curl.jar"
		tmpFile = "#{Time.now.to_i}_#{rand(10000)}.html"
		cmd = "java -jar #{jarpath} '#{url}' #{tmpFile}"
		ret = system(cmd)
		LOGGER.debug("#{cmd} --> #{ret}")
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
			LOGGER.debug "CycleWorker round##{@cycle_roundct} start." if verbose
			start_t = Time.now
			cycle_work
			end_t = Time.now
			LOGGER.debug "CycleWorker round##{@cycle_roundct} finished." if verbose
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
	def mq_connect(opt={})
		@mq_conn = Bunny.new(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
		@mq_conn.start
		@mq_qlist = {}
		@mq_channel = @mq_conn.create_channel
	end

	def mq_createq(route_key)
		@mq_channel ||= mq_connect
		@mq_channel.queue(route_key, :durable => true)
		@mq_qlist[route_key] = true
	end

	def mq_push(route_key, content, opt={})
		@mq_channel ||= mq_connect
		verbose = opt[:verbose]
		mq_createq route_key if @mq_qlist[route_key].nil?
		content = [*content]
		content.each do |piece|
			@mq_channel.default_exchange.publish piece.to_json, routing_key:route_key
			LOGGER.debug "MQUtil: msg #{piece.to_json}" if verbose
		end
		LOGGER.debug "MQUtil: pushed #{content.size} msg to mq[#{route_key}]" if verbose
	end

	def mq_consume(queue, options={})
		@mq_channel ||= mq_connect
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
		dao = DynamicMysqlDao.new
		clazz = nil
		clazz = dao.getClass tableName unless tableName.nil?
		debug = options[:debug] == true
		show_full_body = options[:show_full_body] == true
		silent = options[:silent] == true
		noack_on_err = options[:noack_on_err] == true
		noerr = options[:noerr] == true
		exitOnEmpty = options[:exitOnEmpty] == true
	
		LOGGER.info "Connecting to MQ:#{queue}, options:#{options.to_json}"
	
		conn = Bunny.new(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
		conn.start
		if conn.queue_exists?(queue) == false
			LOGGER.highlight "MQ[#{queue}] not exist, abort."
			return -1
		end
		ch = conn.create_channel
		q = ch.queue(queue, :durable => true)
		err_q = ch.queue("#{queue}_err", :durable => true)
		totalCount = q.message_count
		processedCount = 0
		LOGGER.debug "Subscribe MQ:#{queue} count:[#{totalCount}]"
		return 0 if totalCount == 0 and exitOnEmpty
		q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
			processedCount += 1
			success = true
			begin
				LOGGER.info "[#{q.name}:#{processedCount}/#{totalCount}]: #{show_full_body ? body : body[0..60]}" unless silent
				json = JSON.parse body
				# Process json in yield, save if needed.
				success = yield(json, dao) if block_given?
				# Redirect to err queue.
				ch.default_exchange.publish(body, :routing_key => err_q.name) if success == false && noerr == false
				# Save to DB only if success != FALSE
				clazz.new(json).save if success != false && clazz != nil
				# Debug only onetime.
				exit! if debug
				# Send ACK.
				if success == false && noack_on_err
					LOGGER.debug "noack_on_err is ON, this msg will not ACK."
				else
					ch.ack(delivery_info.delivery_tag)
				end
			rescue => e
				LOGGER.highlight "--> [#{q.name}]: #{body}"
				LOGGER.error e
				# Redirect to err queue only if exception occurred.
				ch.default_exchange.publish(body, :routing_key => err_q.name)
				exit!
			end
			delivery_info.consumer.cancel if processedCount == totalCount and exitOnEmpty
		end
		begin
			LOGGER.debug "Closing connection."
			clazz.mysql_dao.close unless tableName.nil?
			conn.close
		rescue
		end
		processedCount
	end
end
