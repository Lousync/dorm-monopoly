extends Control
class_name BoardView
## 56 格（18×12 外圈）棋盘：世界坐标渲染，滚轮缩放 / 拖拽平移 / 自动跟随行动棋子。
## 表现细节：跳格小跳+挤压、归属描边与底色渐变、装修星级弹跳、悬停高亮、
## 当前行动者脉冲光环、传送淡入淡出。

signal tile_clicked(idx: int)
signal seat_clicked(peer: int)

const TILE := 112.0
static var WORLD := Vector2(GameData.BOARD_COLS, GameData.BOARD_ROWS) * TILE  # 18×12 → (2016, 1344)
const GAP := 5.0
const MIN_ZOOM := 0.22
const MAX_ZOOM := 1.25
## 事件卡从牌堆抽出展示的总时长（房主结算等待与它保持同步）
const DECK_CARD_TIME := 2.35

# 正方形牌桌：四条操作栏拼成一个闭合方框，长方形棋盘嵌在框内
# （底=本地玩家，左/上/右=对手，内容朝向各自主人）
const BAND_SIDE := 240.0     # 左右操作栏宽（座位件厚 220 + 边距）
const BAND_TB := 286.0       # 上下操作栏厚
const HOLE_MX := 16.0        # 棋盘与左右栏的间隙
# 方框边长由棋盘长边驱动，上下间隙动态配平，桌面恒为正方形
static var TABLE := _make_table()

## 棋盘下移贴住玩家数据区：下缘只留小缝，余下空隙留给顶部数据面板
const HOLE_GAP_BOTTOM := 80.0
static var BOARD_OFFSET := _make_board_offset()

static func _make_table() -> Rect2:
	var side: float = WORLD.x + 2.0 * (BAND_SIDE + HOLE_MX)
	var my: float = (side - 2.0 * BAND_TB - WORLD.y) * 0.5
	return Rect2(-(BAND_SIDE + HOLE_MX), -(BAND_TB + my), side, side)

static func _make_board_offset() -> Vector2:
	var hole_bottom := TABLE.end.y - BAND_TB
	return Vector2(HOLE_MX, hole_bottom - HOLE_GAP_BOTTOM - WORLD.y)
const SEAT_SIZE := Vector2(1068, 220)
const SLOT_SIZE := Vector2(148, 196)

var auto_follow := true      # 用户拖拽后关闭，点「跟随」按钮恢复
var cam_locked := false      # 摆拍/剧情演出时锁住自动镜头（focus_* 直接忽略）
var overlay_top := 0.0       # 屏幕层覆盖高度/宽度（镜头居中/适配会避开）
var overlay_left := 0.0
var overlay_right := 0.0
var overlay_bottom := 0.0

var _world: Control
var _table: Node2D
var _zoom := 0.5
var _need_fit := true
var _dragging := false
var _panning := false
var _press_pos := Vector2.ZERO
var _follow_peer := -1
var _hover := -1
var _rot := 0.0              # 视角旋转（弧度，0 = 自己坐南看北）
var _rot_target := 0.0
var _rotating := false
var _center := WORLD * 0.5   # 可视区中心对应的世界坐标（注视点）
var _center_target := WORLD * 0.5

var _tile_sb: Array = []       # 每格 StyleBoxFlat
var _sub_labels: Array = []
var _star_labels: Array = []
var _owners: Array = []        # 上一次渲染的归属（用于渐变过渡）
var _levels: Array = []        # 上一次渲染的等级（用于星级弹跳）
var _tile_tw := {}             # 每格进行中的补间
var _tokens := {}              # peer -> 棋子 Panel
var _animating := {}           # peer -> bool
var _ring: Panel
var _ring_peer := -1
var _ring_tw: Tween
var _owner_color_map := {}     # peer -> Color（render 时刷新）

# 镜头对点跟随（抽卡时对准牌堆）与牌堆抽卡动画
var _has_follow_pt := false
var _follow_pt := Vector2.ZERO
var _deck_pos := {}            # "机会"/"命运" -> world 中心
var _deck_card: Control
var _deck_t := 0.0             # 抽卡动画相位计时（_process 驱动，不用 Tween）
var _deck_from := Vector2.ZERO
var _deck_shown := Vector2.ZERO
var _deck_restore := -1

# 中央转盘（替代骰子的点数来源）
var _wheel: WheelView
var _wheel_restore := -1
var _wheel_wait := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _ready() -> void:
	_table = Node2D.new()
	add_child(_table)
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.size = WORLD
	_table.add_child(_world)
	_build_backdrop()
	_build_tiles()
	_build_interior()
	_build_ring()
	resized.connect(func() -> void: _need_fit = true)
	mouse_exited.connect(func() -> void:
		set_hover(-1)
		_set_seat_hover(-1))
	_build_top_panels()

# ---------------- 坐标换算 ----------------

## 路径序号 -> 格坐标（纯逻辑在 GameData，这里做薄封装）
static func tile_grid(i: int) -> Vector2i:
	return GameData.grid_of(i)

## 格坐标 -> 路径序号（不在外圈返回 -1）
static func grid_to_index(col: int, row: int) -> int:
	return GameData.index_at_grid(col, row)

static func tile_pos(i: int) -> Vector2:
	return BOARD_OFFSET + Vector2(tile_grid(i)) * TILE

func _world_from_view(view_pos: Vector2) -> Vector2:
	return _center + (view_pos - _visible_center()).rotated(-_rot) / _zoom

func _view_from_world(w: Vector2) -> Vector2:
	return (_world.position + _zoom * w).rotated(_rot)

func _visible_center() -> Vector2:
	return _visible_rect().get_center()

## 把镜头状态（注视点/倍率/旋转）落到节点变换上：
## 视口中心项随视角旋转、注视点项不转，保证 view(c)=Vc 且旋转围绕注视点不漂移
func _apply_cam() -> void:
	_world.scale = Vector2.ONE * _zoom
	_table.rotation = _rot
	_world.position = _visible_center().rotated(-_rot) - _center * _zoom

## 注视点限制在桌面内容内（旋转 90° 倍数时可视宽高互换）
func _clamp_center(c: Vector2) -> Vector2:
	var vr := _visible_rect()
	var half := (vr.size.rotated(-_rot) * 0.5).abs() / _zoom
	var mn := TABLE.position + half
	var mx := TABLE.end - half
	var out := c
	out.x = TABLE.get_center().x if mn.x > mx.x else clampf(c.x, mn.x, mx.x)
	out.y = TABLE.get_center().y if mn.y > mx.y else clampf(c.y, mn.y, mx.y)
	return out

func _index_at(view_pos: Vector2) -> int:
	var w := _world_from_view(view_pos) - BOARD_OFFSET
	var col := int(floor(w.x / TILE))
	var row := int(floor(w.y / TILE))
	if col < 0 or col >= GameData.BOARD_COLS or row < 0 or row >= GameData.BOARD_ROWS:
		return -1
	return grid_to_index(col, row)

