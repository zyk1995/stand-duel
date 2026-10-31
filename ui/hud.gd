extends CanvasLayer
## 锁定一行，外加生命、技能冷却和成长层。文案没变就不写 Label，避免每帧重建控件。
## 相机可能在本节点 _ready 之前发出锁定信号，所以先把目标名记下来。

var _label: Label
var _lock := ""
var _got_lock := false


func _ready() -> void:
	_label = $Label as Label
	if _label != null:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _on_lock_changed(target_name: String) -> void:
	_lock = target_name if target_name != "" else "未锁定"
	_got_lock = true
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var lock_text := _lock if _got_lock else "未锁定"
	var hp_line := "生命 —"
	var cd_line := "技能 CD —"
	var layer_line := "成长 0/3"
	var result_line := ""
	var parent_node := get_parent()
	if parent_node != null:
		var player := parent_node.get_node_or_null("Player")
		if player != null and player.has_meta("max_hp"):
			hp_line = "生命 %d/%d" % [int(player.get_meta("hp", 0)), int(player.get_meta("max_hp", 0))]
			layer_line = "成长 %d/3" % int(player.get_meta("layers", 0))
			var cooldowns = player.get_meta("cooldowns", [])
			if typeof(cooldowns) == TYPE_ARRAY and cooldowns.size() >= 3:
				cd_line = "技能 CD %.1f / %.1f / %.1f" % [float(cooldowns[0]), float(cooldowns[1]), float(cooldowns[2])]
		var duel = parent_node.get_node_or_null("Match")
		if duel != null and str(duel.result_text) != "":
			result_line = "\n" + str(duel.result_text)
	var text := "替身对决 · 锁定：%s · Tab 切换\n%s · %s · %s\nQ / E 小技能 · R 大招%s" % [
		lock_text,
		hp_line,
		cd_line,
		layer_line,
		result_line,
	]
	if _label.text != text:
		_label.text = text
