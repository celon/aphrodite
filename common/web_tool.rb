module ShortURLUtil
	include APD::EncodeUtil
	include APD::SpiderUtil
	def short_url(url, opt={})
		return nil if url.nil?
		raise "Url should be started with http/https" unless url.start_with?('http')
		puts "Shorting url: #{url}"
		args = {
			'action'	=> 'shorturl',
			'url'			=> url,
			'format'	=> 'json',
			'username'=> 'zwyang',
			'password'=> 'SzV-85E-n83-X9M'
		}
		retry_ct = 0
		begin
			url = "http://tny.im/yourls-api.php?" + args.to_a.map{ |kv| "#{kv[0]}=#{kv[1]}" }.join('&')
			url = URI.escape url
			response = curl url, verbose:true
			ret = JSON.parse response
			unless ret['shorturl'].nil?
				url = ret['shorturl']
				if opt[:no_protocol] == true
					url = url[7..-1] if url.start_with?('http://')
					url = url[8..-1] if url.start_with?('https://')
				end
				return url
			end
			raise response
		rescue => e
			APD::Logger.error e
			sleep 5
			retry_ct += 1
			retry if retry_ct < 5
			raise e
		end
	end
end

module WebExtraction
	include APD::SpiderUtil
	include APD::LogicControl
	include APD::EncodeUtil

	def screenshot_webpage(url, img_id, opt={})
		www_root = opt[:root] || '/var/nginx/www'
		raise "No directory #{www_root} for screenshot" unless File.directory?(www_root)
		img_path = "/screenshot/#{img_id}.png"
		img_f = www_root + img_path
		if File.file?(img_f) == false
			width, height = 1024, 768
			render_html(
				url, with: :firefox,
				width:width, height:height, render_t:3
			) { |firefox|
				firefox.manage.window.resize_to(width, height)
				puts "Saving screenshot to #{img_f.blue}"
				firefox.save_screenshot(img_f)
				true
			}
		end
		return img_path
	end

	# Render webpage in reader mode, and extract its pictures in reader content.
	def extract_webpage_image(url, reader_img_id, opt={})
		www_root = opt[:root] || '/var/nginx/www'
		width, height = 600, 800
		reader_url = "about:reader?url=#{url}" # Works with firefox only
		reader_html = render_html(
			reader_url, with: :firefox,
			width:width, height:height, render_t:3
		) { |firefox|
			if reader_img_id != nil
				FileUtils.mkdir_p "#{www_root}/screenshot"
				img_f = "#{www_root}/screenshot/#{reader_img_id}.reader.png"
				firefox.manage.window.resize_to(width, height)
				puts "Saving reader screenshot to #{img_f.blue}"
				firefox.save_screenshot(img_f)
			end
			true
		}
		doc = parse_html(reader_html)
		image_urls = []
		# Save images in reader mode, skip small ones.
		empty_size_imgs = []
		doc.xpath('//*/img').each { |img|
			puts "IMAGE #{img.to_s}"
			next if img['width'] != nil && img['width'].to_i < 300
			next if img['height'] != nil && img['height'].to_i < 300
			url = img['src']
			next if url.nil?
			puts "IMAGE extracted: #{url.blue}"
			image_urls.push url
			if img['height'].nil? && img['width'].nil?
				empty_size_imgs.push url
			end
		}
		empty_size_imgs.each { |img_url|
			puts "Download to check filesize of empty size image:\n#{img_url}"
			# Nil would be returned if curl() failed after retrying.
			img_fsize = no_complain {
				curl(img_url, retry:3) { |img_f| File.size(img_f) }
			}
			valid = nil
			if img_fsize.nil?
				valid = false
			else
				valid = (img_fsize >= 50_000) # Consider image is valid if > 50KB
			end
			puts "img #{valid ? ' Y' : 'X' } FSIZE: #{img_fsize || 'ERR'}"
			if valid == false
				image_urls -= [img_url]
			end
		}
		image_urls
	end

	def extract_reader_content(url, opt={})
		width, height = 600, 800
		reader_url = "about:reader?url=#{url}" # Works with firefox only
		title = nil
		content = nil
		reader_html = render_html(
			reader_url, with: :firefox,
			width:width, height:height, render_t:3
		) { |firefox|
			title = firefox.find_element(class: 'reader-title').text.strip
			content = firefox.find_element(class: 'content').text.strip
			true
		}
		return {
			:title => title,
			:content => content
		}
	end
end
