# Example: TimeSeriesBucket.new(10, 6) -> maintain latest 6 buckets for each 10ms
class TimeSeriesBucket
	def initialize(time_unit_ms, units)
		@time_unit_ms = time_unit_ms.to_i
		@bucket_num = units
		# Initializing buckets with bucket_num empty ones.
		@buckets = units.times.map { [] }
		@latest_bucket_id = 0
		@latest_bucket = @buckets[@bucket_num-1]
	end

	def append(t, data) # t in ms
		id = t.to_i / @time_unit_ms
		# puts ['incoming', t] # Debug
		# Put into current bucket
		return(@latest_bucket.push(data)) if id == @latest_bucket_id
		# Fill gap between latest_bucket_id and id
		@buckets += [id-@latest_bucket_id, @bucket_num].min.times.map { [] }
		# Remove old buckets, keep buckets number = @bucket_num
		@buckets.slice!(0, @buckets.size-@bucket_num) # See which is faster
		# @buckets = @buckets[-@bucket_num..-1]
		# Put into latest bucket
		@latest_bucket = @buckets[@bucket_num-1]
		@latest_bucket.push data
		@latest_bucket_id = id # Update latest_bucket_id
	end

	def all_data
		@buckets.reduce(:+)
	end

	def print # Debug
		@buckets.reverse.each_with_index do |bkt, i|
			puts "Bucket ID #{@latest_bucket_id - i}"
			bkt.each { |data| puts "\t\t\tdata: #{data}" }
		end
	end
end
