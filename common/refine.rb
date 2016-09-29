if defined? using == 'method'
	module EncodeRefine
		refine ::Date do
			def to_mysql_time
				self.strftime "%Y-%m-%d 00:00:00"
			end
	
			def to_yyyymmdd
				self.strftime "%Y%m%d"
			end
	
			def to_yyyymm
				self.strftime "%Y%m"
			end

			def to_i
				self.strftime('%Q').to_i
			end
		end

		refine ::DateTime do
			def to_mysql_time
				self.strftime "%Y-%m-%d %H:%M:%S"
			end
	
			def to_yyyymmdd
				self.strftime "%Y%m%d"
			end
	
			def to_yyyymm
				self.strftime "%Y%m"
			end

			def to_i
				self.strftime('%Q').to_i
			end
		end
	
		refine ::Fixnum do
			def strftime(format='%FT%T%:z')
				if self > 9999999999
					return DateTime.strptime(self.to_s, '%Q').strftime format
				end
				DateTime.strptime(self.to_s, '%s').strftime format
			end

			def to_time
				if self > 9999999999
					return DateTime.strptime(self.to_s, '%Q')
				end
				DateTime.strptime(self.to_s, '%s')
			end
		end
	
		refine ::String do
			def strftime(format='%FT%T%:z')
				DateTime.parse(self).strftime format
			end

			def extract_useragent
				res = ''
				# Platform
				res << 'Android ' if include? 'Android '
				res << 'iPad ' if include? 'iPad; '
				res << 'iPhone ' if include? 'iPhone; '
				res << 'Win' if include? 'Windows NT '
				res << 'Mac' if include? 'Macintosh'
				res << 'Mac' if include? 'Darwin'
				# Browser
				{'MicroMessenger'=>'微信', 'QQ'=>'QQ', 'Firefox'=>'firefox', 'NetType'=>'网络'}.each do |attr, display_name|
					res << display_name << (split(attr)[1].split(' ')[0]) << ' ' if include? attr
				end
				return self if res.empty?
				res
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

	class ::Date
		def to_mysql_time
			self.strftime "%Y-%m-%d 00:00:00"
		end

		def to_yyyymmdd
			self.strftime "%Y%m%d"
		end

		def to_yyyymm
			self.strftime "%Y%m"
		end

		def to_i
			self.strftime('%Q').to_i
		end
	end

	class ::DateTime
		def to_mysql_time
			self.strftime "%Y-%m-%d %H:%M:%S"
		end

		def to_yyyymmdd
			self.strftime "%Y%m%d"
		end

		def to_yyyymm
			self.strftime "%Y%m"
		end

		def to_i
			self.strftime('%Q').to_i
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

		def extract_useragent
			res = ''
			# Platform
			res << 'Android ' if include? 'Android '
			res << 'iPad ' if include? 'iPad; '
			res << 'iPhone ' if include? 'iPhone; '
			res << 'Win' if include? 'Windows NT '
			res << 'Mac' if include? 'Macintosh'
			res << 'Mac' if include? 'Darwin'
			# Browser
			{'MicroMessenger'=>'微信', 'QQ'=>'QQ', 'Firefox'=>'firefox', 'NetType'=>'网络'}.each do |attr, display_name|
				res << display_name << (split(attr)[1].split(' ')[0]) << ' ' if include? attr
			end
			return self if res.empty?
			res
		end
	end
end
