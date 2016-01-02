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
			include APD::SpiderUtil
			include APD::EncodeUtil
			include APD::CacheUtil
			include APD::MQUtil
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
		[false, true].each do |mq_mode|
		[false, true].each do |thread_mode|
		[1, 10, 200].each do |prefetch_num|
			@instance.mq_connect march_hare:mq_mode
			@instance.mq_createq 'test'
			# Clear queue first.
			@instance.mq_consume('test', exitOnEmpty:true, silent:true)
			data = { 'x' => 'y' }
			total_ct = 1000
			total_ct.times { @instance.mq_push 'test', data.to_json }
			ct = 0
			threads = []
			t1 = @instance.mq_consume('test', prefetch_num:prefetch_num, thread:thread_mode, exitOnEmpty:true, silent:true) do |d, dao|
				ct += 1
				assert_equal d, data
			end
			threads.push t1
			if thread_mode
				threads.each { |t| t.join }
			end
			assert_equal total_ct, ct, "mq_mode:#{mq_mode}, thread_mode:#{thread_mode}"
			@instance.mq_close
		end
		end
		end
	end
end

class TestDao < TestBoard
	def setup
		super
		@dao = APD::DynamicMysqlDao.new mysql2:false
		@dao2 = APD::DynamicMysqlDao.new mysql2:true
		assert @dao2.mysql2_enabled? if RUBY_ENGINE != 'jruby'
 		@daos = [@dao, @dao2]
	end

	def test_dao
		@daos.each do |dao|
			# Create test table.
			create_table_sql = <<SQL
			CREATE TABLE `test_dao` (
				`tid` bigint(20) NOT NULL,
				`price` double(16,8) NOT NULL,
				`amount` double(16,8) NOT NULL,
				`type` tinyint(2) NOT NULL,
				PRIMARY KEY (`tid`)
			) ENGINE=`InnoDB` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT=COMPACT CHECKSUM=0 DELAY_KEY_WRITE=0;
SQL
			dao.query 'DROP TABLE IF EXISTS test_dao;'
			dao.query create_table_sql
			assert dao.list_tables.include?('test_dao')
			assert dao.dbclient_query('show processlist') != nil

			# Test writing new record.
			clazz = dao.getClass 'test_dao'
			data = clazz.new tid:1, price:2.2, amount:3.3, type:1
			dao.saveObj data
			all_data = dao.queryObjs 'test_dao'
			assert_equal all_data.size, 1
			assert_equal all_data[0].tid, 1
			assert_equal all_data[0].price, 2.2
			assert_equal all_data[0].amount, 3.3
			assert_equal all_data[0].type, 1
			# Pack and parse.
			data = clazz.new data.to_hash
			# Test updating record.
			data.price = 4.4
			data.save true
			all_data = dao.queryObjs 'test_dao'
			assert_equal all_data.size, 1
			assert_equal all_data[0].tid, 1
			assert_equal all_data[0].price, 4.4
			assert_equal all_data[0].amount, 3.3
			assert_equal all_data[0].type, 1

			@dao.query 'DROP TABLE IF EXISTS test_dao;'
			assert (dao.list_tables.include?('test_dao') == false)
		end
	end

	def teardown
		super
		@daos.each { |d| d.close }
	end
end

class TestJSONObj < TestBoard
	def test_jsonobj
		j = APD::JSONObject.new
		j['a'] = 'xxyy'
		assert_equal j.a, 'xxyy'
		assert_equal j.a, j['a']
		j.b = j
		assert_equal j['b'], j
		assert_equal j['b'].a, 'xxyy'
		assert_equal j.b.a, 'xxyy'
		j.c = true
		assert j['c']
		assert j.c
	end
end
