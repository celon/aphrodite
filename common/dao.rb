class MysqlDao
	include EncodeUtil
	include CacheUtil

	def initialize(opt={})
		@activeRecordPool = opt[:activeRecordPool]
		@mysql2_enabled = opt[:mysql2] == true
		if @mysql2_enabled && defined?(Mysql2).nil?
			Logger.warn "Can not load Mysql2 gem, switch back to mysql."
			@mysql2_enabled = false
		end
		@dbconn_mutex = Mutex.new
		@thread_safe = opt[:thread_safe] == true
		init_dbclient
	end

	def mysql2_enabled?
		@mysql2_enabled
	end

	def init_dbclient
		close
		unless @activeRecordPool.nil?
			@poolAdapter = @activeRecordPool.checkout
			@dbclient = @poolAdapter.raw_connection
			Logger.info "Checkout a conn from ActiveRecord pool."
			return
		end
		dbclient = nil
		while true do
			begin
				Logger.info "Initialize MySQL to #{DB_USER}@#{DB_HOST}"
				if @mysql2_enabled
					Logger.highlight "Use mysql2 lib."
					port = DB_PORT if defined? MysqlDao::DB_PORT
					dbclient = Mysql2::Client.new host: DB_HOST, port: port, username: DB_USER, password: DB_PSWD, database: DB_NAME, encoding: 'utf8', reconnect:true, as: :array
					break
				else
					dbclient = Mysql.init
					dbclient.options Mysql::SET_CHARSET_NAME, 'utf8'
					port = DB_PORT if defined? DB_PORT
					dbclient.real_connect(DB_HOST, DB_USER, DB_PSWD, DB_NAME, DB_PORT)
					break
				end
			rescue Exception
				errInfo = $!.message
				Logger.error ("Error in connecting DB, will retry:" + errInfo)
				sleep 2
			end
		end
		@dbclient = dbclient
	end

	def list_tables
		init_dbclient if @dbclient.nil?
		while true
			begin
				tables = []
				dbclient_query('show tables').each do |row|
					tables.push row[0]
				end
				return tables
			rescue => e
				if e.message == "MySQL server has gone away"
					Logger.info(e.message + ", retry.")
					sleep 1
					init_dbclient
					next
				end
				Logger.error "Error in listing tables."
				Logger.error e
				return -1
			end
		end
	end

	def dbclient_query(sql)
		return @dbclient.query(sql) unless @thread_safe == true
		@dbconn_mutex.lock
		ret = nil
		begin
			ret = @dbclient.query(sql)
		ensure
			@dbconn_mutex.unlock
		end
		ret
	end

	def query(sql, log = false)
		init_dbclient if @dbclient.nil?
		while true
			begin
				Logger.debug sql if log == true
				return dbclient_query(sql)
			rescue => e
				if e.message == "MySQL server has gone away"
					Logger.info(e.message + ", retry.")
					sleep 1
					init_dbclient
					next
				elsif e.message.start_with? "Duplicate entry "
					raise e
				end
				Logger.error "Error in querying sql:#{sql}"
				Logger.error e
				return -1
			end
		end
	end

	# Ret: 0:update, 1:insert, -1:error
	def insert_update(sqlInsert, sqlUpdate = nil, log = false)
		while true
			# Try insert, otherwise update.
			begin
				Logger.debug sqlInsert if log == true
				dbclient_query(sqlInsert)
				return 1
			rescue => e
				if e.message == "MySQL server has gone away"
					Logger.info(e.message + ", retry.")
					sleep 1
					init_dbclient
					next
				elsif e.message.start_with? "Duplicate entry "
					return 0 if sqlUpdate.nil?
					ret = query(sqlUpdate, log)
					return -1 if ret == -1
					return 0
				else
					Logger.error "Error in inserting sql:#{sqlInsert}"
					Logger.error e
					return -1
				end
			end
		end
	end

	def close
		if @activeRecordPool != nil
			unless @poolAdapter.nil?
				Logger.info "Checkin a conn from ActiveRecord pool."
				@activeRecordPool.checkin @poolAdapter
				@poolAdapter = nil
				@dbclient = nil
			end
			return
		end
		begin
			if @dbclient != nil
				Logger.info "Closing MySQL conn #{DB_USER}@#{DB_HOST}"
				@dbclient.close 
			end
		rescue => e
			Logger.error "Error in closing DB Conn."
			Logger.error e
		end
	end
end

