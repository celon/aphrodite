class Logger
	class << self
		def getExceptionStackInfo(e)
			return "[#{e.class.name}]\nMSG:[#{e.message}]\n#{getStackInfo(e.backtrace)}"
		end
	
		def debug(str)
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str
		end
	
		def log(str, additional_stack=0)
			str = getExceptionStackInfo(str) if str.is_a?(Exception)
			log_int str, additional_stack
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
	
		private
	
		def getStackInfo(callerInspectInfo)
			info = "StackTrace:\n"
			callerInspectInfo.each { |line| info += line + "\n" }
			return info
		end
	
		@@_apd_logger_max_head_len = 0
		def log_int(o, additional_stack=0, opt={})
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
	end
end

# Override default puts with additional info.
Kernel.module_eval do
	alias :original_puts :puts
	def puts(o, opt={})
		opt = { :info => false } if opt == false
		additionalInfo = opt[:info] != false
		level = opt[:level] || 1
		Logger.log(o, level) if additionalInfo
		original_puts(o) if !additionalInfo
	end
end
