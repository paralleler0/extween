class_name extween extends RefCounted
# extween: an anime.js-inspired high-performance tweening wrapper for godot.

# --- INNER HELPER CLASS FOR STAGGER CONFIGURATIONS ---
class StaggerOptions extends RefCounted:
	var grid: Vector2i = Vector2i.ONE
	var from: Variant = "start" # "start", "center", "end", or an integer index
	var axis: String = "all"    # "all", "x", "y"
# ----------------------------------------------------

var _tween: Tween
var _targets: Array = []
var _duration: float = 1.0
var _transition_type: Tween.TransitionType = Tween.TRANS_LINEAR
var _ease_type: Tween.EaseType = Tween.EASE_IN_OUT
var _parallel: bool = false
var _custom_interpolator: Callable = Callable()

# --- OPTIMIZATION CACHE ---
var _sampled_curve: PackedFloat32Array = PackedFloat32Array()
const CURVE_SAMPLES = 200 # Higher = smoother curve, lower = less memory
# --------------------------

signal completed

const _easing_map := {
	"linear": [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT],
	"inquad": [Tween.TRANS_QUAD, Tween.EASE_IN],
	"outquad": [Tween.TRANS_QUAD, Tween.EASE_OUT],
	"inoutquad": [Tween.TRANS_QUAD, Tween.EASE_IN_OUT],
	"incubic": [Tween.TRANS_CUBIC, Tween.EASE_IN],
	"outcubic": [Tween.TRANS_CUBIC, Tween.EASE_OUT],
	"inoutcubic": [Tween.TRANS_CUBIC, Tween.EASE_IN_OUT],
	"inquart": [Tween.TRANS_QUART, Tween.EASE_IN],
	"outquart": [Tween.TRANS_QUART, Tween.EASE_OUT],
	"inoutquart": [Tween.TRANS_QUART, Tween.EASE_IN_OUT],
	"inquint": [Tween.TRANS_QUINT, Tween.EASE_IN],
	"outquint": [Tween.TRANS_QUINT, Tween.EASE_OUT],
	"inoutquint": [Tween.TRANS_QUINT, Tween.EASE_IN_OUT],
	"insine": [Tween.TRANS_SINE, Tween.EASE_IN],
	"outsine": [Tween.TRANS_SINE, Tween.EASE_OUT],
	"inoutsine": [Tween.TRANS_SINE, Tween.EASE_IN_OUT],
	"inexpo": [Tween.TRANS_EXPO, Tween.EASE_IN],
	"outexpo": [Tween.TRANS_EXPO, Tween.EASE_OUT],
	"inoutexpo": [Tween.TRANS_EXPO, Tween.EASE_IN_OUT],
	"incirc": [Tween.TRANS_CIRC, Tween.EASE_IN],
	"outcirc": [Tween.TRANS_CIRC, Tween.EASE_OUT],
	"inoutcirc": [Tween.TRANS_CIRC, Tween.EASE_IN_OUT],
	"inback": [Tween.TRANS_BACK, Tween.EASE_IN],
	"outback": [Tween.TRANS_BACK, Tween.EASE_OUT],
	"inoutback": [Tween.TRANS_BACK, Tween.EASE_IN_OUT],
	"inelastic": [Tween.TRANS_ELASTIC, Tween.EASE_IN],
	"outelastic": [Tween.TRANS_ELASTIC, Tween.EASE_OUT],
	"inoutelastic": [Tween.TRANS_ELASTIC, Tween.EASE_IN_OUT],
	"inbounce": [Tween.TRANS_BOUNCE, Tween.EASE_IN],
	"outbounce": [Tween.TRANS_BOUNCE, Tween.EASE_OUT],
	"inoutbounce": [Tween.TRANS_BOUNCE, Tween.EASE_IN_OUT]
}

func _init(scene_tree: SceneTree, loop: bool, loop_delay: float) -> void:
	_tween = scene_tree.create_tween()
	_tween.finished.connect(func(): completed.emit())
	if loop:
		_tween.set_loops()
	if loop_delay > 0.0:
		_tween.tween_interval(loop_delay)

static func play_tween(node: Node, targets: Variant, duration: float = 1.0, loop: bool = false, loop_delay: float = 0.0) -> extween:
	var et = extween.new(node.get_tree(), loop, loop_delay)
	et._duration = duration
	if targets is Array:
		et._targets = targets
	else:
		et._targets = [targets]
	return et

