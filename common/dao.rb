class MysqlDao
	include EncodeUtil
	include CacheUtil

	attr_reader :thread_safe

	def initialize(opt={})
		@activeRecordPool = opt[:activeRecordPool]
		@mysql2_enabled = opt[:mysql2] == true
		if @mysql2_enabled && defined?(Mysql2).nil?
			Logger.warn "Can not load Mysql2 gem, switch back to mysql."
			@mysql2_enabled = false
		end
		@thread_safe = opt[:thread_safe] == true
		if @thread_safe == true
			Logger.warn "Dao runs in thread_safe mode, performance will be decreased."
			self.singleton_class.class_eval do
				include LockUtil
				thread_safe :dbclient_query, :close
				thread_safe :init_dbclient
			end
		end
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
		@dbclient.query(sql)
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
	include LockUtil

	# Record any un-read columns.
	attr_accessor :unload_columns

	def mysql_attr_set(mysqlCol, val)
		send "#{self.class.mysql_col_to_attr_name(mysqlCol)}=", val
	end
	def mysql_attr_get(mysqlCol)
		send self.class.mysql_col_to_attr_name(mysqlCol)
	end

	def self.mysql_col_to_attr_name(col)
		to_snake(col)
	end

	def self.mysql_tab_to_class_name(table)
		to_camel(table, true)
	end

	def to_hash
		map = {}
		self.class.mysql_attrs.each do |col, type|
			name = self.class.mysql_col_to_attr_name(col)
			map[name] = mysql_attr_get col
		end
		map
	end

	def initialize(map = {})
		self.class.mysql_attrs.each do |col, type|
			# Set by attr name, check both in camel and snake pattern.
			# Check both in String and Symbol.
			val = map[col]
			val = map[col.to_sym] if val.nil?
			name = self.class.mysql_col_to_attr_name(col)
			val = map[name] if val.nil?
			val = map[name.to_sym] if val.nil?
			name2 = to_camel(col)
			val = map[name2] if val.nil?
			val = map[name2.to_sym] if val.nil?
			# Abort if still miss.
			next if val.nil?
			mysql_attr_set col, val
		end
	end

	def to_json(*args)
		to_hash.to_json
	end

	def to_s
		to_hash.to_s
	end

	def save(update = false)
		self.class.mysql_dao.save self, update
	end

	def delete(real = false)
		self.class.mysql_dao.delete_obj self, real
	end
end

