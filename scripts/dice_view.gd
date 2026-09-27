extends Control
class_name DiceView
## 双骰子控件：自绘骰面 + 掷骰抖动动画。

const PIPS := {
	1: [Vector2(1, 1)],
	2: [Vector2(0, 0), Vector2(2, 2)],
	3: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
	4: [Vector2(0, 0), Vector2(0, 2), Vector2(2, 0), Vector2(2, 2)],
	5: [Vector2(0, 0), Vector2(0, 2), Vector2(1, 1), Vector2(2, 0), Vector2(2, 2)],
	6: [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(2, 0), Vector2(2, 1), Vector2(2, 2)],
}

var v1 := 6
var v2 := 6
var _rolling := false

func _init() -> void:
	custom_minimum_size = Vector2(150, 76)
	size = custom_minimum_size

func set_values(a: int, b: int) -> void:
	v1 = a
	v2 = b
	queue_redraw()

func play_roll(a: int, b: int) -> void:
	if _rolling:
		set_values(a, b)
		return
	_rolling = true
	var tw := create_tween()
	for i in 9:
		tw.tween_callback(_random_face)
		tw.tween_interval(0.06)
	tw.tween_callback(func() -> void:
		set_values(a, b)
		_rolling = false
	)

func _random_face() -> void:
	v1 = randi_range(1, 6)
	v2 = randi_range(1, 6)
	queue_redraw()

func _draw() -> void:
	_draw_die(Rect2(Vector2(3, 5), Vector2(66, 66)), v1)
	_draw_die(Rect2(Vector2(81, 5), Vector2(66, 66)), v2)

func _draw_die(r: Rect2, v: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.ACCENT
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.42, 0.30, 0.08)
	draw_style_box(sb, r)
	var pts: Array = PIPS.get(v, PIPS[1])
	var inset := 14.0
	var spread := r.size.x - inset * 2.0
	for p in pts:
		var c := r.position + Vector2(inset, inset) + Vector2(p.x, p.y) / 2.0 * spread
		draw_circle(c, 5.0, Color(0.16, 0.12, 0.04))
