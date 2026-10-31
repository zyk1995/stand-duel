extends CanvasLayer
## 一行状态。不在这里做进场提示词 UI（那是 W3）。
## 相机可能在本节点 _ready 之前发出锁定信号，所以先把文案记下来。

var _label: Label
var _pending := ""


func _ready() -> void:
	_label = $Label as Label
	if _pending.is_empty():
		_label.text = "替身对决 W0 · WASD 移动 · Tab 切换锁定"
	else:
		_label.text = _pending


func _on_lock_changed(target_name: String) -> void:
	var lock_text := target_name if target_name != "" else "未锁定"
	_pending = "替身对决 W0 · 锁定：%s · Tab 切换" % lock_text
	if _label != null:
		_label.text = _pending
