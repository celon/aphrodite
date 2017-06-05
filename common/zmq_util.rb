class ZMQAdapter
	include APD::LockUtil
	
	def initialize(conn_method, *args)
		if conn_method.nil?
			raise "No conn_method for ZMQAdapter"
		elsif conn_method.is_a? Symbol
			conn_method = method(conn_method)
		end
		@zmq_connect_method = conn_method
		@zmq_connect_method_args = args
	end

	def zmq_req_connector(addr, opt={})
		context = ZMQ::Context.new(1)
		puts "ZMQ Req connecting to server #{addr} ..." if opt[:debug] == true
		requester = context.socket(ZMQ::REQ)
		requester.connect addr
		requester
	end

	def setsockopt(*args)
		zmq_adapter.setsockopt(*args)
	end

	def zmq_adapter
		return @zmq_adapter unless @zmq_adapter.nil?
		raise "zmq:connect_method not set" if @zmq_connect_method.nil?
		@zmq_adapter = @zmq_connect_method.call(*@zmq_connect_method_args)
	end

	def zmq_close
		zmq_adapter.close
		@zmq_adapter = nil
	end

	def zmq_reconnect
		zmq_close
		zmq_adapter
	end

	def start_cli
		zmq_recv try:true, print:true
		loop do
			print "\nZMQ cli> "
			req = STDIN.gets
			if req.nil?
				puts "Goodbye"
				return
			end
			req.strip!
			zmq_send req, verbose:true
			zmq_recv try:true, print:true
		end
	end

	def zmq_send(data, opt={})
		loop do
			rc = zmq_adapter.send_string data
			if rc < 0 # Connection lost
				Logger.warn "rc:#{rc} ZMQ connection lost, re-try..."
				@zmq_adapter = nil
				sleep 1
			else
				puts "--> #{data.size} bytes sent" if opt[:verbose] == true
				return rc
			end
		end
	end

	def zmq_recv(opt={})
		reply = ''
		loop do
			rc = zmq_adapter.recv_string(reply)
			if rc < 0 # Connection lost
				return nil if opt[:try] == true
				Logger.warn "rc:#{rc} ZMQ connection lost, re-try..."
				@zmq_adapter = nil
				sleep 1
			else
				puts "<-- #{reply}" if opt[:print] == true
				return reply
			end
		end
	end

	def zmq_send_recv(data, opt={})
		# Defaulty retry on error.
		retry_on_error = (opt[:retry] == true)

		reply = ''
		loop do
# 			if data.size < 100
# 				Logger.debug "--> #{data}"
# 			else
# 				Logger.debug "--> #{data.size} bytes"
# 			end
			rc = zmq_adapter.send_string data
			if rc < 0 # Connection lost
				raise "ZMQ send rc:#{rc}" unless retry_on_error
				Logger.warn "rc:#{rc} Connection lost, retry..."
				@zmq_adapter = nil
				sleep 1
				next
			end
			rc = zmq_adapter.recv_string(reply)
# 			if reply.size < 100
# 				Logger.debug "<-- #{reply}"
# 			else
# 				Logger.debug "<-- #{reply.size} bytes"
# 			end
			if rc < 0 # Connection lost
				raise "ZMQ recv rc:#{rc}" unless retry_on_error
				Logger.warn "rc:#{rc} Connection lost, retry..."
				@zmq_adapter = nil
				sleep 1
				next
			else
				return reply
			end
		end
	end

	thread_safe :zmq_send, :zmq_recv, :zmq_send_recv, :zmq_close
end

class ZMQBroker
	def initialize(frontend_addr, backend_addr)
		@zmq_server_addr = frontend_addr
		@zmq_server_dealer_addr = backend_addr
		worker_port = backend_addr[-7..-1].split(":")[1]
		@zmq_server_worker_addr = "tcp://localhost:#{worker_port}"
		@zmq_context = ZMQ::Context.new
	end

	def add_workers(num, work_method)
		threads = []
		num.times do |i|
			t = Thread.new do
				Logger.info "ZMQBroker[#{@zmq_server_addr}] starts a worker: #{work_method.owner}:#{work_method.name} at #{@zmq_server_worker_addr}"
				socket = @zmq_context.socket(ZMQ::REP)
				socket.connect @zmq_server_worker_addr
				loop do
					msg = ''
					socket.recv_string msg
					reply = work_method.call(msg, socket)
					socket.send_string(reply.to_s) unless reply.nil?
				end
			end
			threads.push t
		end
		threads
	end

	def start
		frontend = @zmq_context.socket(ZMQ::ROUTER)
		backend = @zmq_context.socket(ZMQ::DEALER)

		frontend.bind @zmq_server_addr
		backend.bind @zmq_server_dealer_addr

		poller = ZMQ::Poller.new
		poller.register(frontend, ZMQ::POLLIN)
		poller.register(backend, ZMQ::POLLIN)

		Logger.info "ZMQBroker[#{@zmq_server_addr}][#{@zmq_server_dealer_addr}] start"
		loop do
			poller.poll(:blocking)
			poller.readables.each do |socket|
				if socket === frontend
					socket.recv_strings(messages = [])
					backend.send_strings(messages)
				elsif socket === backend
					socket.recv_strings(messages = [])
					frontend.send_strings(messages)
				end
			end
		end
	end
end
