# A genernic greedy connection pool
#
# It always try to keep available connections for instant usage.
# Used connections would be recycled/closed.
# Broken connection would be discarded.
#
# pool = GreedyConnectionPool.new(10, opt) {
# 				HTTP.persistent(HOST)
# }
# pool.with { |http| http.get/put/post }
class GreedyConnectionPool
	def initialize(keep_avail_size, opt={}, &block)
		@_debug = opt[:debug] == true
		@_http_startup_block = block
		@_avail_conn = Concurrent::Array.new
		@_occupied_conn = Concurrent::Array.new
		@_keep_avail_size = keep_avail_size
		@_keep_avail_size.times { @_avail_conn.push(create_conn()) }
		@_maintain_thread = Thread.new { maintain() }
		@_maintain_thread.priority = -99
	end

	def create_conn
		@_http_startup_block.call
	end

	def with(&block)
		return if block.nil?
		conn = @_avail_conn.delete_at(0) || create_conn()

		@_occupied_conn.push(conn)
		t = Time.now if @_debug

		block.call(conn)

		t = (Time.now - t)*1000 if @_debug
		@_occupied_conn.delete(conn)
		@_avail_conn.push(conn)
		puts [t.round(4).to_s.ljust(8), 'ms', status] if @_debug
	end

	def maintain
		loop {
			begin
				sleep 0.1
				size = @_avail_conn.size
				next if size >= @_keep_avail_size
				(@_keep_avail_size-size).times {
					@_avail_conn.push(create_conn())
				}
			rescue => e
				APD::Logger.error e
			end
		}
	end

	def status
		{
			:avail => @_avail_conn.size,
			:total => (@_occupied_conn.size + @_avail_conn.size)
		}
	end
end
