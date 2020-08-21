module TwitterV2
	include APD::EncodeUtil
	TWITTER_API_HOST = "https://api.twitter.com"

	# For auth, see:
	# https://developer.twitter.com/en/docs/authentication/oauth-2-0/bearer-tokens
	#
	# Get token with Basic Auth (user = API_KEY passwd = SEC_KEY)
	# {"authorization":"Basic encodebase64(user:pswd)"}
	def twt_get_token(opt)
		verbose = opt[:verbose] == true
		return @_twt_bearer_token if @_twt_bearer_token != nil
		puts "Fetching twitter bearer token" if verbose
		@_twt_consumer_key ||= TWITTER_CONSUMER_KEY if (defined? TWITTER_CONSUMER_KEY)
		@_twt_consumer_key ||= ENV['TWITTER_CONSUMER_KEY']
		@_twt_consumer_sec ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_CONSUMER_SECRET)
		@_twt_consumer_sec ||= ENV['TWITTER_CONSUMER_SECRET']
		url = "#{TWITTER_API_HOST}/oauth2/token"
		res = HTTP.basic_auth(
			user: @_twt_consumer_key,
			pass: @_twt_consumer_sec,
		).post(url, params:{grant_type: "client_credentials"})
		if res.status.success?
			ret = res.body
			begin
				ret = JSON.parse(ret)
				if ret['token_type'] == 'bearer'
					@_twt_bearer_token = ret['access_token']
					puts "twitter bearer token: #{@_twt_bearer_token[0..10]}..." if verbose
				else
					raise "Unexpected twitter bearer token #{ret}"
				end
			rescue => e
				raise "Failed in fetching twitter bearer token #{e.message}"
			end
		else
			raise "Failed in fetching twitter bearer token #{res.inspect}"
		end
		@_twt_bearer_token
	end

	def twt_http_pool(opt={})
		@_twt_http_pool ||= APD::GreedyConnectionPool.new("twitter-api", 2, debug:true) {
			keepalive_timeout = 60
			http_op_timout = 10
			conn = HTTP.use(:auto_inflate).
				persistent(TWITTER_API_HOST, timeout:keepalive_timeout).
				timeout(http_op_timout).
				auth("Bearer #{twt_get_token(verbose:true)}")
			next conn
		}
		@_twt_http_pool
	end

	def twt_req(path, opt={})
		verbose = opt[:verbose] == true

		path = "https://api.twitter.com/2#{path}"
		args = opt[:args] || {}
		method = opt[:method] || :GET

		args_str = args.to_a.
			map { |kv| kv[0].to_s + '=' + kv[1].to_s }.join('&')
		# Convert key into string.
		params = args.to_a.map { |kv| [kv[0].to_s, kv[1]] }.to_h

		twt_http_pool().with { |conn|
			options = conn.default_options().to_hash
			puts options
			if method == :GET
# 				path = "#{path}?#{args_str}"
# 				puts path=='https://api.twitter.com/2/tweets?ids=1228393702244134912,1227640996038684673,1199786642791452673&tweet.fields=created_at&expansions=author_id&user.fields=created_at'
# 				puts path
# 				response = conn.get(path, body: args_str)
				path = 'https://api.twitter.com/2/users/by?usernames=twitterdev,twitterapi,adsapi&user.fields=created_at&expansions=pinned_tweet_id&tweet.fields=author_id,created_at'
				response = conn.get(path)
			elsif method == :POST
				payload = args_str
				response = conn.post path, payload:payload
			elsif method == :DELETE
				payload = args_str
				response = conn.delete path, payload:payload
			elsif method == :PUT
				payload = args_str
				response = conn.put path, payload:payload
			end
			puts response.inspect
			puts response.body
			return response
		}
	end

	def twt_test
		args = {
			:ids => '1228393702244134912,1227640996038684673,1199786642791452673',
			:'tweet.fields' => 'created_at',
			:expansions => 'author_id',
			:'user.fields' => 'created_at'
		}
		twt_req('/tweets', args: args)
	end
end