# --- GLOBAL STAGGER GENERATOR ---
static func stagger(val: Variant, opt: StaggerOptions = null) -> Callable:
	if opt == null:
		opt = StaggerOptions.new()
		
	return func(index: int, total: int, _target: Node) -> Variant:
		var grid_cols = opt.grid.x
		var grid_rows = opt.grid.y
		
		# Compute 2D coordinate inside grid bounds
		var x = index % grid_cols
		var y = index / grid_cols
		
		var cx = (grid_cols - 1) / 2.0
		var cy = (grid_rows - 1) / 2.0
		
		var from_x = 0.0
		var from_y = 0.0
		
		match opt.from:
			"start":
				from_x = 0.0
				from_y = 0.0
			"center":
				from_x = cx
				from_y = cy
			"end":
				from_x = grid_cols - 1
				from_y = grid_rows - 1
			_:
				if str(opt.from).is_valid_int():
					var from_idx = int(opt.from)
					from_x = from_idx % grid_cols
					from_y = from_idx / grid_cols
		
		var dist_x = abs(x - from_x)
		var dist_y = abs(y - from_y)
		
		var distance = 0.0
		match opt.axis:
			"x": distance = dist_x
			"y": distance = dist_y
			_: distance = sqrt(dist_x * dist_x + dist_y * dist_y)
			
		var max_x = max(from_x, (grid_cols - 1) - from_x)
		var max_y = max(from_y, (grid_rows - 1) - from_y)
		var max_distance = 0.0
		
		match opt.axis:
			"x": max_distance = max_x
			"y": max_distance = max_y
			_: max_distance = sqrt(max_x * max_x + max_y * max_y)
			
		var factor = distance / max_distance if max_distance > 0.0 else 0.0
		
		if val is Array and val.size() >= 2:
			return lerp(float(val[0]), float(val[1]), factor)
		elif val is Vector2:
			return lerp(Vector2.ZERO, val, factor)
		elif val is Vector3:
			return lerp(Vector3.ZERO, val, factor)
		else:
			return float(val) * factor

func duration(d: float) -> extween:
	_duration = d
	return self

func easing(easing_string: String) -> extween:
	_custom_interpolator = Callable()
	_sampled_curve.clear()
	var clean = easing_string.to_lower().replace(" ", "")
	if clean.contains("("):
		var parts = clean.split("(")
		var ease_name = parts[0]
		var args_str = parts[1].replace(")", "")
		var args = Array(args_str.split(",")).map(func(x): return float(x))
		_build_parameterized_ease(ease_name, args)
	else:
		if _easing_map.has(clean):
			_transition_type = _easing_map[clean][0]
			_ease_type = _easing_map[clean][1]
		else:
			push_warning("extween: easing '" + easing_string + "' not found. defaulting to linear.")
			_transition_type = Tween.TRANS_LINEAR
			_ease_type = Tween.EASE_IN_OUT
	return self

func steps(number_of_steps: int) -> extween:
	var total_steps = max(1, number_of_steps)
	_sampled_curve.clear()
	_custom_interpolator = func(v: float) -> float:
		return floor(v * total_steps) / total_steps
	_bake_custom_curve()
	return self

func irregular(curve_callable: Callable) -> extween:
	_sampled_curve.clear()
	_custom_interpolator = curve_callable
	_bake_custom_curve()
	return self

func parallel() -> extween:
	_parallel = true
	return self

func add(props: Dictionary, delay_stagger: Variant = 0.0) -> extween:
	var is_first_tweener = true
	for i in range(_targets.size()):
		var target = _targets[i]
		
		var current_delay = 0.0
		if delay_stagger is Callable:
			current_delay = float(delay_stagger.call(i, _targets.size(), target))
		else:
			current_delay = i * float(delay_stagger)
		
		for prop in props.keys():
			var raw_value = props[prop]
			var sanitized_path = NodePath(str(prop).replace(".", ":"))
			
			if target.get_indexed(sanitized_path) == null and not str(prop) in target:
				push_error("extween: property '" + str(prop) + "' not found on target " + str(target))
				continue
				
			var final_value = raw_value
			if raw_value is Callable:
				final_value = raw_value.call(i, _targets.size(), target)
				
			var tweener = _tween.tween_property(target, sanitized_path, final_value, _duration)
			
			if not _sampled_curve.is_empty():
				tweener.set_custom_interpolator(_evaluate_baked_curve)
			elif _custom_interpolator.is_valid():
				tweener.set_custom_interpolator(_custom_interpolator)
			else:
				tweener.set_trans(_transition_type)
				tweener.set_ease(_ease_type)
				
			if current_delay > 0.0:
				tweener.set_delay(current_delay)
				
			if _parallel or not is_first_tweener:
				tweener.parallel()
				
			is_first_tweener = false
			
	_parallel = false 
	return self

func delay(time: float) -> extween:
	_tween.tween_interval(time)
	return self

func pause() -> void:
	_tween.pause()

func play() -> void:
	_tween.play()

func kill() -> void:
	_tween.kill()

