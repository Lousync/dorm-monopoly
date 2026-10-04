extends Control
class_name BoardView
## 56 格（18×12 外圈）棋盘：世界坐标渲染，自研 2D 相机（注视点 / 缩放，取景与近景）、
## 自动跟随行动棋子。
## 表现细节：归属描边与底色渐变、装修房子弹跳、悬停高亮。
##
## **棋子（小人）、当前行动者光环与悬停信息条都不在这里**（批次 11 Task 1 起）：
## 前两者是立在桌上的 3D 实物 / 贴桌垫的一条环（`TableProps`），走子 / 传送 / 弹入那几样动画
## 也在那边；信息条改挂**屏幕层**（Task 3）。本类只留"棋子落在画布哪个像素"这份纯数据
##（`_peer_anchor` / `slot_anchor`），供镜头跟随用。
##
## 注意：本组件住在 `TableView3D` 的 `SubViewport`（2048²）内，滚轮与拖拽平移
## **都不归它管**——滚轮 = 3D/2D 视角连续推移（`TableView3D.set_view`，批次 4 起取消推拉），
## 平移已删除（见批次 1）。

signal tile_clicked(idx: int)
## **已无发射方（批次 5 Task 2 起）**：座位卡整体退场后，画布里不再有"点玩家"的落点 ——
## 「点玩家选目标」批次 9 起由**屏幕层四角身家条**承担（`game._on_corner_bar_clicked`
## 直调 `game._on_seat_clicked(peer)`）。信号与连接一律保留（同下面两条的先例）：
## 玩法入口 `_on_seat_clicked` 仍在，接口别动。
signal seat_clicked(peer: int)
## 下面两条原属「座位卡道具牌位」那一排（已随批次 3 Task 6 拆除），现在**没有发射方**：
## 选道具改由桌面上的手中牌实体调 `game._on_item_slot_clicked`，丢弃按钮的落点待定。
## 信号与连接一律保留 —— 玩法入口函数（`_on_item_slot_clicked` / `_on_discard_clicked`）
## 仍在，接口别动。
signal item_slot_clicked(peer: int, slot: int)   # 见上方说明：已无发射方，接口保留
signal item_discard_clicked(peer: int, slot: int) # 见上方说明：已无发射方，接口保留
signal cancel_clicked()              # 右键单击（未拖拽平移）：取消当前选择

const TILE := 112.0
static var WORLD := Vector2(GameData.BOARD_COLS, GameData.BOARD_ROWS) * TILE  # 18×12 → (2016, 1344)
const GAP := 5.0
## 倍率区间 —— 是「基准倍率 _fit_zoom 的倍数」，不是绝对像素倍率（1.0 = 全景）。
## 棋盘在 2.5D 之后住进 2048² 的 SubViewport，画布尺度从屏幕（1280×800）变了，
## 同一个绝对倍率的含义会差约 3 倍（全景从 0.40 变成 0.97）——所以一律相对基准表达。
## 数值按「屏幕时代 ÷ 当时的全景 0.40」折回来的：原 0.22 / 1.25（抽卡推近那一档已随批次 8 取消）。
const MIN_ZOOM_FACTOR := 0.55   # 下限（全景附近）
const MAX_ZOOM_FACTOR := 3.1    # 上限（明显更近）
const SELECT_COLOR := Color(1.0, 0.86, 0.35)   # 指向性道具「可选中」高亮（金）
## 抽卡演出（`DECK_PUSH_FACTOR` / `DECK_*` / `CARD_SIZE` / 相位动画那一整套）已随批次 8
## 整段搬到屏幕层的 `DeckReveal`（scripts/deck_reveal.gd）：演出不再把 2D 相机推近，
## 所以这里不再需要推近倍数、相位时长与卡尺寸。要改演出节奏改 `DeckReveal` 里的常量。

## 棋盘在桌垫坐标系里的原点（世界坐标）：18×12 格 × 112 = 2016×1344 的那块。
## 批次 5 Task 2 起四条座位栏离开了画布，棋盘不再被一个方框嵌着 —— 这个偏移现在只是
## 「棋盘摆在桌垫的哪儿」，取景与桌垫窗口都以它 + MAT_RECT 为基准。
const BOARD_OFFSET := Vector2(16.0, 226.0)

## 桌垫（印在木桌上的那块"布"）在**世界坐标**里的矩形 = 棋盘 + 一圈留白。
## 留白是刻意的、不是随手取的边距：桌垫外圈仍要看得见一圈"布边" —— 收到 0 时格子会顶到
## 桌垫边缘、木纹直接贴着格子的描边，观感上"棋盘没有垫子"。**下边（MAT_MB）比上边厚**：
## 那一条正是"玩家面前"（本地玩家坐近端，桌上手牌就摆在近端那侧的木纹上，见
## `table_props.HAND_BASE_PX`）—— 留白最厚的方向就是"自己坐的那一头"。
##
## **批次 10：三个一起缩（100/100/260 → 40/40/90）**，为的是"棋盘在桌垫上占比更大"
## （设计 §4.1）。**必须三个一起缩**：只缩一个会让棋盘在桌垫里偏到一边。
## 棋盘占桌垫：宽 2016/2216 = 91.0% → 2016/2096 = **96.2%**、高 1344/1704 = 78.9% →
## 1344/1474 = **91.2%**（下边仍是最厚的一条）。桌垫一缩 ⇒ `MAT_RECT` 跟着变 ⇒
## `TableView3D.TEX_WINDOW_PX` / `MAT_WINDOW_W` 那一套（画布口径）**必须同步重算**。
##
## 这块矩形就是桌面上看得见的那块桌垫：TableView3D 的 `TEX_WINDOW_PX`（画布口径）
## 与它是**同一块地方的同一比例**，改一边必须改另一边（layout_test 有断言钉住两者一致）。
const MAT_MX := 40.0
const MAT_MT := 40.0
const MAT_MB := 90.0
static var MAT_RECT := Rect2(BOARD_OFFSET - Vector2(MAT_MX, MAT_MT),
	WORLD + Vector2(MAT_MX * 2.0, MAT_MT + MAT_MB))

## 桌垫在画布上的宽度（画布像素）。取景把 MAT_RECT **正好**塞成这个宽度、画布正中 ——
## 于是桌垫内容刚好铺满 TableView3D 的纹理窗口（窗口宽就是它，也居中）。
## 与 `TEX_WINDOW_PX` 是一套口径：改这个数必须同步改那边。
const MAT_WINDOW_W := 2020.0

var auto_follow := true      # 用户拖拽后关闭，点「跟随」按钮恢复
var cam_locked := false      # 摆拍/剧情演出时锁住自动镜头（focus_* 直接忽略）
var overlay_top := 0.0       # 屏幕层覆盖高度/宽度（镜头居中/适配会避开）
var overlay_left := 0.0
var overlay_right := 0.0
var overlay_bottom := 0.0

