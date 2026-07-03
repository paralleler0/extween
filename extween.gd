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
				# 'from' animations require setting the target value immediately 
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

static func _is_native_easing(ease_name: String) -> bool:
	var e = ease_name.strip_edges().to_lower()
	return e in ["linear", "sine", "quad", "cubic", "quart", "quint", "expo", "circ", "back", "bounce", "elastic"]

static func _apply_ease(tw: PropertyTween, ease_name: String) -> void:
	match ease_name.to_lower():
		"linear": tw.set_trans(Tween.TRANS_LINEAR)
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

static func evaluate_easing(easing_name: String, t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	var e = easing_name.strip_edges().to_lower()

	if e.begins_with("in("):
		var p = e.split("(")[1].replace(")", "").to_float()
		return pow(t, p)

	if e.begins_with("out("):
		var p = e.split("(")[1].replace(")", "").to_float()
		return 1.0 - pow(1.0 - t, p)

	match e:
		"linear": return t
		"insine": return 1.0 - cos(t * PI * 0.5)
		"outsine": return sin(t * PI * 0.5)
		"inoutcirc": return 0.5 * (1.0 - cos(PI * t))
		"outcirc": return sqrt(1.0 - (t - 1.0) * (t - 1.0))
		_: return t

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
