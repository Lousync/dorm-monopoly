extends Control
class_name WheelView
## 赌场风幸运转轮：13 格（0~12），作为移动点数的来源。
## 转动用 _process 相位驱动（三次缓出 + 多圈），指针扫过格沿时滴答作响，
## 停下后落点格高亮；本项目的持续动画统一手写，不依赖 Tween。

const SEGMENTS := 13
const SEG_ANGLE := TAU / SEGMENTS
## 旋转总时长（房主结算等待与它保持同步）
const SPIN_TIME := 2.4

const COL_A := Color(0.157, 0.188, 0.278)
const COL_B := Color(0.227, 0.267, 0.376)
const COL_ZERO := Color(0.125, 0.125, 0.16)
const COL_MAX := Color(0.71, 0.46, 0.10)
const COL_NUM := Color(0.92, 0.94, 0.98)
const COL_NUM_MAX := Color(1.0, 0.95, 0.75)
## 数字所在半径：取扇区中段（扇区外沿 rr ≈ 186），不贴外圈
const NUM_R := 126.0

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
		# 变换原点已是盘心 c（见上），此处只需给相对盘心的偏移，不能再加 c。
		# y 传的是基线而非字形中心，故 +5 让字形视觉中心落在 NUM_R 上。
		# **批次 13 辛 ④**（用户：「转盘上的数字大一点」）：字号 **15 → 21**、居中框 **40 → 56**、
		# x 偏移 **−20 → −28**（三处同步才仍然居中）。基线补偿按字号等比放大：0.35em ⇒ 15→5、21→**7**
		#（只改字号不补这一项，字形会整体偏高约 2px）。
		# 几何上仍安全：`SEGMENTS = 13`、数字在 `NUM_R = 126` 的半径上 ⇒ 每格弧长约 61px，
		# 21 号字连「12」两个字也只有约 28px，不会与邻格数字打架（`NUM_R` 与扇区几何一字未动）。
		draw_string(f, Vector2(-28, -(NUM_R + 7.0)), str(i), HORIZONTAL_ALIGNMENT_CENTER, 56, 21, num_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 中心毂
	draw_circle(c, 36.0, Color(0.30, 0.215, 0.06))
	draw_circle(c, 30.0, UIKit.ACCENT)
	draw_circle(c + Vector2(-6, -7), 9.0, Color(1, 1, 1, 0.30))
	# 顶部指针**已删**（批次 12 ④）：原先它是画在**画布**上的一个 2D 三角形 —— 随桌垫一起
	# 倾斜，3D 端读起来就是贴在桌面上的一个印刷件（与 ①②⑥ 同一族病）。改由
	# `TableProps.build_wheel` 摆一枚**平贴桌面的 3D 金箭头**（同一位置、同一指向）：
	# 它是与轮缘同族的实物，两端都读得出来（立着的针在 2D 俯视下反而只剩一条棱）。
	# **别把它加回来**：layout_test 有一条反向契约钉"WheelView 不再画指针"。
	# 注意 `_seg_under_pointer()` 的语义**一字未改** —— 中奖格仍按"盘面顶格"算，
	# 3D 箭头只是把那件事**画**出来（指针几何与判奖公式互不影响）。
