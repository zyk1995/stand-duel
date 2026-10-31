extends CanvasLayer
## 进场前：提示词 → 出卡校验 → 确认进匹配。没配 key 时生成器走假数据，界面会写出来源。

var _prompt: LineEdit
var _status: Label
var _confirm: Button
var _card: Dictionary = {}
var _ready_to_enter := false


func _ready() -> void:
	layer = 10
	_build()


func generate_prompt(text: String, allow_network: bool = true) -> Dictionary:
	var generator = _generator()
	if generator == null or not generator.has_method("generate_from_prompt"):
		var missing := {"ok": false, "code": "no_generator", "message": "场景里没有出卡节点"}
		_show_result(missing)
		return missing
	var result: Dictionary = generator.generate_from_prompt(text, allow_network)
	_show_result(result)
	return result


func confirm() -> Dictionary:
	if not _ready_to_enter:
		return {"ok": false, "code": "not_ready", "message": "要先生成并通过校验"}
	var duel = _match()
	if duel == null or not duel.has_method("begin"):
		return {"ok": false, "code": "no_match", "message": "场景里没有对局节点"}
	var began: Dictionary = duel.begin(_card)
	if not bool(began.get("ok", false)):
		_status.text = "未能进局：%s" % str(began.get("message", began.get("code", "")))
		return began
	if _prompt != null:
		_prompt.release_focus()
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	visible = false
	return began


func _build() -> void:
	var panel := Panel.new()
	panel.position = Vector2(700, 16)
	panel.size = Vector2(540, 460)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	box.size = Vector2(508, 428)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "进场前写下替身提示词"
	box.add_child(title)
	_prompt = LineEdit.new()
	_prompt.placeholder_text = "例如：冷静的近战决斗者，风衣，短刃"
	_prompt.custom_minimum_size = Vector2(480, 36)
	box.add_child(_prompt)
	var generate := Button.new()
	generate.text = "生成并校验"
	generate.pressed.connect(_on_generate)
	box.add_child(generate)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(480, 220)
	_status.text = "尚未生成。没有 API key 时会用确定性假卡，仍然走同一套校验。"
	box.add_child(_status)
	_confirm = Button.new()
	_confirm.text = "确认进匹配"
	_confirm.disabled = true
	_confirm.pressed.connect(_on_confirm)
	box.add_child(_confirm)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.text = "进局后 Q / E 小技能，R 大招，Tab 锁定。绿色球拾取成长，本局最多 3 层。"
	box.add_child(hint)


func _on_generate() -> void:
	generate_prompt(_prompt.text if _prompt != null else "", true)


func _on_confirm() -> void:
	confirm()


func _show_result(result: Dictionary) -> void:
	if _status == null or _confirm == null:
		return
	if not bool(result.get("ok", false)):
		_ready_to_enter = false
		_card = {}
		_confirm.disabled = true
		_status.text = "校验失败：%s" % str(result.get("message", result.get("code", "")))
		return
	var card = result.get("card", {})
	if typeof(card) != TYPE_DICTIONARY:
		_ready_to_enter = false
		_confirm.disabled = true
		_status.text = "生成结果不是卡面"
		return
	_card = (card as Dictionary).duplicate(true)
	_ready_to_enter = true
	_confirm.disabled = false
	var stats: Dictionary = _card.get("stats", {})
	var image: Dictionary = result.get("image", {})
	_status.text = "校验通过 · %s\n来源 %s · 尝试 %s\n%s\n力量 %s  速度 %s  射程 %s\n持续 %s  精密 %s  成长 %s\n占位贴图 %s %s" % [
		str(_card.get("name", "")),
		str(result.get("source", "")),
		str(result.get("attempts", 1)),
		str(result.get("message", "")),
		str(stats.get("power", "")),
		str(stats.get("speed", "")),
		str(stats.get("range", "")),
		str(stats.get("stamina", "")),
		str(stats.get("precision", "")),
		str(stats.get("growth", "")),
		str(image.get("mode", "")),
		str(image.get("color", "")),
	]


func _generator():
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("AI")


func _match():
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("Match")