# ---------------- 场景搭建 ----------------

func _build_backdrop() -> void:
	# 一整张连续的木纹桌面：棋盘区和操作栏坐在同一张桌上，没有材质接缝
	var table := Panel.new()
	table.position = TABLE.position - Vector2(30, 30)
	table.size = TABLE.size + Vector2(60, 60)
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.10, 0.085, 0.06), 30, Color(0.30, 0.23, 0.15), 3, 18))
	_world.add_child(table)
	var wood := TextureRect.new()
	wood.texture = UIKit.tex("res://assets/textures/wood_floor.jpg")
	wood.stretch_mode = TextureRect.STRETCH_TILE
	wood.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	wood.position = Vector2(10, 10)
	wood.size = table.size - Vector2(20, 20)
	wood.modulate = Color(0.44, 0.39, 0.33)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(wood)

	# 棋盘区：同一张木纹上轻微压暗 + 描边勾出边界，格子直接落在桌面上
	var bg := Panel.new()
	bg.position = BOARD_OFFSET - Vector2(26, 26)
	bg.size = WORLD + Vector2(52, 52)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.05, 0.05, 0.07, 0.32), 20,
		Color(0.24, 0.19, 0.12, 0.9), 2, 12))
	_world.add_child(bg)

## 格子类型 → Twemoji 主题图标名（assets/icons/，CC-BY 4.0）
const TILE_ICONS := {
	"property": {"daily": "daily", "service": "service", "canteen": "canteen", "study": "study",
		"sport": "sport", "teach": "teach", "dorm": "dorm", "fun": "fun",
		"night": "night", "health": "health"},
	"event": {"机会": "luck", "命运": "fate"},
	"fine": "fine", "bonus": "bonus", "rest": "rest", "casino": "casino",
	"start": "start", "jail": "jail", "go_jail": "gojail",
}

func _tile_icon_name(d: Dictionary) -> String:
	var t := String(d.type)
	var v = TILE_ICONS.get(t, "")
	if v is Dictionary:
		return v.get(String(d.get("group", d.get("name", ""))), "")
	return v

func _build_tiles() -> void:
	for i in GameData.TILES.size():
		var d: Dictionary = GameData.TILES[i]
		var corner: bool = d.type in ["start", "jail", "rest", "go_jail"]
		var base := Color("#38301c") if corner else Color("#242a39")
		var p := Panel.new()
		p.position = tile_pos(i) + Vector2(GAP, GAP)
		p.size = Vector2.ONE * (TILE - GAP * 2.0)
		var sb := UIKit.stylebox(base, 7, Color("#3c4254"), 1)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(p)
		_tile_sb.append(sb)

		var strip := Panel.new()
		strip.position = Vector2(3, 3)
		strip.size = Vector2(TILE - GAP * 2.0 - 6, 9)
		var strip_c: Color = UIKit.ACCENT if corner else (Color(0.93, 0.30, 0.55) if d.type == "casino" else GameData.GROUP_COLORS.get(d.get("group", ""), Color("#566")))
		strip.add_theme_stylebox_override("panel", UIKit.stylebox(strip_c.lightened(0.06), 2))
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(strip)

		# 主题图标水印：垫在牌名下面，给每类格子一个视觉身份
		var casino: bool = d.type == "casino"
		var icon_name := _tile_icon_name(d)
		if icon_name != "":
			var icon_t := UIKit.icon(icon_name)
			if icon_t != null:
				var ic := TextureRect.new()
				ic.texture = icon_t
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ic.position = Vector2((TILE - GAP * 2.0) * 0.5 - 18.0, 20)
				ic.size = Vector2(36, 36)
				ic.modulate = Color(1, 1, 1, 0.42 if not corner else 0.55)
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				p.add_child(ic)

		var name_l := UIKit.label(d.name, 18, UIKit.ACCENT if corner else (Color(0.98, 0.58, 0.78) if casino else UIKit.TEXT))
		name_l.position = Vector2(5, 18)
		name_l.size = Vector2(TILE - GAP * 2.0 - 10, 44)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_world_descend(name_l)
		p.add_child(name_l)

		var sub := UIKit.label("", 14, UIKit.TEXT_DIM)
		sub.position = Vector2(5, 70)
		sub.size = Vector2(TILE - GAP * 2.0 - 10, 17)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_world_descend(sub)
		p.add_child(sub)
		_sub_labels.append(sub)

		var star := UIKit.label("", 15, UIKit.ACCENT)
		star.position = Vector2(5, 68)
		star.size = Vector2(TILE - GAP * 2.0 - 10, 19)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_world_descend(star)
		p.add_child(star)
		_star_labels.append(star)

		_owners.append(-2)
		_levels.append(-1)

func _world_descend(l: Label) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 棋盘中央内区布局（仿实体桌游）：上方标题水印，中央「机会」「命运」两个牌堆，
## 事件卡从对应牌堆抽出展示。
func _build_interior() -> void:
	var c := WORLD * 0.5 + BOARD_OFFSET
	var p := Panel.new()
	p.position = Vector2(c.x - 380, 110)
	p.size = Vector2(760, 104)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.10, 0.11, 0.16, 0.62), 20,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.22), 1))
	_world.add_child(p)

	var title := UIKit.title_label("宿舍大富翁", 42, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.34), 0)
	title.position = Vector2(0, 8)
	title.size = Vector2(760, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(title)

	var sub := UIKit.label("%d × %d 环线 · %d 格 · 10 大产业" % [GameData.BOARD_COLS, GameData.BOARD_ROWS, GameData.TILES.size()],
		16, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.75))
	sub.position = Vector2(0, 66)
	sub.size = Vector2(760, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(sub)

	_build_deck("机会", Vector2(c.x - 560, c.y), UIKit.ACCENT)
	_build_deck("命运", Vector2(c.x + 560, c.y), Color(0.66, 0.56, 0.95))
	_build_wheel(c)

## 一个牌堆：区域底板 + 三层错位卡背 + 牌名 + 小字说明
func _build_deck(dname: String, center: Vector2, accent: Color) -> void:
	_deck_pos[dname] = center
	var zone := Panel.new()
	zone.position = center - Vector2(140, 90)
	zone.size = Vector2(280, 180)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.095, 0.105, 0.15, 0.62), 20,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 4))
	_world.add_child(zone)

	for i in 3:
		var card := Panel.new()
		card.position = center - Vector2(66, 52) + Vector2(5, 5) * float(2 - i)
		card.size = Vector2(132, 84)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var deep := accent.darkened(0.42) if i < 2 else accent
		card.add_theme_stylebox_override("panel", UIKit.card_stylebox(
			Color(0.135, 0.125, 0.075) if accent == UIKit.ACCENT else Color(0.125, 0.11, 0.155),
			10, deep, 2 if i == 2 else 1, 3))
		_world.add_child(card)

	var t := UIKit.label(dname, 28, accent)
	t.position = center - Vector2(66, 42)
	t.size = Vector2(132, 42)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(t)

	var cap := UIKit.label("落在【%s】格时从这里抽卡" % dname, 14,
		Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.7))
	cap.position = center - Vector2(132, -56)
	cap.size = Vector2(264, 20)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(cap)

