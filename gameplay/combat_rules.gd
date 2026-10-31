extends RefCounted
class_name CombatRules
## 六维最小结算。命中管线顺序：射程 → 精密 → 力量 → 持续力 → 速度 → 成长。
## 力量 / 速度 / 射程只在技能 primary_stats 绑定时偏离中轴；未绑定按 3（倍率 1）。
## 这样单技能不会同时吃满这三项。精密不改开阔地伤害，只决定半掩能否命中，以及控制时长。
## 持续力只决定生命上限，不改本次伤害。成长层只在本局叠，0 层时倍率为 1。
## 冷却在技能打出后就按速度公式计算，即使射程或掩体让命中管线提前停下。

const RESOLVE_ORDER: PackedStringArray = [
	"range",
	"precision",
	"power",
	"stamina",
	"speed",
	"growth",
]

const BASE_HP := 1000.0
const SMALL_DAMAGE := 200.0
const ULT_DAMAGE := 400.0
const MAX_LAYERS := 3
const PICKUP_LAYERS := 1
const KNOCKDOWN_LAYERS := 2
const SMALL_CD_MIN := 4.0
const SMALL_CD_MAX := 6.0
const ULT_CD_MIN := 18.0
const ULT_CD_MAX := 25.0
const SMALL_DMG_MIN := 180.0
const SMALL_DMG_MAX := 220.0
const ULT_DMG_MIN := 350.0
const ULT_DMG_MAX := 450.0
const HALF_COVER_SCALE := 0.5
const WINDOW_TAKEN_AMP := 1.25
const SELF_DAMAGE_RATIO := 0.12
const SELF_DAMAGE_MIN := 40.0
const SELF_STUN := 0.8
const REVEAL_TIME := 3.0
const ULTIMATE_COSTS: PackedStringArray = ["stun", "self_damage", "window", "reveal"]


static func resolve_order() -> PackedStringArray:
	return RESOLVE_ORDER


static func damage_factor(power: int) -> float:
	return 0.7 + 0.1 * float(power)


static func cooldown_factor(speed: int) -> float:
	return 1.15 - 0.05 * float(speed)


static func max_hp(stamina: int) -> float:
	return BASE_HP * (0.75 + 0.08 * float(stamina))


## 击倒 +2、拾取 +1，硬顶 3。调用方不要把层数写回将要入库的卡。
static func add_layers(current: int, source: String) -> int:
	var gain := PICKUP_LAYERS
	if source == "knockdown":
		gain = KNOCKDOWN_LAYERS
	var next := current + gain
	if next > MAX_LAYERS:
		return MAX_LAYERS
	if next < 0:
		return 0
	return next


## 0 层不加伤。有层时每层约 +3%×成长，仅本局。
static func growth_factor(growth_stat: int, layers: int) -> float:
	if layers <= 0:
		return 1.0
	return 1.0 + 0.03 * float(growth_stat) * float(layers)


static func stat_value(stats: Dictionary, key: String, fallback: int = 3) -> int:
	var number := fallback
	if typeof(stats) == TYPE_DICTIONARY and stats.has(key):
		var raw = stats[key]
		if typeof(raw) == TYPE_INT:
			number = int(raw)
		elif typeof(raw) == TYPE_FLOAT:
			number = int(round(float(raw)))
		else:
			number = fallback
	if number < 1:
		number = 1
	if number > 5:
		number = 5
	return number


static func binds(skill: Dictionary, key: String) -> bool:
	var stats = skill.get("primary_stats", [])
	if typeof(stats) != TYPE_ARRAY:
		return false
	for item in stats:
		if str(item) == key:
			return true
	return false


static func triple_dip(skill: Dictionary) -> bool:
	return binds(skill, "power") and binds(skill, "speed") and binds(skill, "range")


static func is_ultimate_skill(skill: Dictionary, context: Dictionary) -> bool:
	if bool(context.get("is_ultimate", false)):
		return true
	return skill.has("cost")


