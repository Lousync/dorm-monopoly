extends SceneTree
func _init() -> void:
	var marks := {}
	for i in GameData.TILES.size():
		var d: Dictionary = GameData.TILES[i]
		var t := String(d.type)
		var tag := t.substr(0, 3)
		if t == "shop": tag = "S"
		elif t == "item": tag = "I"
		elif t == "again": tag = "A"
		elif t == "event": tag = "E"
		elif t == "rest": tag = "R"
		elif t == "casino": tag = "C"
		elif t == "property": tag = "地"
		elif t == "start": tag = "起"
		elif t == "jail": tag = "宿"
		elif t == "go_jail": tag = "查"
		marks[i] = tag + String(d.get("name", ""))
	# 按四边输出
	var W: int = GameData.BOARD_COLS
	var H: int = GameData.BOARD_ROWS
	var line := "底边: "
	for i in W: line += "[%d]%s " % [i, marks[i]]
	print(line)
	line = "左边: "
	for i in range(W + H - 2, W - 1, -1): line += "[%d]%s " % [i, marks[i]]
	print(line)
	line = "顶边: "
	for i in range(W + H - 2, 2 * W + H - 3): line += "[%d]%s " % [i, marks[i]]
	print(line)
	line = "右边: "
	for i in range(2 * W + H - 3, 55): line += "[%d]%s " % [i, marks[i]]
	print(line)
	quit()
