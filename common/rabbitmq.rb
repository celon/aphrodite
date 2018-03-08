module MQUtil
	include LockUtil

	def mq_march_hare?
		@mq_march_hare
	end

	def mq_connect(opt={})
		return @mq_conn unless @mq_conn.nil?
		# Use Bunny, otherwise March-hare
		port = 5672
		port = RABBITMQ_PORT if defined? RABBITMQ_PORT
		if defined? Bunny
			# Logger.warn "Bunny found, use it instead of march_hare." if opt[:march_hare] == true
			@mq_march_hare = false
			mq_conn_int = Bunny.new(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :port => port, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
		else
			Logger.warn "Use march_hare instead of bunny." if opt[:march_hare] == false
			@mq_march_hare = true
			mq_conn_int = MarchHare.connect(:read_timeout => 20, :heartbeat => 20, :hostname => RABBITMQ_HOST, :port => port, :username => RABBITMQ_USER, :password => RABBITMQ_PSWD, :vhost => "/")
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
		content = [content] unless content.is_a? Array
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
		q.subscribe(:manual_ack => true, :block => true) do |a, b, c|
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
					# consumer.cancel seems encounter bug.
					Logger.debug "Cancelling bunny consumer may cost 1 minute"
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
		max_process_ct = options[:max_process_ct] || -1
	
		options[:dao] = 'given' unless dao.nil?
		Logger.info "Connecting to MQ:#{queue}, options:#{options.to_json}" unless silent
	
		@mq_channel.basic_qos(prefetch_num) unless prefetch_num.nil?
		q = mq_createq queue
		err_q = mq_createq "#{queue}_err" unless noerr
		remain_ct = q.message_count
		processedCount = 0
		Logger.debug "Subscribe MQ:#{queue} count:[#{remain_ct}]" unless silent
		return 0 if remain_ct == 0 && exitOnEmpty
		q.subscribe(:manual_ack => true, :block => true) do |a, b, c|
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
				could_save = true
				after_save_lbd = nil
				# Save-flag is same as success by default.
				if success.is_a? Array
					option = success[1] || {}
					success = success[0]
					could_save = (option[:save] != false)
					after_save_lbd = option[:after_save_lbd]
					Logger.debug "Automatically save action is disabled for this tuple." if could_save == false
				else
					could_save = (success != false)
				end
				# Redirect to err queue.
				@mq_channel.default_exchange.publish(body, :routing_key => err_q.name) if success == false && noerr == false
				# Save to DB only if success != FALSE
				if could_save && format == :json && clazz != nil
					begin
						tuple = clazz.new(data)
						dao.save(tuple, allow_dup_entry)
						after_save_lbd.call(tuple) unless after_save_lbd.nil?
					rescue Mysql::ServerError::TruncatedWrongValueForField => e
						success = false
					end
				end
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
			if (processedCount == remain_ct && exitOnEmpty) || (max_process_ct > 0 && max_process_ct <= processedCount)
				if mq_march_hare?
					break
				else
					# consumer.cancel seems encounter bug.
					Logger.debug "Cancelling bunny consumer may cost 1 minute"
					consumer.cancel
				end
			end
		end
		processedCount
	end
end

