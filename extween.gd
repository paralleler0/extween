class_name extween
extends Node

# ----------------------------
# EASING ENUM (FIXED)
# ----------------------------
enum Ease {
	LINEAR,

	IN_SINE,
	OUT_SINE,
	IN_OUT_SINE,

	IN_QUAD,
	OUT_QUAD,
	IN_OUT_QUAD,

	IN_CUBIC,
	OUT_CUBIC,
	IN_OUT_CUBIC,

	IN_QUART,
	OUT_QUART,
	IN_OUT_QUART,

	IN_QUINT,
	OUT_QUINT,
	IN_OUT_QUINT,

	IN_EXPO,
	OUT_EXPO,
	IN_OUT_EXPO,

	IN_CIRC,
	OUT_CIRC,
	IN_OUT_CIRC,

	IN_BACK,
	OUT_BACK,
	IN_OUT_BACK,

	IN_BOUNCE,
	OUT_BOUNCE,
	IN_OUT_BOUNCE,

	STEPS,

	IN_ELASTIC,
	OUT_ELASTIC,
	IN_OUT_ELASTIC,

	CUBIC_BEZIER,
	SPRING
}

# ----------------------------
# STRING -> ENUM MAP
# ----------------------------
const EASING_FUNCTIONS = {
	"linear": Ease.LINEAR,

	"sine": Ease.IN_SINE,
	"insine": Ease.IN_SINE,
	"outsine": Ease.OUT_SINE,
	"inoutsine": Ease.IN_OUT_SINE,

	"quad": Ease.IN_QUAD,
	"inquad": Ease.IN_QUAD,
	"outquad": Ease.OUT_QUAD,
	"inoutquad": Ease.IN_OUT_QUAD,

	"cubic": Ease.IN_CUBIC,
	"quart": Ease.IN_QUART,
	"quint": Ease.IN_QUINT,

	"expo": Ease.IN_EXPO,
	"circ": Ease.IN_CIRC,

	"back": Ease.IN_BACK,
	"outback": Ease.OUT_BACK,
	"inoutback": Ease.IN_OUT_BACK,

	"bounce": Ease.OUT_BOUNCE,
	"steps": Ease.STEPS,

	"elastic": Ease.OUT_ELASTIC,
	"cubicbezier": Ease.CUBIC_BEZIER,
	"spring": Ease.SPRING
}

# ----------------------------
# TRACK DATA
# ----------------------------
class CompiledTrack:
	var getter: Callable
	var setter: Callable

	var from_value: float = 0.0
	var to_value: float = 0.0

	var duration: float = 0.0
	var delay: float = 0.0

	var easing_type: int = 0

	var easing_a: float = 0.0
	var easing_b: float = 0.0
	var easing_c: float = 0.0
	var easing_d: float = 0.0

	var is_relative: bool = false
	var relative_multiplier: float = 1.0
	var relative_add: float = 0.0


# ----------------------------
# TIMELINE
# ----------------------------
class CompiledTimeline:
	var bytecode: Array[CompiledTrack] = []
	var elapsed_time: float = 0.0
	var is_playing: bool = false
	var total_duration: float = 0.0

	func play() -> void:
		for track in bytecode:
			if track.is_relative:
				var current_base = float(track.getter.call())
				track.from_value = current_base
				track.to_value = (current_base * track.relative_multiplier) + track.relative_add

		is_playing = true
		extween._register_compiled_run(self)

	func step_process(delta: float) -> bool:
		if not is_playing:
			return true

		elapsed_time += delta
		var active := false

		for track in bytecode:
			if elapsed_time < track.delay:
				active = true
				continue

			var t := (elapsed_time - track.delay) / max(track.duration, 0.00001)
			t = clamp(t, 0.0, 1.0)

			var weight := 1.0

			match track.easing_type:

				Ease.LINEAR:
					weight = t

				Ease.IN_SINE:
					weight = 1.0 - cos((t * PI) * 0.5)
				Ease.OUT_SINE:
					weight = sin((t * PI) * 0.5)
				Ease.IN_OUT_SINE:
					weight = -(cos(PI * t) - 1.0) * 0.5

				Ease.IN_QUAD:
					weight = t * t
				Ease.OUT_QUAD:
					weight = 1.0 - (1.0 - t) * (1.0 - t)
				Ease.IN_OUT_QUAD:
					weight = (2.0 * t * t) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) * 0.5

				Ease.IN_CUBIC:
					weight = t * t * t
				Ease.OUT_CUBIC:
					weight = 1.0 - pow(1.0 - t, 3.0)
				Ease.IN_OUT_CUBIC:
					weight = (4.0 * t * t * t) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5

				Ease.OUT_BOUNCE:
					weight = _bounce_out(t)

				Ease.IN_BOUNCE:
					weight = 1.0 - _bounce_out(1.0 - t)

				Ease.IN_OUT_BOUNCE:
					weight = (_bounce_out(t * 2.0) * 0.5) if t < 0.5 else (1.0 + _bounce_out(t * 2.0 - 1.0)) * 0.5

				_:
					weight = t

			var value = lerp(track.from_value, track.to_value, weight)
			track.setter.call(value)

			if t < 1.0:
				active = true

		return not active


	func _bounce_out(t: float) -> float:
		var n = 7.5625
		var d = 2.75

		if t < 1.0 / d:
			return n * t * t
		elif t < 2.0 / d:
			t -= 1.5 / d
			return n * t * t + 0.75
		elif t < 2.5 / d:
			t -= 2.25 / d
			return n * t * t + 0.9375
		else:
			t -= 2.625 / d
			return n * t * t + 0.984375


