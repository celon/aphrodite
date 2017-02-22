module SpiderUtil
	include EncodeUtil

	USER_AGENTS = {
		'PHONE'		=> 'Mozilla/5.0 (iPhone; CPU iPhone OS 9_3_5 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13G36 Safari/601.1',
		'TABLET'	=> 'Mozilla/5.0 (iPad; CPU OS 9_3_5 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13G36 Safari/601.1',
		'DESKTOP'	=> 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36'
	}

	def post_web(host, path, data, opt={})
		header = {
			'User-Agent'			=> 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:51.0) Gecko/20100101 Firefox/51.0',
			'Accept'					=> '*/*',
			'Accept-Language'	=> 'en-US,en;q=0.5',
			'Accept-Encoding'	=> 'gzip, deflate',
			'Connection'			=> 'keep-alive',
			'Pragma'					=> 'no-cache',
			'Cache-Control'		=> 'no-cache'
		}
		header = opt[:header] unless opt[:header].nil?
		header['Host'] ||= host

		verbose = opt[:verbose] == true
		connect = opt[:connect] ||= Net::HTTP.start(host, (opt[:port] || 80))
		data = map_to_poststr(data) if data.is_a?(Hash)

		header['Content-Type'] = 'application/x-www-form-urlencoded'
		header['Content-Length'] = data.size.to_s
		if verbose
			puts "SpiderUtil.post: host: #{host}"
			puts "SpiderUtil.post: path: #{path}"
			puts "SpiderUtil.post: header: #{header.to_json}"
			puts "SpiderUtil.post: data: #{data.to_json}"
		end
		resp = connect.post path, data, header
		raise "SpiderUtil.post: HTTP CODE #{resp.code}" if resp.code != '200'
		body = resp.body
		# Deflat gzip if possible.
		if body[0..2].unpack('H*') == ["1f8b08"]
			size = body.size
			gz = Zlib::GzipReader.new(StringIO.new(body))    
			body = gz.read
			puts "SpiderUtil.post: deflat from gzip #{size} -> #{body.size}" if verbose
		end
		puts "SpiderUtil.post: response.body [#{body.size}]:#{body[0..300]}" if verbose
		body
	end

	def parse_html(html, encoding=nil, opt={})
		if encoding.is_a?(Hash)
			opt = encoding
			encoding = opt[:encoding]
		end
		return Nokogiri::HTML(html, nil, encoding)
	end

	def parse_web(url, encoding = nil, max_ct = -1, opt = {})
		if encoding.is_a?(Hash)
			opt = encoding
			encoding = opt[:encoding]
			max_ct = opt[:max_ct] || -1
		end
		doc = nil
		ct = 0
		retry_delay = opt[:retry_delay] || 1
		abort_exp = opt[:abort_on]
		while true
			begin
				Logger.debug "Fetching #{url}" if opt[:verbose] == true
				newurl = URI.escape url
				if newurl != url
					# Use java version curl
					doc = curl_javaver url
					raise "Cannot download with java curl" if doc == nil
					if encoding.nil?
						doc = Nokogiri::HTML(doc)
					else
						doc = Nokogiri::HTML(doc, nil, encoding)
					end
				else
					if encoding.nil?
						doc = Nokogiri::HTML(open(url))
					else
						doc = Nokogiri::HTML(open(url), nil, encoding)
					end
				end
				return doc
			rescue => e
				Logger.debug "error in parsing [#{url}]:\n#{e.message}"
				unless abort_exp.nil?
					abort_exp.each do |reason|
						raise e if e.message.include?(reason)
					end
				end
				ct += 1
				raise e if max_ct > 0 && ct >= max_ct
				sleep retry_delay
			end
		end
	end
	
	def curl_native(url, opt={})
		filename = opt[:file]
		max_ct = opt[:retry] || -1
		retry_delay = opt[:retry_delay] || 1
		doc = nil
		ct = 0
		while true
			begin
				open(filename, 'wb') do |file|
					file << open(url).read
				end
				return doc
			rescue => e
				Logger.debug "error in downloading #{url}: #{e.message}"
				ct += 1
				raise e if max_ct > 0 && ct >= max_ct
				sleep retry_delay
			end
		end
	end

	def curl(url, opt={})
		file = opt[:file]
		use_cache = opt[:use_cache] == true
		agent = opt[:agent]
		retry_delay = opt[:retry_delay] || 1
		encoding = opt[:encoding]
		tmp_file_use = false
		if file.nil?
			file = "curl_#{hash_str(url)}.html"
			tmp_file_use = true
		end
		# Directly return from cache file if use_cache=true
		if file != nil && File.file?(file) && use_cache == true
			Logger.debug("#{cmd} --> directly return cache:#{file}") if opt[:verbose] == true
			result = File.open(file, "rb").read
			return result
		end
		cmd = "curl --output '#{file}'"
		cmd += " --fail" unless opt[:allow_http_error]
		cmd += " --silent" unless opt[:verbose]
		cmd += " -A '#{agent}'" unless agent.nil?
		cmd += " --retry #{opt[:retry]}" unless opt[:retry].nil?
		cmd += " --retry-delay #{retry_delay}"
		cmd += " --max-time #{opt[:max_time]}" unless opt[:max_time].nil?
		cmd += " '#{url}'"
		Logger.debug(cmd) if opt[:verbose]
		ret = system(cmd)
		if File.exist?(file)
			unless encoding.nil?
				cmd = "iconv -f #{encoding} -t utf-8//IGNORE '#{file}' -o '#{file}.utf8'"
				Logger.debug(cmd) if opt[:verbose]
				system(cmd)
				cmd = "mv '#{file}.utf8' '#{file}'"
				Logger.debug(cmd) if opt[:verbose]
				system(cmd)
			end
		end
		if File.exist?(file)
			result = File.open(file, "rb").read
			result = result.force_encoding('utf-8') unless encoding.nil?
			File.delete(file) if tmp_file_use
		else
			result = nil
		end
		result
	end
	
	def curl_javaver(url, opt={})
		file = opt[:file]
		tmp_file_use = false
		if file.nil?
			file = "curl_#{hash_str(url)}.html"
			tmp_file_use = true
		end
		jarpath = "#{APD_COMMON_PATH}/res/curl.jar"
		cmd = "java -jar #{jarpath} '#{url}' #{file}"
		ret = system(cmd)
		Logger.debug("#{cmd} --> #{ret}")
		result = ""
		if File.exist?(file)
			result = File.open(file, "rb").read
			File.delete(file) if tmp_file_use
		else
			result = nil
			raise ret
		end
		result
	end

	def map_to_poststr(map)
		str = ""
		(map || {}).each do |k, v|
			v = v.to_s
			str = "#{CGI::escape(k)}=#{CGI::escape(v)}&#{str}"
		end
		str
	end
end
