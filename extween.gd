class_name Extween
extends RefCounted


enum PlayState { PAUSED, PLAYING, COMPLETED }


var _tween: Tween
var _state: PlayState = PlayState.PAUSED
var _context: Node


func _init(context: Node = null):
	if context:
		_context = context
		_tween = context.get_tree().create_tween()


func run_step(step: Dictionary) -> void:
	var targets = step.get("targets", [])
	if not (targets is Array):
		targets = [targets]

	var duration := step.get("duration", 1000.0) / 1000.0
	var ease := step.get("ease", "linear")
	var delay := step.get("delay", 0.0)
	var stagger := step.get("stagger", 0.0)
	var props := step.get("props", {})

	var index := 0

	for target in targets:
		if not is_instance_valid(target):
			continue

		var target_delay = delay + (index * stagger)

		for prop in props.keys():
			var end_val = props[prop]
			var start_val = target.get(prop)

			if _is_simple(end_val):
				var tw = _tween.tween_property(target, prop, end_val, duration)
				_apply_ease(tw, ease)
				tw.set_delay(target_delay)
			else:
				var fn = func(t):
					return evaluate_easing(ease, t)

				var tw2 = _tween.tween_method(func(t):
					var f = fn.call(t)

					if start_val is Vector2 or start_val is Vector3 or start_val is Color:
						target.set(prop, start_val.lerp(end_val, f))
					else:
						target.set(prop, start_val + (end_val - start_val) * f)
				, 0.0, 1.0, duration)

				tw2.set_delay(target_delay)

		index += 1


static func _is_simple(value) -> bool:
	return typeof(value) in [
		TYPE_FLOAT,
		TYPE_INT,
		TYPE_VECTOR2,
		TYPE_VECTOR3,
		TYPE_COLOR
	]


static func _apply_ease(tw: Tween, ease: String) -> void:
	match ease.to_lower():
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


# timeline
class Timeline:
	extends RefCounted

	var _steps: Array = []
	var _engine: Extween
	var _context: Node
	var _index := 0
	var _started := false


	func _init(context: Node):
		_context = context
		_engine = Extween.new(context)


	func to(targets, config: Dictionary) -> Timeline:
		_steps.append({
			"type": "to",
			"targets": targets,
			"props": _extract_props(config),
			"duration": config.get("duration", 1000),
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


	func from(targets, config: Dictionary) -> Timeline:
		for t in targets:
			if not is_instance_valid(t):
				continue
			for k in config.keys():
				t.set(k, config[k])
		return self


	func play() -> void:
		if _started:
			return

		_started = true
		_run_next()


	func _run_next() -> void:
		if _index >= _steps.size():
			return

		var step = _steps[_index]
		_index += 1

		match step.type:
			"wait":
				var timer = _context.get_tree().create_timer(step.duration / 1000.0)
				timer.timeout.connect(_run_next)

			_:
				_engine.run_step(step)
				var timer2 = _context.get_tree().create_timer(step.duration / 1000.0)
				timer2.timeout.connect(_run_next)


	func _extract_props(config: Dictionary) -> Dictionary:
		var props = {}
		var reserved = ["duration", "ease", "delay", "stagger"]

		for k in config.keys():
			if k not in reserved:
				props[k] = config[k]

		return props