# ----------------------------
# COMPILER
# ----------------------------
class Compiler:
	static func compile(params: Dictionary) -> CompiledTimeline:
		var timeline = CompiledTimeline.new()

		var targets_raw = params.get("targets", [])
		var targets: Array = targets_raw if targets_raw is Array else [targets_raw]

		var duration := float(params.get("duration", 1000.0)) / 1000.0
		var delay := float(params.get("delay", 0.0)) / 1000.0

		var easing = str(params.get("easing", "linear")).to_lower()
		var easing_type = EASING_FUNCTIONS.get(easing, Ease.LINEAR)

		for prop_key in params.keys():
			if prop_key in ["targets", "duration", "easing", "delay"]:
				continue

			for target in targets:
				if not is_instance_valid(target):
					continue

				var track = CompiledTrack.new()

				track.duration = duration
				track.delay = delay
				track.easing_type = easing_type

				var captured_target = target
				var captured_key = prop_key

				track.getter = func():
					return captured_target.get(captured_key)

				track.setter = func(v):
					captured_target.set(captured_key, v)

				var value = params[prop_key]

				if value is String:
					var s = value.strip_edges()
					track.is_relative = true

					if s.begins_with("+="):
						track.relative_add = s.substr(2).to_float()
					elif s.begins_with("-="):
						track.relative_add = -s.substr(2).to_float()
					elif s.begins_with("*="):
						track.relative_multiplier = s.substr(2).to_float()
				else:
					track.from_value = float(captured_target.get(prop_key))
					track.to_value = float(value)

				timeline.bytecode.append(track)
				timeline.total_duration = max(
					timeline.total_duration,
					track.delay + track.duration
				)

		return timeline


# ----------------------------
# RUNTIME DRIVER
# ----------------------------
class RuntimeTrackerNode extends Node:
	var active_runs: Array[CompiledTimeline] = []

	func _process(delta: float) -> void:
		for i in range(active_runs.size() - 1, -1, -1):
			if active_runs[i].step_process(delta):
				active_runs.remove_at(i)


static var _runtime_node_ref: WeakRef = weakref(null)


static func play(blueprint: Dictionary) -> CompiledTimeline:
	var compiled = Compiler.compile(blueprint)
	compiled.play()
	return compiled


static func _register_compiled_run(tl: CompiledTimeline) -> void:
	var tracker = _get_runtime_driver()
	if tracker and not tracker.active_runs.has(tl):
		tracker.active_runs.append(tl)


static func _get_runtime_driver() -> RuntimeTrackerNode:
	var driver = _runtime_node_ref.get_ref()
	if is_instance_valid(driver):
		return driver

	var tree = Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null

	var existing = tree.root.get_node_or_null("CompiledTweenRuntime")
	if existing is RuntimeTrackerNode:
		_runtime_node_ref = weakref(existing)
		return existing

	var new_driver = RuntimeTrackerNode.new()
	new_driver.name = "CompiledTweenRuntime"
	tree.root.call_deferred("add_child", new_driver)

	_runtime_node_ref = weakref(new_driver)
	return new_driver