var _world: Control
var _table: Node2D
var _zoom := 0.5
## 基准倍率：全景适配算出来的那个倍率（= 1.0 倍）。所有对外的倍率参数、上限下限
## 都以它为参照 —— 它随画布尺寸自动变，调用方不必知道画布有多大。
var _fit_zoom := 0.5
var _need_fit := true
var _fitted := false         # 是否已做过首次全景取景（之后的 resized 只重算变换）
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
var _strips: Array = []        # 每格顶带 Panel（有主时显示拥有者颜色）
var _strip_cols: Array = []    # 每格顶带当前颜色（避免悬停时反复重建 stylebox）
var _owners: Array = []        # 上一次渲染的归属（用于渐变过渡）
var _soils: Array = []         # 上一次渲染的焦土状态（用于废墟配色切换）
var _tile_hl: Array = []       # 每格「可选中」高亮叠层（选地块/两段式时显示）
var _tile_tw := {}             # 每格进行中的补间
## 每 peer 的**棋子落点**（画布像素）：格心 + 槽位偏移。**棋子本身住在 `TableProps`**（批次 11
## Task 1 搬进 3D，见 scripts/table_props.gd「棋子（小人）」那一段），画布里已经没有它了；
## 但"镜头跟着自己那枚棋子"（`focus_peer` / 自动跟随）仍要一个落点，所以这里留这份**纯数据**：
## 每次 `render` 从状态里重算一次，与 `tile_pos` / `slot_offset` / `TILE` 同一条链。
var _peer_anchor := {}         # peer -> Vector2（画布像素）
## 悬停棋子的信息条**已随批次 11 Task 1 从画布搬走**（原 `_token_tip` 那套）：
## 它挂在画布上 ⇒ 随桌面倾斜、3D 下是歪的。新的载体是**屏幕层**的 `g.token_tip`
##（批次 11 Task 3），数据源仍是下面这份 `_peers_info`。
var _peers_info := {}          # peer -> {name, color, worth, rank, alive}
var _select_tw: Tween          # 「可选中」高亮的呼吸补间
var _owner_color_map := {}     # peer -> Color（render 时刷新）

# 镜头对点跟随（抽卡时对准牌堆）
var _has_follow_pt := false
var _follow_pt := Vector2.ZERO
var _deck_pos := {}            # "机会"/"命运" -> world 中心
## 抽卡演出的**画布内**那套（卡片 / 相位计时 / 抽出起点 / 推近与还原）已随批次 8
## 整段搬到屏幕层的 `DeckReveal`（scripts/deck_reveal.gd）。这里不再有 `_deck_card` /
## `_deck_t` / `_deck_from` / `deck_top_provider` 等成员：演出不再动 2D 相机，
## 也不再需要"从实体摞顶面抽出"的起点供给。印在桌垫上的两摞卡背图案（`_build_deck`）保留。

# 中央转盘（替代骰子的点数来源）
var _wheel: WheelView
var _wheel_restore := GameData.NO_PEER
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
	resized.connect(func() -> void: _need_fit = true)
	mouse_exited.connect(func() -> void: set_hover(-1))

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

## 注视点限制在桌垫内（旋转 90° 倍数时可视宽高互换）。
## rot 省略时用当前 _rot；但算「正要转去的那个视角」的目标时必须显式传 _rot_target，
## 否则会拿旋转前的可视宽高去夹取，目标点偏出数百像素（见 fix/v0.0.2）。
## 边界用 MAT_RECT：它是画布内容的全部（座位栏退场后画布里只剩桌垫）。
## 全景倍率下可视区比桌垫大（画布是方的、桌垫是横的），两条夹取都落到
## 「居中对齐」那一支 —— 即全景时桌垫恒在正中，这正是取景要的。
func _clamp_center(c: Vector2, rot: float = INF) -> Vector2:
	var vr := _visible_rect()
	var r: float = _rot if is_inf(rot) else rot
	var half := (vr.size.rotated(-r) * 0.5).abs() / _zoom
	var mn := MAT_RECT.position + half
	var mx := MAT_RECT.end - half
	var out := c
	out.x = MAT_RECT.get_center().x if mn.x > mx.x else clampf(c.x, mn.x, mx.x)
	out.y = MAT_RECT.get_center().y if mn.y > mx.y else clampf(c.y, mn.y, mx.y)
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
	# 桌垫：批次 2 那张"整张木纹桌面"贴图**降级为印在桌上的桌垫**（设计稿 §五 路线 B），
	# 尺寸收到 MAT_RECT（棋盘 + 一圈留白）。四条座位栏拆掉后画布只剩这一块，
	# 桌垫之外那一圈木桌由 TableView3D 的第二个平面（wood_floor.jpg）承担 ——
	# 这里画出来的是"布"，那里才是"木"。
	var table := Panel.new()
	table.position = MAT_RECT.position
	table.size = MAT_RECT.size
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

	# 棋盘区：同一张木纹上轻微压暗 + 描边勾出边界，格子直接落在桌垫上
	var bg := Panel.new()
	bg.position = BOARD_OFFSET - Vector2(26, 26)
	bg.size = WORLD + Vector2(52, 52)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.05, 0.05, 0.07, 0.32), 20,
		Color(0.24, 0.19, 0.12, 0.9), 2, 12))
	_world.add_child(bg)

## 格子类型 → Twemoji 主题图标名（assets/icons/，CC-BY 4.0）
## 地产的图标逐块放在数据里（d.icon），不再按组查表（组已废除）。
const TILE_ICONS := {
	"event": {"机会": "luck", "命运": "fate"},
	"fine": "fine", "bonus": "bonus", "rest": "rest", "casino": "casino", "shop": "daily",
	"start": "start", "jail": "jail", "go_jail": "gojail",
}

func _tile_icon_name(d: Dictionary) -> String:
	var t := String(d.type)
	if t == "property":
		return String(d.get("icon", "dorm"))
	var v = TILE_ICONS.get(t, "")
	if v is Dictionary:
		return v.get(String(d.get("name", "")), "")
	return v

func _build_tiles() -> void:
	for i in GameData.TILES.size():
		var d: Dictionary = GameData.TILES[i]
		var corner: bool = GameData.is_corner(i)
		var base := Color("#38301c") if corner else Color("#242a39")
		var p := Panel.new()
		p.position = tile_pos(i) + Vector2(GAP, GAP)
		p.size = Vector2.ONE * (TILE - GAP * 2.0)
		# 投影让每格从木纹桌面上「浮」起来（shadow 画在格子外，正好落在 GAP 里）
		var sb := UIKit.stylebox(base, 7, Color("#3c4254"), 1, 4, Color(0, 0, 0, 0.42), Vector2(0, 2))
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(p)
		_tile_sb.append(sb)

		var hl := Panel.new()
		hl.position = p.position
		hl.size = p.size
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hl.visible = false
		hl.add_theme_stylebox_override("panel",
			UIKit.stylebox(Color(0, 0, 0, 0), 7, SELECT_COLOR, 3, 0))
		_world.add_child(hl)
		_tile_hl.append(hl)

		# 顶带 = 唯一的归属标记：只有「已售出的地产」才显示，颜色即拥有者颜色。
		# 无主地产、以及所有非卖的活动格（小卖部 / 赌场 / 四角等）一律不显示。
		var strip := Panel.new()
		strip.position = Vector2(3, 3)
		strip.size = Vector2(TILE - GAP * 2.0 - 6, 12)
		strip.visible = false
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(strip)
		_strips.append(strip)
		_strip_cols.append(Color(0, 0, 0, 0))
		var idx_l := UIKit.label(str(i), 10, Color(1, 1, 1, 0.6))
		idx_l.position = Vector2(TILE - GAP * 2.0 - 22.0, 0)
		idx_l.visible = dev_tile_index
		idx_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(idx_l)
		_tile_idx_labels.append(idx_l)

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

		var name_c: Color = Color(0.98, 0.58, 0.78) if casino else (SHOP_ACCENT if d.type == "shop" else UIKit.TEXT)
		var name_l := UIKit.bold_label(d.name, 18, UIKit.ACCENT if corner else name_c)
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

		# 装修等级的房子**已搬进 3D**（批次 11 Task 2）：画布里不再有 `HouseIcon` Control
		#（原先是右下角 y84-102 那条带里程序绘制的小房子），改由 `TableProps` 在桌面上立一块
		# **薄牌**贴同一份画法烘出来的纹理（见 scripts/table_props.gd「装修房子」那一段，
		# 与 `house_anchor` / `house_screen_pos` / `house_screen_size` 三个只读查询）。
		# 本行留空是有意的：**别再把 2D 房子加回来**（layout_test 有"整套已删净"的反向契约）。

		_owners.append(-2)
		_soils.append(false)

