extends RefCounted
class_name StandLibrary
## 胜者保留库。上限 3。超限不自动丢弃，必须先弃旧再留新。
## 入库前调用校验器。不要绕过 try_keep 直接改内部数组。

const ValidatorScript = preload("res://stand/stand_validator.gd")
const MAX_KEPT := 3

var _cards: Array[Dictionary] = []


func size() -> int:
	return _cards.size()


func get_card(index: int) -> Dictionary:
	if index < 0 or index >= _cards.size():
		return {}
	return _cards[index].duplicate(true)


## 校验失败或已满时 ok=false。成功时放入深拷贝，调用方事后改原字典不会污染库。
func try_keep(card: Dictionary) -> Dictionary:
	var verdict: Dictionary = ValidatorScript.validate(card)
	if not verdict["ok"]:
		return {
			"ok": false,
			"code": "invalid_card",
			"message": "校验未通过，不能保留",
			"errors": verdict["errors"],
		}
	if _cards.size() >= MAX_KEPT:
		return {
			"ok": false,
			"code": "library_full",
			"message": "保留卡已达 3 张，须先弃旧再留新",
		}
	_cards.append(card.duplicate(true))
	return {"ok": true}


func discard(index: int) -> Dictionary:
	if index < 0 or index >= _cards.size():
		return {"ok": false, "code": "bad_index", "message": "弃卡下标无效"}
	_cards.remove_at(index)
	return {"ok": true}
