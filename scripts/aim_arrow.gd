class_name AimArrow
extends Control
## 指向性道具的**屏幕层瞄准箭头**（杀戮尖塔式）：从手牌那张卡拉一条三次贝塞尔的
## **渐宽箭杆 + 大箭头**，指向鼠标；落在合法目标上时由调用方把 tip 吸附到目标中心。
##
## 纯表现层：不吃鼠标（`IGNORE`）、不碰玩法。由 `game._update_aim_arrow()` 每帧驱动
##（`_tgt_stage != ""` 期间显示，其余收起）。
##
## 坐标一律是**屏幕（窗口）像素**，与 `hud_layer` 上的其它控件同一空间。

const COLOR := Color(0.42, 0.78, 0.55)          # 与原型一致的绿
const GLOW := Color(0.42, 0.78, 0.55, 0.28)
const N := 26                                    # 箭杆采样段数
const W_TAIL := 2.5                              # 尾端半宽
const W_HEAD := 13.0                             # 近箭头端半宽
const HEAD_L := 30.0                             # 箭头长
const HEAD_W := 17.0                             # 箭头半宽

var _active := false
var _src := Vector2.ZERO
var _tip := Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 35          # HUD 带内、高于 0 的条与按钮，低于 DeckReveal(40) 与模态(45+)
	visible = false

## 亮出箭头（src=卡所在屏幕点，tip=鼠标/目标屏幕点）。
func show_aim(src: Vector2, tip: Vector2) -> void:
	_src = src
	_tip = tip
	if not _active:
		_active = true
		visible = true
	queue_redraw()

## 收起箭头。
func hide_aim() -> void:
	if not _active:
		return
	_active = false
	visible = false
	queue_redraw()

func is_active() -> bool:
	return _active

func _draw() -> void:
	if not _active:
		return
	# 控制点：先上抬再落下的「吊绳」曲线（与原型同款观感）
	var p0 := _src
	var p3 := _tip
	var p1 := Vector2(p0.x + (p3.x - p0.x) * 0.25, p0.y - 150.0)
	var p2 := Vector2(p0.x + (p3.x - p0.x) * 0.75, p3.y - 90.0)

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in N + 1:
		var t := float(i) / float(N)
		var pt := _bez(p0, p1, p2, p3, t)
		var pt2 := _bez(p0, p1, p2, p3, minf(t + 0.01, 1.0))
		var d := pt2 - pt
		var l := d.length()
		if l < 0.0001:
			l = 1.0
		var nrm := Vector2(-d.y, d.x) / l
		var w := W_TAIL + (W_HEAD - W_TAIL) * pow(t, 0.85)
		left.append(pt + nrm * w)
		right.append(pt - nrm * w)

	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])

	# 箭头（沿末端切线的三角）
	var a := _bez(p0, p1, p2, p3, 0.985)
	var b := _bez(p0, p1, p2, p3, 1.0)
	var ang := (b - a).angle()
	var dir := Vector2(cos(ang), sin(ang))
	var nrm2 := Vector2(-dir.y, dir.x)
	var head_poly := PackedVector2Array([
		p3,
		p3 - dir * HEAD_L + nrm2 * HEAD_W,
		p3 - dir * HEAD_L - nrm2 * HEAD_W,
	])

	# 先描一圈更宽的半透明外发光，再压实体
	draw_colored_polygon(_widen(poly, 4.0), GLOW)
	draw_colored_polygon(poly, COLOR)
	draw_colored_polygon(_widen(head_poly, 4.0), GLOW)
	draw_colored_polygon(head_poly, COLOR)

## 把多边形沿其重心方向外扩 `g` 像素（做外发光用；简单按重心缩放，够用）。
func _widen(poly: PackedVector2Array, g: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var out := PackedVector2Array()
	for p in poly:
		var dir := p - c
		var l := dir.length()
		out.append(p + (dir / l) * g if l > 0.001 else p)
	return out

func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
