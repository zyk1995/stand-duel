extends RefCounted
class_name Costume
## 文生图不做图生模。用卡名哈希出一个颜色，涂到模板胶囊上，并写一张纯色占位图。


static func color_from_card(card: Dictionary) -> Color:
	var seed_text := str(card.get("name", "替身"))
	var mixed := absi(hash(seed_text))
	var red := float((mixed % 160) + 50) / 255.0
	var green := float(((mixed / 17) % 160) + 40) / 255.0
	var blue := float(((mixed / 29) % 160) + 40) / 255.0
	return Color(red, green, blue, 1.0)


static func placeholder(card: Dictionary) -> Dictionary:
	var color := color_from_card(card)
	return {
		"ok": true,
		"mode": "placeholder",
		"url": "",
		"color": color.to_html(false),
	}


static func write_placeholder(card: Dictionary) -> String:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	image.fill(color_from_card(card))
	var path := "user://stand_portrait_placeholder.png"
	image.save_png(path)
	return path


static func apply_to_body(root: Node, card: Dictionary) -> void:
	if root == null:
		return
	_paint(root, color_from_card(card))


static func _paint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		mesh_node.material_override = material
	for child in node.get_children():
		_paint(child, color)