func _world_descend(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

class TableDecor extends Control:
	## 内区装饰（程序绘制，无需素材）：四角金色括号 + 同心圆 + 一圈刻度点。
	## 仿实体桌游的赌台衬底，把原本一大片空荡荡的深色中心填出层次。
	const ACCENT := Color(0.961, 0.702, 0.259)
	const RING_R := 286.0
	const TICKS := 48

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		# 四角括号：给嵌板一个「描金画框」的收边
		var arm := 52.0
		var inset := 16.0
		var w := 2.0
		var col := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30)
		var corners := [
			[Vector2(inset, inset), Vector2(1, 0), Vector2(0, 1)],
			[Vector2(size.x - inset, inset), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(inset, size.y - inset), Vector2(1, 0), Vector2(0, -1)],
			[Vector2(size.x - inset, size.y - inset), Vector2(-1, 0), Vector2(0, -1)],
		]
		for cc in corners:
			var o: Vector2 = cc[0]
			draw_line(o, o + Vector2(cc[1]) * arm, col, w, true)
			draw_line(o, o + Vector2(cc[2]) * arm, col, w, true)

		# 同心圆 + 刻度点：中心「转盘区」的视觉锚
		var ctr := size * 0.5
		draw_arc(ctr, RING_R, 0.0, TAU, 128, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14), 2.0, true)
		draw_arc(ctr, RING_R + 30.0, 0.0, TAU, 128, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.07), 1.0, true)
		for i in TICKS:
			var a := TAU * float(i) / float(TICKS)
			var big: bool = i % 6 == 0
			var pt := ctr + Vector2(cos(a), sin(a)) * (RING_R + 15.0)
			draw_circle(pt, 2.8 if big else 1.3,
				Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.32 if big else 0.15))

