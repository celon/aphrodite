# Javascript like object without any method declaraion.
# Support obj.a,  obj.a=, obj.a? (only when a is boolean)
class JSONObject < Hash
	alias_method :__hash_respond_to?, :respond_to?

	def respond_to?(symbol, include_all=false)
		return true if super(symbol, include_all)
		return false if symbol.nil?
		return false if symbol[-1] == '!'
		return true
	end

	def method_missing(symbol, *args)
		return super(symbol, *args) if __hash_respond_to?(symbol, true)
		# use super to raise error.
		return super(symbol, *args) if symbol.nil?
		return super(symbol, *args) if symbol[-1] == '!'
		# handle hash operation.
		if symbol[-1] == '?' && args.empty?
			# self.xxx?
			return super(symbol, *args) if symbol.size == 1
			val = self.[] symbol[0..-2].to_s
			return true if val == true
			return false if val.nil? || val == false
			return super(symbol, *args)
		elsif symbol[-1] == '=' && args.size == 1
			# self.xxx = yyy
			return super(symbol, *args) if symbol.size == 1
			self.[]= symbol[0..-2].to_s, args[0]
			return args[0]
		elsif args.empty?
			# self.xxx
			val = self.[] symbol.to_s
			return val
		else
			return super(symbol, *args)
		end
	end
end
