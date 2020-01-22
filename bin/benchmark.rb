#!/usr/bin/env ruby

puts "ENV: #{RUBY_ENGINE} #{RUBY_VERSION} #{RUBY_PATCHLEVEL}"

require 'json'

def price_precision(pair)
	8
end

def format_num(f, float=8, decimal=8)
	return ''.ljust(decimal+float+1) if f.nil?
	return ' '.ljust(decimal+float+1, ' ') if f == 0
	return f.rjust(decimal+float+1) if f.is_a? String
	num = f.to_f
	f = "%.#{float}f" % f
	loop do
		break unless f.end_with?('0')
		break if f.end_with?('.0')
		f = f[0..-2]
	end
	segs = f.split('.')
	if num.to_i == num
		return "#{segs[0].rjust(decimal)} #{''.ljust(float, ' ')}"
	else
		return "#{segs[0].rjust(decimal)}.#{segs[1][0..float].ljust(float, ' ')}"
	end
end

def format_price_str(pair, type, price, opt={})
	verbose = opt[:verbose] == true
	toint = 10000000000 # 10^11 is precise enough.
	step = price_precision(pair)
	# Must check class to avoid string*bignum
	raise "price should be a num: #{price}" if price.class != 1.class && price.class != (1.1).class
	raise "step should be a num: #{step}" if step.class != 1.class && step.class != (1.1).class
	step_i = (step * toint).round
	price_i = (price * toint).round
	new_price_i = price_i / step_i * step_i
	if new_price_i == price_i
		return price if opt[:num] == true
		str = format_num(price, price_precision(pair)).strip
		str = str.gsub(/0*$/, '') if str.include?('.')
		str = str.gsub(/\.$/, '') if str.include?('.')
		return str
	end
	raise "Price #{format_num(price, price_precision(pair))} should be integer times of step: #{format_num(step, price_precision(pair))}" if opt[:adjust] != true
	# Adjust price according to type.
	case type
	when 'buy'
		;
	when 'sell'
		new_price_i += step_i
	else
		raise "Unknown type #{type}"
	end
	puts "#{type} price adjusted from #{price_i} to #{new_price_i} according to step: #{step_i}" if verbose
	return new_price_i.to_f/toint.to_f if opt[:num] == true
	str = format_num(new_price_i.to_f/toint.to_f, price_precision(pair)).strip
	str = str.gsub(/0*$/, '') if str.include?('.')
	str = str.gsub(/\.$/, '') if str.include?('.')
	return str
end

def test
	orders = ['buy', 'sell'].map { |t| [t, []] }.to_h
	JSON.parse(orders.to_json)
	JSON.parse(JSON.pretty_generate(orders))

	o = {'T'=>'buy', 'p'=>'0.123512', 's'=>123}
	mo = {'T'=>'sell', 'p'=>'0.099712', 's'=>324}
	o['p'] = o['p'].to_f
	mo['p'] = mo['p'].to_f
	last_order_arbitrage_min = 0.07
	price_precise = 8

	type12_result = {}
	type12_result[:p_real] = p_real = format_price_str('pair', o['T'], o['p'], adjust:true, verbose:false).to_f
	type12_result[:price] = price = mo['p']
	type12_result[:type] = type = mo['T']
	type12_result[:market] = mo['market']
	type12_result[:child_type] = (['sell', 'buy'] - [type]).first
	type12_result[:child_price_threshold] = (p_real/(1+last_order_arbitrage_min)).floor(price_precise) if type == 'sell'
	type12_result[:child_price_threshold] = (p_real*(1+last_order_arbitrage_min)).ceil(price_precise) if type == 'buy'
	type12_result[:cata] = 'A'
	type12_result[:suggest_size] = mo['s']
	type12_result[:explain] = "Direct sell at buy at #{mo}"
end

loop {
	start_t = Time.now.to_f
	ct = 0
	t = 0
	loop {
		100.times { ct += 1; test() }
		t = Time.now.to_f - start_t
		break if t >= 3
	}
	puts (ct/t).to_i
}
