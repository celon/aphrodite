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
			max_ct = opt[:max_ct]
		end
		if max_ct != nil && max_ct > 0
			opt[:max_time] ||= (max_ct * 60)
		end

		doc = nil
		if opt[:render] == true
			doc = render_html url, opt
		else
			doc = curl url, opt
		end
		return Nokogiri::HTML(doc)
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
		header = opt[:header] || {}
		tmp_file_use = false
		if file.nil?
			file = "curl_#{hash_str(url)}_#{Random.rand(10000).to_s.ljust(4)}.html"
			tmp_file_use = true
		end
		# Directly return from cache file if use_cache=true
		if file != nil && File.file?(file) && use_cache == true
			Logger.debug("#{cmd} --> directly return cache:#{file}") if opt[:verbose] == true
			result = File.open(file, "rb").read
			return result
		end
		cmd = "curl --output '#{file}' -L " # -L Follow 301 redirection.
		cmd += " --fail" unless opt[:allow_http_error]
		cmd += " --silent" unless opt[:verbose]
		cmd += " -A '#{agent}'" unless agent.nil?
		cmd += " --retry #{opt[:retry]}" unless opt[:retry].nil?
		cmd += " --retry-delay #{retry_delay}"
		cmd += " --max-time #{opt[:max_time]}" unless opt[:max_time].nil?
		header.each do |k, v|
			cmd += " --header '#{k}: #{v}'"
		end
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
			begin
				File.delete(file) if tmp_file_use
			rescue => e
				Logger.error e
			end
		else
			result = nil
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

	def href_url(homeurl, href)
		return nil if href.nil?
		return href if (href =~ /^[a-zA-Z]\:\/\// ) == 0
		raise "#{homeurl} is not a URI" unless (homeurl =~ /^[a-zA-Z]*\:\/\// ) == 0
		protocol = homeurl.split('://')[0]
		segs = homeurl.split('/')
		base_domain = segs[0..2].join('/')
		if segs.size > 3
			base_dir = homeurl.split('/')[0..-2].join('/')
		else
			base_dir = base_domain
		end
		return "#{protocol}:#{href}" if href[0..1] == '//'
		return "#{base_domain}#{href}" if href[0] == '/'
		return "#{base_dir}/#{href}"
	end

	########################################
	# Phantomjs task proxy.
	########################################
	include ExecUtil
	def render_html(url, opt={})
		task_file = "/tmp/phantomjs_#{hash_str(url)}.task"
		html_file = "/tmp/phantomjs_#{hash_str(url)}.html"
		task = {
			'url'			=>	url,
			'settings'=>	opt[:settings],
			'html'		=>	opt[:html] || html_file,
			'timeout'	=>	(opt[:timeout] || 300)*1000,
			'image'		=>	opt[:image],
			'switch_device_after_fail' => (opt[:switch_device_after_fail] == true),
			'action'			=> opt[:action],
			'action_time' => (opt[:action_time] || 15),
			'post_render_wait_time' => (opt[:post_render_wait_time] || 0)
		}
		task.keys.each do |k|
			task.delete k if task[k].nil?
			opt.delete k
		end
		File.open(task_file, 'w') { |f| f.write(JSON.pretty_generate(task)) }
		command = "phantomjs #{APD_COMMON_PATH}/html_render.js -f #{task_file}"
		# Force do not use thread, pass other options to exec_command().
		opt[:thread] = false
		status = exec_command(command, opt)
		raise status.to_json unless status['ret'] == true
		html = File.read(html_file)
		begin
			FileUtils.rm task_file
			FileUtils.rm html_file
		rescue => e
			Logger.error e
		end
		html
	end
end
