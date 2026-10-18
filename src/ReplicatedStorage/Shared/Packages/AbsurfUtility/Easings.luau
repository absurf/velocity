local module = {}

module = {

	["easeInSine"] = function(x : number)
		return 1 - math.cos((x * math.pi) / 2);
	end,

	["easeOutSine"] = function(x : number)
		return math.sin((x * math.pi) / 2);
	end,

	["easeInOutSine"] = function(x : number)
		return -(math.cos(math.pi * x) - 1) / 2;
	end,

	["easeInCubic"] = function(x : number)
		return x * x * x;
	end,

	["easeOutCubic"] = function(x : number)
		return 1 - math.pow(1 - x, 3);
	end,

	["easeInOutCubic"] = function(x : number)

		if x < 0.5 then
			return 4 * x * x * x
		else
			return 1 - math.pow(-2 * x + 2, 3) / 2
		end

	end,

	["easeInQuint"] = function(x : number)
		return x * x * x * x * x;
	end,

	["easeOutQuint"] = function(x : number)
		return 1 - math.pow(1 - x, 5);
	end,

	["easeInOutQuint"] = function(x : number)
		if x < 0.5 then
			return 16 * x * x * x * x * x
		else
			return 1 - math.pow(-2 * x + 2, 5) / 2
		end
	end,

	["easeInCirc"] = function(x : number)
		return 1 - math.sqrt(1 - math.pow(x, 2));
	end,

	["easeOutCirc"] = function(x : number)
		return math.sqrt(1 - math.pow(x - 1, 2));
	end,

	["easeInOutCirc"] = function(x : number)
		if x < 0.5 then
			return (1 - math.sqrt(1 - math.pow(2 * x, 2))) / 2
		else
			return (math.sqrt(1 - math.pow(-2 * x + 2, 2)) + 1) / 2
		end
	end,

	["easeInElastic"] = function(x : number)
		local c4 = (2 * math.pi) / 3

		if x == 0 then
			return 0
		elseif x == 1 then
			return 1
		else
			return -math.pow(2, 10 * x - 10) * math.sin((x * 10 - 10.75) * c4)
		end
	end,

	["easeOutElastic"] = function(x : number)
		local c4 = (2 * math.pi) / 3

		if x == 0 then
			return 0
		elseif x == 1 then
			return 1
		else
			return math.pow(2, -10 * x) * math.sin((x * 10 - 0.75) * c4) + 1
		end
	end,

	["easeInOutElastic"] = function(x : number)
		local c5 = (2 * math.pi) / 4.5

		if x == 0 then
			return 0
		elseif x == 1 then
			return 1
		elseif x < 0.5 then
			return -(math.pow(2, 20 * x - 10) * math.sin((20 * x - 11.125) * c5)) / 2
		else
			return (math.pow(2, -20 * x + 10) * math.sin((20 * x - 11.125) * c5)) / 2 + 1
		end
	end,

	["easeInQuad"] = function(x : number)
		return x * x;
	end,

	["easeOutQuad"] = function(x : number)
		return 1 - (1 - x) * (1 - x);
	end,

	["easeInOutQuad"] = function(x : number)
		if x < 0.5 then
			return 2 * x * x
		else
			return 1 - math.pow(-2 * x + 2, 2) / 2
		end
	end,

	["easeInQuart"] = function(x : number)
		return x * x * x * x;
	end,

	["easeOutQuart"] = function(x : number)
		return 1 - math.pow(1 - x, 4);
	end,

	["easeInOutQuart"] = function(x : number)
		if x < 0.5 then
			return 8 * x * x * x * x
		else
			return 1 - math.pow(-2 * x + 2, 4) / 2
		end
	end,

	["easeInExpo"] = function(x : number)
		if x == 0 then
			return 0
		else
			return math.pow(2, 10 * x - 10)
		end
	end,

	["easeOutExpo"] = function(x : number)
		if x == 1 then
			return 1
		else
			return 1 - math.pow(2, -10 * x)
		end
	end,

	["easeInOutExpo"] = function(x : number)
		if x == 0 then
			return 0
		elseif x == 1 then
			return 1
		elseif x < 0.5 then
			return math.pow(2, 20 * x - 10) / 2
		else
			return (2 - math.pow(2, -20 * x + 10)) / 2
		end
	end,

	["easeInBack"] = function(x : number)
		local c1 = 1.70158
		local c3 = c1 + 1

		return c3 * x * x * x - c1 * x * x
	end,

	["easeOutBack"] = function(x : number)
		local c1 = 1.70158
		local c3 = c1 + 1

		return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2)
	end,

	["easeInOutBack"] = function(x : number)
		local c1 = 1.70158
		local c2 = c1 * 1.525

		if x < 0.5 then
			return (math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
		else
			return (math.pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2
		end
	end,

	["easeInBounce"] = function(x : number)
		return 1 -  module.easeOutBounce(1 - x)
	end,

	["easeOutBounce"] = function(x : number)
		local n1 = 7.5625
		local d1 = 2.75

		if x < 1 / d1 then
			return n1 * x * x
		elseif x < 2 / d1 then
			x = x - 1.5 / d1
			return n1 * x * x + 0.75
		elseif x < 2.5 / d1 then
			x = x - 2.25 / d1
			return n1 * x * x + 0.9375
		else
			x = x - 2.625 / d1
			return n1 * x * x + 0.984375
		end
	end,

	["easeInOutBounce"] = function(x : number)
		if x < 0.5 then
			return (1 - module.easeOutBounce(1 - 2 * x)) / 2
		else
			return (1 + module.easeOutBounce(2 * x - 1)) / 2
		end
	end,

	["easeLinear"] = function(x : number)
		return x
	end,

}

return module