## 中央转盘：点数来源，掷点时镜头对准它
func _build_wheel(center: Vector2) -> void:
	_wheel = WheelView.new()
	_wheel.size = Vector2(400, 400)
	_wheel.position = center - _wheel.size * 0.5
	_world.add_child(_wheel)

func wheel_center() -> Vector2:
	return _wheel.position + _wheel.size * 0.5 if _wheel != null else WORLD * 0.5

## 转盘在游戏界面坐标（飘字用，含视角旋转）
func wheel_screen_pos() -> Vector2:
	return global_position + _view_from_world(wheel_center())

## 转盘点数：镜头对准转盘，转完后镜头回到行动棋子
func spin_wheel(value: int, restore_peer := -1) -> void:
	if _wheel == null:
		return
	_wheel.spin_to(value)
	_wheel_restore = restore_peer
	_wheel_wait = WheelView.SPIN_TIME + 0.1
	focus_point(wheel_center(), false)

func is_wheel_spinning() -> bool:
	return _wheel != null and _wheel.spinning

func deck_center(deck: String) -> Vector2:
	return _deck_pos.get(deck, WORLD * 0.5)

## 抽卡展示的相位动画：滑出 0.32s → 停留 1.75s → 收回 0.28s
const DECK_OUT := 0.32
const DECK_HOLD := 1.75
const DECK_BACK := 0.28

func _tick_deck_card(delta: float) -> void:
	if _deck_card == null or not is_instance_valid(_deck_card):
		return
	_deck_t += delta
	var c: Control = _deck_card
	if _deck_t < DECK_OUT:
		var k: float = _ease_out_back(_deck_t / DECK_OUT)
		c.position = _deck_from.lerp(_deck_shown, k)
		c.modulate.a = minf(_deck_t / 0.18, 1.0)
		var sc := 0.5 + 0.5 * k
		c.scale = Vector2(sc, sc)
	elif _deck_t < DECK_OUT + DECK_HOLD:
		c.position = _deck_shown
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
	elif _deck_t < DECK_OUT + DECK_HOLD + DECK_BACK:
		var k2: float = (_deck_t - DECK_OUT - DECK_HOLD) / DECK_BACK
		c.position = _deck_shown.lerp(_deck_from, k2)
		c.modulate.a = 1.0 - k2
		var sc2 := 1.0 - 0.4 * k2
		c.scale = Vector2(sc2, sc2)
	else:
		var restore := _deck_restore
		c.queue_free()
		_deck_card = null
		if restore != -1:
			focus_peer(restore)
		else:
			_has_follow_pt = false

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

## 是否正在牌堆位置展示抽卡（供对局层暂停「镜头跟棋子」抢占）
func is_showing_deck_card() -> bool:
	return _deck_card != null and is_instance_valid(_deck_card)

