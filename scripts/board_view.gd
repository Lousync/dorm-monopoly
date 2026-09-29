extends Control
class_name BoardView
## 112 格（35×23 外圈）大棋盘：世界坐标渲染，滚轮缩放 / 拖拽平移 / 自动跟随行动棋子。
## 表现细节：跳格小跳+挤压、归属描边与底色渐变、装修星级弹跳、悬停高亮、
## 当前行动者脉冲光环、传送淡入淡出。

signal tile_clicked(idx: int)

const TILE := 56.0
const COLS := 35
const ROWS := 23
const WORLD := Vector2(COLS, ROWS) * TILE   # (1960, 1288)
const GAP := 3.0
const MIN_ZOOM := 0.2
const MAX_ZOOM := 1.25

var auto_follow := true      # 用户拖拽后关闭，点「跟随」按钮恢复
var overlay_right := 0.0     # 右侧面板等覆盖宽度（镜头居中/适配会避开）
var overlay_bottom := 0.0    # 底部覆盖高度

var _world: Control
var _zoom := 0.5
var _need_fit := true
var _dragging := false
var _panning := false
var _press_pos := Vector2.ZERO
var _follow_peer := -1
var _hover := -1

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

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _ready() -> void:
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.size = WORLD
	add_child(_world)
	_build_backdrop()
	_build_tiles()
	_build_decor()
	_build_ring()
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
	return Vector2(tile_grid(i)) * TILE

func _world_from_view(view_pos: Vector2) -> Vector2:
	return (view_pos - _world.position) / _zoom

func _index_at(view_pos: Vector2) -> int:
	var w := _world_from_view(view_pos)
	var col := int(floor(w.x / TILE))
	var row := int(floor(w.y / TILE))
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return -1
	return grid_to_index(col, row)

# ---------------- 场景搭建 ----------------