# Should be automatically generated from MySQL table schema.
class DynamicMysqlObj
	extend EncodeUtil

	def setMysqlAttr(mysqlCol, val)
		send "#{self.class.mysqlCol2attrName(mysqlCol)}=", val
	end
	def getMysqlAttr(mysqlCol)
		send self.class.mysqlCol2attrName(mysqlCol)
	end

	def self.mysqlCol2attrName(col)
		snake2Camel(col)
	end
	def self.mysqlTable2className(table)
		snake2Camel(table, true)
	end

	def to_hash
		map = {}
		self.class.mysql_attrs.each do |col, type|
			name = self.class.mysqlCol2attrName(col)
			map[name] = getMysqlAttr col
		end
		map
	end

	def initialize(map = {})
		self.class.mysql_attrs.each do |col, type|
			# Set by attr name, check both in camel and snake pattern.
			# Check both in String and Symbol.
			val = map[col]
			val = map[col.to_sym] if val.nil?
			name = self.class.mysqlCol2attrName(col)
			val = map[name] if val.nil?
			val = map[name.to_sym] if val.nil?
			# Abort if still miss.
			next if val.nil?
			setMysqlAttr col, val
		end
	end

	def to_json(*args)
		to_hash.to_json
	end

	def to_s
		to_hash.to_s
	end

	def save(update = false)
		Logger.highlight "WARNING: DynamicMysqlObj.save is not thread-safe." if Thread.current != Thread.main
		self.class.mysql_dao.saveObj self, update
	end

	def delete(real = false)
		Logger.highlight "WARNING: DynamicMysqlObj.delete is not thread-safe." if Thread.current != Thread.main
		self.class.mysql_dao.deleteObj self, real
	end
end

