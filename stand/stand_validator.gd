extends RefCounted
class_name StandValidator
## 替身卡运行时校验，对齐 docs/stand_card.schema.json 与策划书硬规则。
## 不内嵌通用 JSON Schema 引擎。schema 改字段时这里要一起改。
## 黑名单按子串匹配，否定句（例如「不能重置大招」）也可能被拒，这是 W0 的已知缺口。
## 只检查 primary_stats 是否同时包含力量、速度、射程；文案里写了三连吃但没写进主属性时，这里不会拦。

const STAT_KEYS: PackedStringArray = ["power", "speed", "range", "stamina", "precision", "growth"]
const ULTIMATE_COSTS: PackedStringArray = ["stun", "self_damage", "window", "reveal"]
const BLACKLIST: PackedStringArray = [
	"秒杀",
	"无视掩体",
	"全图无代价索敌",
	"无条件真实伤害",
	"真实伤害且无条件",
	"无敌",
	"免死",
	"无限叠加",
	"无限叠伤",
	"无代价重置大招",
	"重置大招",
	"完整复制他人技能",
	"超长硬控",
]
const HEIGHT_MIN := 1.5
const HEIGHT_MAX := 2.0

var _errors: Array[Dictionary] = []


## 返回 {ok: bool, errors: Array}。errors 元素为 {code, message}。一次收集全部问题，方便夹具对照。
static func validate(card: Dictionary) -> Dictionary:
	# 同一脚本里不能用 class_name 自引用，否则 4.7 编译期找不到类型。
	var checker = load("res://stand/stand_validator.gd").new()
	checker._run(card)
	return {"ok": checker._errors.is_empty(), "errors": checker._errors}


func _run(card: Dictionary) -> void:
	_check_stats(card.get("stats", null))
	_check_skills(card.get("skills", null))
	_check_ultimate(card.get("ultimate", null))
	_check_passive(card.get("passive", null))
	_check_appearance(card.get("appearance", null))
	_check_required_text(card)
	_check_blacklist(card)


func _err(code: String, message: String) -> void:
	_errors.append({"code": code, "message": message})


func _check_stats(stats) -> void:
	if typeof(stats) != TYPE_DICTIONARY:
		_err("stats_sum", "缺少六维")
		return
	var parsed := {}
	for key in STAT_KEYS:
		if not stats.has(key):
			_err("stat_bounds", "缺少属性 %s" % key)
			continue
		var read := _read_whole_number(stats[key])
		if not read["ok"]:
			_err("stat_bounds", "%s 必须是整数" % key)
			continue
		var value := int(read["value"])
		parsed[key] = value
		if value < 1 or value > 5:
			_err("stat_bounds", "%s 超出 1–5" % key)
	for key in stats.keys():
		if not (String(key) in STAT_KEYS):
			_err("stat_bounds", "多余属性 %s" % String(key))
	if parsed.size() != STAT_KEYS.size():
		return
	var total := 0
	var fives := 0
	var lows := 0
	var all_three := true
	for key in STAT_KEYS:
		var value := int(parsed[key])
		total += value
		if value == 5:
			fives += 1
		if value <= 2:
			lows += 1
		if value != 3:
			all_three = false
	if total != 18:
		_err("stats_sum", "六维之和必须为 18，当前 %d" % total)
	# 有 5 且总和恰好 18 时，数学上必然出现 ≤2。规则仍单独写明，避免以后放宽总分时丢掉短板。
	if fives > 1:
		_err("short_stat", "至多 1 项为 5，当前 %d 项" % fives)
	if fives >= 1 and lows < 1:
		_err("short_stat", "存在 5 时至少要有 1 项 ≤ 2")
	if all_three:
		_err("all_threes", "禁止六维全 3")


func _check_skills(skills) -> void:
	if typeof(skills) != TYPE_ARRAY or skills.size() != 2:
		_err("skills", "必须恰好 2 个小技能")
	if typeof(skills) != TYPE_ARRAY:
		return
	for i in skills.size():
		_check_skill(skills[i], "skills[%d]" % i, false)


func _check_ultimate(ultimate) -> void:
	if typeof(ultimate) != TYPE_DICTIONARY:
		_err("ultimate_cost", "缺少大招")
		return
	_check_skill(ultimate, "ultimate", true)
	if not ultimate.has("cost"):
		_err("ultimate_cost", "大招必须带代价（硬直 / 自伤 / 空窗 / 暴露）")
		return
	var cost := str(ultimate["cost"])
	if not (cost in ULTIMATE_COSTS):
		_err("ultimate_cost", "大招代价 %s 不在允许列表" % cost)


