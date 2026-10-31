extends Camera3D
## 锁定第三人称。默认锁最近目标；meta hurt_priority 越大越优先，用来表示「刚受伤」。
## 每帧扫描 lock_target 组。W0 目标极少。人数上去后应改成进组/出组时维护候选，避免每帧分配数组。

signal lock_changed(target_name: String)

@export var player_path: NodePath = NodePath("../Player")
@export var arm_length := 6.0
@export var camera_height := 2.6

var _lock_enabled := true
var _forward := Vector3(0, 0, -1)
var _right := Vector3(1, 0, 0)
var _target: Node3D = null
var _announced := ""
var _player: Node3D = null


func _ready() -> void:
	current = true
	_player = get_node_or_null(player_path) as Node3D
	update_aim()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_TAB:
			_lock_enabled = not _lock_enabled
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	update_aim()


func aim_axes() -> Dictionary:
	return {"forward": _forward, "right": _right}


## 未锁定时返回 null。
func locked_point():
	if _target == null:
		return null
	return _target.global_position


func update_aim() -> void:
	if _player == null:
		_player = get_node_or_null(player_path) as Node3D
	_target = _pick_target() if _lock_enabled else null
	if _player != null and _target != null:
		var flat := _target.global_position - _player.global_position
		flat.y = 0.0
		if flat.length() > 0.05:
			_forward = flat.normalized()
	elif _player != null:
		var face := -_player.global_transform.basis.z
		face.y = 0.0
		if face.length() > 0.1:
			_forward = face.normalized()
	_right = _forward.cross(Vector3.UP)
	if _right.length() < 0.001:
		_right = Vector3.RIGHT
	else:
		_right = _right.normalized()
	if _player != null:
		var look_point := _player.global_position + Vector3.UP * 1.3
		if _target != null:
			look_point = _target.global_position + Vector3.UP * 0.4
		global_position = _player.global_position - _forward * arm_length + Vector3.UP * camera_height
		if global_position.distance_squared_to(look_point) > 0.0001:
			look_at(look_point, Vector3.UP)
	_announce()


func _pick_target() -> Node3D:
	if _player == null:
		return null
	var best: Node3D = null
	var best_score := 1.0e20
	for node in get_tree().get_nodes_in_group("lock_target"):
		if node == _player or not (node is Node3D):
			continue
		var candidate := node as Node3D
		var distance := _player.global_position.distance_to(candidate.global_position)
		var hurt := float(candidate.get_meta("hurt_priority", 0.0))
		# 受伤加权必须压过地图尺度内的距离差，否则「优先受伤目标」不成立。
		var score := distance - hurt * 10000.0
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _announce() -> void:
	var label := ""
	if _target != null:
		if _target.has_meta("display_name"):
			label = str(_target.get_meta("display_name"))
		else:
			label = _target.name
	if label == _announced:
		return
	_announced = label
	lock_changed.emit(label)
