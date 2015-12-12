class ZWYLogger

	def getExceptionStackInfo(e)
		return "[#{e.class.name}]\nMSG:[#{e.message}]\n#{getStackInfo(e.backtrace)}"
	end

	def debug(str)
		str = getExceptionStackInfo(str) if str.is_a?(Exception)
		log_int str.to_s
	end

	def log(str, additional_stack=0)
		str = getExceptionStackInfo(str) if str.is_a?(Exception)
		log_int str.to_s, additional_stack
	end

	def info(str)
		str = getExceptionStackInfo(str) if str.is_a?(Exception)
		log_int str.to_s.blue
	end

	def highlight(str)
		str = getExceptionStackInfo(str) if str.is_a?(Exception)
		log_int str.to_s.red
	end

	def warn(str)
		if str.is_a?(Exception)
			log_int getExceptionStackInfo(str).light_magenta
		else
			log_int str.to_s.light_magenta + "\n" +  getStackInfo(caller).light_magenta
		end
	end

	def error(str)
		if str.is_a?(Exception)
			log_int getExceptionStackInfo(str).light_red
		else
			log_int str.to_s.light_red + "\n" +  getStackInfo(caller).light_red
		end
	end

	def fatal(str)
		if str.is_a?(Exception)
			log_int getExceptionStackInfo(str).red
		else
			log_int str.to_s.red + "\n" +  getStackInfo(caller).red
		end
	end

	private

	def getStackInfo(callerInspectInfo)
		info = "StackTrace:\n"
		callerInspectInfo.each { |line| info += line + "\n" }
		return info
	end

	@@maxHeadLen = 30
	def log_int(o, additional_stack=0)
		head = caller(2 + additional_stack).first.split(":in")[0]
		head = head.split('/').last
		head = "#{Time.now.strftime("%m/%d-%H:%M:%S.%L")} [#{head}]:"
		@@maxHeadLen = head.size if head.size > @@maxHeadLen
		print "\r#{head.ljust(@@maxHeadLen)}#{o}\n"
	end

end

# Override default puts with additional info.
def puts(o, additionalInfo = true)
	LOGGER.log(o, 1) if additionalInfo
	super(o) if !additionalInfo
end

LOGGER = ZWYLogger.new