## 仿桌游抽卡：镜头对准牌堆，卡片从堆中滑出、放大展示，再收回；
## 展示结束后镜头回到 restore_peer 的棋子（-1 则停在原地）。
func play_deck_card(deck: String, kind: String, text: String, restore_peer := -1) -> void:
	if not _deck_pos.has(deck):
		return
	if _deck_card != null and is_instance_valid(_deck_card):
		_deck_card.queue_free()
		_deck_card = null

	var center: Vector2 = _deck_pos[deck]
	var style: Array = UIKit.card_palette(kind)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(style[1], 14, style[0], 2, 10))
	card.custom_minimum_size = Vector2(560, 150)
	var m := UIKit.margins(18, 18, 10, 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	var title := UIKit.label(deck, 22, style[0])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var body := UIKit.label(text, 15, UIKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(524, 0)  # 卡宽 560 - 左右边距，锁定换行宽度
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 30
	_world.add_child(card)
	card.size = Vector2(560, 150)
	card.pivot_offset = card.size * 0.5

	var start := center - card.size * 0.5 + Vector2(0, 54)
	var shown := center - card.size * 0.5 - Vector2(0, 140)
	shown.x = clampf(shown.x, 16.0, WORLD.x - card.size.x - 16.0)
	card.position = start
	card.modulate.a = 0.0
	card.scale = Vector2(0.5, 0.5)
	focus_point(center + Vector2(0, -110), false)

	_deck_card = card
	_deck_t = 0.0
	_deck_from = start
	_deck_shown = shown
	_deck_restore = restore_peer

func _build_ring() -> void:
	_ring = Panel.new()
	_ring.size = Vector2(64, 64)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.z_index = 15
	var sb := UIKit.stylebox(Color(0, 0, 0, 0), 32, UIKit.ACCENT, 3)
	sb.draw_center = false
	_ring.add_theme_stylebox_override("panel", sb)
	_ring.visible = false
	_world.add_child(_ring)

# ---------------- 视口：缩放 / 平移 / 跟随 ----------------

func _process(delta: float) -> void:
	if _need_fit and size.x > 10.0:
		_need_fit = false
		fit_overview(true)  # 初始镜头：四人围桌全景
	if auto_follow and _has_follow_pt:
		_pan_toward(_follow_pt, delta)
	elif auto_follow and _follow_peer != -1 and _tokens.has(_follow_peer):
		var tk: Control = _tokens[_follow_peer]
		_pan_toward(tk.position + tk.size * 0.5, delta)
	if _rotating:
		var k := 1.0 - exp(-7.0 * delta)
		_rot = lerp_angle(_rot, _rot_target, k)
		_center = _center.lerp(_center_target, k)
		if absf(wrapf(_rot_target - _rot, -PI, PI)) < 0.004 and _center.distance_to(_center_target) < 1.0:
			_rot = _rot_target
			_center = _center_target
			_rotating = false
	if _ring_peer != -1 and _tokens.has(_ring_peer):
		var tk2: Control = _tokens[_ring_peer]
		_ring.position = tk2.position + tk2.size * 0.5 - _ring.size * 0.5
	_tick_deck_card(delta)
	if _wheel_wait > 0.0:
		_wheel_wait -= delta
		if _wheel_wait <= 0.0 and _wheel_restore != -1:
			focus_peer(_wheel_restore)
			_wheel_restore = -1
	_apply_cam()

## 镜头平滑推向某个世界坐标点（棋子中心 / 牌堆）
func _pan_toward(world_center: Vector2, delta: float) -> void:
	_center = _center.lerp(_clamp_center(world_center), 1.0 - exp(-6.0 * delta))

func _visible_rect() -> Rect2:
	return Rect2(overlay_left, overlay_top, size.x - overlay_left - overlay_right, size.y - overlay_top - overlay_bottom)

## 全桌概览（把整张围桌塞进可视区域，回到自己视角）；hard=true 立即到位
func fit_overview(hard := false) -> void:
	auto_follow = false
	_follow_peer = -1
	_has_follow_pt = false
	_rot_target = 0.0
	_rotating = true
	var vr := _visible_rect()
	var occ := _occupied_rect()
	var osize := occ.size.rotated(_rot_target).abs()
	_zoom = clampf(minf(vr.size.x / (osize.x + 40.0), vr.size.y / (osize.y + 40.0)), MIN_ZOOM, 1.0)
	_center_target = occ.get_center()
	if hard:
		_rot = 0.0
		_rotating = false
		_center = _center_target
	_apply_cam()

## 镜头对准某格 / 某棋子；hard=true 立即居中（显式对焦会打断进行中的转视角动画）
func focus_grid(idx: int, zoom: float, hard := true) -> void:
	if cam_locked:
		return
	auto_follow = false
	_follow_peer = -1
	_has_follow_pt = false
	_rotating = false
	_zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	if hard:
		_center = _clamp_center(tile_pos(idx) + Vector2(TILE, TILE) * 0.5)
		_center_target = _center
	_apply_cam()

## 镜头跟随一个世界坐标点（抽卡时对准牌堆）
func focus_point(world_pt: Vector2, hard := false) -> void:
	if cam_locked or not at_home_view():
		return  # 摆拍锁定或身在别人视角时，对局镜头不抢方向盘
	auto_follow = true
	_follow_peer = -1
	_has_follow_pt = true
	_follow_pt = world_pt
	_rotating = false
	if hard:
		_center = _clamp_center(world_pt)
		_center_target = _center
	_apply_cam()

func focus_peer(peer: int, hard := false) -> void:
	if cam_locked or not at_home_view():
		return  # 身在别人视角时，对局镜头不抢方向盘
	auto_follow = true
	_follow_peer = peer
	_has_follow_pt = false
	_rotating = false
	if hard and _tokens.has(peer):
		var tk: Control = _tokens[peer]
		_center = _clamp_center(tk.position + tk.size * 0.5)
		_center_target = _center
	_apply_cam()

func _zoom_at(factor: float, anchor: Vector2) -> void:
	var before := _world_from_view(anchor)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_center = _clamp_center(before - (anchor - _visible_center()).rotated(-_rot) / _zoom)
	_apply_cam()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.12, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.12, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_dragging = true
				_panning = false
				_press_pos = mb.position
			elif _dragging:
				if mb.button_index == MOUSE_BUTTON_LEFT and not _panning:
					var e := _seat_edge_at(mb.position)
					if e != -1:
						Fx.play("click", -10.0)
						rotate_to_edge(e)
						seat_clicked.emit(int(_seats[e].peer))
					else:
						var idx := _index_at(mb.position)
						if idx >= 0:
							Fx.play("click", -10.0)
							tile_clicked.emit(idx)
				if not (mb.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
					_dragging = false
					_panning = false
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var mask := mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)
		if _dragging and mask != 0:
			if _panning or mm.position.distance_to(_press_pos) > 6.0:
				_panning = true
				_set_seat_hover(-1)
				_rotating = false   # 拖拽立即接管，转场动画不再拉扯
				auto_follow = false
				_has_follow_pt = false
				_center = _clamp_center(_center - mm.relative.rotated(-_rot) / _zoom)
				_apply_cam()
		else:
			set_hover(_index_at(mm.position))
			_set_seat_hover(_seat_edge_at(mm.position))

## 设置悬停格（-1 清除），触发高亮渐变
func set_hover(idx: int) -> void:
	if idx == _hover:
		return
	var old := _hover
	_hover = idx
	if old >= 0:
		_animate_tile(old, false)
	if idx >= 0:
		_animate_tile(idx, true)

# ---------------- 四人围桌座位 ----------------

var _seats := {}         # edge(0底 1左 2上 3右) -> 座位部件字典
var _seat_of_peer := {}  # peer -> edge
var _my_peer := -1

## 按行动顺序落座：e0=自己，e1=下家(左)，e2=对家(上)，e3=上家(右)；人不满空位不建
func build_seats(players: Array, my_peer: int) -> void:
	for e in _seats:
		(_seats[e].root as Control).queue_free()
	_seats.clear()
	_seat_of_peer.clear()
	_my_peer = my_peer
	var my_i := 0
	for i in players.size():
		if int(players[i].peer) == my_peer:
			my_i = i
			break
	for k in players.size():
		var p: Dictionary = players[(my_i + k) % players.size()]
		_seats[k] = _make_seat(p, k)
		_seat_of_peer[int(p.peer)] = k

func seat_count() -> int:
	return _seats.size()

func seat(peer: int) -> Dictionary:
	return _seats.get(int(_seat_of_peer.get(peer, -1)), {})

## 第 e 条操作栏的方框区域（世界坐标）：上下栏横贯全边、左右栏嵌在上下栏之间，拼成闭合方框
func _seat_bar(e: int) -> Rect2:
	var ht := TABLE.position.y + BAND_TB
	var hb := TABLE.end.y - BAND_TB
	match e:
		1: return Rect2(TABLE.position.x, ht, BAND_SIDE, hb - ht)
		3: return Rect2(WORLD.x + HOLE_MX, ht, BAND_SIDE, hb - ht)
		2: return Rect2(TABLE.position.x, TABLE.position.y, TABLE.size.x, BAND_TB)
		_: return Rect2(TABLE.position.x, hb, TABLE.size.x, BAND_TB)

func _seat_center(e: int) -> Vector2:
	return _seat_bar(e).get_center()

func _occupied_rect() -> Rect2:
	var r := Rect2(Vector2.ZERO, WORLD).grow(30.0)
	for e in _seats:
		r = r.merge(_seat_bar(e))
	# 顶部空区（数据轨 + 小卖部/赌场设施）：没有上家座位时也要整体入画
	var zone_top := TABLE.position.y + BAND_TB
	r = r.merge(Rect2(Vector2(-HOLE_MX, zone_top),
		Vector2(WORLD.x + 2.0 * HOLE_MX, BOARD_OFFSET.y - 26.0 - zone_top)))
	return r

var _view_edge := 0         # 当前视角所在的座位边（0=自己）

## 视角旋转：点谁转谁（TA 的区域转到屏幕下方变正）；空格/点自己回自己视角
func rotate_to_seat(peer: int) -> void:
	rotate_to_edge(int(_seat_of_peer.get(peer, -1)))

func rotate_to_edge(e: int, hard := false) -> void:
	if e < 0 or not _seats.has(e):
		return
	_view_edge = e
	_rot_target = -e * PI * 0.5
	_center_target = _clamp_center(_seat_center(e))
	if hard:
		_rot = _rot_target
		_center = _center_target
		_rotating = false
	else:
		_rotating = true
	auto_follow = false
	_follow_peer = -1
	_has_follow_pt = false
	_apply_cam()

func rotate_home() -> void:
	rotate_to_edge(0)

## 「跟随」：视角转回自己并恢复行动跟随（绕过别人视角的镜头闸）
func go_home_follow(peer: int) -> void:
	auto_follow = true
	_follow_peer = peer
	_has_follow_pt = false
	_view_edge = 0
	_rot_target = 0.0
	_rotating = true

## Tab：按行动顺序循环切换到下一个有人的座位视角
func rotate_next() -> void:
	var order: Array = _seats.keys()
	order.sort()
	var i: int = order.find(_view_edge)
	rotate_to_edge(int(order[(i + 1) % order.size()]))

func is_rotating() -> bool:
	return _rotating

## 是否坐在自己的视角上（≈0°）；转去别人座位期间对局层不应把镜头拉回
func at_home_view() -> bool:
	return absf(wrapf(_rot, -PI, PI)) < 0.3

func _seat_edge_at(view_pos: Vector2) -> int:
	var wpt := _world_from_view(view_pos)
	for e in _seats:
		if _seat_bar(e).has_point(wpt):
			return e
	return -1

func _seat_at(view_pos: Vector2) -> int:
	var e := _seat_edge_at(view_pos)
	return int(_seats[e].peer) if e != -1 else -1

var _hover_seat := -1  # 悬停中的座位边（-1 无）

## 悬停反馈：内容卡提亮 + 手势光标，明示「这块可以点」
func _set_seat_hover(e: int) -> void:
	if e == _hover_seat:
		return
	var old := _hover_seat
	_hover_seat = e
	if old != -1 and _seats.has(old):
		_seat_hover_fx(old, false)
	if e != -1 and _seats.has(e):
		_seat_hover_fx(e, true)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if e != -1 else Control.CURSOR_ARROW

func _seat_hover_fx(e: int, hovered: bool) -> void:
	var content: Control = _seats[e].get("content")
	if content == null or not is_instance_valid(content):
		return
	var tw := create_tween()
	tw.tween_property(content, "modulate", Color(1.16, 1.16, 1.24) if hovered else Color.WHITE, 0.12)

## 一个座位：整条操作栏面板（拼方框的一边）+ 旋转排布的内容件
## （头像/名字/现金/体力 + 5 个道具牌位），内容朝向座位主人
func _make_seat(p: Dictionary, e: int) -> Dictionary:
	var bar := _seat_bar(e)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(holder)

	# 栏底：极淡的暗色横条，只负责拼出方框轮廓，不描边不抢眼
	var bar_sb := UIKit.stylebox(Color(0.03, 0.035, 0.06, 0.40), 18, Color(0, 0, 0, 0), 0)
	var body := Panel.new()
	body.position = bar.position
	body.size = bar.size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_stylebox_override("panel", bar_sb)
	holder.add_child(body)

	var root := Control.new()
	root.size = SEAT_SIZE
	root.pivot_offset = SEAT_SIZE * 0.5
	root.rotation_degrees = e * 90.0
	root.position = bar.get_center() - SEAT_SIZE * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(root)

	# 内容卡：紧凑包住信息与牌位，回合高亮描边画在这里而不是整条栏上
	var sb := UIKit.stylebox(Color(0.078, 0.086, 0.124, 0.88), 16, Color(0, 0, 0, 0), 2)
	var card := Panel.new()
	card.size = SEAT_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)

	var chip: Control
	var piece := UIKit.piece_tex(int(p.color) % 4)
	if piece != null:
		var tr := TextureRect.new()
		tr.texture = piece
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(16, 16)
		tr.size = Vector2(52, 60)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		chip = tr
	else:
		chip = UIKit.chip(GameData.PLAYER_COLORS[int(p.color) % 4], 26)
		chip.position = Vector2(22, 26)
		root.add_child(chip)

	var name_l := UIKit.label(String(p.name), 21, UIKit.TEXT)
	name_l.position = Vector2(78, 14)
	name_l.size = Vector2(158, 56)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_l)

	var money_l := UIKit.label(GameData.fmt_money(int(p.money)), 22, UIKit.ACCENT)
	money_l.position = Vector2(14, 92)
	money_l.size = Vector2(224, 40)
	money_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(money_l)

	var stamina_row := HBoxContainer.new()
	stamina_row.position = Vector2(14, 148)
	stamina_row.size = Vector2(224, 40)
	stamina_row.add_theme_constant_override("separation", 5)
	stamina_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stamina_row)
	var bolt := UIKit.label("⚡", 20, Color(1.0, 0.85, 0.3))
	bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_row.add_child(bolt)
	var pips: Array = []
	for i in 5:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(24, 30)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", UIKit.stylebox(Color(1, 1, 1, 0.07), 4, Color(0, 0, 0, 0.25), 1))
		stamina_row.add_child(pip)
		pips.append(pip)

	var slots: Array = []
	for i in 5:
		var sp := Panel.new()
		sp.position = Vector2(254.0 + float(i) * (SLOT_SIZE.x + 10.0), 12)
		sp.size = SLOT_SIZE
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.add_theme_stylebox_override("panel", UIKit.stylebox(Color(1, 1, 1, 0.035), 10,
			Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.55), 1))
		root.add_child(sp)
		var plus := UIKit.label("+", 34, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.4))
		plus.set_anchors_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.add_child(plus)
		slots.append(sp)

	return {"root": holder, "content": root, "sb": sb, "chip": chip, "name_l": name_l, "money_l": money_l,
		"pips": pips, "slots": slots, "edge": e, "peer": int(p.peer),
		"shown": int(p.money), "tw": null}

