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

	# Ref: https://rdoc.info/gems/twitter/Twitter/REST
	def twitter_api(method_symbol, *args, &block)
		begin
			Timeout::timeout(120) do
	 			return _twitter.send(method_symbol, *args, *block)
			end
		rescue Timeout::Error => e
			APD::Logger.highlight "Time out, retry"
			retry
		rescue Twitter::Error::RequestEntityTooLarge => e
			APD::Logger.highlight "Time out, retry"
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

class Tweet
	[
		:id, :text, :lang,
		:retweet_count, :favorite_count
	].each { |k|
		define_method(k) { |*method_args, &method_block|
			self.instance_variable_get(:@attrs)[k]
		}
	}
	def initialize(t, opt={}) # Tweet from 
		if t.is_a?(Twitter::Tweet)
			@attrs = t.attrs
		elsif t.is_a?(Hash)
			@attrs = t
		else
			raise "Unrecognized tweet #{t.class}"
		end
		if opt[:media] != nil
			@attrs[:extended_entities] ||= {}
			@attrs[:extended_entities][:media] = opt[:media].map { |m| m.to_h }
		end
	end

	def to_h
		@attrs
	end

	def url
		"https://twitter.com/#{user.screen_name}/status/#{id}"
	end

	def is_rt?
		@attrs[:retweeted_status] != nil
	end

	def retweeted_tweet
		orig = @attrs[:retweeted_status]
		return nil if orig.nil?
		medias = media_list()
		if medias.empty?
			return Tweet.new(orig)
		else # retweeted_status has no media info anymore.
			return Tweet.new(orig, media:media_list)
		end
	end

	def has_quoted?
		@attrs[:quoted_status] != nil
	end

	def quoted_tweet
		orig = @attrs[:quoted_status]
		return nil if orig.nil?
		return Tweet.new(orig)
	end

	def created_at
		if @created_at.nil?
			@created_at = DateTime.parse(@attrs[:created_at])
		end
		@created_at
	end

	def hashtags
		@attrs[:entities][:hashtags] || []
	end

	def user_mentions
		@attrs[:entities][:user_mentions] || []
	end

	def user
		TwitterUser.new(@attrs[:user])
	end

	def media_list
		ext_media = @attrs.dig(:extended_entities, :media)
		media = @attrs.dig(:entities, :media)
		return [] if ext_media.nil? && media.nil?
		(ext_media || media).map { |m| TwitterMedia.new(m) }
	end

	def to_s(prefix='', color=nil)
		# time user:
		# text (If is not RT)
		# [media list]
		s = "#{prefix}#{url}"
		if is_rt?
			s = s + "\n#{prefix}#{created_at} #{user} RT:"
		else
			s = s + "\n#{prefix}#{created_at} #{user}:\n#{' '*(prefix.size)}#{text}"
			media_list.each { |m|
				s = s + "\n#{' '*(prefix.size)}[#{m}]"
			}
		end
		s = s.send(color) if color != nil
		if is_rt?
			s = s + "\n" + retweeted_tweet.to_s(prefix + '     ', :blue)
		elsif has_quoted?
			s = s + "\n" + quoted_tweet.to_s(prefix + '  Qt:', :green)
		end
		s
	end

	# Translate content into HTML, expand URLs
	def text_to_html
		t = text()
		(@attrs.dig(:entities, :urls) || []).each { |url_info|
			t = t.gsub(
				url_info[:url],
				"<a href='#{url_info[:expanded_url]}'>#{url_info[:display_url]}</a>"
			)
		}
		"<div> #{t} </div>"
	end

	# Render tweet in HTML, expand URLs and append medias.
	def to_html(opt={})
		full_html = opt[:full_html] == true
		html = <<HTML
<div>
	<a href='#{url}'>#{created_at}</a>
	#{user.to_html}
HTML
		body = <<BODY
	#{text_to_html}
	#{media_list.map { |m| m.to_html }.join}
BODY
	if is_rt?
		html = html + " Retweet : <br>\n" + retweeted_tweet.to_html
	elsif has_quoted?
		html = html + body + " Quote : <br>\n" + quoted_tweet.to_html
	else
		html = html + body
	end
	html += "\n</div>"
	if full_html
		html = <<FULL
<html><head>
		<meta charset='UTF-8'>
	</head>
	<body>
	#{html}
	</body>
</html>
FULL
	end
	html
	end
end

class TwitterUser
	[
		:id, :name, :screen_name,
		:description, :url,
		:followers_count, :verified,
		:profile_image_url_https
	].each { |k|
		define_method(k) { |*method_args, &method_block|
			self.instance_variable_get(:@user)[k]
		}
	}
	def initialize(u)
		if u.is_a?(Hash)
			@user = u
		else
			raise "Unrecognized user #{u.class}"
		end
	end

	def to_h
		@user
	end

	def to_s
		"#{screen_name}[#{name}]"
	end

	def to_html
		html = <<HTML
<span>
	<a href="https://twitter.com/#{screen_name}/" />
		#{screen_name} [#{name}] 
		<img src=#{profile_image_url_https} />
	</a>
</span>
HTML
	end
end

class TwitterMedia
	attr_reader :size, :content_type, :url
	[:id, :type].each { |k|
		define_method(k) { |*method_args, &method_block|
			self.instance_variable_get(:@m)[k]
		}
	}
	def initialize(m)
		@m = m
		if is_photo?
			@size = @m[:sizes][:large]
			@content_type = 'photo'
			@url = @m[:media_url_https]
		elsif is_video?
			@size = @m[:sizes][:large]
			res = @m[:video_info][:variants].
				sort_by { |v| v['bitrate'] }.last
			@content_type = res[:content_type]
			@url = res[:url]
		else
			raise "Unknown media type #{m}"
		end
	end

	def to_h
		@m
	end

	def is_photo?
		type == 'photo'
	end

	def is_video?
		type == 'video' || type == 'animated_gif'
	end

	def to_s
		if is_photo?
			"Photo #{size[:w]}x#{size[:h]} #{url}"
		elsif is_video?
			"#{content_type} #{size[:w]}x#{size[:h]} #{url}"
		else
			"UNKNOWN twitter media #{m}"
		end
	end

	def to_html
		if is_photo?
			html = <<HTML
	<img src="#{url}" "/>
HTML
		elsif is_video?
			html = <<HTML
<video controls>
	<source src="#{url}" type="#{content_type}">
	Your browser does not support the video tag.
</video>
HTML
		else
			"UNKNOWN twitter media #{m}"
		end
	end
end