static func nominal_cooldown(skill: Dictionary, is_ultimate: bool) -> float:
	var fallback := 22.0 if is_ultimate else 5.0
	var cd := float(skill.get("cooldown", fallback))
	if is_ultimate:
		if cd < ULT_CD_MIN or cd > ULT_CD_MAX:
			cd = clampf(cd, ULT_CD_MIN, ULT_CD_MAX)
	elif cd < SMALL_CD_MIN or cd > SMALL_CD_MAX:
		cd = clampf(cd, SMALL_CD_MIN, SMALL_CD_MAX)
	return cd


static func base_damage_of(skill: Dictionary, is_ultimate: bool) -> float:
	var kind := str(skill.get("kind", "damage"))
	if kind == "control" or kind == "shield":
		return 0.0
	var fallback := ULT_DAMAGE if is_ultimate else SMALL_DAMAGE
	var value := float(skill.get("base_damage", fallback))
	if is_ultimate:
		return clampf(value, ULT_DMG_MIN, ULT_DMG_MAX)
	return clampf(value, SMALL_DMG_MIN, SMALL_DMG_MAX)


static func effective_range(skill: Dictionary, range_stat: int) -> float:
	var authored := float(skill.get("range", 0.0))
	if not binds(skill, "range"):
		return authored
	return authored * (0.7 + 0.1 * float(range_stat))


static func dash_distance(skill: Dictionary, speed: int) -> float:
	if str(skill.get("kind", "")) != "dash":
		return 0.0
	var base := float(skill.get("range", 0.0))
	if not binds(skill, "speed"):
		return base
	return base * (0.85 + 0.05 * float(speed))


static func knockback_distance(skill: Dictionary, power: int) -> float:
	if not binds(skill, "power"):
		return 0.0
	return 0.35 * float(power)


## 仅控制技能。时长相对精密中轴 3，再乘守方速度的受控缩短（与冷却同一系数）。
static func control_duration(skill: Dictionary, precision: int, defender_speed: int) -> float:
	if str(skill.get("kind", "")) != "control":
		return 0.0
	var base := float(skill.get("duration", 0.0))
	var aim := 1.0 + 0.1 * float(precision - 3)
	var taken := cooldown_factor(defender_speed)
	var duration := base * aim * taken
	if duration < 0.0:
		return 0.0
	return duration