# --- OPTIMIZED CACHING MECHANICS ---
func _bake_custom_curve() -> void:
	if not _custom_interpolator.is_valid():
		return
	_sampled_curve.resize(CURVE_SAMPLES + 1)
	for i in range(CURVE_SAMPLES + 1):
		var t = float(i) / float(CURVE_SAMPLES)
		_sampled_curve[i] = _custom_interpolator.call(t)
	_custom_interpolator = Callable()

func _evaluate_baked_curve(t: float) -> float:
	if t <= 0.0: return _sampled_curve[0]
	if t >= 1.0: return _sampled_curve[CURVE_SAMPLES]
	
	var exact_idx = t * CURVE_SAMPLES
	var low_idx = int(exact_idx)
	var high_idx = low_idx + 1
	var weight = exact_idx - low_idx
	
	return lerp(_sampled_curve[low_idx], _sampled_curve[high_idx], weight)

func _bounce_sub_calculation(t: float) -> float:
	if t < (1.0 / 2.75): return 7.5625 * t * t
	elif t < (2.0 / 2.75): t -= (1.5 / 2.75); return 7.5625 * t * t + 0.75
	elif t < (2.5 / 2.75): t -= (2.25 / 2.75); return 7.5625 * t * t + 0.9375
	else: t -= (2.625 / 2.75); return 7.5625 * t * t + 0.984375

