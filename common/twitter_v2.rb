#####################################################################
# class TweetV2:
#   API V2 tweet json parser.
# class TwitterMonitor:
#   A statistic tool based on live data of API V2 search/stream.
# module TwitterAPIV2:
#   API V2 wrapper with connection pool and auto authentication.
#####################################################################
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
		_parse_all()
		tags = @hashtags + @cashtags
		[
			@ref_tweet_retweeted,
			@ref_tweet_quoted,
			@ref_tweet_replied_to
		].each { |tweet|
			tweet = _tweet_by_id(tweet)
			tags += tweet.all_tags if tweet != nil
		}
		tags
	end

	# URLs and also from retweeted/quoted/replied_to tweets
	def all_urls
		_parse_all()
		tags = @urls
		[
			@ref_tweet_retweeted,
			@ref_tweet_quoted,
			@ref_tweet_replied_to
		].each { |tweet|
			tweet = _tweet_by_id(tweet)
			tags += tweet.all_urls if tweet != nil
		}
		tags
	end

	def untaint_text
		_render()
		@untaint_text
	end

	def rendered_text
		_render()
		@rendered_text
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

		rendered_text = @text
		untaint_text = @text # Those not included in any entity
		footnotes = []
		# Render hashtags and urls in @text, from last to first.
		@entities.sort_by { |a| a['start'] }.reverse.each { |a|
			s, e = a['start'], a['end']
			str_before = ''
			str_before = rendered_text[0..(s-1)] if s > 0
			str_include = rendered_text[s..(e-1)] || ''
			str_after = rendered_text[e..-1] || ''
			untaint_text = str_before + (untaint_text[e..-1] || '') # Remove text.

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
		@rendered_text = rendered_text.gsub(/(\n|\r)/, ' ').gsub(/\s{2,}/, ' ').strip
		@untaint_text = untaint_text.gsub(/(\n|\r)/, ' ').gsub(/\s{2,}/, ' ').strip
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

class TwitterMonitor
	def initialize(opt={})
		dir = opt[:dir] || '.'
		@valid_seconds = opt[:valid_seconds] || 7*24*3600 # 1 week by default.
		FileUtils.mkdir_p("#{dir}/tmp")
		@status_f = "#{dir}/tmp/monitor.twitter.status"
		if File.file?(@status_f)
			# load_state
			state = JSON.parse(File.read(@status_f))
			@tag_stat = state[0]
			@url_stat = state[1]
		else
			@tag_stat = {}
			@url_stat = {}
		end
		@ignore_tags = {}
		@known_tags = {}
		@block_tags = {}
	end

	def save_state
		puts "saving status"
		File.open(@status_f, 'w') { |f|
			f.write(JSON.pretty_generate([
				@tag_stat,
				@url_stat
			]))
		}
	end

	def set_block_tags(tags={})
		if tags.is_a?(Hash)
			@block_tags = tags
		elsif tags.is_a?(Array)
			@block_tags = tags.map { |t|
				[t.upcase, 1]
			}.to_h
		end
		@block_tags.keys.each { |t|
			@tag_stat.delete(t)
		}
		self
	end

	def set_ignore_tags(tags={})
		if tags.is_a?(Hash)
			@ignore_tags = tags
		elsif tags.is_a?(Array)
			@ignore_tags = tags.map { |t|
				[t.upcase, 1]
			}.to_h
		end
		@ignore_tags.keys.each { |t|
			@tag_stat.delete(t)
		}
		self
	end

	def set_known_tags(tags={})
		if tags.is_a?(Hash)
			@known_tags = tags
		elsif tags.is_a?(Array)
			@known_tags = tags.map { |t|
				[t.upcase, 1]
			}.to_h
		end
		self
	end

	def set_merge_tags(map)
		@merge_tags = map
		if map != nil
			map.each { |old_tag, new_tag|
				next if @tag_stat[old_tag].nil?
				# Migration
				if @tag_stat[new_tag].nil?
					@tag_stat[new_tag] = @tag_stat.delete(old_tag)
				else
					# Merge
					# 'records' => [[t, data]]
					# 'stat' => { 'ct' => 0 }
					old_stat = @tag_stat.delete(old_tag)
					new_stat = @tag_stat[new_tag]
					new_stat['records'] = (new_stat['records'] + old_stat['records']).sort_by { |r| r[0] }
					new_stat['stat']['ct'] = new_stat['stat']['ct'] + old_stat['stat']['ct']
				end
			}
		end
		self
	end

	def watch
		trap("SIGINT") {
			# print("\033[0;0H#{"Exiting after saving status"}")
			print("Exiting after saving status")
			save_state
			exit
		}
		ct = 0
		twt_filter_stream() { |tweet|
			# Block tweet contains any blocked_tag
			blocked_tag = tweet.all_tags.find { |tag|
				@block_tags[tag['tag'].upcase] != nil
			}
			if blocked_tag != nil
				print "BLOCKED because: \##{blocked_tag['tag']} #{@block_tags[blocked_tag['tag']]}\n".red
				next
			end

			# Block tweet that contains entities only.
			if tweet.untaint_text.size <= 1
				print "BLOCKED because of no info: #{tweet.rendered_text}\n".red
				next
			end

			stat(tweet)
			# print "\033[0;0H"
			print "\n#{'-'*40}\n#{tweet}\n"
			# print_stat()
			ct += 1
			save_state() if ct % 10 == 0
		}
	end

	def print_stat
		ct = 0
		tag_info = []
		max_tag_ct = nil
		@tag_stat.each { |tag, info|
			c = info['stat']['ct']
			max_tag_ct ||= c
			if @known_tags[tag].nil?
				s = "#{tag.yellow} #{info['stat']['ct']}"
			else
				s = "#{tag} #{info['stat']['ct']}"
			end
			tag_info.push s
			ct += 1
			break if c < max_tag_ct/61.8
		}
		str = tag_info.join(" ")
		print "\n#{str}\n"
	end

	def stat(tweet)
		now = Time.now.to_f
		tweet.all_tags.each { |tag|
			tag = tag['tag'].upcase
			next if @ignore_tags[tag] != nil
			if @merge_tags != nil && @merge_tags[tag] != nil
				tag = @merge_tags[tag] # Mapping to other tag.
			end
			_stat(now, @tag_stat, tag, tweet.id)
		}
		tweet.all_urls.each { |url|
			url = (url['unwound_url'] || url['display_url']).downcase
			_stat(now, @url_stat, url, tweet.id)
		}
		@tag_stat = sort_stat_by_ct(@tag_stat)
		@url_stat = sort_stat_by_ct(@url_stat)
	end

	def _stat(t, stat_map, data, tweet_id)
		stat_map[data] ||= {
			'records' => [],
			'stat' => { 'ct' => 0 }
		}
		ct = stat_map[data]['stat']['ct']

		# Keep records in @valid_seconds
		oldest_info = nil
		records = stat_map[data]['records']
		loop {
			oldest_info = records.first # t, data
			break if oldest_info.nil?
			break if t - oldest_info[0] <= @valid_seconds
			records.shift
			ct -= 1
		}
		records.push([t, tweet_id])
		ct += 1

		stat_map[data]['stat']['ct'] = ct
	end

	def sort_stat_by_ct(stat_map)
		stat_map.to_a.sort_by { |tag, info|
			info.dig('stat', 'ct') || 0
		}.reverse.to_h
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
		@_twt_consumer_key ||= raise("No TWITTER_BEARER_TOKEN, TWITTER_CONSUMER_KEY or TWITTER_KEY set in ENV")
		@_twt_consumer_sec ||= TWITTER_CONSUMER_SECRET if (defined? TWITTER_CONSUMER_SECRET)
		@_twt_consumer_sec ||= ENV['TWITTER_CONSUMER_SECRET']
		@_twt_consumer_sec ||= ENV['TWITTER_SEC']
		@_twt_consumer_sec ||= raise("No TWITTER_BEARER_TOKEN, TWITTER_CONSUMER_SECRET or TWITTER_SET set in ENV")
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

	def twt_filter_stream(opt={})
		_twt_stream("https://api.twitter.com/2/tweets/search/stream", opt)
	end

	def twt_sample_stream(opt={})
		_twt_stream("https://api.twitter.com/2/tweets/sample/stream", opt)
	end

	def _twt_stream(stream_url, opt={})
		debug = opt[:debug] == true
		debug_dir = './debug/tweets/'
		FileUtils.mkdir_p debug_dir if debug

		# Add or remove values from the optional parameters below. Full list of parameters can be found in the docs:
		# https://developer.twitter.com/en/docs/twitter-api/tweets/filtered-stream/api-reference/get-tweets-search-stream
		params = opt[:params] || {
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

		req = @_twt_stream_request = Typhoeus::Request.new(stream_url, options)
		buffer = nil
		req.on_body do |chunk|
			next if chunk.strip.empty?
			t = nil
			begin
				t = TweetV2.new(JSON.parse(chunk))
				buffer = nil
			rescue
				if buffer != nil # Merge with buffer and try again.
					begin
						t = TweetV2.new(JSON.parse(buffer + chunk))
						buffer = nil
					rescue # Failed again, append chunk to buffer.
						print "Append more chunk to buffer:\n#{chunk}\n".red if debug
						buffer = buffer + chunk
						next
					end
				else
					buffer = chunk
					print "Set chunk to buffer:\n#{chunk}\n".red if debug
					next
				end
			end
			no_complain {
				File.open("#{debug_dir}/#{t.id}", "w") { |f| f.write(JSON.pretty_generate(t.json)) }
			} if debug
			next(yield(t)) if block_given?
			print "#{'.'*40}\n#{t.to_s}\n"
		end
		req.run
	end

	def twt_format_tweet_json(json)
		TweetV2.new(json).to_s
	end

	def twt_example
		twt_stream_rules()
		puts "Above are currently rules for search stream."
		puts "Stream samples now"
		twt_sample_stream()
	end
end
