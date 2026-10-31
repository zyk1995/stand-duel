extends Node3D
## 开阔地上的半掩、全掩和一次成长拾取。掩体不挡出生点到训练桩的中轴线。


func _ready() -> void:
	_cover("HalfCover", Vector3(6, 1.0, -4), Vector3(1.2, 2.0, 1.2), "half", Color(0.55, 0.46, 0.28))
	_cover("FullCover", Vector3(-6, 1.0, -8), Vector3(1.6, 2.2, 0.8), "full", Color(0.28, 0.3, 0.34))
	_pickup(Vector3(2.4, 0.9, 2.0))


func _cover(node_name: String, pos: Vector3, size: Vector3, kind: String, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.add_to_group("cover")
	body.set_meta("cover_kind", kind)
	body.set_meta("size", size)
	# 无头假渲染器没有网格 RID，运行时新建 Mesh 会在 surface 查询里报错。判定只看 meta。
	if DisplayServer.get_name() != "headless":
		var mesh_node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_node.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		mesh_node.material_override = material
		body.add_child(mesh_node)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)


func _pickup(pos: Vector3) -> void:
	var area := Area3D.new()
	area.name = "GrowthPickup"
	area.position = pos
	area.add_to_group("growth_pickup")
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	shape_node.shape = shape
	area.add_child(shape_node)
	if DisplayServer.get_name() != "headless":
		var mesh_node := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.56
		mesh_node.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.35, 0.82, 0.4)
		mesh_node.material_override = material
		area.add_child(mesh_node)
	area.body_entered.connect(_on_pickup_body)
	add_child(area)


func _on_pickup_body(body: Node) -> void:
	if body == null or body.name != "Player":
		return
	var duel = get_parent().get_node_or_null("Match")
	if duel == null or not duel.started:
		return
	if duel.has_method("grant_local_pickup"):
		var granted: Dictionary = duel.grant_local_pickup()
		if not bool(granted.get("ok", false)):
			return
	var pickup := get_node_or_null("GrowthPickup")
	if pickup != null:
		pickup.queue_free()
