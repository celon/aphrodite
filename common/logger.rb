require 'concurrent'
class Logger
	class << self
		def getExceptionStackInfo(e)
			return "[#{e.class.name}]\nMSG:[#{e.message}]\n#{getStackInfo(e.backtrace)}"
		end
	
		def debug(str)
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str
		end
	
		def log(str, additional_stack=0, opt={})
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str, additional_stack, opt
		end
	
		def info(str)
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str, nil, color: :blue
		end
	
		def highlight(str)
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str, nil, color: :red
		end
	
		def warn(str)
			if str.is_a?(Exception)
				log_int getExceptionStackInfo(str), nil, color: :light_magenta
			else
				log_int str, nil, color: :light_magenta
			end
		end
	
		def error(str)
			if str.is_a?(Exception)
				log_int getExceptionStackInfo(str), nil, color: :light_red
			else
				log_int (str.to_s + "\n" +  getStackInfo(caller)), nil, color: :light_red
			end
		end
	
		def fatal(str)
			if str.is_a?(Exception)
				log_int getExceptionStackInfo(str), nil, color: :red
			else
				log_int (str.to_s + "\n" +  getStackInfo(caller)), nil, color: :red
			end
		end
		@@_apd_logger_max_head_len = 0
		@@_apd_logger_async_tasks = Concurrent::Array.new
		@@_apd_logger_file = nil
		@@_apd_logger_file_writer = nil
		def global_output_file=(f)
			raise "Logger:global_output_file exists #{@@_apd_logger_file}" unless @@_apd_logger_file.nil?
			@@_apd_logger_file = f
			@@_apd_logger_file_writer = File.open(f, 'a')
		end
		@@_apd_logger_file_w_thread = Thread.new {
			fputs_ct = 0
			loop {
				begin
					sleep() # Wait for _log_async() is called
					loop { # Once waked up, process all tasks in batch
						task = @@_apd_logger_async_tasks.delete_at(0)
						break if task.nil?
						head, msg, opt = task
						head = head.split(":in")[0].split('/').last.gsub('.rb', '')
						head = "#{opt[:time].strftime("%m/%d-%H:%M:%S.%4N")} #{head} "
						@@_apd_logger_max_head_len = [head.size, @@_apd_logger_max_head_len].max
						msg = "#{head.ljust(@@_apd_logger_max_head_len)}#{msg}"
						msg = msg.send(opt[:color]) unless opt[:color].nil?

						print(opt[:inline] ? "\r#{msg}" : "\r#{msg}\n")
						if opt[:nofile] != true && @@_apd_logger_file_writer != nil
							fputs_ct += 1
							@@_apd_logger_file_writer.puts(msg)
						end
					}
				rescue => e
					print "#{e.to_s}\n"
					e.backtrace.each { |s| print "#{s}\n" }
				end
			}
		}
	
		private
	
		def getStackInfo(callerInspectInfo)
			info = "StackTrace:\n"
			callerInspectInfo.each { |line| info += line + "\n" }
			return info
		end
	

		def log_int_async(o, additional_stack=0, opt={})
			opt[:time] ||= Time.now
			additional_stack ||= 0
			head = caller(2 + additional_stack).first
			@@_apd_logger_async_tasks.push([head, o, opt])
			@@_apd_logger_file_w_thread.wakeup unless @@_apd_logger_file_w_thread.nil?
		end

		def log_int_sync(o, additional_stack=0, opt={})
			additional_stack ||= 0
			o = o.to_s
			head = caller(2 + additional_stack).first.split(":in")[0]
			head = head.split('/').last.gsub('.rb', '')
			if opt[:time].nil?
				head = "#{Time.now.strftime("%m/%d-%H:%M:%S.%4N")} #{head} "
			else
				head = "#{opt[:time].strftime("%m/%d-%H:%M:%S.%4N")} #{head} "
			end
			@@_apd_logger_max_head_len = head.size if head.size > @@_apd_logger_max_head_len
			msg = "\r#{head.ljust(@@_apd_logger_max_head_len)}#{o}\n"
			begin
				msg = msg.send(opt[:color]) unless opt[:color].nil?
			rescue => e
				msg << "\nBTX::Logger: Failed to set color #{opt[:color]}, error:#{e.message}\n"
			end
			print msg
		end

		alias_method :log_int, :log_int_async
# 		alias_method :log_int, :log_int_sync
	end
end

# Override default puts with additional info.
Kernel.module_eval do
	alias :original_puts :puts
	# Use original puts in below cases:
	# puts msg, false
	# puts msg, info:false
	def puts(o, opt={})
		opt = { :info => false } if opt == false
		return original_puts(o) if (opt[:info] == false)
		level = opt[:level] || 1
		Logger.log(o, level, opt)
	end
end