func _check_skill(skill, path: String, is_ultimate: bool) -> void:
	if typeof(skill) != TYPE_DICTIONARY:
		_err("skills", "%s 不是对象" % path)
		return
	for field in ["name", "effect", "condition", "cover_interact"]:
		if typeof(skill.get(field, null)) != TYPE_STRING or str(skill.get(field)).is_empty():
			_err("skills", "%s 缺少 %s" % [path, field])
	for field in ["range", "cooldown", "duration"]:
		if not _is_non_negative_number(skill.get(field, null)):
			_err("skills", "%s.%s 必须是 ≥ 0 的数" % [path, field])
	_check_primary(skill.get("primary_stats", null), path)
	if is_ultimate:
		return


func _check_primary(stats_value, path: String) -> void:
	if typeof(stats_value) != TYPE_ARRAY:
		_err("primary_stats", "%s 缺少主属性" % path)
		return
	if stats_value.size() < 1 or stats_value.size() > 2:
		_err("primary_stats", "%s 主属性须为 1–2 项" % path)
	var seen := {}
	for stat_name in stats_value:
		var key := str(stat_name)
		if not (key in STAT_KEYS):
			_err("primary_stats", "%s 主属性 %s 无法识别" % [path, key])
		seen[key] = true
	if seen.has("power") and seen.has("speed") and seen.has("range"):
		_err("triple_dip", "%s 禁止同时吃满力量、速度、射程" % path)


func _check_passive(passive) -> void:
	if typeof(passive) != TYPE_DICTIONARY:
		_err("passive", "缺少被动")
		return
	if typeof(passive.get("name", null)) != TYPE_STRING or str(passive.get("name")).is_empty():
		_err("passive", "被动缺少名称")
	if typeof(passive.get("effect", null)) != TYPE_STRING or str(passive.get("effect")).is_empty():
		_err("passive", "被动缺少效果")
	var trigger := str(passive.get("trigger", ""))
	if trigger != "always" and trigger != "conditional":
		_err("passive", "被动触发必须是 always 或 conditional")


func _check_appearance(appearance) -> void:
	if typeof(appearance) != TYPE_DICTIONARY:
		_err("humanoid", "缺少外形")
		_err("height", "缺少身高")
		return
	if appearance.get("humanoid", false) != true:
		_err("humanoid", "替身必须是人形")
	var height = appearance.get("height_m", null)
	if not _is_number(height):
		_err("height", "身高必须是数字")
		return
	var meters := float(height)
	if meters < HEIGHT_MIN or meters > HEIGHT_MAX:
		_err("height", "身高必须在 1.5–2.0 米，当前 %.2f" % meters)


func _check_required_text(card: Dictionary) -> void:
	if typeof(card.get("name", null)) != TYPE_STRING or str(card.get("name")).is_empty() or str(card.get("name")).length() > 32:
		_err("text", "名称须为 1–32 字")
	if typeof(card.get("blurb", null)) != TYPE_STRING or str(card.get("blurb")).is_empty() or str(card.get("blurb")).length() > 120:
		_err("text", "人设简述须为 1–120 字")
	for field in ["avatar_prompt", "turnaround_prompt", "model_spec"]:
		if typeof(card.get(field, null)) != TYPE_STRING or str(card.get(field)).is_empty():
			_err("text", "缺少 %s" % field)


func _check_blacklist(card: Dictionary) -> void:
	var texts: PackedStringArray = []
	_collect_strings(card, texts)
	var joined := "\n".join(texts)
	for phrase in BLACKLIST:
		if phrase in joined:
			_err("blacklist", "命中黑名单：%s" % phrase)


func _collect_strings(value, into: PackedStringArray) -> void:
	match typeof(value):
		TYPE_STRING:
			into.append(value)
		TYPE_DICTIONARY:
			for key in value.keys():
				_collect_strings(value[key], into)
		TYPE_ARRAY:
			for item in value:
				_collect_strings(item, into)


func _read_whole_number(value) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": value}
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), round(float(value))):
		return {"ok": true, "value": int(round(float(value)))}
	return {"ok": false}


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_non_negative_number(value) -> bool:
	return _is_number(value) and float(value) >= 0.0
