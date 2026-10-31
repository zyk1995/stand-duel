extends Node
class_name CombatStub
## W0 不结算伤害。顺序与策划书一致：射程 → 精密 → 力量 → 持续力 → 速度 → 成长。

const RESOLVE_ORDER: PackedStringArray = [
	"range",
	"precision",
	"power",
	"stamina",
	"speed",
	"growth",
]


func resolve_order() -> PackedStringArray:
	return RESOLVE_ORDER


func resolve_hit(_attacker_stats: Dictionary, _skill: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": "not_implemented",
		"message": "战斗结算留到 W1",
	}
