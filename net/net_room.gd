extends Node
class_name NetRoom
## W0 联网占位。W2 再做主机权威房间（Godot Multiplayer / ENet）。不要在主循环里当成功路径调用。


func host_room(_port: int = 7777) -> Dictionary:
	return {
		"ok": false,
		"code": "not_implemented",
		"message": "主机权威房间留到 W2",
	}


func join_room(_address: String = "127.0.0.1", _port: int = 7777) -> Dictionary:
	return {
		"ok": false,
		"code": "not_implemented",
		"message": "加入房间留到 W2",
	}