# ---------------- 顶部区域：数据轨 + 小卖部 / 赌场两座常驻设施 ----------------

var _rank_rows := []                # {peer, cell, name_l, money_l, prop_l}
var _rank_box: HBoxContainer
var _world_log: RichTextLabel
var _casino_pool_l: Label
var _casino_status_l: Label
var _shop_slots: Array = []         # {card, price_l}（道具系统解冻后接货架存货）
var _shop_refresh: Button

const SHOP_ACCENT := Color(0.42, 0.78, 0.55)    # 小卖部：菜绿
const CASINO_ACCENT := Color(0.93, 0.3, 0.55)   # 赌场：与赌场格同色
const SHOP_QUALITIES := [Color(0.93, 0.93, 0.93), Color(0.42, 0.78, 0.55),
	Color(0.36, 0.6, 0.92), Color(0.66, 0.47, 0.92), Color(0.96, 0.62, 0.25)]  # 白绿蓝紫橙
const SHOP_WOOD_TEXT := Color(0.78, 0.7, 0.58)     # 木柜台上的米黄字
const CASINO_FELT_TEXT := Color(0.72, 0.8, 0.68)   # 绿呢桌上的浅绿字

## 顶部空区：上层数据轨（战况四家横排 + 最近战报），下层左右两座常驻设施
## （左小卖部 / 右赌场，世界坐标随桌面旋转；小卖部为道具系统的桌面柜台壳子）
func _build_top_panels() -> void:
	var top := TABLE.position.y + BAND_TB + 36.0
	var bot := BOARD_OFFSET.y - 36.0
	var left := -HOLE_MX
	var right := WORLD.x + HOLE_MX
	var half := (right - left - 16.0) * 0.5
	var rail_h := 88.0
	_make_rank_rail(Rect2(left, top, half, rail_h))
	_make_log_rail(Rect2(right - half, top, half, rail_h))
	var fy := top + rail_h + 12.0
	var fh := bot - fy
	_make_shop(Rect2(left, fy, half, fh))
	_make_casino(Rect2(right - half, fy, half, fh))

