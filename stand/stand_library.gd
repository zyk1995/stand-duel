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
## 成长层只活在本局，入库前会剥掉。
func try_keep(card: Dictionary) -> Dictionary:
	var base := _without_layers(card)
	var verdict: Dictionary = ValidatorScript.validate(base)
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
	_cards.append(base.duplicate(true))
	return {"ok": true}


## 对局结算：校验通过后若已满，先弃最旧的一张再留。校验失败时一张都不丢。
func keep_winner_replacing_oldest(card: Dictionary) -> Dictionary:
	var base := _without_layers(card)
	var verdict: Dictionary = ValidatorScript.validate(base)
	if not verdict["ok"]:
		return {
			"ok": false,
			"code": "invalid_card",
			"message": "校验未通过，不能保留",
			"errors": verdict["errors"],
			"discarded_oldest": false,
		}
	var discarded := false
	var dropped_name := ""
	if _cards.size() >= MAX_KEPT:
		dropped_name = str(_cards[0].get("name", ""))
		_cards.remove_at(0)
		discarded = true
	_cards.append(base.duplicate(true))
	return {"ok": true, "discarded_oldest": discarded, "dropped_name": dropped_name}


## 败者卡销毁：不入库，也不改动已有收藏。
func destroy_loser(card: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"destroyed": true,
		"kept": false,
		"name": str(card.get("name", "")),
	}


func _without_layers(card: Dictionary) -> Dictionary:
	var copy := card.duplicate(true)
	for key in ["layers", "runtime_layers", "growth_layers"]:
		copy.erase(key)
	return copy


func discard(index: int) -> Dictionary:
	if index < 0 or index >= _cards.size():
		return {"ok": false, "code": "bad_index", "message": "弃卡下标无效"}
	_cards.remove_at(index)
	return {"ok": true}