static func resolve(attacker_stats: Dictionary, skill: Dictionary, context: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"hit": false,
		"code": "",
		"message": "",
		"applied": [],
		"damage": 0.0,
		"self_damage": 0.0,
		"self_stun": 0.0,
		"window": 0.0,
		"revealed": false,
		"reveal_time": 0.0,
		"cooldown": 0.0,
		"knockback": 0.0,
		"dash_distance": 0.0,
		"control_duration": 0.0,
		"hit_scale": 0.0,
		"effective_range": 0.0,
		"max_hp": 0.0,
		"growth_factor": 1.0,
		"layers_after": 0,
	}
	if typeof(skill) != TYPE_DICTIONARY or skill.is_empty():
		result.code = "bad_skill"
		result.message = "缺少技能"
		return result
	if typeof(attacker_stats) != TYPE_DICTIONARY:
		attacker_stats = {}
	var is_ultimate := is_ultimate_skill(skill, context)
	if is_ultimate:
		if not skill.has("cost"):
			result.code = "ultimate_cost"
			result.message = "大招必须带代价"
			return result
		var cost := str(skill.get("cost", ""))
		if not (cost in ULTIMATE_COSTS):
			result.code = "ultimate_cost"
			result.message = "大招代价无效"
			return result
	if triple_dip(skill):
		result.code = "triple_dip"
		result.message = "禁止单技能同时吃满力量、速度、射程"
		return result

	var distance := float(context.get("distance", 0.0))
	var cover := str(context.get("cover", "none"))
	var defender_stats = context.get("defender_stats", {})
	if typeof(defender_stats) != TYPE_DICTIONARY:
		defender_stats = {}
	var layers := int(context.get("layers", 0))
	if layers < 0:
		layers = 0
	if layers > MAX_LAYERS:
		layers = MAX_LAYERS
	result.layers_after = layers

	var precision := stat_value(attacker_stats, "precision", 3)
	var power := stat_value(attacker_stats, "power", 3)
	var speed := stat_value(attacker_stats, "speed", 3)
	var growth := stat_value(attacker_stats, "growth", 3)
	var range_stat := stat_value(attacker_stats, "range", 3)
	var defender_stamina := stat_value(defender_stats, "stamina", 3)
	var defender_speed := stat_value(defender_stats, "speed", 3)
	var power_used := power if binds(skill, "power") else 3
	var speed_used := speed if binds(skill, "speed") else 3
	var range_used := range_stat if binds(skill, "range") else 3

	var cd := nominal_cooldown(skill, is_ultimate) * cooldown_factor(speed_used)
	result.cooldown = cd
	result.dash_distance = dash_distance(skill, speed)
	result.knockback = knockback_distance(skill, power)

	var applied: Array = []
	var eff_range := effective_range(skill, range_used)
	result.effective_range = eff_range
	applied.append("range")
	if distance > eff_range:
		result.ok = true
		result.hit = false
		result.code = "out_of_range"
		result.message = "超出射程，攻击无效"
		_pay_cost(result, skill, is_ultimate)
		result.applied = applied
		return result

	applied.append("precision")
	var hit_scale := 1.0
	if cover == "full":
		result.ok = true
		result.hit = false
		result.code = "full_cover"
		result.message = "全掩阻挡"
		result.hit_scale = 0.0
		_pay_cost(result, skill, is_ultimate)
		result.applied = applied
		return result
	if cover == "half":
		if precision < 3:
			result.ok = true
			result.hit = false
			result.code = "half_cover"
			result.message = "半掩且精密低于中轴，未命中"
			result.hit_scale = 0.0
			_pay_cost(result, skill, is_ultimate)
			result.applied = applied
			return result
		# 过了中轴只表示打中半掩，伤害固定折半，精密再高也不加伤害倍率。
		hit_scale = HALF_COVER_SCALE
	result.hit_scale = hit_scale

	applied.append("power")
	var raw := base_damage_of(skill, is_ultimate) * damage_factor(power_used) * hit_scale

	applied.append("stamina")
	result.max_hp = max_hp(defender_stamina)

	applied.append("speed")
	var kind := str(skill.get("kind", "damage"))
	if kind == "control":
		result.control_duration = control_duration(skill, precision, defender_speed)

	applied.append("growth")
	var gfactor := growth_factor(growth, layers)
	result.growth_factor = gfactor
	var damage := raw * gfactor
	if float(context.get("defender_window", 0.0)) > 0.0 and damage > 0.0:
		damage *= WINDOW_TAKEN_AMP
		result.defender_window = true
	result.damage = damage
	_pay_cost(result, skill, is_ultimate)

	var connected := damage > 0.0 or kind == "control" or kind == "shield" or kind == "dash"
	result.ok = true
	result.hit = connected
	result.code = "hit" if connected else "no_damage"
	result.message = "命中" if connected else "未造成效果"
	result.applied = applied
	return result


static func _pay_cost(result: Dictionary, skill: Dictionary, is_ultimate: bool) -> void:
	if not is_ultimate:
		return
	var cost := str(skill.get("cost", ""))
	var damage := float(result.get("damage", 0.0))
	if cost == "stun":
		result.self_stun = SELF_STUN
	elif cost == "self_damage":
		result.self_damage = maxf(SELF_DAMAGE_MIN, damage * SELF_DAMAGE_RATIO)
	elif cost == "window":
		result.window = maxf(1.0, float(skill.get("duration", 1.2)))
	elif cost == "reveal":
		result.revealed = true
		result.reveal_time = REVEAL_TIME
