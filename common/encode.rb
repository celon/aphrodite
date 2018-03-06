module EncodeUtil
	def encode64(data)
		Base64.encode64(data.nil? ? '':data).strip.gsub("\n", '')
	end

	def decode64(data)
		return nil if data.nil? || data.empty?
		Base64.decode64(data).force_encoding("UTF-8")
	end

	def hash_str(data)
		data.nil? ? Digest::MD5.hexdigest("") : Digest::MD5.hexdigest(data)
	end

	def md5(data)
		data.nil? ? Digest::MD5.hexdigest("") : Digest::MD5.hexdigest(data)
	end

	def to_camel(snake, capFirst = false)
		camel = nil
		snake.split('_').each do |w|
			if camel.nil?
				camel = w.capitalize if capFirst
				camel = w if !capFirst
			else
				camel << w.capitalize
			end
		end
		camel
	end

	def to_snake(camel)
		camel.gsub(/::/, '/').
		gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
		gsub(/([a-z\d])([A-Z])/,'\1_\2').
		tr("-", "_").
		downcase
	end
end

module LZString
	def lz_context
		@lz_context ||= ExecJS.compile(File.read("#{APD_COMMON_PATH}/../res/lz-string-1.3.3-min.js"))
	end

	def lz_compressToBase64(string)
		lz_context.call("LZString.compressToBase64", string)
	end

	def lz_decompressFromBase64(string)
		lz_context.call("LZString.decompressFromBase64", string)
	end
end

module ShortURLUtil
	include EncodeUtil
	def short_url(url, opt={})
		return nil if url.nil?
		raise "Url should be started with http/https" unless url.start_with?('http')
		encode_url = encode64(url)
		url = "http://dwz.wailian.work/api.php?url=#{encode_url}&site=sina"
		response = curl url
	end
end
