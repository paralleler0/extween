class_name Extween
extends RefCounted

enum PlayState { PAUSED, PLAYING, COMPLETED }

var _tween: Tween
var _state: PlayState = PlayState.PAUSED
var _context: Node

func _init(context: Node = null):
	if context and is_instance_valid(context):
		_context = context
		_reset_tween()

func _reset_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _context and is_instance_valid(_context):
		_tween = _context.get_tree().create_tween()
		_tween.stop() # Hold execution until explicitly played

func get_godot_tween() -> Tween:
	return _tween

func run_step(step: Dictionary) -> void:
	if not _tween or not _tween.is_valid():
		return

	var step_type: String = step.get("type", "to")
	
	if step_type == "wait":
		var duration := float(step.get("duration", 0.0)) / 1000.0
		_tween.interval(duration)
		return

	var targets = step.get("targets", [])
	if not (targets is Array):
		targets = [targets]

	var duration := float(step.get("duration", 1000.0)) / 1000.0
	var ease_name := str(step.get("ease", "linear"))
	var delay := float(step.get("delay", 0.0))
	var stagger := float(step.get("stagger", 0.0))
	var props := step.get("props", {})

	# Native easing optimization check
	var is_native_ease := _is_native_easing(ease_name)
	
	# Create a parallel group for target staggers within this single step
	_tween.parallel()

	for index in range(targets.size()):
		var target = targets[index]
		if not is_instance_valid(target):
			continue

		var target_delay = delay + (index * stagger)

		for prop in props.keys():
			var end_val = props[prop]
			
			if step_type == "from":
				# 'from' animations set the target value immediately 
				# before the tween loop interpolates back to its original value
				var start_val = target.get(prop)
				target.set(prop, end_val)
				end_val = start_val

			if is_native_ease and _is_simple(end_val):
				var tw := _tween.tween_property(target, prop, end_val, duration)
				_apply_ease(tw, ease_name)
				if target_delay > 0.0:
					tw.set_delay(target_delay)
			else:
				# Fixed: Use a deferred binding object to read start values live
				var binder = _InterpolationBinder.new(target, prop, end_val, ease_name)
				var tw2 := _tween.tween_method(binder.interpolate, 0.0, 1.0, duration)
				if target_delay > 0.0:
					tw2.set_delay(target_delay)

static func _is_simple(value) -> bool:
	return typeof(value) in [
		TYPE_FLOAT,
		TYPE_INT,
		TYPE_VECTOR2,
		TYPE_VECTOR3,
		TYPE_COLOR
	]

# ==============================================================================
# ANIME.JS INTEGRATED EASING ENGINE
# ==============================================================================

static func _is_native_easing(ease_name: String) -> bool:
	var e = ease_name.strip_edges().to_lower()
	# Strip typical anime.js prefixes to check for native capability
	var base = e.replace("easeinout", "").replace("easein", "").replace("easeout", "")
	if base == "": base = "linear"
	return base in ["linear", "sine", "quad", "cubic", "quart", "quint", "expo", "circ", "back", "bounce", "elastic"]

static func _apply_ease(tw: PropertyTween, ease_name: String) -> void:
	var e = ease_name.strip_edges().to_lower()
	
	# Determine Direction
	if e.begins_with("easeinout"):
		tw.set_ease(Tween.EASE_IN_OUT)
	elif e.begins_with("easeout"):
		tw.set_ease(Tween.EASE_OUT)
	elif e.begins_with("easein"):
		tw.set_ease(Tween.EASE_IN)
	else:
		tw.set_ease(Tween.EASE_IN_OUT) # Fallback / Default
		
	# Determine Equation type
	var base = e.replace("easeinout", "").replace("easein", "").replace("easeout", "")
	match base:
		"", "linear": tw.set_trans(Tween.TRANS_LINEAR)
		"sine": tw.set_trans(Tween.TRANS_SINE)
		"quad": tw.set_trans(Tween.TRANS_QUAD)
		"cubic": tw.set_trans(Tween.TRANS_CUBIC)
		"quart": tw.set_trans(Tween.TRANS_QUART)
		"quint": tw.set_trans(Tween.TRANS_QUINT)
		"expo": tw.set_trans(Tween.TRANS_EXPO)
		"circ": tw.set_trans(Tween.TRANS_CIRC)
		"back": tw.set_trans(Tween.TRANS_BACK)
		"bounce": tw.set_trans(Tween.TRANS_BOUNCE)
		"elastic": tw.set_trans(Tween.TRANS_ELASTIC)
		_: tw.set_trans(Tween.TRANS_LINEAR)

