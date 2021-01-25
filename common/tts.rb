module TTS
	# Count non-ascii chars in title and content.
	# Generate [[title], [paragraph]] to contain not more than correspond chars.
	# If title is given, all text would be used unless it is longer than (max title+max content)
	# If title is empty, try to get more words from content as title.
	# Support Chinese and English by delimiters.
	def decide_speech_text(title, content, max_title_chars, max_content_chars)
		total_chars = 0
		title_texts, content_texts = [], []
		finished = false
		title = (title || '').strip
		title_missing = title.strip.empty?
		title_sentences = title.split(/[。？\\n]/)
		title_sentences.each do |s|
			chars = s.chars.select { |c| c.ord > 256 }.size
			# Contain first sentence at least.
			if title_texts.empty?
				title_texts.push s
				total_chars += chars
			elsif total_chars + chars >= (max_title_chars + max_content_chars)
				break (finished = true)
			else
				title_texts.push s
				total_chars += chars
			end
		end
		return [title_texts, []] if finished

		# Contain text as much as possible.
		total_chars = 0
		content = (content || '').strip
		content.split(/[。？\\n]/).each do |paragraph|
			paraprah_sentences = paragraph.split(/[。？]./)
			paraprah_sentences.each do |s|
				chars = s.chars.select { |c| c.ord > 256 }.size
				if title_missing # Auto generate title.
					if total_chars + chars >= max_title_chars
						title_missing = false
						total_chars = 0
					end
					title_texts.push s
					total_chars += chars
				else
					break (finished = true) if total_chars + chars >= max_content_chars
					content_texts.push s
					total_chars += chars
				end
			end
			break if finished
		end
		return [title_texts, content_texts]
	end
end
