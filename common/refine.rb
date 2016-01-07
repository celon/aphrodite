if defined? using == 'method'
	module EncodeRefine
		refine ::DateTime do
			def to_mysql_time
				self.strftime "%Y-%m-%d %H:%M:%S"
			end
	
			def to_yyyymmdd
				self.strftime "%Y%m%d"
			end
		end
	
		refine ::Fixnum do
			def strftime(format='%FT%T%:z')
				if self > 9999999999
					return Date.strptime(self.to_s, '%Q').strftime format
				end
				DateTime.strptime(self.to_s, '%s').strftime format
			end
		end
	
		refine ::String do
			def strftime(format='%FT%T%:z')
				DateTime.parse(self).strftime format
			end
		end
	end
else
	# Monkey patch here.
	module EncodeRefine
	end

	Kernel.module_eval do
		def using(module_name)
			puts "WARNING!!! Current ruby engine [#{RUBY_ENGINE}] does not support keyword[using], use monkey patch instead."
		end
	end

	class ::DateTime
		def to_mysql_time
			self.strftime "%Y-%m-%d %H:%M:%S"
		end

		def to_yyyymmdd
			self.strftime "%Y%m%d"
		end
	end

	class ::Fixnum
		def strftime(format='%FT%T%:z')
			if self > 9999999999
				return Date.strptime(self.to_s, '%Q').strftime format
			end
			DateTime.strptime(self.to_s, '%s').strftime format
		end
	end

	class ::String
		def strftime(format='%FT%T%:z')
			DateTime.parse(self).strftime format
		end
	end
end
