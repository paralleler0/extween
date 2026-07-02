class_name extween
extends RefCounted
# extween: an anime.js-inspired tweening wrapper for godot.

var _tween: Tween
var _targets: Array = []
var _duration: float = 1.0
var _transition_type: Tween.TransitionType = Tween.TRANS_QUAD
var _ease_type: Tween.EaseType = Tween.EASE_IN_OUT
var _parallel: bool = false
var _custom_interpolator: Callable = Callable()

signal completed

const _easing_map := {
	"spring": ["custom_spring", [1.0, 100.0, 10.0, 0.0]], # anime.js physics fallback defaults
	
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

func duration(d: float) -> extween:
	_duration = d
	return self

func easing(easing_string: String) -> extween:
	_custom_interpolator = Callable()
	var clean = easing_string.to_lower().replace(" ", "")
	
	if clean.contains("("):
		var parts = clean.split("(")
		var ease_name = parts[0]
		var inner_str = parts[1].trim_suffix(")")
		
		# Detect if configuration is dictionary-based e.g., spring({bounce:0.15,duration:300})
		if inner_str.begins_with("{") and inner_str.ends_with("}"):
			var dict_content = inner_str.trim_prefix("{").trim_suffix("}")
			var pairs = dict_content.split(",")
			var dict_args = {}
			for pair in pairs:
				var kv = pair.split(":")
				if kv.size() == 2:
					dict_args[kv[0].strip_edges()] = float(kv[1].strip_edges())
			
			_build_parameterized_ease_dict(ease_name, dict_args)
		else:
			# Handle standard array string formatting e.g., spring(1, 100, 10, 0)
			var args = Array(inner_str.split(",")).map(func(x): return float(x) if x.is_valid_float() else 0.0)
			_build_parameterized_ease(ease_name, args)
	else:
		if _easing_map.has(clean):
			var map_val = _easing_map[clean]
			if map_val[0] is String and map_val[0] == "custom_spring":
				_build_parameterized_ease("spring", map_val[1])
			else:
				_transition_type = map_val[0]
				_ease_type = map_val[1]
		else:
			push_warning("extween: easing '" + easing_string + "' not found. defaulting to spring.")
			_build_parameterized_ease("spring", [])
	return self

func steps(number_of_steps: int) -> extween:
	var total_steps = max(1, number_of_steps)
	_custom_interpolator = func(v: float) -> float:
		return floor(v * total_steps) / total_steps
	return self

func irregular(curve_callable: Callable) -> extween:
	_custom_interpolator = curve_callable
	return self

func parallel() -> extween:
	_parallel = true
	return self

func add(props: Dictionary, delay_stagger: float = 0.0) -> extween:
	for i in range(_targets.size()):
		var target = _targets[i]
		var current_delay = i * delay_stagger
		
		for prop in props.keys():
			var raw_value = props[prop]
			var sanitized_path = NodePath(str(prop).replace(".", ":"))
			
			if not target.get_indexed(sanitized_path) != null and not str(prop) in target:
				push_error("extween: property '" + str(prop) + "' not found on target " + str(target))
				continue
			
			var final_value = raw_value
			if raw_value is Callable:
				final_value = raw_value.call(i, _targets.size(), target)
				
			var tweener = _tween.tween_property(target, sanitized_path, final_value, _duration)
			
			if _custom_interpolator.is_valid():
				tweener.set_custom_interpolator(_custom_interpolator)
			else:
				tweener.set_trans(_transition_type)
				tweener.set_ease(_ease_type)
			
			if current_delay > 0:
				tweener.set_delay(current_delay)
				
			if _parallel or i > 0 or prop != props.keys()[0]:
				tweener.parallel()
				
	_parallel = false
	return self

func delay(time: float) -> extween:
	_tween.tween_interval(time)
	return self

func pause() -> void: _tween.pause()
func play() -> void: _tween.play()
func kill() -> void: _tween.kill()

func _build_parameterized_ease_dict(name: String, dict_args: Dictionary) -> void:
	if name == "spring":
		# anime.js perceived spring default settings: bounce = 0.5, duration = 628
		var bounce = dict_args.get("bounce", 0.5)
		var duration_ms = dict_args.get("duration", 628.0)
		
		# Overwrite tween instance duration with perceived spring calculation (matching anime.js override logic)
		_duration = duration_ms / 1000.0 
		
		# Map visual "bounce" and "duration" to raw mass/stiffness/damping via standard SwiftUI conversions
		var mass = 1.0
		var zeta = 0.0
		if bounce > 0.0:
			zeta = 1.0 - bounce
		elif bounce < 0.0:
			zeta = 1.0 / (1.0 + bounce)
		else:
			zeta = 1.0
			
		var duration_scaled = _duration
		var omega = (2.0 * PI) / (duration_scaled * sqrt(max(0.001, 1.0 - zeta * zeta)))
		if zeta >= 1.0:
			omega = (2.0 * PI) / duration_scaled
			
		var stiffness = mass * (omega * omega)
		var damping = 2.0 * zeta * sqrt(stiffness * mass)
		
		_build_parameterized_ease("spring", [mass, stiffness, damping, 0.0])

func _build_parameterized_ease(name: String, args: Array) -> void:
	match name:
		"spring":
			var mass = args[0] if args.size() > 0 else 1.0
			var stiffness = args[1] if args.size() > 1 else 100.0
			var damping = args[2] if args.size() > 2 else 10.0
			var velocity = args[3] if args.size() > 3 else 0.0
			
			var omega = sqrt(stiffness / mass)
			var zeta = damping / (2.0 * sqrt(stiffness * mass))
			
			_custom_interpolator = func(t: float) -> float:
				if t <= 0.0: return 0.0
				if t >= 1.0: return 1.0
				
				# Convert uniform 0-1 time scale to natural system settling progression
				var t_scaled = t * 12.0 
				
				if zeta < 1.0:
					var omega_d = omega * sqrt(1.0 - zeta * zeta)
					var envelope = exp(-zeta * omega * t_scaled)
					return 1.0 - envelope * (cos(omega_d * t_scaled) + ((zeta * omega - velocity) / omega_d) * sin(omega_d * t_scaled))
				else:
					var envelope = exp(-omega * t_scaled)
					return 1.0 - envelope * (1.0 + (omega - velocity) * t_scaled)
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
				return ((ay * guess + by) * cy) * guess
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
				if t < 1.0: t -= 1.0; return -0.5 * (a * pow(2.0, 10.0 * t) * sin((t - s) * (2.0 * PI) / p))
				t -= 1.0; return a * pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * PI) / p) * 0.5 + 1.0
		_:
			push_warning("extween: parameterized easing '" + name + "' not supported. falling back to spring.")
			_build_parameterized_ease("spring", [])