func _zone_panel(rect: Rect2, sb: StyleBox) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", sb)
	_world.add_child(panel)
	return panel

func _mini_card_back() -> Panel:
	var cb := Panel.new()
	cb.size = Vector2(34, 46)
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.125, 0.11, 0.155), 8,
		Color(UIKit.ACCENT_DEEP.r, UIKit.ACCENT_DEEP.g, UIKit.ACCENT_DEEP.b), 1, 3))
	return cb

func _fixture_icon(icon_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UIKit.icon(icon_name)
	t.custom_minimum_size = Vector2(30, 30)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _make_rank_rail(rect: Rect2) -> void:
	var panel := _zone_panel(rect, UIKit.stylebox(Color(0.078, 0.086, 0.124, 0.82), 16,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.5), 1))
	var m := UIKit.margins(16, 12, 10, 8)
	m.position = Vector2(16, 10)
	m.size = rect.size - Vector2(32, 18)  # Panel 非容器，内衬需显式铺满
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var cap := UIKit.label("战况", 14, UIKit.TEXT_DIM)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)
	_rank_box = HBoxContainer.new()
	_rank_box.add_theme_constant_override("separation", 16)
	_rank_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rank_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_rank_box)

func _make_log_rail(rect: Rect2) -> void:
	var panel := _zone_panel(rect, UIKit.stylebox(Color(0.078, 0.086, 0.124, 0.82), 16,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.5), 1))
	var m := UIKit.margins(16, 12, 10, 8)
	m.position = Vector2(16, 10)
	m.size = rect.size - Vector2(32, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var cap := UIKit.label("最近战报", 14, UIKit.TEXT_DIM)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)
	_world_log = RichTextLabel.new()
	_world_log.bbcode_enabled = true
	_world_log.scroll_following = true
	_world_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_log.add_theme_font_size_override("normal_font_size", 15)
	_world_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_world_log)

## 小卖部（左半）：木柜台 + 绿白条纹雨棚 + 货架 3 格 + 品质图例 + 刷新按钮
## （道具系统解冻后接货架存货 / 刷新费用 / 购买操作，规格零迁移）
func _make_shop(rect: Rect2) -> void:
	var panel := _zone_panel(rect, UIKit.card_stylebox(Color(0.135, 0.095, 0.06, 0.97), 18,
		Color(0.36, 0.25, 0.13), 2, 14))
	# 雨棚：绿白竖条纹 + 圆弧垂边，压在柜台顶上
	var band := HBoxContainer.new()
	band.position = Vector2(14, 12)
	band.size = Vector2(rect.size.x - 28.0, 30)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(band)
	var scal := HBoxContainer.new()
	scal.position = Vector2(14, 42)
	scal.size = Vector2(rect.size.x - 28.0, 20)
	scal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scal)
	for i in 24:
		var c := SHOP_ACCENT if i % 2 == 0 else Color(0.93, 0.9, 0.8)
		var cr := ColorRect.new()
		cr.color = c
		cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(cr)
		var cup := Panel.new()
		var cup_w := (rect.size.x - 28.0) / 24.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.corner_radius_bottom_left = int(cup_w * 0.5)
		sb.corner_radius_bottom_right = int(cup_w * 0.5)
		sb.border_width_bottom = 1
		sb.border_color = Color(0, 0, 0, 0.2)
		cup.add_theme_stylebox_override("panel", sb)
		cup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scal.add_child(cup)
	var m := UIKit.margins(0, 0, 0, 0)
	m.position = Vector2(18, 76)
	m.size = rect.size - Vector2(36, 88)  # 上让位雨棚，下留 12 底边距
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var plaque := UIKit.panel_container(Color(0.1, 0.07, 0.045, 0.95), 8, Color(0.5, 0.36, 0.18), 1)
	head.add_child(plaque)
	var pm := UIKit.margins(12, 10, 4, 4)
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(pm)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_child(ph)
	ph.add_child(_fixture_icon("daily"))
	ph.add_child(UIKit.label("小卖部", 24, Color(0.93, 0.88, 0.75)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	head.add_child(UIKit.label("每回合限购 1 件 · 刷新费递增", 14, SHOP_WOOD_TEXT))
	var shelf := HBoxContainer.new()
	shelf.add_theme_constant_override("separation", 28)
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(shelf)
	for i in 3:
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 5)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shelf.add_child(slot)
		var card := Panel.new()
		card.custom_minimum_size = Vector2(150, 150)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0.06, 0.045, 0.03, 0.95), 10,
			Color(0.45, 0.32, 0.16, 0.55), 1))
		slot.add_child(card)
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cc)
		cc.add_child(UIKit.label("＋", 36, Color(0.93, 0.88, 0.75, 0.16)))
		var price_l := UIKit.label("待上架", 13, SHOP_WOOD_TEXT)
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(price_l)
		_shop_slots.append({"card": card, "price_l": price_l})
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 5)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(legend)
	for qi in SHOP_QUALITIES.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(13, 13)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var qc: Color = SHOP_QUALITIES[qi]
		dot.add_theme_stylebox_override("panel", UIKit.stylebox(qc, 6, Color(0, 0, 0, 0.4), 1))
		legend.add_child(dot)
		legend.add_child(UIKit.label(["白", "绿", "蓝", "紫", "橙"][qi], 13, SHOP_WOOD_TEXT))
	_shop_refresh = UIKit.button("刷新货架 · ¥—", 14)
	_shop_refresh.disabled = true
	_shop_refresh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(_shop_refresh)


