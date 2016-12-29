module TwitterUtil
	def twitter(key = nil, secret = nil, access_token = nil, access_token_secret = nil)
		@_twt_key = key unless key.nil?
		@_twt_key ||= TWITTER_CONSUMER_KEY if (defined? TWITTER_CONSUMER_KEY)
		@_twt_secret = secret unless secret.nil?
		@_twt_secret ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_CONSUMER_SECRET)
		@_twt_token = access_token unless access_token.nil?
		@_twt_token ||= TWITTER_ACCESS_TOKEN if (defined? TWITTER_ACCESS_TOKEN)
		@_twt_token_secret = access_token_secret unless access_token_secret.nil?
		@_twt_token_secret ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_ACCESS_TOKEN_SECRET)
		@_twt_client ||= Twitter::REST::Client.new do |config|
			  config.consumer_key    = @_twt_key
			  config.consumer_secret = @_twt_client
				config.access_token        = @_twt_token
			  config.access_token_secret = @_twt_token_secret
		end
	end

	def twt_tweets(user)
		options = {count: 10, include_rts: true}
# 		twitter.user_timeline(user, options)
		twitter.user_timeline
	end
end