class DynamicMysqlDao < MysqlDao
	include EncodeUtil
	include LockUtil
	using EncodeRefine

	MYSQL_TYPE_MAP = {
		:tinyint	=> :to_i,
		:smallint	=> :to_i,
		:mediumint	=> :to_i,
		:int	=> :to_i,
		:bigint	=> :to_i,
		:double	=> :to_f,
		:float	=> :to_f,
		:date	=> :to_datetime,
		:datetime	=> :to_datetime,
		:timestamp	=> :to_datetime,
		:char	=> :to_s,
		:varchar	=> :to_s,
		:tinytext	=> :to_s,
		:text	=> :to_s,
		:mediumtext	=> :to_s,
		:longtext	=> :to_s,
		:base64	=> :base64,
		:json	=> :json,
		:tinyblob	=> :bin,
		:blob	=> :bin,
		:mediumblob	=> :bin,
		:longblob	=> :bin
	}

	MYSQL_CLASS_MAP = {}

	def get_class(table)
		return MYSQL_CLASS_MAP[table] unless MYSQL_CLASS_MAP[table].nil?
		Logger.debug "Detecting table[#{table}] structure."
		selectSql = "SELECT "
		attrs = {}
		attrs_info = {}
		lazy_attrs, pri_attrs = {}, []
		query("SHOW FULL COLUMNS FROM #{table}").each do |name, type, c, allow_null, key, default_value, e, p, comment|
			attrs_info[name] = {
				:allow_null	=> (allow_null == 'YES'),
				:default_value	=>	default_value
			}
			type = type.split('(')[0]
			selectSql << "#{name}, "
			attrs[name] = [type]
			unless comment.nil? or comment.empty?
				comment.split(',')[0].split('|').each do |t|
					t = t.strip
					next if t.empty?
					# Lazyload only works for non-primary keys.
					next (lazy_attrs[name] = true) if t == 'lazyload' && key != 'PRI'
					attrs[name] << t
				end
			end
			pri_attrs << name if key == 'PRI'
			# Logger.debug "#{name.ljust(25)} => #{type.ljust(10)} c:#{comment} k:#{key}"
			raise "Unsupported type[#{type}], fitStructure failed." if MYSQL_TYPE_MAP[type.to_sym].nil?
		end

		class_name = DynamicMysqlObj.mysql_tab_to_class_name table
		class_name = "#{class_name}_DB"
		# Define in root_module
		root_module = self.class.to_s.split('::').first
		if root_module.empty?
			root_module = Object
		else
			root_module = Object.const_get root_module
		end
		full_class_name = "#{root_module}::#{class_name}"

		if root_module.const_defined? class_name
			if root_module.const_defined? class_name
				raise "Cannot generate class #{full_class_name}, const conflict." if root_module.const_defined? class_name
			else
				Logger.highlight "Generate class #{full_class_name} instead, because const conflict."
			end
		end
		Logger.debug "Generate class[#{full_class_name}] for #{table}"

		current_dao = self
		# Dynamic class generating.
		clazz = Class.new(DynamicMysqlObj)
		clazz.instance_eval { attr_accessor :__init_from_db }
		# Set attr_accessor for lazy and non-lazy attrs.
		attrs.each do |a, type|
			# puts "clazz.instance_eval { attr_accessor #{to_snake(a).to_sym} }"
			clazz.instance_eval { attr_accessor to_snake(a).to_sym }
			next if lazy_attrs[a] != true
			# Lazy load for lazy_attrs
			clazz.instance_eval do
				attr_accessor "__#{a}_loaded".to_sym
				# Getter: only load from db for first reading, and obj must be initialized from db.
				define_method(a.to_sym) do |*args|
					opt = args[0] || {}
					if opt[:no_load] == true || send(:__init_from_db) != true || send("__#{a}_loaded".to_sym) == true
						# puts "read lazyload #{a} directly."
						instance_variable_get "@#{a}".to_sym
					else
						load_sql = "select #{a} from #{table} where "
						pri_attrs.each do |pk|
							load_sql << "#{pk}=#{current_dao.gen_mysql_val(send(pk.to_sym), attrs[pk])}"
						end
						# puts "read lazyload #{a} from db."
						current_dao.query(load_sql).each do |value|
							value = current_dao.parse_mysql_val(value, type)
							instance_variable_set "@#{a}".to_sym, value
							break
						end
						# instance_variable_set "@#{a}".to_sym, value
						send("__#{a}_loaded=".to_sym, true)
						instance_variable_get "@#{a}".to_sym
					end
				end
				# Setter
				define_method("#{a}=".to_sym) do |value|
					# puts "set lazyload #{a} #{value.inspect}"
					send("__#{a}_loaded=".to_sym, true)
					instance_variable_set "@#{a}".to_sym, value
				end
			end
		end

		clazz.define_singleton_method :mysql_pri_attrs do pri_attrs; end
		clazz.define_singleton_method :mysql_lazy_attrs do lazy_attrs; end
		clazz.define_singleton_method :mysql_attrs do attrs; end
		clazz.define_singleton_method :mysql_attrs_info do attrs_info; end
		clazz.define_singleton_method :mysql_table do table; end
		clazz.define_singleton_method :mysql_dao do current_dao; end
		MYSQL_CLASS_MAP[table] = clazz
		root_module.const_set class_name, clazz
	end
	thread_safe :get_class

	def parse_mysql_val(string, type)
		begin
			return nil if string.nil?
			return string.force_encoding("UTF-8") if type.empty?
			val = string
			# Extract from package.
			type.each do |t|
	 			break if val.nil?
				method = MYSQL_TYPE_MAP[t.to_sym]
				raise "Unsupport mysql type:#{type}" if method.nil?
				method = method.to_sym
				case method
				when :to_datetime
					val = DateTime.parse(val) if method == :to_datetime
				when :base64
					val = decode64 val
				when :json
					val = JSON.parse val.gsub("\n", "\\n").gsub("\r", "\\r")
				when :bin
					val = val[0] if val.size > 0
				when :to_s
				else
					val = val.send method
				end
			end
			return nil if val.nil?
			val = val.force_encoding("UTF-8") if val.is_a? String
			return val
		rescue => e
			Logger.error "Error in parse_mysql_val:[#{string}] for type:[#{type}]"
			Logger.error e
			raise e
		end
	end

	def gen_mysql_val(val, type)
		return 'NULL' if val.nil?
		return "'#{val}'" if type.empty?
		string = val
		# Pack in reverse order.
		hex_pack = false
		type.reverse.each do |t|
			method = MYSQL_TYPE_MAP[t.to_sym]
			raise "Unsupport mysql type:#{type}" if method.nil?
			method = method.to_sym
			case method
			when :to_datetime
				val = val.strftime '%Y%m%d%H%M%S'
			when :base64
				val = encode64 val
			when :json
				val = val.to_json
			when :bin
				val = "UNHEX('#{val.to_s.b.unpack('H*')[0]}')"
				hex_pack = true
			when :to_s
			else
				val = val.to_s
			end
		end
		val = "'#{val}'" if val.is_a?(String) && !hex_pack
		val
	end

	def query_objs(table, whereClause = "", opt={})
		whereClause, opt = '', whereClause if whereClause.is_a?(Hash) && opt.empty?
		omit_column = opt[:omit_column] || []
		clazz = get_class table
		raise "Cannot get class from table:#{table}" unless clazz.is_a? Class
		sql = "select "
		pri_attrs  = clazz.mysql_pri_attrs
		all_attrs  = clazz.mysql_attrs
		lazy_attrs = clazz.mysql_lazy_attrs
		selected_attrs = []
		all_attrs.each do |name, type|
			raise "Could not omit attr[#{name}] because it is primary attribute." if omit_column.include?(name.to_sym) && pri_attrs.include?(name)
			next if omit_column.include? name.to_sym
			next if lazy_attrs[name] == true
			selected_attrs.push name
			sql << "#{name}, "
		end
		sql = "#{sql[0..-3]} from #{table} #{whereClause}"
		ret = []
		query(sql).each do |row|
			obj = clazz.new
			obj.unload_columns = omit_column
			# puts "set unload_columns #{omit_column.inspect}"
			obj.__init_from_db = true
			selected_attrs.each_with_index do |name, index|
				type = all_attrs[name]
				val = parse_mysql_val row[index], type
				obj.mysql_attr_set name, val
			end
			ret << obj
		end
		ret
	end

	def save_all(array, update = false)
		raise "Only receive obj arrays." unless array.is_a? Array
		array.each { |o| save o, update }
	end

	def save(obj, update = false)
		raise "Only DynamicMysqlObj could be operated." unless obj.is_a? DynamicMysqlObj
		sql = "INSERT INTO #{obj.class.mysql_table} SET "
		setSql = ""
		pri_attrs = obj.class.mysql_pri_attrs
		lazy_attrs = obj.class.mysql_lazy_attrs
		mysql_attrs_info = obj.class.mysql_attrs_info
		# puts obj.unload_columns.inspect
		obj.class.mysql_attrs.each do |col, type|
			val = obj.mysql_attr_get col
			should_next = false
			# Do not overwrite unload columns.
			should_next = true if obj.unload_columns != nil && obj.unload_columns.include?(col.to_sym)
			# Do not overwrite unload lazy attrs.
			should_next = true if lazy_attrs[col] == true && obj.send("__#{col}_loaded".to_sym) != true
			value = gen_mysql_val(val, type)
			# Do not use NULL to overwrite attr that has default value.
			should_next = true if value == 'NULL' && mysql_attrs_info[col][:default_value] != nil
			# Error if should_next on a primary key.
			raise "Could not determine primary key when saving obj:#{obj.inspect}" if should_next && pri_attrs.include?(col)
			next if should_next
			setSql << "#{col}=#{value}, "
		end
		setSql = setSql[0..-3]
		sql << setSql
		sql << " ON DUPLICATE KEY UPDATE " << setSql if update
		query sql
	end

	def delete_all(array, real = false)
		raise "Only receive obj arrays." unless array.is_a? Array
		array.each { |o| delete_obj o, real }
	end

	def delete_obj(obj, real = false)
		raise "Only DynamicMysqlObj could be operated." unless obj.is_a? DynamicMysqlObj
		if real
			sql = "DELETE FROM #{obj.class.mysql_table} WHERE "
			attrSql = ""
			obj.class.mysql_attrs.each do |col, type|
				val = obj.mysql_attr_get col
				next if val.nil?
				attrSql << "#{col}=#{gen_mysql_val(val, type)} AND "
			end
			attrSql = attrSql[0..-6]
			sql << attrSql
			query sql
		else
			raise "#{obj.class} do not contain column[deleted]" unless obj.respond_to? :deleted=
			return Logger.warn "obj is already marked as deleted." if obj.deleted
			obj.deleted = true
			save obj, true
		end
	end
end
