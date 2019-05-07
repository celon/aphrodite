require 'date'
require 'json'
puts RUBY_ENGINE

start_time = DateTime.now

str = 'string'
array = ['string1', 'string']
1999999.times do
	str.gsub('s', 'i').split('r')
	array.include?(str)
end

end_time = DateTime.now
elasped_ms = (end_time - start_time) * 24*3600 * 1000
puts "String operation - cost: #{elasped_ms.to_f} ms"

start_time = DateTime.now

f = 0.12313123
19999999.times do
	(f / (1 - 0.00316623) ).round(7)
end

end_time = DateTime.now
elasped_ms = (end_time - start_time) * 24*3600 * 1000
puts "Float computation - cost: #{elasped_ms.to_f} ms"

start_time = DateTime.now

19999999.times do
	a= {}
	a[str] = f
	a[str]
end

end_time = DateTime.now
elasped_ms = (end_time - start_time) * 24*3600 * 1000
puts "Map operation - cost: #{elasped_ms.to_f} ms"

start_time = DateTime.now

a = {'key'=>'value'}
999999.times do
	JSON.parse(JSON.dump(a))
end

end_time = DateTime.now
elasped_ms = (end_time - start_time) * 24*3600 * 1000
puts "JSON operation - cost: #{elasped_ms.to_f} ms"