func _build_parameterized_ease(name: String, args: Array) -> void:
	match name:
		"in":
			var p = args[0] if args.size() > 0 else 1.675
			_custom_interpolator = func(t: float) -> float: return pow(t, p)
		"out":
			var p = args[0] if args.size() > 0 else 1.675
			_custom_interpolator = func(t: float) -> float: return 1.0 - pow(1.0 - t, p)
		"inout":
			var p = args[0] if args.size() > 0 else 1.675
			_custom_interpolator = func(t: float) -> float:
				return 0.5 * pow(t * 2.0, p) if t < 0.5 else 1.0 - 0.5 * pow(2.0 - t * 2.0, p)
		"outin":
			var p = args[0] if args.size() > 0 else 1.675
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: return 0.5 * (1.0 - pow(1.0 - t * 2.0, p))
				return 0.5 + 0.5 * pow((t - 0.5) * 2.0, p)
		"spring":
			var m = args[0] if args.size() > 0 else 1.0
			var k = args[1] if args.size() > 1 else 100.0
			var c = args[2] if args.size() > 2 else 10.0
			var v0 = args[3] if args.size() > 3 else 0.0
			var w0 = sqrt(k / m)
			var zeta = c / (2.0 * sqrt(k * m))
			if zeta < 1.0:
				var wd = w0 * sqrt(1.0 - zeta * zeta)
				_custom_interpolator = func(t: float) -> float:
					if t <= 0.0: return 0.0
					if t >= 1.0: return 1.0
					var envelope = exp(-zeta * w0 * t)
					var c2 = (v0 + zeta * w0) / wd
					return 1.0 - envelope * (cos(wd * t) + c2 * sin(wd * t))
			else:
				_custom_interpolator = func(t: float) -> float:
					if t <= 0.0: return 0.0
					if t >= 1.0: return 1.0
					return 1.0 - (1.0 + (v0 + w0) * t) * exp(-w0 * t)
		"outinquad":
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: return -2.0 * t * (t - 1.0)
				t = t * 2.0 - 1.0; return 0.5 * t * t + 0.5
		"outincubic":
			_custom_interpolator = func(t: float) -> float:
				t = t * 2.0 - 1.0; return 0.5 * (t * t * t + 1.0)
		"outinquart":
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: t = t * 2.0 - 1.0; return 0.5 * (1.0 - t * t * t * t)
				t = t * 2.0 - 1.0; return 0.5 * (t * t * t * t + 1.0)
		"outinquint":
			_custom_interpolator = func(t: float) -> float:
				t = t * 2.0 - 1.0; return 0.5 * (t * t * t * t * t + 1.0)
		"outinsine":
			_custom_interpolator = func(t: float) -> float:
				return 0.5 * sin(t * PI) if t < 0.5 else 0.5 * (2.0 - cos((t - 0.5) * PI))
		"outinexpo":
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: return 0.5 * (1.0 - pow(2.0, -20.0 * t))
				return 0.5 + 0.5 * (pow(2.0, 20.0 * (t - 1.0)))
		"outincirc":
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: return 0.5 * sqrt(1.0 - pow(t * 2.0 - 1.0, 2.0))
				return 0.5 + 0.5 * (1.0 - sqrt(1.0 - pow((t - 0.5) * 2.0, 2.0)))
		"outinback":
			var s = args[0] if args.size() > 0 else 1.70158
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: t = t * 2.0 - 1.0; return 0.5 * (t * t * ((s + 1.0) * t + s) + 1.0)
				t = (t - 0.5) * 2.0; return 0.5 + 0.5 * (t * t * ((s + 1.0) * t - s))
		"outinelastic":
			var a = args[0] if args.size() > 0 else 1.0
			var p = args[1] if args.size() > 1 else 0.3
			_custom_interpolator = func(t: float) -> float:
				var s = p / (2.0 * PI) * asin(1.0 / a) if a >= 1.0 else p / 4.0
				if t < 0.5:
					t = t * 2.0
					return 0.5 * (a * pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * PI) / p) + 1.0)
				t = (t - 0.5) * 2.0 - 1.0
				return 0.5 + 0.5 * (-(a * pow(2.0, 10.0 * t) * sin((t - s) * (2.0 * PI) / p)))
		"outinbounce":
			_custom_interpolator = func(t: float) -> float:
				if t < 0.5: return 0.5 * (1.0 - _bounce_sub_calculation(1.0 - t * 2.0))
				return 0.5 + 0.5 * _bounce_sub_calculation((t - 0.5) * 2.0)
		"cubicbezier":
			var x1 = args[0] if args.size() > 0 else 0.0
			var y1 = args[1] if args.size() > 1 else 0.0
			var x2 = args[2] if args.size() > 2 else 1.0
			var y2 = args[3] if args.size() > 3 else 1.0
			var cx = 3.0 * x1
			var bx = 3.0 * (x2 - x1) - cx
			var ax = 1.0 - cx - bx
			var cy = 3.0 * y1
			var by = 3.0 * (y2 - y1) - cy
			var ay = 1.0 - cy - by
			_custom_interpolator = func(t: float) -> float:
				if t <= 0.0: return 0.0
				if t >= 1.0: return 1.0
				var guess = t
				for i in range(4):
					var current_x = ((ax * guess + bx) * guess + cx) * guess - t
					if abs(current_x) < 1e-5: break
					var derivative_x = (3.0 * ax * guess + 2.0 * bx) * guess + cx
					if abs(derivative_x) < 1e-5: break
					guess -= current_x / derivative_x
				return ((ay * guess + by) * guess + cy) * guess
		"inback":
			var s = args[0] if args.size() > 0 else 1.70158
			_custom_interpolator = func(t: float) -> float: return t * t * ((s + 1.0) * t - s)
		"outback":
			var s = args[0] if args.size() > 0 else 1.70158
			_custom_interpolator = func(t: float) -> float: t -= 1.0; return t * t * ((s + 1.0) * t + s) + 1.0
		"inoutback":
			var s = (args[0] if args.size() > 0 else 1.70158) * 1.525
			_custom_interpolator = func(t: float) -> float:
				t *= 2.0
				if t < 1.0: return 0.5 * (t * t * ((s + 1.0) * t - s))
				t -= 2.0; return 0.5 * (t * t * ((s + 1.0) * t + s) + 2.0)
		"inelastic":
			var a = args[0] if args.size() > 0 else 1.0
			var p = args[1] if args.size() > 1 else 0.3
			_custom_interpolator = func(t: float) -> float:
				if t == 0.0 or t == 1.0: return t
				var s = p / (2.0 * PI) * asin(1.0 / a) if a >= 1.0 else p / 4.0
				t -= 1.0; return -(a * pow(2.0, 10.0 * t) * sin((t - s) * (2.0 * PI) / p))
		"outelastic":
			var a = args[0] if args.size() > 0 else 1.0
			var p = args[1] if args.size() > 1 else 0.3
			_custom_interpolator = func(t: float) -> float:
				if t == 0.0 or t == 1.0: return t
				var s = p / (2.0 * PI) * asin(1.0 / a) if a >= 1.0 else p / 4.0
				return a * pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * PI) / p) + 1.0
		"inoutelastic":
			var a = args[0] if args.size() > 0 else 1.0
			var p = args[1] if args.size() > 1 else 0.45
			_custom_interpolator = func(t: float) -> float:
				if t == 0.0 or t == 1.0: return t
				var s = p / (2.0 * PI) * asin(1.0 / a) if a >= 1.0 else p / 4.0
				t *= 2.0
				if t < 1.0: 
					t -= 1.0; return -0.5 * (a * pow(2.0, 10.0 * t) * sin((t - s) * (2.0 * PI) / p))
				t -= 1.0; return a * pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * PI) / p) * 0.5 + 1.0
		_:
			push_warning("extween: parameterized easing '" + name + "' not supported. falling back to linear.")
			_transition_type = Tween.TRANS_LINEAR
			_ease_type = Tween.EASE_IN_OUT
			return

	_bake_custom_curve()
