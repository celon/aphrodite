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
