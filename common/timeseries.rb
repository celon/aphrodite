# Example: TimeSeriesBucket.new(10, 6) -> maintain latest 6 buckets for each 10ms
class TimeSeriesBucket
	def initialize(time_unit_ms, units)
		@time_unit_ms = time_unit_ms.to_i
		raise "time_unit_ms #{time_unit_ms} is 0" if @time_unit_ms == 0
		@bucket_num = units
		# Initializing buckets with bucket_num empty ones.
		@buckets = units.times.map { [] }
		@latest_bucket_id = 0
		@latest_bucket = @buckets[@bucket_num-1]
		@useless_bucket = []
	end

	def shift
		@buckets[0].shift
	end

	# Regroup buckets.
	# Append data into last bucket.
	def append(t, data) # t in ms
		id = t.to_i / @time_unit_ms
		# puts ['incoming', t] # Debug
		# Put into current bucket
		if id == @latest_bucket_id
			return if data.nil?
			return(@latest_bucket.push(data))
		end
		# Fill gap between latest_bucket_id and id
		gap = [id-@latest_bucket_id, @bucket_num].min

		# Method 1, no shift() needed
		# push(): 19-20K, is faster than +=, and N.times {}
		if gap == 1
			@buckets.push(@buckets.shift.clear)
		elsif gap == 2
			@buckets.push(@buckets.shift.clear)
			@buckets.push(@buckets.shift.clear)
		else
			gap.times { @buckets.push(@buckets.shift.clear) }
		end
		
		# Method 2, no shift() needed
# 		gap.times {
# 			@buckets.push(@buckets.shift.clear)
# 		}

		# Method 3
# 		if gap == 1
# 			@buckets.push([])
# 		elsif gap == 2
# 			@buckets.push(@useless_bucket)
# 			@buckets.push([])
# 		else
# 			(gap-1).times { @buckets.push(@useless_bucket) }
# 			@buckets.push([])
# 		end
# 		@buckets.shift(gap)

		# @buckets += ([[]] * ([id-@latest_bucket_id, @bucket_num].min)) # 13~17K in backtesting
		# @buckets.concat([[]] * gap) # concat() 17K

		# Put into latest bucket
		@latest_bucket = @buckets[@bucket_num-1]
		@latest_bucket.push(data) if data != nil
		@latest_bucket_id = id # Update latest_bucket_id
	end

	def each(&block) # Faster than all_data().each
		@buckets.each { |b| b.each(&block) }
	end

	def each_bucket_top(&block)
		@buckets.each { |b| block.call(b.first) }
	end

	def all_data
		# @buckets.reduce(:+) # 28K -> 18K
		all = []
		@buckets.each { |d| all.concat(d) } # 28L -> 22K
		all
	end

	def print # Debug
		@buckets.reverse.each_with_index do |bkt, i|
			puts "Bucket ID #{@latest_bucket_id - i}"
			bkt.each { |data| puts "\t\t\tdata: #{data}" }
		end
	end
end
