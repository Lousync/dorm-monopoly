extends Control
class_name DiceView
## 双骰子控件：自绘骰面，掷骰时减速换面 + 位置抖动 + 落定回弹，
## 掷出双数时骰子短暂发光。

const PIPS := {
	1: [Vector2(1, 1)],
	2: [Vector2(0, 0), Vector2(2, 2)],
	3: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
	4: [Vector2(0, 0), Vector2(0, 2), Vector2(2, 0), Vector2(2, 2)],
	5: [Vector2(0, 0), Vector2(0, 2), Vector2(1, 1), Vector2(2, 0), Vector2(2, 2)],
	6: [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(2, 0), Vector2(2, 1), Vector2(2, 2)],
}

## 掷骰动画总时长（房主等 DICE_WAIT 与它保持同步）
const ROLL_TIME := 1.05

var v1 := 6
var v2 := 6
var doubles := false
var _rolling := false
var _jitter := Vector2.ZERO
var _glow := 0.0:
	set(v):
		_glow = v
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(150, 76)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(a: int, b: int) -> void:
	v1 = a
	v2 = b
	doubles = a == b
	queue_redraw()

func play_roll(a: int, b: int) -> void:
	if _rolling:
		set_values(a, b)
		return
	_rolling = true
	doubles = false
	_glow = 0.0
	Fx.play("dice", -2.0)
	var tw := create_tween()
	var interval := 0.05
	for i in 9:
		tw.tween_callback(_random_face)
		tw.tween_interval(interval)
		interval *= 1.18  # 越滚越慢
	tw.tween_callback(_settle.bind(a, b))
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _rolling = false)
	if a == b:
		tw.tween_property(self, "_glow", 1.0, 0.12)
		tw.tween_property(self, "_glow", 0.0, 0.9).set_delay(0.35)

func _random_face() -> void:
	v1 = randi_range(1, 6)
	v2 = randi_range(1, 6)
	_jitter = Vector2(randf_range(-4, 4), randf_range(-4, 4))
	Fx.play("tick", -14.0, randf_range(0.8, 1.3))
	queue_redraw()

func _settle(a: int, b: int) -> void:
	set_values(a, b)
	_jitter = Vector2.ZERO
	if a == b:
		Fx.play("pop", -4.0)
	queue_redraw()

func _draw() -> void:
	_draw_die(Rect2(Vector2(3, 5) + _jitter * 0.6, Vector2(66, 66)), v1, _glow if doubles else 0.0)
	_draw_die(Rect2(Vector2(81, 5) + _jitter * 0.6, Vector2(66, 66)), v2, _glow)

func _draw_die(r: Rect2, v: int, glow: float) -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.35)
	shadow.set_corner_radius_all(12)
	shadow.shadow_color = Color(0, 0, 0, 0.4)
	shadow.shadow_size = 6
	shadow.shadow_offset = Vector2(0, 3)
	draw_style_box(shadow, r.grow(2))
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.ACCENT
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.42, 0.30, 0.08)
	if glow > 0.0:
		sb.border_color = Color(1.0, 0.95, 0.75).lerp(Color(0.42, 0.30, 0.08), 1.0 - glow)
		sb.shadow_color = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55 * glow)
		sb.shadow_size = int(14 * glow)
		sb.shadow_offset = Vector2.ZERO
	draw_style_box(sb, r)
	# 顶部高光条
	var hi := Rect2(r.position + Vector2(8, 4), Vector2(r.size.x - 16, 5))
	draw_rect(hi, Color(1, 1, 1, 0.22), true)
	var pts: Array = PIPS.get(v, PIPS[1])
	var inset := 14.0
	var spread := r.size.x - inset * 2.0
	for p in pts:
		var c := r.position + Vector2(inset, inset) + Vector2(p.x, p.y) / 2.0 * spread
		draw_circle(c + Vector2(0, 1.5), 5.0, Color(0.10, 0.07, 0.02, 0.5))
		draw_circle(c, 5.0, Color(0.16, 0.12, 0.04))