func _build_backdrop() -> void:
	var bg := Panel.new()
	bg.position = Vector2(-26, -26)
	bg.size = WORLD + Vector2(52, 52)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.stylebox(Color(0.086, 0.098, 0.137), 22, Color("#3c4254"), 2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	bg.add_theme_stylebox_override("panel", sb)
	_world.add_child(bg)

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

		var strip := ColorRect.new()
		strip.position = Vector2(2, 2)
		strip.size = Vector2(TILE - GAP * 2.0 - 4, 5)
		strip.color = UIKit.ACCENT if corner else GameData.GROUP_COLORS.get(d.get("group", ""), Color("#566"))
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(strip)

		var name_l := UIKit.label(d.name, 12, UIKit.ACCENT if corner else UIKit.TEXT)
		name_l.position = Vector2(4, 10)
		name_l.size = Vector2(TILE - GAP * 2.0 - 8, 26)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_world_descend(name_l)
		p.add_child(name_l)

		var sub := UIKit.label("", 10, UIKit.TEXT_DIM)
		sub.position = Vector2(4, 36)
		sub.size = Vector2(TILE - GAP * 2.0 - 8, 12)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_world_descend(sub)
		p.add_child(sub)
		_sub_labels.append(sub)

		var star := UIKit.label("", 10, UIKit.ACCENT)
		star.position = Vector2(4, 34)
		star.size = Vector2(TILE - GAP * 2.0 - 8, 14)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_world_descend(star)
		p.add_child(star)
		_star_labels.append(star)

		_owners.append(-2)
		_levels.append(-1)

func _world_descend(l: Label) -> void:
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_decor() -> void:
	var c := WORLD * 0.5
	var p := Panel.new()
	p.position = c - Vector2(360, 130)
	p.size = Vector2(720, 260)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.stylebox(Color(0.10, 0.11, 0.16, 0.65), 26, Color("#3c4254"), 1)
	p.add_theme_stylebox_override("panel", sb)
	_world.add_child(p)

	var title := UIKit.label("宿舍大富翁", 62, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.30))
	title.position = Vector2(0, 52)
	title.size = Vector2(720, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(title)

	var sub := UIKit.label("35 × 23 环线 · 112 格 · 10 大产业", 19, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.75))
	sub.position = Vector2(0, 138)
	sub.size = Vector2(720, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(sub)

	var hint := UIKit.label("滚轮缩放 · 拖拽平移 · 点击格子查看详情", 15, Color(UIKit.TEXT_DIM.r, UIKit.TEXT_DIM.g, UIKit.TEXT_DIM.b, 0.55))
	hint.position = Vector2(0, 172)
	hint.size = Vector2(720, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hint)

func _build_ring() -> void:
	_ring = Panel.new()
	_ring.size = Vector2(40, 40)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.z_index = 15
	var sb := UIKit.stylebox(Color(0, 0, 0, 0), 20, UIKit.ACCENT, 3)
	sb.draw_center = false
	_ring.add_theme_stylebox_override("panel", sb)
	_ring.visible = false
	_world.add_child(_ring)

# ---------------- 视口：缩放 / 平移 / 跟随 ----------------

func _process(delta: float) -> void:
	if _need_fit and size.x > 10.0:
		_need_fit = false
		focus_grid(0, 0.8, true)  # 初始镜头：起点角、可读倍率
	if auto_follow and _follow_peer != -1 and _tokens.has(_follow_peer):
		var tk: Control = _tokens[_follow_peer]
		var center := tk.position + tk.size * 0.5
		var vr := _visible_rect()
		var target := vr.position + vr.size * 0.5 - center * _zoom
		_world.position = _world.position.lerp(_clamp_pos(target), 1.0 - exp(-6.0 * delta))
	if _ring_peer != -1 and _tokens.has(_ring_peer):
		var tk2: Control = _tokens[_ring_peer]
		_ring.position = tk2.position + tk2.size * 0.5 - _ring.size * 0.5

func _visible_rect() -> Rect2:
	return Rect2(0, 0, size.x - overlay_right, size.y - overlay_bottom)

## 全图概览（把 112 格整块塞进可视区域）
func fit_overview() -> void:
	auto_follow = false
	_follow_peer = -1
	var vr := _visible_rect()
	_zoom = clampf(minf(vr.size.x / (WORLD.x + 40.0), vr.size.y / (WORLD.y + 40.0)), MIN_ZOOM, 1.0)
	_world.scale = Vector2.ONE * _zoom
	_world.position = _clamp_pos(vr.position + (vr.size - WORLD * _zoom) * 0.5)

## 镜头对准某格 / 某棋子；hard=true 立即居中
func focus_grid(idx: int, zoom: float, hard := true) -> void:
	auto_follow = false
	_follow_peer = -1
	_zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	_world.scale = Vector2.ONE * _zoom
	var center := tile_pos(idx) + Vector2(TILE, TILE) * 0.5
	if hard:
		var vr := _visible_rect()
		_world.position = _clamp_pos(vr.position + vr.size * 0.5 - center * _zoom)

func focus_peer(peer: int, hard := false) -> void:
	auto_follow = true
	_follow_peer = peer
	if hard and _tokens.has(peer):
		var tk: Control = _tokens[peer]
		var vr := _visible_rect()
		_world.position = _clamp_pos(vr.position + vr.size * 0.5 - (tk.position + tk.size * 0.5) * _zoom)

func _zoom_at(factor: float, anchor: Vector2) -> void:
	var before := _world_from_view(anchor)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_world.scale = Vector2.ONE * _zoom
	_world.position = _clamp_pos(anchor - before * _zoom)

func _clamp_pos(p: Vector2) -> Vector2:
	var vr := _visible_rect()
	var m := 26.0
	var x := p.x
	var y := p.y
	if WORLD.x * _zoom < vr.size.x:
		x = vr.position.x + (vr.size.x - WORLD.x * _zoom) * 0.5
	else:
		x = clampf(x, vr.end.x - WORLD.x * _zoom - m, vr.position.x + m)
	if WORLD.y * _zoom < vr.size.y:
		y = vr.position.y + (vr.size.y - WORLD.y * _zoom) * 0.5
	else:
		y = clampf(y, vr.end.y - WORLD.y * _zoom - m, vr.position.y + m)
	return Vector2(x, y)

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
				auto_follow = false
				_world.position = _clamp_pos(_world.position + mm.relative)
		else:
			set_hover(_index_at(mm.position))

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
			var tk := _make_token(GameData.PLAYER_COLORS[slot], String(p.name))
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
			var tk2: Panel = _tokens[peer]
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
	return tile_pos(idx) + Vector2(TILE, TILE) * 0.5 - Vector2(10, 10) + _slot_offset(slot)

func _slot_offset(slot: int) -> Vector2:
	match slot % 4:
		0: return Vector2(-14, -14)
		1: return Vector2(14, -14)
		2: return Vector2(-14, 14)
		_: return Vector2(14, 14)

func _make_token(color: Color, pname: String) -> Panel:
	var tk := Panel.new()
	tk.size = Vector2(20, 20)
	var sb := UIKit.stylebox(color, 10, Color(0.95, 0.95, 0.97), 2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	tk.add_theme_stylebox_override("panel", sb)
	tk.tooltip_text = pname
	tk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tk.z_index = 20
	return tk

func token_world_pos(peer: int) -> Vector2:
	if not _tokens.has(peer):
		return Vector2.ZERO
	var tk: Control = _tokens[peer]
	return tk.position + tk.size * 0.5

## 棋子在游戏界面坐标（飘字用）
func token_screen_pos(peer: int) -> Vector2:
	return global_position + _world.position + token_world_pos(peer) * _zoom

func _kill_token_tw(peer: int) -> void:
	if not _tokens.has(peer):
		return
	var tk: Panel = _tokens[peer]
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
	var tk: Panel = _tokens[p]
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

func _teleport_anim(p: int, tk: Panel) -> void:
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
