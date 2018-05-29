require_relative '../common/bootstrap'

include APD::CacheUtil
include APD::EncodeUtil
def redis_db
	0
end

######################### CONF ###########################
options = OpenStruct.new
options.banner = "Usage: -k key [-v val] [--delete]"
OptionParser.new do |opts|
	opts.on("-h", "--hash key", "Hash key") do |n|
		options[:hash] = n
	end

	opts.on("-k", "--key string", "Target key") do |v|
		options[:key] = v
	end

	opts.on("-v", "--value string", "Value content") do |v|
		options[:value] = v
	end

	opts.on("-e", "--encode codename", "Encode name of value") do |n|
		options[:encode] = n
	end

	opts.on("-m", "--mode name", "Operation mode") do |n|
		options[:mode] = n
	end
end.parse!

hash = options[:hash]
key = options[:key]
value = options[:value]
encode = options[:encode]
value = decode64(value) if encode == 'base64' && value != nil

# Mode selection.
delete = options[:mode] == 'del'
array_append = options[:mode] == 'array_append'

######################### MAIN ###########################

abort "No key specified." if key.nil?
if delete
	# Delete mode
	abort "Value should not be specified in delete mode." unless value.nil?
	if hash.nil?
		puts "Delete #{key}"
		redis.del key
	else
		puts "Delete Hash #{hash} : #{key}"
		redis.hdel hash, key
	end
elsif array_append
	abort "Value should be specified in array append mode." if value.nil?
	puts "Append to #{key}"
	redis.rpush key, value
else
	if hash.nil?
		if value.nil?
			# Get KV mode
			print redis.get key
		else
			# Set KV mode
			redis.set key, value
		end
	else
		if value.nil?
			# Get Hash KV mode
			print(redis.hget(hash, key))
		else
			# Set Hash KV mode
			redis.hset hash, key, value
		end
	end
end
