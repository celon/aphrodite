# require_relative './conf/config'
# Should load config before this file.

require 'rubygems'
require 'bundler/setup'

require 'uri'
require 'date'

require 'bunny'
require 'redis'
require 'nokogiri'
require "mysql"
require "mysql2"
require 'logger'
require 'colorize'
require 'json'

# Load refinement and utility before regular files.
require_relative './refine'
require_relative './util'

Dir["#{File.dirname(__FILE__)}/*.rb"].each { |f| require f }
