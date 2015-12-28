require_relative '../conf/config'

gem 'minitest'
require 'minitest/autorun'

class TestBoard < Minitest::Test
	def setup
		require_relative '../../common/bootstrap'
		@tmp_dir = "#{File.dirname(__FILE__)}/../tmp"
		@res_dir = "#{File.dirname(__FILE__)}/../res"
		FileUtils.mkdir_p @tmp_dir
	end

	def compare_test_file(filename)
		FileUtils.compare_file "#{@tmp_dir}/#{filename}", "#{@res_dir}/#{filename}"
	end
end

class TestUtil < TestBoard
	def setup
		super
		@target_class = Class.new do
			include SpiderUtil
			include EncodeUtil
			include CacheUtil
			include MQUtil
		end
		@instance = @target_class.new
	end

	def test_spider_util
		@instance.parse_web 'https://www.yahoo.com'
		@instance.download 'https://www.gnu.org/graphics/heckert_gnu.small.png', "#{@tmp_dir}/gnu.png"
		begin
			@instance.download 'https://xxxxxxxx/xxx.png', "#{@tmp_dir}/err.png", 2
			assert false
		rescue => e
			# Should be here.
			assert true
		end
		assert compare_test_file('gnu.png')
	end

	def test_encode_util
		assert_equal 'FlyingCatIsHere', (@instance.snake2Camel 'flying_cat_is_here', true)
		assert_equal 'woofingDog', (@instance.snake2Camel 'woofing_dog', false)
		assert_equal 'flying_cat_is_here', (@instance.camel2Snake 'FlyingCatIsHere')
		assert_equal 'woofing_dog', (@instance.camel2Snake 'woofingDog')
		str = 'abcdefg'
		assert_equal str, @instance.decode64(@instance.encode64(str))
	end

	def test_cache_util
		assert (@instance.redis != nil)
	end

	def test_mq_util
		[true, false].each do |mode|
			@instance.mq_connect march_hare:mode
			@instance.mq_createq 'test'
			# Clear queue first.
			@instance.mq_consume('test', exitOnEmpty:true, silent:true)
			data = { 'x' => 'y' }
			total_ct = 1000
			total_ct.times { @instance.mq_push 'test', data.to_json }
			ct = 0
			@instance.mq_consume('test', exitOnEmpty:true, silent:true) do |d, dao|
				ct += 1
				assert_equal d, data
			end
			assert_equal ct, total_ct
			@instance.mq_close
		end
	end
end

class TestDao < TestBoard
	def setup
		super
		@dao = DynamicMysqlDao.new mysql2:false
		@dao2 = DynamicMysqlDao.new mysql2:true
		assert @dao2.mysql2_enabled? if RUBY_ENGINE != 'jruby'
 		@daos = [@dao, @dao2]
	end

	def test_dao
		@daos.each do |dao|
			assert dao.list_tables != nil
			assert dao.dbclient_query('show processlist') != nil
		end
	end

	def teardown
		super
		@daos.each { |d| d.close }
	end
end
