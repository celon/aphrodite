# require_relative './conf/config'
# Should load config before this file.

require 'rubygems'
require 'bundler/setup'

def require_try(lib)
	begin
		require lib
	rescue LoadError => e
		puts "Fail to load [#{lib}], skip."
	end
end

def require_anyof(*libs)
	success = false
	error = nil
	libs.each do |lib|
		begin
			require lib
			success = true
			break
		rescue LoadError => e
			error = e
			puts "Fail to load [#{lib}], try optional choice."
			next
		end
	end
	raise error unless success
end

require_anyof 'bunny', 'march_hare'
require_try 'mysql2'

require 'uri'
require 'open-uri'
require 'date'
require 'redis'
require 'nokogiri'
require "mysql"
require 'logger'
require 'colorize'
require 'json'
require 'base64'

# Load refinement and utility before regular files.
require_relative './refine'
require_relative './util'

Dir["#{File.dirname(__FILE__)}/*.rb"].each { |f| require f }
