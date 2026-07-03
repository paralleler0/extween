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
		_tween.stop()
		_tween.finished.connect(func(): _state = PlayState.COMPLETED)

func get_godot_tween() -> Tween:
	return _tween

func run_step(step: Dictionary) -> void:
	if not _tween or not _tween.is_valid():
		return
		
	var step_type: String = step.get("type", "to")
	if step_type == "wait":
		var duration := float(step.get("duration", 0.0)) / 1000.0
		_tween.append_interval(duration)
		return
		
	var targets = step.get("targets", [])
	if not (targets is Array):
		targets = [targets]
		
	var duration := float(step.get("duration", 1000.0)) / 1000.0
	var ease_name := str(step.get("ease", "linear"))
	var delay := float(step.get("delay", 0.0)) / 1000.0
	
	var total_targets = targets.size()
	var step_stagger = step.get("stagger", 0.0)
	var step_stagger_options = step.get("stagger_options", {})
	var props := step.get("props", {})
	var is_native_ease := _is_native_easing(ease_name)
	
	# Ensure this entire step blocks the next step sequentially
	_tween.chain()
	
	for index in range(total_targets):
		var target = targets[index]
		if not is_instance_valid(target):
			continue
			
		# Spatial grid offset delay evaluation
		var target_delay = delay
		if step_stagger_options.keys().size() > 0:
			target_delay += (Stagger.calculate(step_stagger, index, total_targets, step_stagger_options) / 1000.0)
		else:
			target_delay += (index * (float(step_stagger) / 1000.0))
			
		for prop in props.keys():
			var end_val = props[prop]
			
			# Dynamic property grid offset interpolation checks
			if end_val is Dictionary and end_val.has("__is_stagger"):
				end_val = Stagger.calculate(end_val.value, index, total_targets, end_val.options)
				
			# Forces properties to execute in parallel relative to the step start anchor
			if index > 0 or prop != props.keys()[0]:
				_tween.parallel()
				
			if step_type == "from":
				# Native types optimization path
				if is_native_ease and _is_simple(end_val):
					# Use a custom internal method binder to safely initialize values
					# only when this specific tween segment officially begins running
					var setup_tw = _tween.tween_method(
						func(_v):
							if is_instance_valid(target):
								var current = target.get(prop)
								target.set(prop, end_val)
								# Dynamically updates the downstream property tween target endpoint
								_tween.custom_step(0.0)
						, 0.0, 0.0, 0.0)
						
					if target_delay > 0.0:
						setup_tw.set_delay(target_delay)
						
					_tween.parallel()
					var main_tw = _tween.tween_property(target, prop, target.get(prop), duration)
					_apply_ease(main_tw, ease_name)
					main_tw.set_delay(target_delay)
				else:
					# Complex custom curves evaluation execution pipeline
					var binder = _InterpolationBinder.new(target, prop, end_val, ease_name, true)
					var tw2 = _tween.tween_method(binder.interpolate, 0.0, 1.0, duration)
					if target_delay > 0.0:
						tw2.set_delay(target_delay)
			else:
				# Standard "to" operations execution pipeline
				if is_native_ease and _is_simple(end_val):
					var tw := _tween.tween_property(target, prop, end_val, duration)
					_apply_ease(tw, ease_name)
					if target_delay > 0.0:
						tw.set_delay(target_delay)
				else:
					var binder = _InterpolationBinder.new(target, prop, end_val, ease_name, false)
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
	var base = e.replace("easeinout", "").replace("easein", "").replace("easeout", "")
	if base == "":
		base = "linear"
	return base in ["linear", "sine", "quad", "cubic", "quart", "quint", "expo", "circ", "back", "bounce", "elastic"]