## 赌场（右半）：绿呢牌桌 + 金色滚边 + 两张卡背，奖池/状态活数据；对局玩法仍在弹层
func _make_casino(rect: Rect2) -> void:
	var panel := _zone_panel(rect, UIKit.card_stylebox(Color(0.062, 0.155, 0.105, 0.97), 18,
		Color(UIKit.ACCENT_DEEP.r, UIKit.ACCENT_DEEP.g, UIKit.ACCENT_DEEP.b), 2, 14))
	# 牌桌内圈金线
	var ring := Panel.new()
	ring.position = Vector2(10, 10)
	ring.size = rect.size - Vector2(20, 20)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0, 0, 0, 0), 12,
		Color(UIKit.ACCENT_HI.r, UIKit.ACCENT_HI.g, UIKit.ACCENT_HI.b, 0.3), 1))
	panel.add_child(ring)
	var m := UIKit.margins(18, 16, 16, 14)
	m.position = Vector2(18, 16)
	m.size = rect.size - Vector2(36, 30)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(_fixture_icon("casino"))
	head.add_child(UIKit.label("宿舍赌场", 26, UIKit.ACCENT_HI))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	head.add_child(UIKit.label("踩到赌场格开局 · 全员入局 · 赢家通吃", 14, CASINO_FELT_TEXT))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mid)
	var pot_row := HBoxContainer.new()
	pot_row.add_theme_constant_override("separation", 24)
	pot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(pot_row)
	var cb_l := _mini_card_back()
	cb_l.rotation = -0.12
	cb_l.pivot_offset = Vector2(17, 23)
	pot_row.add_child(cb_l)
	var pot_panel := UIKit.panel_container(Color(0.03, 0.07, 0.05, 0.9), 12,
		Color(UIKit.ACCENT_HI.r, UIKit.ACCENT_HI.g, UIKit.ACCENT_HI.b, 0.45), 1)
	pot_row.add_child(pot_panel)
	var pm := UIKit.margins(28, 28, 10, 8)
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pot_panel.add_child(pm)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_child(pv)
	var cap := UIKit.label("当前奖池", 14, CASINO_FELT_TEXT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(cap)
	_casino_pool_l = UIKit.label("¥0", 42, UIKit.ACCENT)
	_casino_pool_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_casino_pool_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(_casino_pool_l)
	var cb_r := _mini_card_back()
	cb_r.rotation = 0.12
	cb_r.pivot_offset = Vector2(17, 23)
	pot_row.add_child(cb_r)
	_casino_status_l = UIKit.label("歇业中 · 等待有人踩中赌场格", 15, CASINO_FELT_TEXT)
	_casino_status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_casino_status_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_casino_status_l)


## 赌场设施活数据（pool = 0 视为歇业）
func update_casino(pool: int, status: String) -> void:
	if _casino_pool_l != null and is_instance_valid(_casino_pool_l):
		_casino_pool_l.text = GameData.fmt_money(pool)
	if _casino_status_l != null and is_instance_valid(_casino_status_l):
		_casino_status_l.text = status
		_casino_status_l.add_theme_color_override("font_color",
			UIKit.ACCENT if pool > 0 else CASINO_FELT_TEXT)


## 战况轨：按行动顺序四家横排（现金由对局层刷新）
func build_rank(players: Array) -> void:
	for r in _rank_rows:
		(r.cell as Control).queue_free()
	_rank_rows.clear()
	for p in players:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(row)
		var chip := UIKit.chip(GameData.PLAYER_COLORS[int(p.color) % 4], 13)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var name_l := UIKit.label(String(p.name), 16, UIKit.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_l)
		var money_l := UIKit.label(GameData.fmt_money(int(p.money)), 16, UIKit.ACCENT)
		money_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(money_l)
		var prop_l := UIKit.label("", 12, UIKit.TEXT_DIM)
		prop_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		prop_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(prop_l)
		_rank_box.add_child(cell)
		_rank_rows.append({"peer": int(p.peer), "cell": cell, "name_l": name_l,
			"money_l": money_l, "prop_l": prop_l})

func rank_count() -> int:
	return _rank_rows.size()

func update_rank_row(peer: int, money: int, prop_text: String) -> void:
	for r in _rank_rows:
		if int(r.peer) == peer:
			(r.money_l as Label).text = GameData.fmt_money(money)
			(r.prop_l as Label).text = prop_text
			return

## 最近战报镜像（世界面板）
func world_log_line(bb: String) -> void:
	if _world_log != null and is_instance_valid(_world_log):
		_world_log.append_text(bb + "\n")

# ---------------- 渲染状态快照 ----------------

