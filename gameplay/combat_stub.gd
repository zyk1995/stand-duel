extends Node
class_name CombatStub
## 场景上的结算入口。公式在 combat_rules.gd，方便无头测试不实例化节点。

const Rules = preload("res://gameplay/combat_rules.gd")


func resolve_order() -> PackedStringArray:
	return Rules.resolve_order()


func resolve_hit(attacker_stats: Dictionary, skill: Dictionary, context: Dictionary = {}) -> Dictionary:
	return Rules.resolve(attacker_stats, skill, context)