static func _apply_ease(tw: PropertyTween, ease_name: String) -> void:
	var e = ease_name.strip_edges().to_lower()
	if e.begins_with("easeinout"):
		tw.set_ease(Tween.EASE_IN_OUT)
	elif e.begins_with("easeout"):
		tw.set_ease(Tween.EASE_OUT)
	elif e.begins_with("easein"):
		tw.set_ease(Tween.EASE_IN)
	else:
		tw.set_ease(Tween.EASE_IN_OUT)
		
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
	
	if e.begins_with("in(") and e.ends_with(")"):
		var p = e.get_slice("(", 1).replace(")", "").to_float()
		return pow(t, p)
	if e.begins_with("out(") and e.ends_with(")"):
		var p = e.get_slice("(", 1).replace(")", "").to_float()
		return 1.0 - pow(1.0 - t, p)
	if e.begins_with("cubicbezier(") or e.begins_with("bezier("):
		var raw = e.get_slice("(", 1).replace(")", "")
		var params = raw.split(",")
		if params.size() == 4:
			return _solve_bezier(t, params[0].to_float(), params[1].to_float(), params[2].to_float(), params[3].to_float())
	if e.begins_with("spring("):
		var raw = e.get_slice("(", 1).replace(")", "")
		var params = raw.split(",")
		var mass := 1.0 if params.size() < 1 else params[0].to_float()
		var stiffness := 100.0 if params.size() < 2 else params[1].to_float()
		var damping := 10.0 if params.size() < 3 else params[2].to_float()
		var velocity := 0.0 if params.size() < 4 else params[3].to_float()
		return _solve_spring(t, mass, stiffness, damping, velocity)
		
	match e:
		"insine": return 1.0 - cos(t * PI * 0.5)
		"outsine": return sin(t * PI * 0.5)
		"inoutcirc": return 0.5 * (1.0 - cos(PI * t)) if t < 0.5 else 0.5 * (1.0 + sqrt(1.0 - pow(2.0 * t - 2.0, 2.0)))
		"outcirc": return sqrt(1.0 - pow(t - 1.0, 2.0))
		_: return t

static func _solve_bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if x1 == y1 and x2 == y2:
		return t
	var low := 0.0
	var high := 1.0
	var guess_x := 0.0
	for i in range(8):
		guess_x = (low + high) / 2.0
		var x = 3.0 * pow(1.0 - guess_x, 2.0) * guess_x * x1 + 3.0 * (1.0 - guess_x) * pow(guess_x, 2.0) * x2 + pow(guess_x, 3.0)
		if x > t:
			high = guess_x
		else:
			low = guess_x
	return 3.0 * pow(1.0 - guess_x, 2.0) * guess_x * y1 + 3.0 * (1.0 - guess_x) * pow(guess_x, 2.0) * y2 + pow(guess_x, 3.0)

static func _solve_spring(t: float, mass: float, stiffness: float, damping: float, velocity: float) -> float:
	var w0 = sqrt(stiffness / mass)
	var zeta = damping / (2.0 * sqrt(stiffness * mass))
	var envelope = exp(-zeta * w0 * t)
	if zeta < 1.0:
		var wd = w0 * sqrt(1.0 - zeta * zeta)
		return 1.0 - envelope * (cos(wd * t) + ((zeta * w0 - velocity) / wd) * sin(wd * t))
	else:
		return 1.0 - envelope * (1.0 + (w0 - velocity) * t)

# ==============================================================================
# SPATIAL 2D/1D STAGGER CALCULATION CORE
# ==============================================================================
class Stagger:
	static func calculate(base_val, current_index: int, total_count: int, options: Dictionary) -> Variant:
		var grid = options.get("grid", [])
		var from_pos = options.get("from", "first")
		
		if grid.size() < 2:
			var index_factor = (total_count - 1 - current_index) if from_pos == "last" else current_index
			return _evaluate_output(base_val, index_factor, total_count)
			
		var cols: int = grid[0]
		var rows: int = grid[1]
		
		var current_x = current_index % cols
		var current_y = current_index / cols
		
		var center_x = (cols - 1) / 2.0
		var center_y = (rows - 1) / 2.0
		
		var pivot_x := 0.0
		var pivot_y := 0.0
		
		match from_pos:
			"center":
				pivot_x = center_x
				pivot_y = center_y
			"last":
				pivot_x = cols - 1
				pivot_y = rows - 1
			"first", _:
				pivot_x = 0.0
				pivot_y = 0.0
				
		var dx = current_x - pivot_x
		var dy = current_y - pivot_y
		var distance = sqrt(dx*dx + dy*dy)
		
		var max_dx = max(pivot_x, cols - 1 - pivot_x)
		var max_dy = max(pivot_y, rows - 1 - pivot_y)
		var max_distance = sqrt(max_dx*max_dx + max_dy*max_dy)
		if max_distance == 0: max_distance = 1.0
		
		var normalized_factor = distance / max_distance
		
		if base_val is Array and base_val.size() == 2:
			return _lerp_any(base_val[0], base_val[1], normalized_factor)
		elif base_val is float or base_val is int:
			return float(base_val) * distance
			
		return base_val

	static func _evaluate_output(base_val, index: int, total: int) -> Variant:
		var factor = float(index) / max(1, total - 1)
		if base_val is Array and base_val.size() == 2:
			return _lerp_any(base_val[0], base_val[1], factor)
		return float(base_val) * index

	static func _lerp_any(a, b, t: float) -> Variant:
		if a is Vector2 and b is Vector2: return a.lerp(b, t)
		if a is Vector3 and b is Vector3: return a.lerp(b, t)
		if a is Color and b is Color: return a.lerp(b, t)
		return lerp(float(a), float(b), t)
