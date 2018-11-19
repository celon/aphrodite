require 'mail'
require 'optparse'
require 'optparse/time'
require 'ostruct'

class MailTask
	def self.email_plain(receiver, subject, content='EMPTY', bcc = nil, opt={})
		hostname = ENV['HOSTNAME'] || abort("No ENV variable HOSTNAME")
		author = (opt[:from] || "Automator <automator@#{hostname}>")
		content ||= ""
		content += File.read(opt[:html_file]) unless opt[:html_file].nil?
		puts "email_plain #{author} -> #{receiver} | #{subject} | content:#{content.size} attachment:#{opt[:file] != nil}"
		content = 'NO CONTENT' if content.empty?
		Mail.deliver do
			to      receiver
			from    author
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

	def self.email_mailgun(receiver, subject, content='EMPTY', bcc = nil, opt={})
		require 'mailgun'
		mailgun_key = ENV['MAILGUN_KEY'] || abort("No variable MAILGUN_KEY")
		mailgun_site = ENV['MAILGUN_SITE'] || abort("No variable MAILGUN_SITE")
		mg_client = Mailgun::Client.new mailgun_key
		mb_obj = Mailgun::MessageBuilder.new()
		# Define the from address
		if opt[:shown_name].nil?
			mb_obj.from("automator@#{mailgun_site}")
		else
			mb_obj.from("automator@#{mailgun_site}", {"first"=>opt[:shown_name]})
		end
		# Define a to recipient
		receiver.split(',').each do |addr|
			mb_obj.add_recipient(:to, addr.strip)
		end
		if bcc != nil
			bcc.split(',').each do |addr|
				mb_obj.add_recipient(:bcc, addr.strip)
			end
		end
		# mb_obj.add_recipient(:cc, cc_addr)
		# Define the subject
		mb_obj.subject(subject || '')
		html = nil
		html = File.read(opt[:html_file]) unless opt[:html_file].nil?
		html = opt[:html] unless opt[:html].nil?
		mb_obj.body_html(html) unless html.nil?
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
			files.each do |f| # Attach a file and rename it.
				mb_obj.add_attachment f, File.basename(f)
			end
		end
		# Need at least one of 'text' or 'html' parameters specified
		content = 'NO CONTENT' if html.nil? && content.nil?
		mb_obj.set_text_body(content) unless content.nil?
		puts "email -> #{receiver} | #{subject} | content:#{(content||'').size} | html:#{(html||'').size} attachment:#{opt[:file] != nil}"

		# Schedule message in the future
		# mb_obj.set_delivery_time("tomorrow 8:00AM", "PST");

		# Finally, send your message using the client
		puts "Communicating with Mailgun."
		result = mg_client.send_message(mailgun_site, mb_obj)
		puts result.body
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
	
		opts.on("-z", "--mailgun", "true/false") do |v|
			options[:mailgun] = v
		end
	end.parse!

	abort "Subject missed, abort sending email" if options[:subject].nil?
	abort "Recipients missed, abort sending email" if options[:recipients].nil?
	if options[:mailgun] == true
		MailTask.email_mailgun(
			options[:recipients],
			options[:subject],
			nil,
			nil,
			html_file:options[:html_file],
			file:options[:attachment],
			from:options[:sender]
		)
	else
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
end
