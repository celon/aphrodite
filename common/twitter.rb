module TwitterUtil
	include SleepUtil

	def _twitter_config
	end

	def _twitter(key = nil, secret = nil, access_token = nil, access_token_secret = nil)
		_twitter_config()
		@_twt_key ||= key unless key.nil?
		@_twt_key ||= TWITTER_CONSUMER_KEY if (defined? TWITTER_CONSUMER_KEY)
		@_twt_secret ||= secret unless secret.nil?
		@_twt_secret ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_CONSUMER_SECRET)
		@_twt_token ||= access_token unless access_token.nil?
		@_twt_token ||= TWITTER_ACCESS_TOKEN if (defined? TWITTER_ACCESS_TOKEN)
		@_twt_token_secret ||= access_token_secret unless access_token_secret.nil?
		@_twt_token_secret ||= TWITTER_ACCESS_TOKEN_SECRET if (defined? TWITTER_ACCESS_TOKEN_SECRET)
		@_twt_client ||= Twitter::REST::Client.new do |config|
		  config.consumer_key    = @_twt_key
		  config.consumer_secret = @_twt_secret
			config.access_token        = @_twt_token
		  config.access_token_secret = @_twt_token_secret
		end
	end

	def twitter_api(method_symbol, *args, &block)
		begin
 			return _twitter.send(method_symbol, *args, *block)
		rescue Twitter::Error::RequestEntityTooLarge => e
			retry
		rescue Twitter::Error::TooManyRequests => e
			# NOTE: Your process could go to sleep for up to 15 minutes but if you
			# retry any sooner, it will almost certainly fail with the same exception.
			graphic_sleep(e.rate_limit.reset_in + 1)
			retry
		rescue HTTP::ConnectionError => e
			sleep 5
			retry
		rescue => e
			APD::Logger.highlight "Twitter api error: #{e.message}"
			if e.message.include?("execution expired")
				@_twt_client = nil
				retry
			elsif e.message.include?("Over capacity")
				@_twt_client = nil
				sleep 60
				retry
			else
				raise e
			end
		end
	end
end
