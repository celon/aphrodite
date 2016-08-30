class ZMQAdapter
	include APD::LockUtil
	
	def initialize(method)
		@zmq_connect_method = method
	end

	def zmq_adapter
		return @zmq_adapter unless @zmq_adapter.nil?
		raise "zmq:connect_method not set" if @zmq_connect_method.nil?
		@zmq_adapter = @zmq_connect_method.call
	end

	def zmq_send(data)
		loop do
			rc = zmq_adapter.send_string data
			if rc < 0 # Connection lost
				Logger.warn "rc:#{rc} ZMQ connection lost, re-try..."
				@zmq_adapter = nil
				sleep 1
			else
				return rc
			end
		end
	end

	def zmq_recv
		reply = ''
		loop do
			rc = zmq_adapter.recv_string(reply)
			if rc < 0 # Connection lost
				Logger.warn "rc:#{rc} ZMQ connection lost, re-try..."
				@zmq_adapter = nil
				sleep 1
			else
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

	thread_safe :zmq_send, :zmq_recv, :zmq_send_recv
end