func render(state: Dictionary) -> void:
	var tiles: Array = state.get("tiles", [])
	var players: Array = state.get("players", [])
	var color_of := {}
	for p in players:
		color_of[int(p.peer)] = GameData.PLAYER_COLORS[int(p.color)]
	_owner_color_map = color_of

	for i in _tile_sb.size():
		var owner_id := GameData.NO_OWNER
		var level := 0
		if i < tiles.size():
			owner_id = int(tiles[i].get("owner", GameData.NO_OWNER))
			level = int(tiles[i].get("level", 0))
		if owner_id != _owners[i]:
			_owners[i] = owner_id
			_animate_tile(i, _hover == i)
		if level != _levels[i]:
			_levels[i] = level
			_set_star(i, level)

		var d: Dictionary = GameData.TILES[i]
		var sub: Label = _sub_labels[i]
		match String(d.type):
			"property":
				sub.text = _short_money(int(d.price)) if owner_id == GameData.NO_OWNER else ""
			"fine":
				sub.text = "-" + _short_money(int(d.amount))
			"bonus":
				sub.text = "+" + _short_money(int(d.amount))
			"start":
				sub.text = "+" + _short_money(GameData.SALARY)
			"jail":
				sub.text = "反省处"
			"go_jail":
				sub.text = "送你进去"
			"rest":
				sub.text = "免费休息"
			"event":
				sub.text = "?"
			"casino":
				sub.text = "全员豪赌"

	var phase := String(state.get("phase", "playing"))
	if phase == "ended":
		_set_ring(-1)
	else:
		_set_ring(int(state.get("turn", -1)))

	# 棋子：新建带弹入，动画中的不动
	var seen := {}
	for p in players:
		var peer := int(p.peer)
		seen[peer] = true
		var slot := int(p.color)
		if not _tokens.has(peer):
			var tk := _make_token(slot, String(p.name))
			tk.set_meta("slot", slot)
			_tokens[peer] = tk
			_animating[peer] = false
			_world.add_child(tk)
			tk.position = _token_at(int(p.pos), slot)
			tk.pivot_offset = tk.size * 0.5
			tk.scale = Vector2.ZERO
			var tw := tk.create_tween()
			tw.tween_property(tk, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not _animating.get(peer, false):
			var tk2: Control = _tokens[peer]
			tk2.set_meta("slot", slot)
			tk2.position = _token_at(int(p.pos), slot)

	for peer in _tokens.keys():
		if not seen.has(peer):
			_tokens[peer].queue_free()
			_tokens.erase(peer)

func _short_money(v: int) -> String:
	if v >= 1000:
		var k := float(v) / 1000.0
		var s := "%.1f" % k
		if s.ends_with(".0"):
			s = s.substr(0, s.length() - 2)
		return "¥%sk" % s
	return "¥%d" % v

func _animate_tile(i: int, hovered: bool) -> void:
	var d: Dictionary = GameData.TILES[i]
	var corner: bool = d.type in ["start", "jail", "rest", "go_jail"]
	var base := Color("#38301c") if corner else Color("#242a39")
	var border := Color("#3c4254")
	var border_w := 1
	var owner_id := int(_owners[i])
	if owner_id >= 0 and _owner_color_map.has(owner_id):
		var oc: Color = _owner_color_map[owner_id]
		base = base.lerp(oc, 0.20)
		border = oc
		border_w = 3
	if hovered:
		base = base.lerp(Color(1, 1, 1), 0.12)
	var sb: StyleBoxFlat = _tile_sb[i]
	if _tile_tw.has(i) and (_tile_tw[i] as Tween).is_valid():
		_tile_tw[i].kill()
	var tw := create_tween()
	_tile_tw[i] = tw
	tw.set_parallel(true)
	tw.tween_property(sb, "bg_color", base, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sb, "border_color", border, 0.22)
	tw.tween_property(sb, "border_width_left", border_w, 0.15)
	tw.tween_property(sb, "border_width_right", border_w, 0.15)
	tw.tween_property(sb, "border_width_top", border_w, 0.15)
	tw.tween_property(sb, "border_width_bottom", border_w, 0.15)
	tw.set_parallel(false)

func _set_star(i: int, level: int) -> void:
	var star: Label = _star_labels[i]
	star.text = "★".repeat(level)
	if level <= 0:
		return
	star.pivot_offset = star.size * 0.5
	star.scale = Vector2(1.9, 1.9)
	var tw := star.create_tween()
	tw.tween_property(star, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_ring(peer: int) -> void:
	if peer == _ring_peer:
		return
	_ring_peer = peer
	if _ring_tw != null and _ring_tw.is_valid():
		_ring_tw.kill()
		_ring_tw = null
	if peer == -1 or not _tokens.has(peer):
		_ring.visible = false
		return
	_ring.visible = true
	_ring.scale = Vector2.ONE
	_ring.pivot_offset = _ring.size * 0.5
	_ring_tw = create_tween()
	_ring_tw.set_loops()
	_ring_tw.tween_property(_ring, "scale", Vector2(1.16, 1.16), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ring_tw.parallel().tween_property(_ring, "modulate:a", 0.55, 0.55)
	_ring_tw.tween_property(_ring, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ring_tw.parallel().tween_property(_ring, "modulate:a", 1.0, 0.55)

# ---------------- 棋子 ----------------

func _token_target(p: Dictionary, slot: int) -> Vector2:
	return _token_at(int(p.pos), slot)

func _token_at(idx: int, slot: int) -> Vector2:
	return tile_pos(idx) + Vector2(TILE, TILE) * 0.5 - Vector2(22, 25) + _slot_offset(slot)

func _slot_offset(slot: int) -> Vector2:
	match slot % 4:
		0: return Vector2(-28, -28)
		1: return Vector2(28, -28)
		2: return Vector2(-28, 28)
		_: return Vector2(28, 28)

## 棋子：Kenney 桌游小人（CC0），按玩家槽位取色；素材缺失时退回纯色圆片
func _make_token(slot: int, pname: String) -> Control:
	var piece := UIKit.piece_tex(slot)
	var tk: Control
	if piece != null:
		var tr := TextureRect.new()
		tr.texture = piece
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(44, 50)
		tk = tr
	else:
		var p := Panel.new()
		var sb := UIKit.stylebox(GameData.PLAYER_COLORS[slot % 4], 10, Color(0.95, 0.95, 0.97), 2, 4, Color(0, 0, 0, 0.45))
		p.add_theme_stylebox_override("panel", sb)
		p.size = Vector2(20, 20)
		tk = p
	tk.pivot_offset = tk.size * 0.5
	tk.tooltip_text = pname
	tk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tk.z_index = 20
	return tk

func token_world_pos(peer: int) -> Vector2:
	if not _tokens.has(peer):
		return Vector2.ZERO
	var tk: Control = _tokens[peer]
	return tk.position + tk.size * 0.5

## 棋子在游戏界面坐标（飘字用，含视角旋转）
func token_screen_pos(peer: int) -> Vector2:
	return global_position + _view_from_world(token_world_pos(peer))

func _kill_token_tw(peer: int) -> void:
	if not _tokens.has(peer):
		return
	var tk: Control = _tokens[peer]
	if tk.has_meta("tw"):
		var old = tk.get_meta("tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()

## 传送落点（游戏层先 set_teleport_target 再 play_move(peer, [], t)）
func set_teleport_target(peer: int, idx: int) -> void:
	if _tokens.has(peer):
		_tokens[peer].set_meta("tp", idx)

## 逐步走子动画（每步小跳 + 挤压 + 落地音）；path 为空表示传送（淡出淡入）
func play_move(peer: int, path: Array, step_time: float) -> void:
	var p := int(peer)
	if not _tokens.has(p):
		return
	var tk: Control = _tokens[p]
	_kill_token_tw(p)
	_animating[p] = true
	if path.is_empty():
		_teleport_anim(p, tk)
		return
	if auto_follow:
		_follow_peer = p
	var tw := create_tween()
	tk.set_meta("tw", tw)
	var slot := int(tk.get_meta("slot", 0))
	for step in path:
		var pos := _token_at(int(step), slot)
		tw.tween_callback(Fx.play.bind("tick", -8.0, randf_range(0.9, 1.2)))
		tw.tween_property(tk, "position", pos, step_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(tk, "scale", Vector2(1.28, 1.28), step_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(tk, "scale", Vector2.ONE, step_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void:
		_animating[p] = false
	)

func _teleport_anim(p: int, tk: Control) -> void:
	var slot := int(tk.get_meta("slot", 0))
	var tw := create_tween()
	tk.set_meta("tw", tw)
	if tk.has_meta("tp"):
		var target := int(tk.get_meta("tp"))
		var pos := _token_at(target, slot)
		tw.tween_property(tk, "scale", Vector2(1.5, 1.5), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(tk, "modulate:a", 0.0, 0.16)
		tw.tween_callback(func() -> void:
			tk.position = pos
			Fx.play("pop", -6.0)
		)
		tw.tween_property(tk, "modulate:a", 1.0, 0.22)
		tw.parallel().tween_property(tk, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_interval(0.1)
	tw.tween_callback(func() -> void:
		tk.remove_meta("tp")
		_animating[p] = false
	)
