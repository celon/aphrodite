require_relative '../common/bootstrap'

class MailTask
	def self.email_plain(receiver, subject, content, bcc = nil, opt={})
		content ||= ""
		content += File.read(opt[:html_file]) unless opt[:html_file].nil?
		APD::Logger.info "email_plain -> #{receiver} | #{subject} | content:#{content.size} attachment:#{opt[:file] != nil}"
		Mail.deliver do
			to      receiver
			from    (opt[:from] || 'Automator <automator@noreply.com>')
			subject subject
			html_part do
				content_type 'text/html; charset=UTF-8'
				body content
			end
			unless opt[:file].nil?
				files = opt[:file]
				if files.is_a?(String)
					files = files.split(",")
					files = files.
						map { |f| f.strip }.
						select { |f| f.size > 0 }.
						uniq
				elsif files.is_a?(Array)
					files = files.uniq
				elsif files.nil?
					files = []
				else
					abort "Files class error: #{files.class}"
				end
				files.each do |f|
					add_file f
				end
			end
		end
	end
end

if __FILE__ == $0
	# Send email by arguments
	options = OpenStruct.new
	options.banner = "Usage: [-v] -f from -r recipients -s subject -h html_file [-a attachment] "
	OptionParser.new do |opts|
		opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
			options[:verbose] = v
		end
	
		opts.on("-f", "--from address", "Email sender") do |v|
			options[:sender] = v
		end
	
		opts.on("-r", "--recipient recipients", "Email receiver") do |v|
			options[:recipients] = v
		end
	
		opts.on("-s", "--subject subject", "Email subject") do |v|
			options[:subject] = v
		end
	
		opts.on("-h", "--html html-file", "Email content in HTML file") do |n|
			options[:html_file] = n
		end
	
		opts.on("-a", "--attachment file", "Attachment file") do |v|
			options[:attachment] = v
		end
	end.parse!
	puts options

	abort "Subject missed, abort sending email" if options[:subject].nil?
	abort "Recipients missed, abort sending email" if options[:recipients].nil?
	MailTask.email_plain(
		options[:recipients],
		options[:subject],
		nil,
		nil,
		html_file:options[:html_file],
		file:options[:attachment],
		from:options[:sender]
	)
end
