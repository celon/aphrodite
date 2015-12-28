if defined? using == 'method'
	module EncodeRefine
		refine DateTime do
			def toMySQLFormat
				self.strftime "%Y-%m-%d %H:%M:%S"
			end
	
			def toYYYYmmdd
				self.strftime "%Y%m%d"
			end
		end
	
		refine Fixnum do
			def strftime(format='%FT%T%:z')
				if self > 9999999999
					return Date.strptime(self.to_s, '%Q').strftime format
				end
				DateTime.strptime(self.to_s, '%s').strftime format
			end
		end
	
		refine String do
			def strftime(format='%FT%T%:z')
				DateTime.parse(self).strftime format
			end
		end
	end
else
	# Monkey patch here.
	module EncodeRefine
	end

	def using(module_name)
		puts "WARNING!!! Current ruby implementation does not support keyword[using], use monkey patch instead."
	end

	class DateTime
		def toMySQLFormat
			self.strftime "%Y-%m-%d %H:%M:%S"
		end

		def toYYYYmmdd
			self.strftime "%Y%m%d"
		end
	end

	class Fixnum
		def strftime(format='%FT%T%:z')
			if self > 9999999999
				return Date.strptime(self.to_s, '%Q').strftime format
			end
			DateTime.strptime(self.to_s, '%s').strftime format
		end
	end

	class String
		def strftime(format='%FT%T%:z')
			DateTime.parse(self).strftime format
		end
	end
end
