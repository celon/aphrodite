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
			return ret['shorturl'] unless ret['shorturl'].nil?
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
