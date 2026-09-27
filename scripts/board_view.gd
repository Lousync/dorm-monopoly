extends Control
class_name BoardView
## 28 格棋盘渲染：地块（组色条/价格/主人描边/装修星级）+ 玩家棋子与移动动画。

signal tile_clicked(idx: int)

const TILE := 90.0
const BOARD := TILE * 8.0  # 720

var _tile_sb: Array = []       # 每格的 StyleBoxFlat（描边随主人变色）
var _sub_labels: Array = []    # 每格价格/状态小字
var _star_labels: Array = []   # 每格装修星级
var _tokens := {}              # peer -> 棋子 Panel
var _animating := {}           # peer -> bool

func _init() -> void:
	custom_minimum_size = Vector2(BOARD, BOARD)
	size = Vector2(BOARD, BOARD)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	_build_tiles()

static func tile_pos(i: int) -> Vector2:
	var col: int
	var row: int
	if i < 8:
		col = 7 - i
		row = 7
	elif i < 15:
		col = 0
		row = 7 - (i - 7)
	elif i < 22:
		col = i - 14
		row = 0
	else:
		col = 7
		row = i - 21
	return Vector2(col, row) * TILE

func _build_tiles() -> void:
	for i in GameData.TILES.size():
		var d: Dictionary = GameData.TILES[i]
		var corner: bool = d.type in ["start", "jail", "rest", "go_jail"]
		var p := Panel.new()
		p.position = tile_pos(i)
		p.size = Vector2(TILE, TILE)
		var sb := UIKit.stylebox(Color("#2c2417") if corner else Color("#252a38"), 8, Color("#3c4254"), 1)
		p.add_theme_stylebox_override("panel", sb)
		p.tooltip_text = d.name
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(p)
		_tile_sb.append(sb)

		var strip := ColorRect.new()
		strip.position = Vector2(6, 6)
		strip.size = Vector2(TILE - 12, 6)
		strip.color = UIKit.ACCENT if corner else GameData.GROUP_COLORS.get(d.get("group", ""), Color("#566"))
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(strip)

		var vb := VBoxContainer.new()
		vb.position = Vector2(5, 17)
		vb.size = Vector2(TILE - 10, TILE - 24)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(vb)

		var name_l := UIKit.label(d.name, 12)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_l)

		var sub := UIKit.label("", 11, UIKit.TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(sub)
		_sub_labels.append(sub)

		var star := UIKit.label("", 12, UIKit.ACCENT)
		star.position = Vector2(TILE - 50, TILE - 22)
		star.size = Vector2(46, 18)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(star)
		_star_labels.append(star)

		p.gui_input.connect(_on_tile_input.bind(i))

func _on_tile_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(idx)

## 渲染一份状态快照（不移动动画中的棋子）
func render(state: Dictionary) -> void:
	var tiles: Array = state.get("tiles", [])
	var players: Array = state.get("players", [])
	var color_of := {}
	for p in players:
		color_of[int(p.peer)] = GameData.PLAYER_COLORS[int(p.color)]

	for i in _tile_sb.size():
		var owner_id := -1
		var level := 0
		if i < tiles.size():
			owner_id = int(tiles[i].get("owner", -1))
			level = int(tiles[i].get("level", 0))
		var sb: StyleBoxFlat = _tile_sb[i]
		if owner_id != -1 and color_of.has(owner_id):
			sb.set_border_width_all(3)
			sb.border_color = color_of[owner_id]
		else:
			sb.set_border_width_all(1)
			sb.border_color = Color("#3c4254")

		var d: Dictionary = GameData.TILES[i]
		var sub: Label = _sub_labels[i]
		match String(d.type):
			"property":
				sub.text = "¥%d" % int(d.price) if owner_id == -1 else ""
			"fine":
				sub.text = "-¥%d" % int(d.amount)
			"start":
				sub.text = "+¥%d" % GameData.SALARY
			"jail":
				sub.text = "反省处"
			"go_jail":
				sub.text = "送你进去"
			"rest":
				sub.text = "免费休息"
			"event":
				sub.text = "?"
		_star_labels[i].text = "★".repeat(level)

	var seen := {}
	for p in players:
		var peer := int(p.peer)
		seen[peer] = true
		var slot := int(p.color)
		if not _tokens.has(peer):
			var tk := _make_token(GameData.PLAYER_COLORS[slot], String(p.name))
			tk.set_meta("slot", slot)
			_tokens[peer] = tk
			add_child(tk)
			tk.position = _token_target(p, slot)
		elif not _animating.get(peer, false):
			var tk2: Panel = _tokens[peer]
			tk2.set_meta("slot", slot)
			tk2.position = _token_target(p, slot)

	for peer in _tokens.keys():
		if not seen.has(peer):
			_tokens[peer].queue_free()
			_tokens.erase(peer)

func _token_target(p: Dictionary, slot: int) -> Vector2:
	return tile_pos(int(p.pos)) + Vector2(TILE, TILE) * 0.5 - Vector2(10, 10) + _slot_offset(slot)

func _slot_offset(slot: int) -> Vector2:
	match slot % 4:
		0: return Vector2(-17, -17)
		1: return Vector2(17, -17)
		2: return Vector2(-17, 17)
		_: return Vector2(17, 17)

func _make_token(color: Color, pname: String) -> Panel:
	var tk := Panel.new()
	tk.size = Vector2(20, 20)
	var sb := UIKit.stylebox(color, 10, Color(0.95, 0.95, 0.95), 2)
	tk.add_theme_stylebox_override("panel", sb)
	tk.tooltip_text = pname
	tk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tk.z_index = 10
	return tk

## 逐步走子动画（本地表现，host 用等时长的定时器保持节奏一致）
func play_move(peer: int, path: Array, step_time: float) -> void:
	if not _tokens.has(int(peer)):
		return
	var tk: Panel = _tokens[int(peer)]
	_animating[int(peer)] = true
	if tk.has_meta("tw"):
		var old = tk.get_meta("tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := create_tween()
	tk.set_meta("tw", tw)
	var slot := int(tk.get_meta("slot", 0))
	for step in path:
		var pos := tile_pos(int(step)) + Vector2(TILE, TILE) * 0.5 - Vector2(10, 10) + _slot_offset(slot)
		tw.tween_property(tk, "position", pos, step_time)
	tw.finished.connect(func() -> void:
		_animating[int(peer)] = false
	)
