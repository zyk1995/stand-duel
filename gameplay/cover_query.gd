extends RefCounted
class_name CoverQuery
## 线段对掩体盒。cover 组节点带 meta cover_kind（half / full）和 size（盒全尺寸，中心在节点上）。
## 人数和掩体都少，只在出招时查一次，不放进每帧循环。


static func between(tree: SceneTree, from: Vector3, to: Vector3) -> String:
	if tree == null:
		return "none"
	var hit_half := false
	for node in tree.get_nodes_in_group("cover"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		if not _hits(body, from, to):
			continue
		var kind := str(body.get_meta("cover_kind", "full"))
		if kind == "full":
			return "full"
		hit_half = true
	if hit_half:
		return "half"
	return "none"


static func _hits(body: Node3D, from: Vector3, to: Vector3) -> bool:
	var size: Vector3 = body.get_meta("size", Vector3(1, 2, 1))
	var inverse := body.global_transform.affine_inverse()
	var local_from := inverse * from
	var local_to := inverse * to
	var half := size * 0.5
	return _segment_aabb(local_from, local_to, -half, half)


static func _segment_aabb(a: Vector3, b: Vector3, box_min: Vector3, box_max: Vector3) -> bool:
	var delta := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in 3:
		var origin := a.x
		var step := delta.x
		var low := box_min.x
		var high := box_max.x
		if axis == 1:
			origin = a.y
			step = delta.y
			low = box_min.y
			high = box_max.y
		elif axis == 2:
			origin = a.z
			step = delta.z
			low = box_min.z
			high = box_max.z
		if absf(step) < 0.000001:
			if origin < low or origin > high:
				return false
			continue
		var inv := 1.0 / step
		var t1 := (low - origin) * inv
		var t2 := (high - origin) * inv
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		if t1 > tmin:
			tmin = t1
		if t2 < tmax:
			tmax = t2
		if tmin > tmax:
			return false
	return true
