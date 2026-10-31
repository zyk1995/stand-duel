extends SceneTree
## W3 无头自检。退出码 0 且打印 “W3 checks passed” 才算通过。
## 不访问网络。godot --headless --path . --script res://tests/run_w3_checks.gd

const AiScript = preload("res://ai/stand_generator.gd")
const ValidatorScript = preload("res://stand/stand_validator.gd")
const CardScript = preload("res://stand/stand_card.gd")
const CostumeScript = preload("res://ai/costume.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ai = AiScript.new()
	_check_offline(ai)
	_check_weaken(ai)
	_check_parse(ai)
	ai.free()
	if _failed == 0:
		print("W3 checks passed")
		quit(0)
	else:
		print("W3 checks failed: %d" % _failed)
		quit(1)


func _check(cond: bool, message: String) -> void:
	if cond:
		return
	_failed += 1
	print("FAIL: ", message)


func _check_offline(ai) -> void:
	var empty: Dictionary = ai.generate_from_prompt("   ", false)
	_check(not bool(empty.get("ok", true)) and str(empty.get("code", "")) == "empty_prompt", "空提示词应失败")
	var first: Dictionary = ai.generate_from_prompt("镜花", false)
	var second: Dictionary = ai.generate_from_prompt("镜花", false)
	_check(bool(first.get("ok", false)), "假数据应能出卡：%s" % str(first.get("message", "")))
	_check(str(first.get("source", "")).begins_with("fixture"), "无网络时应走 fixture，实际 " + str(first.get("source", "")))
	_check(bool(ValidatorScript.validate(first.get("card", {})).get("ok", false)), "假卡必须通过校验")
	_check(str(first.get("card", {}).get("name", "")) == str(second.get("card", {}).get("name", "")), "同一提示词名字应稳定")
	_check(first.get("card", {}).get("stats", {}) == second.get("card", {}).get("stats", {}), "同一提示词六维应稳定")
	var banned: Dictionary = ai.generate_from_prompt("秒杀一切", false)
	_check(bool(banned.get("ok", false)), "黑名单提示词应弱化成合法卡")
	_check(bool(ValidatorScript.validate(banned.get("card", {})).get("ok", false)), "弱化后的卡要通过校验")
	var image: Dictionary = first.get("image", {})
	_check(str(image.get("mode", "")) == "placeholder", "文生图保持占位")
	_check(str(image.get("url", "")).begins_with("user://"), "占位图写到本地 user://")
	_check(str(image.get("color", "")).length() >= 6, "占位颜色应有色值")
	var card: Dictionary = first.get("card", {})
	var expected := CostumeScript.color_from_card(card)
	_check(str(image.get("color", "")) == expected.to_html(false), "占位色与模板换色一致")


func _check_weaken(ai) -> void:
	var loaded = CardScript.load_file("res://stand/fixtures/invalid_overpowered.json")
	_check(loaded != null, "应能读到非法夹具")
	if loaded == null:
		return
	var raw: Dictionary = loaded.data
	_check(not bool(ValidatorScript.validate(raw).get("ok", true)), "非法夹具先失败")
	var weakened: Dictionary = ai.weaken_card(raw)
	var verdict: Dictionary = ValidatorScript.validate(weakened)
	_check(bool(verdict.get("ok", false)), "弱化后应通过：%s" % str(verdict.get("errors", [])))
	_check(bool(weakened.get("appearance", {}).get("humanoid", false)), "弱化后必须是人形")
	_check(float(weakened.get("appearance", {}).get("height_m", 99)) <= 2.0, "身高应被钳进 2 米")
	_check(float(weakened.get("appearance", {}).get("height_m", 0)) >= 1.5, "身高不应低于 1.5 米")


func _check_parse(ai) -> void:
	var url: Dictionary = ai._split_url("https://api.openai.com/v1")
	_check(bool(url.get("tls", false)) and str(url.get("host", "")) == "api.openai.com", "应拆出主机名")
	_check(int(url.get("port", 0)) == 443 and str(url.get("prefix", "")) == "/v1", "https 默认 443，路径前缀保留")
	var plain: Dictionary = ai._split_url("http://127.0.0.1:8080/v1")
	_check(not bool(plain.get("tls", true)) and int(plain.get("port", 0)) == 8080, "自定义端口应保留")
	var parsed = ai._extract_json("说明\n```json\n{\"name\":\"A\"}\n```")
	_check(typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("name", "")) == "A", "应从包裹文本里抽出 JSON")
	_check(ai._extract_json("没有对象") == null, "没有 JSON 时应失败")
