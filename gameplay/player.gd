extends CharacterBody3D
## 模板人形。WASD 移动；进局后 Q / E 小技能，R 大招。进场面板还开着时不放技能。

const SPEED := 6.0
const GRAVITY := 20.0

var _forward := Vector3(0, 0, -1)
var _right := Vector3(1, 0, 0)
var _held: Dictionary = {}


func _physics_process(delta: float) -> void:
	_read_camera_axes()
	_poll_skills()
	var wish := _wish_direction()
	var locked: Variant = _locked_focus()
	if locked is Vector3:
		var to_target := (locked as Vector3) - global_position
		to_target.y = 0.0
		if to_target.length() > 0.05:
			look_at(global_position + to_target.normalized(), Vector3.UP)
	elif wish.length() > 0.05:
		look_at(global_position + wish, Vector3.UP)
	if wish.length() > 0.05:
		velocity.x = wish.x * SPEED
		velocity.z = wish.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _read_camera_axes() -> void:
	var cam := _camera()
	if cam == null or not cam.has_method("aim_axes"):
		return
	var axes: Dictionary = cam.aim_axes()
	_forward = axes.get("forward", _forward)
	_right = axes.get("right", _right)


func _wish_direction() -> Vector3:
	var input_x := 0.0
	var input_z := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_z += 1.0
	if input_x == 0.0 and input_z == 0.0:
		return Vector3.ZERO
	# input_z 为负表示前进。相机 forward 已经是水平朝向目标的单位向量。
	var wish := _right * input_x + _forward * (-input_z)
	wish.y = 0.0
	if wish.length() <= 0.001:
		return Vector3.ZERO
	return wish.normalized()


func _locked_focus() -> Variant:
	var cam := _camera()
	if cam == null or not cam.has_method("locked_point"):
		return null
	return cam.locked_point()


func _poll_skills() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var entry := parent_node.get_node_or_null("Entry")
	if entry != null and entry.visible:
		return
	_edge(KEY_Q, 0)
	_edge(KEY_E, 1)
	_edge(KEY_R, 2)


func _edge(key: Key, index: int) -> void:
	var down := Input.is_physical_key_pressed(key)
	var was := bool(_held.get(key, false))
	_held[key] = down
	if not down or was:
		return
	var parent_node := get_parent()
	if parent_node == null:
		return
	var duel = parent_node.get_node_or_null("Match")
	if duel != null and duel.has_method("local_cast"):
		duel.local_cast(index)


func _camera() -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("LockOnCamera")