class DynamicMysqlDao < MysqlDao
	include EncodeUtil
	using EncodeRefine

	MYSQL_TYPE_MAP = {
		:tinyint => :to_i,
		:smallint => :to_i,
		:mediumint => :to_i,
		:int => :to_i,
		:bigint => :to_i,
		:double => :to_f,
		:float => :to_f,
		:date => :to_datetime,
		:datetime => :to_datetime,
		:timestamp => :to_datetime,
		:char => :to_s,
		:varchar => :to_s,
		:text => :to_s,
		:mediumtext => :to_s,
		:base64 => :base64,
		:json => :json
	}

	MYSQL_CLASS_MAP = {}
	DYNAMIC_CLASS_GENERATE_LOCK = Mutex.new

	def getClass(table)
		return MYSQL_CLASS_MAP[table] unless MYSQL_CLASS_MAP[table].nil?
		DYNAMIC_CLASS_GENERATE_LOCK.lock
		ret = nil
		begin
			ret = getClass_int(table)
		ensure
			DYNAMIC_CLASS_GENERATE_LOCK.unlock
		end
		ret
	end

	def getClass_int(table)
		return MYSQL_CLASS_MAP[table] unless MYSQL_CLASS_MAP[table].nil?
		Logger.debug "Detecting table[#{table}] structure."
		selectSql = "SELECT "
		attrs = {}
		priAttrs = []
		query("SHOW FULL COLUMNS FROM #{table}").each do |name, type, c, n, key, d, e, p, comment|
			type = type.split('(')[0]
			selectSql << "#{name}, "
			attrs[name] = [type]
			unless comment.nil? or comment.empty?
				comment.split(',')[0].split('|').each do |t|
					attrs[name] << t.strip unless t.strip.empty?
				end
			end
			priAttrs << key if key == 'PRI'
			# Logger.debug "#{name.ljust(25)} => #{type.ljust(10)} c:#{comment} k:#{key}"
			throw Exception.new("Unsupported type[#{type}], fitStructure failed.") if MYSQL_TYPE_MAP[type.to_sym].nil?
		end

		className = DynamicMysqlObj.mysqlTable2className table
		if Object.const_defined? className
			className = "#{className}Daobj"
			if Object.const_defined? className
				throw Exception.new("Cannot generate class #{className}, const conflict.") if Object.const_defined? className
			else
				Logger.highlight "Generate class #{className} instead, because const conflict."
			end
		end
		Logger.debug "Generate class[#{className}] for #{table}"
		# Prepare attr_accessor
		attrCode = ""
		attrs.keys.each { |a| attrCode << ":#{DynamicMysqlObj.mysqlCol2attrName(a)}, " }
		attrCode = "attr_accessor #{attrCode}" unless attrCode.empty?
		attrCode.strip!
		attrCode = attrCode[0..-2] if attrCode.end_with? ','
		# Dynamic class generating.
		clazz = Class.new(DynamicMysqlObj) do
			eval attrCode
		end
		clazz.define_singleton_method :mysql_pri_attrs do priAttrs; end
		clazz.define_singleton_method :mysql_attrs do attrs; end
		clazz.define_singleton_method :mysql_table do table; end
		activeDao = self
		clazz.define_singleton_method :mysql_dao do activeDao; end
		MYSQL_CLASS_MAP[table] = clazz
		Object.const_set className, clazz
	end

	def mysqlStr2val(string, type)
		return nil if string.nil?
		return string.force_encoding("UTF-8") if type.empty?
		val = string
		# Extract from package.
		type.each do |t|
			method = MYSQL_TYPE_MAP[t.to_sym]
			throw Exception.new("Unsupport mysql type:#{type}") if method.nil?
			method = method.to_sym
			case method
			when :to_datetime
				val = DateTime.parse(val) if method == :to_datetime
			when :base64
				val = decode64 val
			when :json
				val = JSON.parse val.gsub("\n", "\\n").gsub("\r", "\\r")
			when :to_s
			else
				val = val.send method
			end
		end
		val = val.force_encoding("UTF-8") if val.is_a? String
		val
	end

	def val2mysqlStr(val, type)
		return 'NULL' if val.nil?
		return "'#{val}'" if type.empty?
		string = val
		# Pack in reverse order.
		type.reverse.each do |t|
			method = MYSQL_TYPE_MAP[t.to_sym]
			throw Exception.new("Unsupport mysql type:#{type}") if method.nil?
			method = method.to_sym
			case method
			when :to_datetime
				val = val.strftime '%Y%m%d%H%M%S'
			when :base64
				val = encode64 val
			when :json
				val = val.to_json
			when :to_s
			else
				val = val.to_s
			end
		end
		val = "'#{val}'" if val.is_a? String
		val
	end

	def queryObjs(table, whereClause = "")
		clazz = getClass table
		throw Exception.new("Cannot get class from table:#{table}") unless clazz.is_a? Class
		sql = "select "
		clazz.mysql_attrs.each { |name, type| sql << "#{name}, " }
		sql = "#{sql[0..-3]} from #{table} #{whereClause}"
		ret = []
		query(sql).each do |row|
			obj = clazz.new
			ct = 0
			clazz.mysql_attrs.each do |name, type|
				val = mysqlStr2val row[ct], type
				obj.setMysqlAttr name, val
				ct += 1
			end
			ret << obj
		end
		ret
	end

	def saveObjs(array, update = false)
		throw Exception.new("Only receive obj arrays.") unless array.is_a? Array
		array.each { |o| saveObj o, update }
	end

	def saveObj(obj, update = false)
		throw Exception.new("Only DynamicMysqlObj could be operated.") unless obj.is_a? DynamicMysqlObj
		sql = "INSERT INTO #{obj.class.mysql_table} SET "
		setSql = ""
		obj.class.mysql_attrs.each do |col, type|
			val = obj.getMysqlAttr col
			next if val.nil?
			setSql << "#{col}=#{val2mysqlStr(val, type)}, "
		end
		setSql = setSql[0..-3]
		sql << setSql
		sql << " ON DUPLICATE KEY UPDATE " << setSql if update
		query sql
	end

	def deleteObjs(array, real = false)
		throw Exception.new("Only receive obj arrays.") unless array.is_a? Array
		array.each { |o| deleteObj o, real }
	end

	def deleteObj(obj, real = false)
		throw Exception.new("Only DynamicMysqlObj could be operated.") unless obj.is_a? DynamicMysqlObj
		if real
			sql = "DELETE FROM #{obj.class.mysql_table} WHERE "
			attrSql = ""
			obj.class.mysql_attrs.each do |col, type|
				val = obj.getMysqlAttr col
				next if val.nil?
				attrSql << "#{col}=#{val2mysqlStr(val, type)} AND "
			end
			attrSql = attrSql[0..-6]
			sql << attrSql
			query sql
		else
			throw Exception.new("#{obj.class} do not contain column[deleted]") unless obj.respond_to? :deleted=
			return Logger.warn "obj is already marked as deleted." if obj.deleted
			obj.deleted = true
			saveObj obj, true
		end
	end

	def self.test
		dynDao = DynamicMysqlDao.new
		dynDao.list_tables.each do |t|
			o = dynDao.queryObjs(t, "limit 1")
			oldData = o.to_json
			next if o.empty?
			dynDao.saveObj o[0]
			o = dynDao.queryObjs(t, "limit 1")
			newData = o.to_json
			Logger.error "Failed\nOLD:#{oldData}\nNEW:#{newData}" if oldData != newData
		end
	end
end