static func evaluate_easing(easing_name: String, t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	var e = easing_name.strip_edges().to_lower()

	# 1. Custom Functional Power Easings: out(3), in(2.5)
	if e.begins_with("in(") and e.ends_with(")"):
		var p = e.get_slice("(", 1).replace(")", "").to_float()
		return pow(t, p)
	if e.begins_with("out(") and e.ends_with(")"):
		var p = e.get_slice("(", 1).replace(")", "").to_float()
		return 1.0 - pow(1.0 - t, p)

	# 2. Anime.js Parametric Bezier Engine: cubicBezier(.42, 0, .58, 1)
	if e.begins_with("cubicbezier(") or e.begins_with("bezier("):
		var raw = e.get_slice("(", 1).replace(")", "")
		var params = raw.split(",")
		if params.size() == 4:
			return _solve_bezier(t, params[0].to_float(), params[1].to_float(), params[2].to_float(), params[3].to_float())

	# 3. Anime.js Damped Spring Engine: spring(mass, stiffness, damping, velocity)
	if e.begins_with("spring("):
		var raw = e.get_slice("(", 1).replace(")", "")
		var params = raw.split(",")
		# Default fallback settings matching anime.js physics presets
		var mass := 1.0 if params.size() < 1 else params[0].to_float()
		var stiff := 100.0 if params.size() < 2 else params[1].to_float()
		var damp := 10.0 if params.size() < 3 else params[2].to_float()
		var velocity := 0.0 if params.size() < 4 else params[3].to_float()
		return _solve_spring(t, mass, stiff, damp, velocity)

	# Fallback evaluations for explicitly typed non-native variations
	match e:
		"insine": return 1.0 - cos(t * PI * 0.5)
		"outsine": return sin(t * PI * 0.5)
		"inoutcirc": return 0.5 * (1.0 - cos(PI * t)) if t < 0.5 else 0.5 * (1.0 + sqrt(1.0 - pow(2.0 * t - 2.0, 2.0)))
		"outcirc": return sqrt(1.0 - pow(t - 1.0, 2.0))
		_: return t

# Analytical approximation solver for Cubic Bezier curves
static func _solve_bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if x1 == y1 and x2 == y2: return t # Linear optimization
	# Use binary search to resolve the X coordinate value cleanly over time
	var low := 0.0
	var high := 1.0
	var guess_x := 0.0
	
	for i in range(8): # 8 iterations give high performance sub-pixel precision
		guess_x = (low + high) / 2.0
		var x = 3.0 * pow(1.0 - guess_x, 2.0) * guess_x * x1 + 3.0 * (1.0 - guess_x) * pow(guess_x, 2.0) * x2 + pow(guess_x, 3.0)
		if x > t: high = guess_x
		else: low = guess_x
		
	# Evaluate and return the matching solved Y coordinate
	return 3.0 * pow(1.0 - guess_x, 2.0) * guess_x * y1 + 3.0 * (1.0 - guess_x) * pow(guess_x, 2.0) * y2 + pow(guess_x, 3.0)

# Simplified Harmonic Spring physics integration over standardized timeframe
static func _solve_spring(t: float, mass: float, stiffness: float, damping: float, velocity: float) -> float:
	var w0 = sqrt(stiffness / mass)
	var zeta = damping / (2.0 * sqrt(stiffness * mass))
	var envelope = exp(-zeta * w0 * t)
	
	if zeta < 1.0: # Underdamped spring curve
		var wd = w0 * sqrt(1.0 - zeta * zeta)
		return 1.0 - envelope * (cos(wd * t) + ((zeta * w0 - velocity) / wd) * sin(wd * t))
	else: # Overdamped or critically damped spring curve
		return 1.0 - envelope * (1.0 + (w0 - velocity) * t)

# ==============================================================================
# INTERNAL HELPER CLASSES & API TIMELINE
# ==============================================================================

# Inner class resolving frame-delayed start values for custom expressions
class _InterpolationBinder:
	extends RefCounted
	
	var target: Object
	var prop: StringName
	var start_val
	var end_val
	var ease_name: String
	var is_initialized := false
	
	func _init(t: Object, p: StringName, e_val, e_name: String):
		target = t
		prop = p
		end_val = e_val
		ease_name = e_name

	func interpolate(t: float) -> void:
		if not is_instance_valid(target):
			return
		if not is_initialized:
			start_val = target.get(prop)
			is_initialized = true
			
		var f = Extween.evaluate_easing(ease_name, t)
		if start_val is Vector2 or start_val is Vector3 or start_val is Color:
			target.set(prop, start_val.lerp(end_val, f))
		else:
			target.set(prop, start_val + (end_val - start_val) * f)


# Timeline API Implementation
class Timeline:
	extends RefCounted

	var _steps: Array = []
	var _engine: Extween
	var _context: Node
	var _started := false

	func _init(context: Node):
		_context = context
		_engine = Extween.new(context)

	func to(targets, config: Dictionary) -> Timeline:
		_steps.append({
			"type": "to",
			"targets": targets,
			"props": _extract_props(config),
			"duration": config.get("duration", 1000.0),
			"ease": config.get("ease", "linear"),
			"delay": config.get("delay", 0.0),
			"stagger": config.get("stagger", 0.0)
		})
		return self

	func from(targets, config: Dictionary) -> Timeline:
		_steps.append({
			"type": "from",
			"targets": targets,
			"props": _extract_props(config),
			"duration": config.get("duration", 1000.0),
			"ease": config.get("ease", "linear"),
			"delay": config.get("delay", 0.0),
			"stagger": config.get("stagger", 0.0)
		})
		return self

	func wait(ms: float) -> Timeline:
		_steps.append({
			"type": "wait",
			"duration": ms
		})
		return self

	func play() -> void:
		if _started:
			return
		_started = true
		
		# Compile the structural sequential chain onto the single native Engine Tween
		for step in _steps:
			_engine.run_step(step)
			
		_engine.get_godot_tween().play()

	func _extract_props(config: Dictionary) -> Dictionary:
		var props = {}
		var reserved = ["duration", "ease", "delay", "stagger"]
		for k in config.keys():
			if k not in reserved:
				props[k] = config[k]
		return props
