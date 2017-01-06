module FileUtil
	def tail(file, opt={})
		verbose = opt[:verbose] == true
		sleep_interval = opt[:interval] || 0.1
	
		f = nil
		begin
			f = File.open(file,"r")
			# seek to the end of the most recent entry
	# 		f.seek(0,IO::SEEK_END)
		rescue Errno::ENOENT
			sleep sleep_interval
			retry
		end
	
		ct = 0
		loop do
			select([f])
			line = f.gets
			if line.nil? || line.size == 0
				sleep sleep_interval
				next
			end
			ret = yield line.strip if block_given?
			puts "#{ct.to_s.ljust(5)}: #{line}" if verbose
			ct += 1
			break if ret == false
		end
	end
end