## 棋盘中央内区布局（仿实体桌游）：深绿绒面嵌板 + 金色装饰，中央「机会」「命运」
## 两个牌堆，事件卡从对应牌堆抽出展示。
func _build_interior() -> void:
	var c := WORLD * 0.5 + BOARD_OFFSET

	# 绒面嵌板：整圈格子围出来的内区铺一层深绿桌布 + 描金边，
	# 原本这里是一大片没有内容的深色，视觉上「塌」下去
	var pad := TILE + 6.0
	var inlay := Panel.new()
	inlay.position = BOARD_OFFSET + Vector2(pad, pad)
	inlay.size = WORLD - Vector2(pad, pad) * 2.0
	inlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inlay.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.033, 0.052, 0.046), 26,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.20), 2, 16,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.04)))
	_world.add_child(inlay)
	# 中心暖光：桌布中央一点金光，把视线收拢到转盘
	inlay.add_child(UIKit.grad_rect(
		[Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.10),
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.0)],
		[0.0, 1.0], true, Vector2(0.5, 0.5), Vector2(0.5, 0.12)))
	# 四周压暗：否则整块绒面会「平」在画面上，与木桌的过渡也太硬
	inlay.add_child(UIKit.grad_rect(
		[Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.46)], [0.0, 1.0], true,
		Vector2(0.5, 0.5), Vector2(0.5, -0.10)))
	var deco := TableDecor.new()
	inlay.add_child(deco)

	# 标题牌：压在嵌板上沿之内，金边 + 金色细分隔线
	var p := Panel.new()
	p.position = Vector2(c.x - 380, BOARD_OFFSET.y + pad + 18.0)
	p.size = Vector2(760, 96)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.055, 0.095, 0.082, 0.72), 20,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.30), 1, 6))
	_world.add_child(p)

	var title := UIKit.title_label("宿舍大富翁", 42, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.42), 0)
	title.position = Vector2(0, 6)
	title.size = Vector2(760, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.22)
	rule.position = Vector2(300, 60)
	rule.size = Vector2(160, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(rule)

	var sub := UIKit.label("%d × %d 环线 · %d 格 · 10 大产业" % [GameData.BOARD_COLS, GameData.BOARD_ROWS, GameData.TILES.size()],
		16, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.8))
	sub.position = Vector2(0, 64)
	sub.size = Vector2(760, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(sub)

	_build_deck("机会", Vector2(c.x - 560, c.y), UIKit.ACCENT)
	_build_deck("命运", Vector2(c.x + 560, c.y), Color(0.66, 0.56, 0.95))
	_build_wheel(c)

## 一个牌堆：区域底板 + 三层错位卡背 + 牌名 + 小字说明
##
## 卡背尺寸与错缝量是**常量**（`DECK_CARD_*`）：`deck_screen_size` 要用同一份数算"整体脚印"，
## 两处各写一个 90/135/6 就是两处会漂开的数。
func _build_deck(dname: String, center: Vector2, accent: Color) -> void:
	_deck_pos[dname] = center
	var zone := Panel.new()
	zone.position = center - Vector2(140, 90)
	zone.size = Vector2(280, 180)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_theme_stylebox_override("panel", UIKit.card_stylebox(Color(0.095, 0.105, 0.15, 0.62), 20,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 4))
	_world.add_child(zone)

	# 牌堆：3 张竖版卡背错位叠放（用同一套 CC0 卡背图案；抽卡就是从这上面抽走一张）
	for i in 3:
		var card := TextureRect.new()
		card.texture = _deck_back_tex(dname)
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.modulate = Color(1, 1, 1, 0.55 + 0.22 * float(i))   # 越靠上越实，做出堆叠感
		# 落点 = center 左上再错缝。x 取半张宽（45 = DECK_CARD_W / 2）；**y 写 66 而不是 67.5**
		#（= 半张高）—— 那 1.5 像素是既有的、没写理由的偏移，**本波不动它**：改它会动印刷图案，
		# 而印刷图案一动，`deck_screen_size` 的口径与 3D 侧的贴合都得跟着重核。
		card.position = center - Vector2(DECK_CARD_W * 0.5, 66.0) \
			+ Vector2(DECK_CARD_OFF, DECK_CARD_OFF) * float(2 - i)
		card.size = Vector2(DECK_CARD_W, DECK_CARD_H)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(card)

	# 牌堆名压在堆叠中央：垫一块深色小牌，压在花纹上也读得清
	var tplate := UIKit.panel_container(Color(0.05, 0.055, 0.08, 0.84), 8,
		Color(accent.r, accent.g, accent.b, 0.6), 1, 2)
	tplate.position = center - Vector2(48, 15)
	tplate.size = Vector2(96, 30)
	tplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(tplate)
	var tm := UIKit.margins(6, 6, 3, 3)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tplate.add_child(tm)
	var t := UIKit.label(dname, 18, accent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tm.add_child(t)

	var cap := UIKit.label("落在【%s】格时从这里抽卡" % dname, 14,
		Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.7))
	cap.position = center - Vector2(132, -78)
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

## 转盘在画布上的**半径**（画布像素，与 wheel_screen_pos 同口径）。
## 转盘的尺寸是 `_world` 的局部值（_build_wheel 里 size = 400），而 `_world` 带**镜头倍率**
##（_apply_cam: `_world.scale = _zoom`），所以它落到画布上只有 `200 × _zoom` —— 取景、
## 人数变化都会改它（**滚轮不改**：滚轮只推 3D 视角，不碰这个 `_zoom`）。
## 3D 实体（TableProps 的轮缘）得按这个半径换算成
## 世界单位，才能一直跟住桌垫上画出来的那个轮子。
## 只读查询，不碰镜头与玩法（与 Task 4 要加的手牌锚点同类）。
func wheel_screen_radius() -> float:
	return _wheel.size.x * 0.5 * _zoom if _wheel != null else 0.0

## 转盘点数：镜头对准转盘，转完后镜头回到行动棋子
func spin_wheel(value: int, restore_peer := GameData.NO_PEER) -> void:
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

## **印在桌垫上**那摞卡背（`_build_deck` 画的那块）在**画布像素**里的落点 ——
## 与 `wheel_screen_pos` / `tile_screen_pos` 同一条链、同一口径（都是
## `global_position + _view_from_world(某局部点)`；board 住在 SubViewport 原点，两者数值相等）。
##
## 为什么要有这个公开入口（批次 6 Task 3）：3D 侧的实体摞要接住的正是这块印刷图案，
## 而 `game._refresh_board_followers` 原先自己拼 `board._view_from_world(board.deck_center(...))`
## —— **漏了 `global_position` 那一项、还调了私有方法**。只因 board 在 SubViewport 原点才没出事；
## 换个位置（或谁把这条链复制到别处）就会静默漂开。**跟图案走的物件一律走这个入口**。
func deck_screen_pos(deck: String) -> Vector2:
	return global_position + _view_from_world(deck_center(deck))

## 一摞牌堆里**单张卡背**的尺寸与三张之间错开的量（`_world` 局部单位，见 `_build_deck`）。
## 只在这里写一次：`_build_deck` 画它、`deck_screen_size` 用它算"整体脚印"，两处各写一个
## 90/135/6 就是两处会悄悄漂开的数。
const DECK_CARD_W := 90.0
const DECK_CARD_H := 135.0
const DECK_CARD_OFF := 6.0

## 印在桌垫上那摞卡背的**整体脚印**（画布像素：宽 × 进深）—— 与 `wheel_screen_radius` 同形
##（那个给"转盘在画布上的半径"，这个给"牌堆在画布上的脚印"）。
##
## 单张 90×135、3 张各错 (6,6) ⇒ 整体 **102×147**（`_world` 局部单位）；而 `_world` 带**镜头倍率**
##（`_apply_cam`: `_world.scale = _zoom`）⇒ 落到画布上只有 `102×147 × _zoom`。取景 /
## 人数变化都会改 `_zoom`（**滚轮不改**：滚轮只推 3D 视角）。
##
## 为什么要有这个入口（终审修复波 F）：3D 侧的实体摞要**盖住印着的这块图案**，跟图案走的
## 第一件（转盘轮缘）早就在尺寸上也跟着 `_zoom` 走（`wheel_screen_radius`），第二件（牌堆）
## 原先**只跟位置、尺寸写死世界常数** ⇒ 取景一变印刷图案整体胀大、摞不动，
## 只盖住图案的约四分之一（面积比）—— 而那一刻正是玩家盯着牌堆的时候。
## 两个"跟印刷"的物件从此同一条口径：位置与尺寸都由 BoardView 报，3D 侧只负责换算。
func deck_screen_size(deck: String) -> Vector2:
	if not _deck_pos.has(deck):
		return Vector2.ZERO
	return Vector2(DECK_CARD_W + DECK_CARD_OFF * 2.0,
		DECK_CARD_H + DECK_CARD_OFF * 2.0) * _zoom

## 抽卡演出的相位动画 / 卡面构建 / 推近整段（`_tick_deck_card`、`_show_deck_face`、
## `_ease_out_back`、`_refresh_deck_from`、`is_showing_deck_card`、`play_deck_card`、
## `CARD_SIZE`、`_make_card_art`、`_card_face_front`、`_card_face_back`）已随批次 8
## 搬到屏幕层的 `DeckReveal`（scripts/deck_reveal.gd）。**本类不再演抽卡**：演出不动 2D 相机，
## 所以这里连"推近倍数 / 相位时长 / 抽出起点"都不需要了。印在桌垫上的两摞卡背图案
##（`_build_deck`，用下面的 `_deck_back_tex`）与两摞实体牌堆（`TableProps`）都原样保留。

## 机会 / 命运各用一套 CC0 的 Atlas 牌卡背（矢量，来源见根目录 LICENSE）。
## 现在只服务于**印在桌垫上的**那两摞卡背图案（`_build_deck`）—— 抽卡演出的那张卡
## 由 `DeckReveal` 自己取素材（同一个来源）。
func _deck_back_tex(deck: String) -> Texture2D:
	return UIKit.tex("res://assets/cards/atlas_back_green_darkred.svg" if deck == "机会"
		else "res://assets/cards/atlas_back_blue_brown.svg")

## 2D 镜头的「取景键」（缩放 + 注视点）—— 给"跟图案的实体"判**镜头动过没有**用
##（`game._process` 按它补推：镜头逐帧在动、而那条重推原先只挂在状态广播上）。
## 只读、不触发任何变换重算（`_apply_cam` 才是摆相机那一条）。
## 与 `_view_from_world` 用的是同一对量（`_zoom` / `_center`）—— 它们就是"印刷图案在哪"的全部输入。
func cam_key() -> Vector3:
	return Vector3(_zoom, _center.x, _center.y)

## 当前行动者光环在**画布像素**下的半径。光环压着格子 ⇒ 与转盘轮缘 / 两摞牌堆同一条口径
##（位置与尺寸都跟 2D 相机：`_world` 局部尺寸 32 是原来那枚 64×64 Panel 的半径，
##  过一遍镜头变换就是它在画布上的半径）—— 3D 侧拿它量真变换换算成世界半径
##（`table_props._apply_ring_size`），取景一变环就跟着改，不会与格子脱开。
##
## 为什么用"量真变换"而不是直接给 `32 × _zoom`：同 `deck_screen_size` 那条 ——
## 画布像素与世界之间隔着贴图窗口（`TEX_WINDOW_PX`）与桌面尺寸两个旋钮，写死换算常数会静默失配。
const RING_R_WORLD := 32.0      # `_world` 局部半径（原 2D 光环 Panel 的 64×64 的一半）
func token_ring_radius_px() -> float:
	return _view_from_world(Vector2(RING_R_WORLD, 0.0)) \
		.distance_to(_view_from_world(Vector2.ZERO))

# ---------------- 装修房子（批次 11 Task 2） ----------------
#
# 每格右下那条带里原先画着的那座房子（`HouseIcon`，见 `_build_tiles` —— **那份 2D 绘制已随本
# 任务删掉**，现在房子只有 3D 薄牌这一份）。这里报的是它**该在哪儿、该有多大**：R4 裁定房子
# 压在格子上 ⇒ 位置与尺寸都跟印刷口径（与转盘轮缘 / 两摞牌堆 / 行动光环同一条）。
# **改这两条常量就得连房子薄牌的观感一起重核。**

## 房子在**格子内**的相对位置与尺寸（`_world` 局部像素；与 `_build_tiles` 里那个
## `Vector2(TILE - GAP * 2.0 - 30, 84)` + `Vector2(26, 18)` 一字不差 —— 搬进 3D 时照抄，
## 「格内相对位置不变」是设计 §8 的不变量）。放右下 y84-102 那条带：色带(3-15)/图标水印(20-56)/
## 名称(18-62)/副标题(70-87) 都已占位，只有这条底带是空的。
const HOUSE_LOCAL_POS := Vector2(TILE - GAP * 2.0 - 30.0, 84.0)
const HOUSE_LOCAL_SIZE := Vector2(26.0, 18.0)

## 某格那条带里**印着的**房子图案的**中心**（画布像素）= 格心（`tile_pos` + GAP）+ 格内相对位置
## + 半尺寸。**这是 `_world` 局部坐标**：`_clamp_center` 那一系用的就是它，**不是**印刷口径。
func house_anchor(idx: int) -> Vector2:
	return tile_pos(idx) + Vector2(GAP, GAP) + HOUSE_LOCAL_POS + HOUSE_LOCAL_SIZE * 0.5

## 房子图案在**画布**上的落点（中心）—— `house_anchor` 过一遍 2D 镜头变换，与
## `tile_screen_pos` / `deck_screen_pos` / `wheel_screen_pos` / `token_screen_pos` **同一条链**
##（`global_position + _view_from_world(局部点)`）。3D 侧摆房子用**它**，不用 `house_anchor` ——
## 房子画在 `_world` 里、带着镜头变换，拿局部坐标摆会整体偏开（T1 的棋子就那么偏过一格）。
func house_screen_pos(idx: int) -> Vector2:
	return global_position + _view_from_world(house_anchor(idx))

## 房子图案在**画布**上的尺寸（宽 × 高）—— 与 `deck_screen_size` 同形：
## `_world` 局部尺寸 × `_zoom`（`_apply_cam` 给 `_world.scale` 的就是它）。
## 3D 侧的薄牌要**盖住**这块图案 ⇒ 尺寸也得跟（只跟位置不跟尺寸的话，取景一变就盖不住）。
## 3D 侧仍走「量真变换」把这两个画布像素折成世界单位（见 `table_props._apply_house_size`）。
func house_screen_size() -> Vector2:
	return HOUSE_LOCAL_SIZE * _zoom

# ---------------- 视口：缩放 / 平移 / 跟随 ----------------

func _process(delta: float) -> void:
	if _need_fit and size.x > 10.0:
		_need_fit = false
		if not _fitted:
			_fitted = true
			fit_overview(true)  # 初始镜头：桌垫概览（全屏那一档）
		else:
			_apply_cam()        # 仅重算变换：resized 不该把对局中途的视角/跟随清零
	if auto_follow and _has_follow_pt:
		_pan_toward(_follow_pt, delta)
	elif auto_follow and _follow_peer != -1 and _peer_anchor.has(_follow_peer):
		_pan_toward(_peer_anchor[_follow_peer], delta)
	if _rotating:
		var k := 1.0 - exp(-7.0 * delta)
		_rot = lerp_angle(_rot, _rot_target, k)
		# 跟随镜头（_pan_toward）自己会驱动 _center，这里不要去抢：
		# 两者同时写 _center 会互相拉扯，_center 永远到不了 _center_target，
		# 于是 _rotating 卡在 true，对局层的回正逻辑被一直抑制（见 fix/v0.0.2）。
		var follow_drives: bool = auto_follow and (_has_follow_pt \
			or (_follow_peer != -1 and _peer_anchor.has(_follow_peer)))
		if not follow_drives:
			_center = _center.lerp(_center_target, k)
		if absf(wrapf(_rot_target - _rot, -PI, PI)) < 0.004 \
				and (follow_drives or _center.distance_to(_center_target) < 1.0):
			_rot = _rot_target
			if not follow_drives:
				_center = _center_target
			_rotating = false
	# （原先这里逐帧把 2D 光环摆到棋子中心上。批次 11 Task 1 起光环是 `TableProps` 里的一条
	#  3D 环、由它自己的 `_process` 跟着棋子走 —— 画布这一层不再有任何逐帧跟随。）
	if _wheel_wait > 0.0:
		_wheel_wait -= delta
		if _wheel_wait <= 0.0 and _wheel_restore != GameData.NO_PEER:
			focus_peer(_wheel_restore)
			_wheel_restore = GameData.NO_PEER
	_apply_cam()

## 镜头平滑推向某个世界坐标点（棋子中心 / 牌堆）
func _pan_toward(world_center: Vector2, delta: float) -> void:
	_center = _center.lerp(_clamp_center(world_center), 1.0 - exp(-6.0 * delta))

func _visible_rect() -> Rect2:
	return Rect2(overlay_left, overlay_top, size.x - overlay_left - overlay_right, size.y - overlay_top - overlay_bottom)

## 「基准倍率的倍数」→ 绝对倍率，并夹到允许区间（1.0 = 全景）。
## 所有设置倍率的地方都走这里：调用点一律写倍数，别写绝对字面量（画布尺度一变换算就废）。
func _zoom_from_factor(factor: float) -> float:
	return clampf(factor, MIN_ZOOM_FACTOR, MAX_ZOOM_FACTOR) * _fit_zoom

## 桌垫概览（批次 5 Task 2 起就是"取景的全部"）：把**整块桌垫**（MAT_RECT）正好塞成
## `MAT_WINDOW_W` 画布像素宽、画布正中 —— 于是桌垫内容与 TableView3D 的纹理窗口严丝合缝，
## 桌面上就是"木桌 + 居中一块印着棋盘的桌垫"。hard=true 立即到位。
##
## 为什么不再按"可视区大小自适应"：窗口是一块**写死的**画布矩形（`TEX_WINDOW_PX`），
## 若取景按可视区自适应，两者就会脱钩（画布一变，桌垫内容就滑出窗口）。
## 这条把窗口与取景锁成同一个比例关系，`mat_rect_px()`（桌垫的画布口径）也跟着它走。
func fit_overview(hard := false) -> void:
	auto_follow = false
	_follow_peer = -1
	_has_follow_pt = false
	# 基准倍率 = 桌垫正好铺满窗口宽度。全景就是它本身（1.0 倍），别的倍率都以它换算。
	_fit_zoom = MAT_WINDOW_W / MAT_RECT.size.x
	_zoom = _zoom_from_factor(1.0)
	_center_target = MAT_RECT.get_center()
	if hard:
		_center = _center_target
	_apply_cam()

## 镜头对准某格 / 某棋子；hard=true 立即居中。
## zoom 是「基准倍率（全景）的倍数」：1.0 = 全景，2.0 = 比全景近一倍。
func focus_grid(idx: int, zoom: float, hard := true) -> void:
	if cam_locked:
		return
	auto_follow = false
	_follow_peer = -1
	_has_follow_pt = false
	_rotating = false
	_zoom = _zoom_from_factor(zoom)
	if hard:
		_center = _clamp_center(tile_pos(idx) + Vector2(TILE, TILE) * 0.5)
		_center_target = _center
	_apply_cam()

## 镜头跟随一个世界坐标点（抽卡时对准牌堆）
## （`focus_point_zoom` 已随批次 8 删除：它唯一的调用方是抽卡推近，而演出已搬到屏幕层
##  `DeckReveal`、不再动 2D 相机。要"对准某点"用 `focus_point`。）
func focus_point(world_pt: Vector2, hard := false) -> void:
	if cam_locked:
		return  # 摆拍锁定；视角已固定在自己座位（v0.5.0 批次 1 删转视角）
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
	if cam_locked:
		return  # 摆拍锁定；视角已固定在自己座位（v0.5.0 批次 1 删转视角）
	auto_follow = true
	_follow_peer = peer
	_has_follow_pt = false
	_rotating = false
	if hard and _peer_anchor.has(peer):
		_center = _clamp_center(_peer_anchor[peer])
		_center_target = _center
	_apply_cam()

func _zoom_at(factor: float, anchor: Vector2) -> void:
	var before := _world_from_view(anchor)
	_zoom = clampf(_zoom * factor, MIN_ZOOM_FACTOR * _fit_zoom, _zoom_clamp_max * _fit_zoom)
	_center = _clamp_center(before - (anchor - _visible_center()).rotated(-_rot) / _zoom)
	_apply_cam()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		# 滚轮不再自己缩放：方向已交给 3D 相机（Table3D._unhandled_input → set_view，
		# 改的是**视角推移的目标值**，不是推拉）。
		# 2D 相机的 _zoom 现在只由 `focus_grid`（摆拍 / 格详情近景）驱动；抽卡推近已随批次 8
		# 取消（演出搬到屏幕层 `DeckReveal`，相机全程不动）。
		# _zoom_at 现在没有调用者，按计划保留（备 2D 缩放用）。
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_dragging = true
				_panning = false
				_press_pos = mb.position
			elif _dragging:
				if mb.button_index == MOUSE_BUTTON_LEFT and not _panning:
					# 座位卡已拆（批次 5 Task 2）：画布里只剩棋盘与牌堆，左键单击 = 点格子。
					# 「点玩家选目标」从批次 9 起走**屏幕层四角身家条**（`game._on_corner_bar_clicked`），
					# 桌面这条链上早已没有"点玩家"的落点。
					var idx := _index_at(mb.position)
					if idx >= 0:
						Fx.play("click", -10.0)
						tile_clicked.emit(idx)
				elif mb.button_index == MOUSE_BUTTON_RIGHT and not _panning:
					cancel_clicked.emit()   # 右键单击（非拖拽平移）取消当前选择
				if not (mb.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
					_dragging = false
					_panning = false
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var mask := mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)
		if _dragging and mask != 0:
			# 只判定「位移超过阈值 = 拖拽」，用于抑制拖拽结束时的误点击。
			# 相机平移本身不再需要：取景已由 3D 相机（TableView3D）接管，2D 相机不响应拖拽。
			if _panning or mm.position.distance_to(_press_pos) > 6.0:
				_panning = true
		else:
			# 悬停棋子的信息条已搬到屏幕层（批次 11 Task 3 接上）：这里只剩格子的悬停高亮。
			set_hover(_index_at(mm.position))

## 镜头是否还在转（对局层用它避让：转的时候不抢注视点）。
## 转视角本身已在批次 1 删除（`_rot_target` 恒为 0），但 `_rotating` 这套状态保留 ——
## 它是「镜头正在动、别来抢」这条判据的载体，`game._refresh_actions` 仍在读。
func is_rotating() -> bool:
	return _rotating

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

	# 座位卡（四条操作栏 + 内容件 + 倒计时簇 + 道具牌位）已随批次 5 Task 2 **整体退场**：
	# 名字 / 身家 / 操作倒计时改由**屏幕层四角身家条**承担（公开背包批次 9 起另有玩家道具弹窗、
	# 选目标改点四角条；中间那层桌上 3D 立牌也随批次 9 退场）。
	# 画布里从此只剩棋盘与两摞牌堆（牌垫阶段按钮也已在批次 7 退场：画布里再无按钮）。
	#
	# 注意下面几条**保留的接口**：它们今天没有座位卡可落点了，但玩法侧仍在调，
	# 按批次 3 的先例「保留接口 + 加注说明」，不删。

# ---------------- 相机缩放上限 + 开发者叠层 ----------------

var _zoom_clamp_max := MAX_ZOOM_FACTOR   # 缩放倍率上限（× 基准倍率；滚轮不碰缩放，改由 focus_grid 读它）
var _tile_idx_labels: Array = []    # 开发者模式：格子编号叠层
var dev_tile_index := false:
	set(v):
		dev_tile_index = v
		for l in _tile_idx_labels:
			if is_instance_valid(l):
				(l as Label).visible = v

const SHOP_ACCENT := Color(0.42, 0.78, 0.55)    # 小卖部格名：菜绿

## 被选中的道具卡（绿光）：peer=-1 表示无
var item_selected := {"peer": -1, "slot": -1}
var _discard_hl := {"peer": -1, "slot": -1}

# ---------------- 牌垫阶段按钮：批次 7 已退场 ----------------
# 原来桌垫下缘那两枚「转转盘 / 使用道具」整体拆掉（用户要求：按钮不画在桌面上）。
# 掷轮改为**桌面转盘实体**（仍在，`table_props.wheel_hit`）与**屏幕右下角动作按钮**两条入口；
# 出牌改为点手中牌直出（见 game._on_hand_clicked）。`mat_rect_px()` 保留：它是桌垫在画布上的
# 矩形口径，取景与测试按它量，与按钮无关。

## 桌垫在**画布**上的矩形（px）：`MAT_RECT × 基准倍率`，中心恒在可视区中心
##（取景就是这么定的）。它与 `TableView3D.TEX_WINDOW_PX` 是同一块地方 —— 一边是画布口径、
## 一边是世界口径；`table_3d.gd` 里有一条断言把它们钉在一起。
##
## **当前没有任何生产调用方**（只被测试引用：`layout_test.gd` 拿它量手牌是否落在桌垫之外），
## 批次 7 删掉牌垫阶段按钮后它唯一的生产用途（按钮落位）随之消失。**别当死代码删掉** ——
## 批次 9 的取景（棋盘放大、重定标画布常量）会接上它。
func mat_rect_px() -> Rect2:
	var r := Rect2(Vector2.ZERO, MAT_RECT.size * _fit_zoom)
	r.position = _visible_center() - r.size * 0.5
	return r

## 指向性道具：高亮可选格子 / 可选玩家（两者互斥）。**座位卡退场后前者仍是画布上的金框、
## 后者在画布里已无落点** —— "哪些玩家可被选中"改由**屏幕四角身家条**点亮
##（`game._refresh_corner_highlight`，批次 9）。两者由 `game._push_peer_highlight`
## 在同一个调用点一起推，判据只有一份。
func set_select_peers(peers: Array) -> void:
	_set_hl_tiles([])
	_set_hl_peers(peers)
	_pulse_select(not peers.is_empty())

func set_select_tiles(idxs: Array) -> void:
	_set_hl_peers([])
	_set_hl_tiles(idxs)
	_pulse_select(not idxs.is_empty())

func clear_select() -> void:
	_set_hl_peers([])
	_set_hl_tiles([])
	_pulse_select(false)

## 「哪些玩家此刻可被选中」的高亮：**画布里没有落点了**（座位卡与桌上立牌都已退场）。
## **保留接口不删**（`game._begin_peer_target` 仍在调）。
## 这条反馈本身**不在画布里**：批次 9 起由**屏幕四角身家条**承担
##（`game._refresh_corner_highlight` —— 可选中的那条描金边 + 提亮），
## 与屏幕层那句文字提示（`game._show_target_hint`）一起构成完整的"能点谁"。
func _set_hl_peers(_peers: Array) -> void:
	pass

func _set_hl_tiles(idxs: Array) -> void:
	for i in _tile_hl.size():
		var hl = _tile_hl[i]
		if hl != null and is_instance_valid(hl):
			(hl as Panel).visible = i in idxs

func _pulse_select(on: bool) -> void:
	if _select_tw != null and _select_tw.is_valid():
		_select_tw.kill()
		_select_tw = null
	if not on:
		return
	var apply := func(a: float) -> void:
		for hl in _tile_hl:
			if hl != null and is_instance_valid(hl) and (hl as Panel).visible:
				hl.modulate.a = a
	_select_tw = create_tween().set_loops()
	_select_tw.tween_method(apply, 1.0, 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	_select_tw.tween_method(apply, 0.45, 1.0, 0.7).set_trans(Tween.TRANS_SINE)

## 丢弃待确认：记下「哪一位玩家的第几个道具槽待确认丢弃」。
##
## **只剩状态、没有任何落点（不是死代码，别删）**：座位卡上的道具牌位在批次 3 Task 6 拆掉、
## 座位卡本身在批次 5 Task 2 退场 ⇒ 原先"把那张卡的 ✕ 点红"的循环**已删除**，
## `board_view` 里再没有可点红 / 点绿的落点（`开发台账.md` §三 记的就是这一句）。
## 待确认的**可见**反馈在桌面上那张手牌自己身上（`table_props.set_hand_discard_pending`，
## 牌身染红），入口是**手牌上点右键**（`game._on_table_click` → `_on_discard_clicked`）。
## **为什么留着**：玩法侧（`game._on_discard_clicked`）仍在调它，接口不能断 ——
## 与 `set_item_selected` / `_set_hl_peers` 同例（无落点的接口按批次 3 先例保留）。
func mark_discard_pending(peer: int, slot: int) -> void:
	_discard_hl = {"peer": peer, "slot": slot}

## 记「当前选中的道具槽」。
##
## **只剩状态、没有落点**（不是死代码，别删）：座位卡的牌位在批次 3 Task 6 拆掉、
## 座位卡本身在批次 5 Task 2 退场 ⇒ 以前那两圈"给牌位点绿光"的循环无处可画。
## 选中的**可见**反馈在桌面上那张手牌自己身上（`table_props.set_hand_selected`：抬起 + 提亮）。
## **为什么留着**：玩法侧（`game._on_item_slot_clicked` / `_clear_item_selection`）仍在写它、
## 接口不能断。公开背包（看别人的道具）现在由**玩家道具弹窗**承担（`scripts/player_popup.gd`，
## 批次 9；原先是桌上立牌那排品质色小卡），它是只读展示、不接点选 —— 这条高亮**不会**跟着复活。
func set_item_selected(peer: int, slot: int) -> void:
	item_selected = {"peer": peer, "slot": slot}

## 镜头调试信息（开发者面板）
func cam_info() -> String:
	return "缩放 %.2f · 旋转 %.1f° · 注视 (%d, %d)" % [_zoom, rad_to_deg(_rot), int(_center.x), int(_center.y)]

# ---------------- 渲染状态快照 ----------------

func render(state: Dictionary) -> void:
	var tiles: Array = state.get("tiles", [])
	var players: Array = state.get("players", [])
	var color_of := {}
	for p in players:
		color_of[int(p.peer)] = GameData.PLAYER_COLORS[int(p.color)]
	_owner_color_map = color_of

	# 悬停棋子时要浮出「昵称 / 身家 / 排名」——身家与排名在这里一次算好
	var pinfo := {}
	var worths := []
	for p in players:
		var peer := int(p.peer)
		var w := GameData.net_worth_of(peer, int(p.get("money", 0)), tiles)
		pinfo[peer] = {
			"name": String(p.get("name", "?")), "color": color_of[peer],
			"worth": w, "rank": 0, "alive": bool(p.get("alive", true)),
		}
		worths.append([w, peer])
	worths.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	for i in worths.size():
		pinfo[int(worths[i][1])]["rank"] = i + 1
	_peers_info = pinfo

	for i in _tile_sb.size():
		var owner_id := GameData.NO_OWNER
		var soil := false
		if i < tiles.size():
			owner_id = int(tiles[i].get("owner", GameData.NO_OWNER))
			soil = bool(tiles[i].get("soil", false))
		if owner_id != _owners[i] or soil != _soils[i]:
			_owners[i] = owner_id
			_soils[i] = soil
			_animate_tile(i, _hover == i)
		# 装修等级（`tiles[i].level`）**本类不再消费**：房子是 3D 的薄牌，由 `game._refresh_houses`
		# 喂给 `table_props.set_houses`（批次 11 Task 2）。画布里那套 `_levels` / `_set_house` 已删净。

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

	for i2 in mini(tiles.size(), _tile_sb.size()):
		if bool(tiles[i2].get("soil", false)):
			var prog: int = int(tiles[i2].get("soil_prog", 0))
			var target: int = int(GameData.TILES[i2].price)
			_sub_labels[i2].text = "焦土 %d/%d" % [prog, target]

	# 棋子（小人）与当前行动者的光环**都搬到 3D 了**（批次 11 Task 1，见
	# scripts/table_props.gd「棋子（小人）与当前行动者光环」那一段）：画布里不再建棋子 Control。
	# 这里只留一份**纯数据**——每 peer 的棋子落点，镜头跟随（`focus_peer` / 自动跟随）要用它。
	# 落点走 `slot_anchor`（**`_world` 局部坐标**）：`_clamp_center` 就是按 MAT_RECT 那个空间夹取的。
	# **TableProps 摆棋子用的是 `token_screen_pos`**（同一个公式再过一遍 2D 镜头变换）—— 因为棋子
	# 要落在**印刷图案**上（图案在 `_world` 里、带着镜头变换）。两个空间差着"镜头在原点、倍率 1"
	# 那一档（全景下约一格），**别互相串**。
	# （原先这里还按 `state.phase` 决定"结束时把光环收掉"：光环现在归 game.gd，
	#  它在广播时按 `st.turn` / `phase` 调 `table_props.set_ring`。）
	_peer_anchor = {}
	for p in players:
		_peer_anchor[int(p.peer)] = slot_anchor(int(p.pos), int(p.color))

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
	var corner: bool = GameData.is_corner(i)
	var base := Color("#38301c") if corner else Color("#242a39")
	var border := Color("#3c4254")
	var border_w := 1
	var owner_id := int(_owners[i])
	if i < _soils.size() and bool(_soils[i]):
		base = Color(0.13, 0.11, 0.09)
		border = Color(0.5, 0.34, 0.18)
		border_w = 2
	# 归属只由顶带表示：格子的底色与边框始终是无主时的样子（不再有拥有者色边框/底色）
	if i < _strips.size():
		# 判「有主」必须和 NO_OWNER(-100) 比：**机器人 peer 是负数**（-1 起编号），
		# 写成 owner_id >= 0 会把机器人买的地全部漏掉（本项目踩过的经典坑）
		var owned := String(d.type) == "property" \
			and owner_id != GameData.NO_OWNER and _owner_color_map.has(owner_id)
		var strip := _strips[i] as Panel
		strip.visible = owned
		if owned:
			var sc: Color = _owner_color_map[owner_id]
			if _strip_cols[i] != sc:
				_strip_cols[i] = sc
				strip.add_theme_stylebox_override("panel",
					UIKit.card_stylebox(sc.lightened(0.06), 3, sc.darkened(0.35), 1, 0))
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

## 装修房子（`HouseIcon` / `_house_icons` / `_levels` / `_set_house`）**已随批次 11 Task 2
## 搬进 3D**（`TableProps` 的「装修房子」那一段）。原先这里住着：`_build_tiles` 里每格建一个
## 程序绘制的 `HouseIcon` Control、`render` 里按等级差调 `_set_house`（含"装修成功弹一下"的
## 2D 缩放补间）——**整段删除，接口不留空壳**：3D 侧的能力是
## `TableProps.set_houses(levels)`（等级 → 烘好的等级纹理，`0` = 不摆），
## 位置与尺寸取自下面三个只读查询（**压在印着的那座房子上** ⇒ 与轮缘 / 牌堆 / 光环同一条口径）。
## **画法只留一份**：`HouseIcon` 这个类搬到 `TableProps` 里去了（烘纹理要跑它的 `_draw`，
## 复制一份就会与桌垫上原来的形状/配色漂开）—— `layout_test` 有"本类不再带 HouseIcon"的反向契约。

## 当前行动者光环 / 2D 棋子整套**已随批次 11 Task 1 搬进 3D**（`TableProps` 的
## 「棋子（小人）与当前行动者光环」那一段）。原先这里住着 `_set_ring`（2D Panel 逐帧跟随 +
## 呼吸补间）、`_make_token` / `_token_at` / `_token_target`（棋子 Control）、`token_world_pos` /
## `token_screen_pos`（棋子的画布坐标）、`_token_at_view` / `_set_token_hover` /
## `_ensure_token_tip` / `_place_token_tip`（2D 悬停信息条）、`play_move` / `_teleport_anim` /
## `_kill_token_tw` / `set_teleport_target`（逐格走 / 传送动画）——**整段删除，接口不留空壳**：
## 3D 侧的同名能力是 `TableProps.set_tokens` / `play_token_move` / `set_token_teleport` /
## `set_ring` / `token_hit` / `token_world_pos`。悬停条改由**屏幕层**承担（批次 11 Task 3）。
## `layout_test` 有"这 12 个方法都已退场"的反向契约，谁加回来先红。
## （`token_screen_pos` **不在**那张名单里：名字被新的一条接走了 —— 旧的取 `peer`、新的取
##  `(idx, slot)`，是"棋子落在印刷图案哪个像素"的入口，3D 侧摆棋子要用。）
##
## **保留 / 新增**的几条**纯坐标**入口（3D 侧与格详情卡都要用）：
## `tile_pos`（静态，格心）、`slot_offset`（槽位偏移）、`slot_anchor`（两者的合成，`_world` 局部
## 坐标 —— 画布这层的镜头跟随用它）、`token_screen_pos`（再叠一遍镜头变换 = **印刷口径**的落点，
## `TableProps` 摆棋子用它）、`tile_screen_pos`（格详情卡锚点）、`token_ring_radius_px`（光环半径）。

## 一个槽位在格内的偏移（画布像素）。0~3 对应四个角：远左 / 远右 / 近左 / 近右。
## **公开**（批次 11 Task 1 起）：3D 侧摆棋子要用它 —— 与 `tile_pos` / `TILE` 同一条链，
## 不另立一份（另立一份就会漂开）。
func slot_offset(slot: int) -> Vector2:
	match slot % 4:
		0: return Vector2(-28, -28)
		1: return Vector2(28, -28)
		2: return Vector2(-28, 28)
		_: return Vector2(28, 28)

## 某格 + 某槽位的**棋子落点**（画布像素）= 格心（`tile_pos(idx) + TILE/2`）+ 槽位偏移。
## `TableProps` 摆棋子走它、画布这层的镜头跟随（`_peer_anchor`）也走它 —— 公式只写这一处。
func slot_anchor(idx: int, slot: int) -> Vector2:
	return tile_pos(idx) + Vector2(TILE, TILE) * 0.5 + slot_offset(slot)

## 某个格子的**画布坐标**（格子中心）—— 格详情卡要悬浮在它上方（`game._board_to_screen`
## 再折成屏幕坐标）。**保留**：它跟棋子无关（棋子的画布坐标那两条已随棋子搬进 3D 删掉），
## 锚的仍是**印在桌垫上**的那一格。
func tile_screen_pos(idx: int) -> Vector2:
	return global_position + _view_from_world(tile_pos(idx) + Vector2(TILE, TILE) * 0.5)

## 某格 + 某槽位的**棋子落点**在**画布**上的坐标：`slot_anchor` 过一遍 2D 镜头变换 ——
## 与 `tile_screen_pos` / `deck_screen_pos` / `wheel_screen_pos` **同一条链**
##（`global_position + _view_from_world(局部点)`）。3D 侧摆棋子用**它**，不用 `slot_anchor`。
##
## **为什么差这一步就不能用 `slot_anchor`**：棋子要坐在**印在桌垫上的**那一格上，而格子画在
## `_world` 里、带着 2D 镜头的缩放与平移（`_apply_cam`：`_world.scale = _zoom`、
## `_world.position = 可视中心 - 注视点 × _zoom`）。`slot_anchor` 给的是**局部**坐标 ——
## 只有"镜头在原点、倍率 1"时才等于印刷位置；全景取景下它离印刷位置差着
## **约 (37, 134) 画布像素（≈ 一格）**，棋子会整体偏到别的格上（批次 11 Task 1 出图逮到：
## 小人/光环离自己那格一格远）。同 `deck_screen_pos` 那条注释说的"漏了 global_position 那一项"
## 是同一类错，只是这里的漏项是**整个镜头变换**。
func token_screen_pos(idx: int, slot: int) -> Vector2:
	return global_position + _view_from_world(slot_anchor(idx, slot))
