extends RefCounted
class_name StandCard
## 替身卡装载。W0 不做数值修正，只把 JSON 收成字典。

var data: Dictionary = {}


func _init(raw: Dictionary = {}) -> void:
	data = raw.duplicate(true)


## 解析失败时返回 null。调用方要自己判断。
static func from_json_text(text: String):
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	# 同一脚本里不能用 class_name 自引用。
	return load("res://stand/stand_card.gd").new(parsed)


## 读 res:// 或绝对路径。文件缺失或 JSON 不是对象时返回 null。
static func load_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	return from_json_text(FileAccess.get_file_as_string(path))
