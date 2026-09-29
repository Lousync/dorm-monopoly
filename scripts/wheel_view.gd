extends Control
class_name WheelView
## 赌场风幸运转轮：25 格（0~24），作为移动点数的来源。
## 转动用 _process 相位驱动（三次缓出 + 多圈），指针扫过格沿时滴答作响，
## 停下后落点格高亮；本项目的持续动画统一手写，不依赖 Tween。

const SEGMENTS := 25
const SEG_ANGLE := TAU / SEGMENTS
## 旋转总时长（房主结算等待与它保持同步）
const SPIN_TIME := 2.4

const COL_A := Color(0.157, 0.188, 0.278)
const COL_B := Color(0.227, 0.267, 0.376)
const COL_ZERO := Color(0.125, 0.125, 0.16)
const COL_MAX := Color(0.71, 0.46, 0.10)
const COL_NUM := Color(0.92, 0.94, 0.98)
const COL_NUM_MAX := Color(1.0, 0.95, 0.75)

var value := 0                 # 当前停住的点数
var spinning := false

var _rotation := 0.0           # 轮盘当前旋转角
var _spin_from := 0.0
var _spin_to := 0.0
var _spin_t := 0.0
var _last_seg := 0

func _init() -> void:
	custom_minimum_size = Vector2(400, 400)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 转到指定点数：至少多转一整圈，三次缓出减速停稳
func spin_to(v: int) -> void:
	v = clampi(v, 0, SEGMENTS - 1)
	value = v
	_spin_from = _rotation
	var target := -float(v + 0.5) * SEG_ANGLE
	while target < _spin_from + TAU - 0.0001:
		target += TAU
	_spin_to = target
	_spin_t = 0.0
	spinning = true
	_last_seg = _seg_under_pointer()
	Fx.play("dice", -6.0)
	queue_redraw()

func _seg_under_pointer() -> int:
	var a := fposmod(-_rotation, TAU)
	return int(floor(a / SEG_ANGLE)) % SEGMENTS

func _process(delta: float) -> void:
	if not spinning:
		return
	_spin_t += delta
	var k := minf(_spin_t / SPIN_TIME, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)  # 三次缓出
	_rotation = lerpf(_spin_from, _spin_to, e)
	var seg := _seg_under_pointer()
	if seg != _last_seg:
		_last_seg = seg
		var near := 1.0 - absf(k - 1.0)  # 越接近停下音调越清脆
		Fx.play("tick", -12.0, randf_range(0.85, 1.15) + near * 0.35)
	queue_redraw()
	if k >= 1.0:
		spinning = false
		_rotation = fposmod(_spin_to, TAU)
		_finish()

func _finish() -> void:
	queue_redraw()
	if value == SEGMENTS - 1:
		Fx.play("cash", -6.0)
		Fx.play("pop", -4.0)
	elif value == 0:
		Fx.play("bad", -10.0)
	else:
		Fx.play("pop", -10.0)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# 金属外圈
	draw_circle(c, r, Color(0.30, 0.215, 0.06))
	draw_circle(c, r - 3.0, Color(0.961, 0.702, 0.259).darkened(0.25))
	draw_circle(c, r - 9.0, Color(0.11, 0.125, 0.175))
	# 分段扇形
	var rr := r - 14.0
	var steps := 4
	for i in SEGMENTS:
		var a0 := -PI / 2 + float(i) * SEG_ANGLE + _rotation
		var a1 := a0 + SEG_ANGLE
		var col := COL_ZERO if i == 0 else (COL_MAX if i == SEGMENTS - 1 else (COL_A if i % 2 == 0 else COL_B))
		if not spinning and i == value:
			col = col.lightened(0.12)
		var pts := PackedVector2Array()
		pts.append(c)
		for k in steps + 1:
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, col)
		# 分隔细线
		draw_line(c + Vector2(cos(a0), sin(a0)) * (rr - 4.0), c + Vector2(cos(a0), sin(a0)) * rr,
			Color(0, 0, 0, 0.45), 1.5)
	# 各格数字（随盘面旋转，顶格朝外）
	var f := ThemeDB.fallback_font
	for i in SEGMENTS:
		draw_set_transform(c, (float(i) + 0.5) * SEG_ANGLE + _rotation, Vector2.ONE)
		var num_col := COL_NUM_MAX if i == SEGMENTS - 1 else (COL_NUM if i % 2 == 0 else Color(0.78, 0.81, 0.88))
		if i == 0:
			num_col = Color(0.62, 0.65, 0.72)
		draw_string(f, c + Vector2(-20, -(rr - 18.0)), str(i), HORIZONTAL_ALIGNMENT_CENTER, 40, 15, num_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 中心毂
	draw_circle(c, 36.0, Color(0.30, 0.215, 0.06))
	draw_circle(c, 30.0, UIKit.ACCENT)
	draw_circle(c + Vector2(-6, -7), 9.0, Color(1, 1, 1, 0.30))
	# 顶部指针（向下的三角）
	var tip := c + Vector2(0, -(r - 14.0))
	var left := c + Vector2(-13.0, -(r + 12.0))
	var right := c + Vector2(13.0, -(r + 12.0))
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.42, 0.30, 0.08))
	draw_colored_polygon(PackedVector2Array([tip, left + Vector2(3, -2), right - Vector2(3, 2)]), UIKit.ACCENT)
