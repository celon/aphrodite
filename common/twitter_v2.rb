class TweetV2
	attr_reader :id, :json

	def initialize(json)
		# From live stream.
		# {
		#   data : { tweet_data }
		#   includes : { users : [], tweets: [ tweet_data ] }
		# }
		# From ref data: json = tweet_data only
		json = JSON.parse(json) if json.is_a?(String)
		@json = json
		if json['data'] != nil
			@data = json['data']
			@includes = json['includes']
		else
			@data = json
			@includes = nil
		end
		@id = @data['id'] || raise("No id from tweet data #{json}")
	end

	# Hashtags, cashtags and also from retweeted/quoted/replied_to tweets
	def all_tags
	end

	# URLs and also from retweeted/quoted/replied_to tweets
	def all_urls
	end

	def _parse_all
		return if @parsed
		@create_t = DateTime.parse(@data['created_at'])
		@lang = @data['lang']
		@text = @data['text']
		@user_list = (@includes || {})['users']
		@tweet_list = (@includes || {})['tweets']

		@entities = []
		entity_keys = ['hashtags', 'cashtags', 'urls', 'mentions', 'annotations']
		entity_keys.each { |k|
			values = @data.dig("entities", k) || []
			instance_variable_set("@#{k}".to_sym, values) # Also set @hashtags, @urls ...
			@entities += values
		}
		(@data['entities'] || []).each { |k, v|
			if entity_keys.include?(k) == false
				info = JSON.pretty_generate(v)
				puts "Unknown key #{k} in entities: #{info}"
			end
		}

		referenced_tweets_types = ['quoted', 'replied_to', 'retweeted']
		(@data['referenced_tweets'] || []).each { |ref|
			type = ref['type']
			id = ref['id']
			instance_variable_set("@ref_tweet_#{type}".to_sym, id)
			if referenced_tweets_types.include?(type) == false
				info = JSON.pretty_generate(ref)
				puts "Unknown type #{type} in referenced_tweets: #{info}"
			end
		}

		@parsed = true
	end

	def _user_by_id(id)
		@user_list.first { |u| u['id'] == id }
	end

	def _tweet_by_id(id)
		return nil if @tweet_list.nil?
		tweet = @tweet_list.first { |t| t['id'] == id }
		return nil if tweet.nil?
		TweetV2.new(tweet)
	end

	def _render
		return if @rendered
		_parse_all()

		# Render hashtags and urls in @text, from last to first.
		rendered_text = @text
		footnotes = []
		@entities.sort_by { |a| a['start'] }.reverse.each { |a|
			s, e = a['start'], a['end']
			str_before = ''
			str_before = rendered_text[0..(s-1)] if s > 0
			str_include = rendered_text[s..(e-1)]
			str_after = rendered_text[e..-1]
			if a['tag'] != nil # Render hashtags in green, cashtags in orange.
				tag = a['tag']
				if @cashtags.include?(tag)
					rendered_text = "#{str_before}#{('$'+tag).light_yellow}#{str_after}"
				else
					rendered_text = "#{str_before}#{('#'+tag).light_green}#{str_after}"
				end
			elsif a['url'] != nil # Render links in blue.
				rendered_text = "#{str_before}#{a['display_url'].light_blue}#{str_after}"
				tmp_notes = []
				['title', 'description'].each { |k|
					tmp_notes.push(a[k]) if a[k] != nil
				}
				if tmp_notes.size > 0
					footnotes.push(a['unwound_url'])
					footnotes = footnotes + tmp_notes
				elsif a['unwound_url'] != nil && a['unwound_url'].include?(a['display_url']) == false
					# Url is too long to display
					footnotes.push(a['unwound_url'])
				end
			elsif a['username'] != nil # Render mentions in blue.
				rendered_text = "#{str_before}#{('@'+a['username']).blue}#{str_after}"
			elsif a['probability'] != nil # Render annotations in underline.
				rendered_text = "#{str_before}#{str_include.underline}#{str_after}"
			end
		}
		# Remove newlines and duplicated space.
		rendered_text = rendered_text.gsub(/(\n|\r)/, ' ').gsub(/\s{2,}/, ' ')
		@rendered_text = rendered_text
		@rendered_footnotes = footnotes
		@rendered = true
	end

	def to_lines
		_parse_all()

		if @ref_tweet_retweeted != nil
			parent_tweet = _tweet_by_id(@ref_tweet_retweeted)
			return ['RT'] + parent_tweet.to_lines if parent_tweet != nil
		end

		lines = [@id]
		if @ref_tweet_replied_to != nil
			parent_tweet = _tweet_by_id(@ref_tweet_replied_to)
			if parent_tweet != nil
				lines.push 'RE:'
				lines += parent_tweet.to_lines
				lines.push("\t|")
				lines.push("\t|")
			end
		end

		_render()
		lines.push @rendered_text
		if @rendered_footnotes.size > 0
			lines += (@rendered_footnotes.map { |n| "\t#{n.cyan}" })
		end

		if @ref_tweet_quoted != nil
			parent_tweet = _tweet_by_id(@ref_tweet_quoted)
			if parent_tweet != nil
				lines.push 'Ref:'
				lines += (parent_tweet.to_lines.map { |n| "\t>\t#{n}" })
			end
		end

		lines
	end

	def to_s
		to_lines().join("\n")
	end
