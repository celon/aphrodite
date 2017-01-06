require_relative '../conf/config'

gem 'minitest'
require 'minitest/autorun'
require 'openssl'

# Only if openssl is toooooold
# OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

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

class TestTwitter < TestBoard
	def setup
		super
		@target_class = Class.new do
			include APD::TwitterUtil
		end
		@instance = @target_class.new
	end

	def test_twitter
		begin
			@instance.twitter_api(:home_timeline, count:300).each_with_index do |t, i|
				puts i
				puts t.id
				puts t.full_text
			end
			assert true
		rescue Twitter::Error::Forbidden => e
			APD::Logger.info "Unable to verify twitter credentials, skip twitter test."
			assert true
		end
	end
end

class TestUtil < TestBoard
	def setup
		super
		@target_class = Class.new do
			include APD::SpiderUtil
			include APD::EncodeUtil
			include APD::LZString
			include APD::CacheUtil
			include APD::MQUtil
			def redis_db
				0
			end
		end
		@instance = @target_class.new
	end

	def test_spider_util
		@instance.parse_web 'https://www.yahoo.com'
		@instance.curl 'https://www.gnu.org/graphics/heckert_gnu.small.png', file:"#{@tmp_dir}/gnu.png"
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
		assert_equal 'FlyingCatIsHere', (@instance.to_camel 'flying_cat_is_here', true)
		assert_equal 'woofingDog', (@instance.to_camel 'woofing_dog', false)
		assert_equal 'flying_cat_is_here', (@instance.to_snake 'FlyingCatIsHere')
		assert_equal 'woofing_dog', (@instance.to_snake 'woofingDog')
		str = 'abcdefg'
		assert_equal str, @instance.decode64(@instance.encode64(str))
		assert_equal 'x', @instance.lz_decompressFromBase64('B5A=')
		assert_equal 'B5A=', @instance.lz_compressToBase64('x')
	end

	def test_cache_util
		assert (@instance.redis != nil)
	end

	def test_mq_util
		@dao = APD::DynamicMysqlDao.new mysql2:false
		[false, true].each do |mq_mode|
		[false, true].each do |thread_mode|
		[1, 10, 100].each do |prefetch_num|
			@instance.mq_connect march_hare:mq_mode
			@instance.mq_createq 'test'
			# Clear queue first.
			@instance.mq_consume('test', dao:@dao, exitOnEmpty:true, silent:true)
			data = { 'x' => 'y' }
			total_ct = 100
			total_ct.times do
				@instance.mq_push 'test', data.to_json
			end
			ct = 0
			threads = []
			t1 = @instance.mq_consume('test', dao:@dao, prefetch_num:prefetch_num, thread:thread_mode, exitOnEmpty:true, silent:true) do |d, dao|
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
				`bindata` longblob DEFAULT NULL COMMENT 'lazyload',
				`price` double(16,8) ,
				`amount` double(16,8) ,
				`type` tinyint(2) NOT NULL DEFAULT 9,
				PRIMARY KEY (`tid`)
			) ENGINE=`InnoDB` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ROW_FORMAT=COMPACT CHECKSUM=0 DELAY_KEY_WRITE=0;
SQL
			dao.query 'DROP TABLE IF EXISTS test_dao;'
			dao.query create_table_sql
			assert dao.list_tables.include?('test_dao')
			assert dao.dbclient_query('show processlist') != nil

			# Test writing new record.
			clazz = dao.get_class 'test_dao'
			assert_equal clazz, APD::TestDao_DB
			data = clazz.new tid:1, price:2.2, amount:3.3, type:nil, bindata:'this is bin data.'
			dao.save data
			# Read from db.
			all_data = dao.query_objs 'test_dao'
			assert_equal all_data.size, 1
			assert_equal all_data[0].tid, 1
			assert_equal all_data[0].price, 2.2
			assert_equal all_data[0].amount, 3.3
			# Check if set nil on attr that has default value.
			assert_equal all_data[0].type, 9
			# Lazyload attrs will be nil if set no_load.
			assert_equal all_data[0].bindata(no_load:true), nil
			# Save obj with lazy_attr not loaded yet, lazy attr should not be overwritten.
			all_data[0].save true
			all_data = dao.query_objs 'test_dao'
			# Lazyload attrs will be db value in normal invokation.
			assert_equal all_data[0].bindata, 'this is bin data.'
			# Overwrite attrs with NULL, check coinsistence.
			all_data[0].bindata = nil
			all_data[0].save true
			all_data = dao.query_objs 'test_dao'
			assert_equal all_data[0].bindata, nil
			# Overwrite attrs, check coinsistence.
			all_data[0].bindata = "Re-written data"
			all_data[0].save true
			all_data = dao.query_objs 'test_dao'
			assert_equal all_data[0].bindata, "Re-written data"
			# Read with omit option.
			begin
				all_data = dao.query_objs 'test_dao', omit_column:[:tid, :price]
			rescue => e
				assert e.message.start_with? 'Could not omit attr'
				assert e.message.end_with? 'because it is primary attribute.'
			end
			all_data = dao.query_objs 'test_dao', omit_column:[:amount, :price]
			assert_equal all_data.size, 1
			assert_equal all_data[0].tid, 1
			assert_equal all_data[0].price, nil
			assert_equal all_data[0].amount, nil
			assert_equal all_data[0].type, 9
			assert_equal all_data[0].bindata(no_load:true), nil
			assert_equal all_data[0].bindata, 'Re-written data'
			all_data[0].save true
			all_data = dao.query_objs 'test_dao'
			assert_equal all_data[0].price, 2.2
			assert_equal all_data[0].amount, 3.3

			# Pack and parse.
			data = clazz.new data.to_hash
			# Test updating record.
			data.price = 4.4
			data.save true
			all_data = dao.query_objs 'test_dao'
			assert_equal all_data.size, 1
			assert_equal all_data[0].tid, 1
			assert_equal all_data[0].price, 4.4
			assert_equal all_data[0].amount, 3.3
			assert_equal all_data[0].type, 9

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

class TestLockUtil < TestBoard
	def test_lock_util
		test_class = Class.new do
			include APD::LockUtil
			def f; end
			def f2; end
			def f3; end
			def f4; end
			thread_safe :f, :f2
			thread_safe :f3, :f4
		end

		c1 = test_class.new
		c1.f
		locks = c1.method_locks
		assert_equal locks[:f], locks[:f2]
		c1.f2
		new_locks = c1.method_locks
		assert_equal locks[:f], new_locks[:f]
		assert_equal locks[:f], new_locks[:f2]
		c1.f3
		locks = c1.method_locks
		assert (locks[:f3] != locks[:f]) 
		c1.f4
		assert (locks[:f3] != locks[:f]) 
		assert (locks[:f4] != locks[:f]) 
		assert_equal locks[:f3], new_locks[:f4]
		
		c2 = test_class.new
		c2.f
		new_locks = c2.method_locks
		assert (locks[:f] != new_locks[:f])
		assert_equal new_locks[:f], new_locks[:f2]
		c2.f2
		new_locks = c2.method_locks
		assert (locks[:f] != new_locks[:f])
		assert_equal new_locks[:f], new_locks[:f2]
	end
end