# ==============================================================================
# INTERNAL HELPER CLASSES & API TIMELINE
# ==============================================================================
class _InterpolationBinder:
	extends RefCounted
	var target: Object
	var prop: StringName
	var start_val
	var end_val
	var ease_name: String
	var is_from_type: bool
	var is_initialized := false
	
	func _init(t: Object, p: StringName, e_val, e_name: String, is_from: bool):
		target = t
		prop = p
		end_val = e_val
		ease_name = e_name
		is_from_type = is_from
		
	func interpolate(t: float) -> void:
		if not is_instance_valid(target):
			return
		if not is_initialized:
			var current_live_val = target.get(prop)
			if is_from_type:
				start_val = end_val
				end_val = current_live_val
				target.set(prop, start_val)
			else:
				start_val = current_live_val
			is_initialized = true
			
		var f = Extween.evaluate_easing(ease_name, t)
		if start_val is Vector2 or start_val is Vector3 or start_val is Color:
			target.set(prop, start_val.lerp(end_val, f))
		else:
			target.set(prop, start_val + (end_val - start_val) * f)

class Timeline:
	extends RefCounted
	var _steps: Array = []
	var _engine: Extween
	var _context: Node
	var _started := false
	var _loops := 1
	
	func _init(context: Node):
		_context = context
		_engine = Extween.new(context)
		
	func stagger(value, options: Dictionary = {}) -> Dictionary:
		return { "__is_stagger": true, "value": value, "options": options }
		
	func to(targets, config: Dictionary, global_stagger_val = null, global_stagger_options: Dictionary = {}) -> Timeline:
		var parsed_stagger = config.get("stagger", 0.0)
		var parsed_options = {}
		
		if global_stagger_val != null:
			parsed_stagger = global_stagger_val
			parsed_options = global_stagger_options
		elif config.has("stagger_options"):
			parsed_options = config.get("stagger_options", {})
			
		_steps.append({
			"type": "to",
			"targets": targets,
			"props": _extract_props(config),
			"duration": config.get("duration", 1000.0),
			"ease": config.get("ease", "linear"),
			"delay": config.get("delay", 0.0),
			"stagger": parsed_stagger,
			"stagger_options": parsed_options
		})
		return self
		
	func from(targets, config: Dictionary, global_stagger_val = null, global_stagger_options: Dictionary = {}) -> Timeline:
		var parsed_stagger = config.get("stagger", 0.0)
		var parsed_options = {}
		
		if global_stagger_val != null:
			parsed_stagger = global_stagger_val
			parsed_options = global_stagger_options
		elif config.has("stagger_options"):
			parsed_options = config.get("stagger_options", {})
			
		_steps.append({
			"type": "from",
			"targets": targets,
			"props": _extract_props(config),
			"duration": config.get("duration", 1000.0),
			"ease": config.get("ease", "linear"),
			"delay": config.get("delay", 0.0),
			"stagger": parsed_stagger,
			"stagger_options": parsed_options
		})
		return self
		
	func wait(ms: float) -> Timeline:
		_steps.append({
			"type": "wait",
			"duration": ms
		})
		return self
		
	func set_loops(loops: int) -> Timeline:
		_loops = loops
		return self
		
	func play() -> void:
		if _started:
			return
		_started = true
		var native_tween = _engine.get_godot_tween()
		if native_tween:
			native_tween.set_loops(_loops)
		for step in _steps:
			_engine.run_step(step)
		_engine._state = Extween.PlayState.PLAYING
		_engine.get_godot_tween().play()
		
	func _extract_props(config: Dictionary) -> Dictionary:
		var props = {}
		var reserved = ["duration", "ease", "delay", "stagger", "stagger_options"]
		for k in config.keys():
			if k not in reserved:
				props[k] = config[k]
		return props