end

module TwitterAPIV2
	include APD::EncodeUtil
	include APD::LogicControl
	TWITTER_API_HOST = "https://api.twitter.com"

	# For auth, see:
	# https://developer.twitter.com/en/docs/authentication/oauth-2-0/bearer-tokens
	#
	# Get token with Basic Auth (user = API_KEY passwd = SEC_KEY)
	# {"authorization":"Basic encodebase64(user:pswd)"}
	def twt_get_token(opt={})
		return @_twt_bearer_token if @_twt_bearer_token != nil

		# Detect from system.
		verbose = opt[:verbose] == true
		@_twt_bearer_token ||= TWITTER_BEARER_TOKEN if (defined? TWITTER_BEARER_TOKEN)
		@_twt_bearer_token ||= ENV['TWITTER_BEARER_TOKEN']
		return @_twt_bearer_token if @_twt_bearer_token != nil

		# Fetch from twitter API by key/sec
		puts "Fetching twitter bearer token" if verbose
		@_twt_consumer_key ||= TWITTER_CONSUMER_KEY if (defined? TWITTER_CONSUMER_KEY)
		@_twt_consumer_key ||= ENV['TWITTER_CONSUMER_KEY']
		@_twt_consumer_key ||= ENV['TWITTER_KEY']
		@_twt_consumer_sec ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_CONSUMER_SECRET)
		@_twt_consumer_sec ||= ENV['TWITTER_CONSUMER_SECRET']
		@_twt_consumer_sec ||= ENV['TWITTER_SEC']
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
		@_twt_http_pool ||= APD::GreedyConnectionPool.new("twitter-api", 1, debug:true) {
			keepalive_timeout = 60
			http_op_timout = 10
			conn = HTTP.use(:auto_inflate).
				persistent(TWITTER_API_HOST, timeout:keepalive_timeout).
				timeout(http_op_timout).
				auth("Bearer #{twt_get_token(verbose:true)}").
				headers(:accept => "application/json")
			next conn
		}
		@_twt_http_pool
	end

	def twt_req_internal(path, opt={})
		verbose = opt[:verbose] == true
		silent = opt[:silent] == true
		req_t = Time.now

		path = "https://api.twitter.com/2#{path}"
		args = opt[:args] || {}
		method = opt[:method] || :GET

		args_str = ""
		if args.is_a?(Hash)
			if method == :GET
				args_str = args.to_a.
					map { |kv| kv[0].to_s + '=' + kv[1].to_s }.join('&')
			else
				args_str = args.to_json # For logging only.
			end
		elsif args.is_a?(String)
			raise "Please pass args in hashmap when method is not GET" if method != :GET
			args_str = args
		else
			raise "Unsupported args: #{args.inspect}"
		end

		return twt_http_pool().with { |conn|
			pre_t = ((Time.now - req_t)*1000).round(3)
			puts "--> #{method} #{path} #{pre_t} ms #{args_str.blue}", level:5 unless silent
			req_t = Time.now.to_f
			req_e = nil
			begin
				if method == :GET
					path = "#{path}?#{args_str}"
					response = conn.get(path)
				elsif method == :POST
					response = conn.post path, json: args
				elsif method == :DELETE
					response = conn.delete path, json: args
				elsif method == :PUT
					response = conn.put path, json: args
				end
			rescue => e
				req_e = e
			end
			req_t = Time.now.to_f - req_t
			unless silent
				req_ms = (req_t*1000).round(3)
				response = response.to_s
				puts "<-- #{method} #{path} #{req_ms} ms\n#{(response || "")[0..255].blue}", level:5
			end
			raise req_e if req_e != nil
			response = response.to_s
			begin
				response = JSON.parse(response)
				next response
			rescue
				raise "Twitter API response is not JSON:\n#{response}"
			end
		}
	end

	def twt_req(path, opt={})
		begin
			return twt_req_internal(path, opt)
		rescue => e
			return nil if opt[:allow_fail] == true
			APD::Logger.error e
			raise e
		end
	end

	def twt_stream_rules(opt={})
		rules = twt_req('/tweets/search/stream/rules')
		return nil if rules.nil? && opt[:allow_fail] == rue
		if rules['data'].nil?
			puts ['twt stream rules [0]'.ljust(24), 'tag'.ljust(24), 'value'.ljust(32)].join(' ')
			return []
		end
		puts ["twt stream rules [#{rules['data'].size}]".ljust(24), 'tag'.ljust(24), 'value'.ljust(32)].join(' ')
		rules['data'].each { |r| # contains 'id', 'tag', 'value'
			puts [r['id'].ljust(24), (r['tag'] || '---').ljust(24), r['value'].ljust(32)].join(' ')
		}
		rules['data']
	end

	def twt_stream_rule_set(rules, opt={})
		puts "Old twitter stream rules"
		old_rules = twt_stream_rules(opt)
		return nil if old_rules.nil? && opt[:allow_fail] == rue

		old_rule_values = old_rules.map { |r| {'value'=>r['value']} }
		delete_rules = (old_rule_values - rules).map { |r|
			# Find id from old_rules.
			id = old_rules.first { |r1| r1['value'] == r['value'] }['id']
			{ 'id' => id }
		}
		add_rules = rules - old_rule_values

		if delete_rules.size > 0
			body = { "delete" => { "ids" => delete_rules.map { |r| r['id'] } } }
			puts "Will post rule delete command"
			puts JSON.pretty_generate(body)
			res = twt_req('/tweets/search/stream/rules', method: :POST, args: body)
			return nil if res.nil? && opt[:allow_fail] == rue
		end
		if add_rules.size > 0
			body = { "add" => add_rules }
			puts "Will post rule add command"
			puts JSON.pretty_generate(body)
			res = twt_req('/tweets/search/stream/rules', method: :POST, args: body)
			return nil if res.nil? && opt[:allow_fail] == rue
		end
		true
	end

	def twt_stream(opt={})
		debug = opt[:debug] == true
		debug_dir = './debug/tweets/'
		FileUtils.mkdir_p debug_dir if debug

		# Add or remove values from the optional parameters below. Full list of parameters can be found in the docs:
		# https://developer.twitter.com/en/docs/twitter-api/tweets/filtered-stream/api-reference/get-tweets-search-stream
		params = {
			"expansions": "author_id,entities.mentions.username,in_reply_to_user_id,referenced_tweets.id,referenced_tweets.id.author_id",
			"tweet.fields": "attachments,author_id,conversation_id,created_at,entities,id,in_reply_to_user_id,lang",
			# "expansions": "attachments.poll_ids,attachments.media_keys,author_id,entities.mentions.username,geo.place_id,in_reply_to_user_id,referenced_tweets.id,referenced_tweets.id.author_id",
			# "tweet.fields": "attachments,author_id,conversation_id,created_at,entities,geo,id,in_reply_to_user_id,lang",
			# "user.fields": "description",
			# "media.fields": "url", 
			# "place.fields": "country_code",
			# "poll.fields": "options"
		}
		options = {
			timeout: 0,
			method: 'get',
			headers: {
				"User-Agent": "v2FilteredStreamRuby",
				"Authorization": "Bearer #{twt_get_token()}"
			},
			params: params
		}

		stream_url = "https://api.twitter.com/2/tweets/search/stream"
		req = @_twt_stream_request = Typhoeus::Request.new(stream_url, options)
		req.on_body do |chunk|
			next if chunk.strip.empty?
			t = nil
			begin
				t = TweetV2.new(JSON.parse(chunk))
			rescue
				print "Discard corrupted twitter stream chunk:\n#{chunk.inspect}\n".red
				next
			end
			no_complain {
				File.open("#{debug_dir}/#{t.id}", "w") { |f| f.write(JSON.pretty_generate(t.json)) }
			} if debug
			next(yield(t)) if block_given?
			print "#{'.'*40}\n#{t.to_s}\n" if debug
		end
		req.run
	end

	def twt_format_tweet_json(json)
		TweetV2.new(json).to_s
	end

	def twt_test
# 		puts TweetV2.new(File.read('./debug/tweets/1297370148072853504')).to_s
# 		return
		ret = twt_stream_rule_set([
			{"value" => "farm finance"},
			{"value" => "farming"},
			{"value" => "defi"}
		])
# 		twt_stream_rules()
		twt_stream(debug:true)
	end
end
