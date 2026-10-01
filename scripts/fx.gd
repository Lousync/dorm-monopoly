extends Node
## 特效/音效单例：程序合成的 8-bit 风音效（无外部素材）、
## 场景淡入淡出、界面震屏、飘字、结算彩带。

const RATE := 22050

var _bank := {}
var _pool: Array = []
var _pool_i := 0
var _fade: ColorRect
var _scene_busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sounds()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

	var layer := CanvasLayer.new()
	layer.layer = 100
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.055, 0.085)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	add_child(layer)

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(960, 600))

# ---------------- 音效 ----------------

func play(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _bank.has(sname):
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _bank[sname]
	p.volume_db = vol_db - 9.0
	p.pitch_scale = maxf(0.05, pitch)
	p.play()

## 换场景：先压黑，切换后淡入
func go_to(scene_path: String) -> void:
	if _scene_busy:
		return
	_scene_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.16)
	await tw.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, 0.24)
	_scene_busy = false

## 控件震屏（game 根节点 / 面板均可）
func shake(node: Control, strength := 7.0, dur := 0.3) -> void:
	if not is_instance_valid(node):
		return
	if not node.has_meta("orig_pos"):
		node.set_meta("orig_pos", node.position)
	var orig: Vector2 = node.get_meta("orig_pos")
	var tw := node.create_tween()
	var steps := 6
	for i in steps:
		var f := 1.0 - float(i) / float(steps)
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * f
		tw.tween_property(node, "position", orig + off, dur / steps)
	tw.tween_property(node, "position", orig, dur / steps)

## 世界坐标飘字（+¥2000 / -¥800 之类）
func float_text(parent: Control, pos: Vector2, text: String, color: Color, size := 18) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", 7)
	l.z_index = 90
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.reset_size()
	l.position = pos + Vector2(randf_range(-10, 10), -14.0) - l.size * 0.5
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 46.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.55)
	tw.tween_callback(l.queue_free)

## 结算彩带：从区域顶部撒下彩色纸屑
func confetti(parent: Control, area: Rect2, count := 80) -> void:
	var palette: Array = GameData.PLAYER_COLORS.duplicate()
	palette.append(Color(0.96, 0.70, 0.26))
	palette.append(Color(0.92, 0.92, 0.96))
	for i in count:
		var r := ColorRect.new()
		r.size = Vector2(randf_range(5, 8), randf_range(8, 12))
		r.color = palette.pick_random()
		r.position = Vector2(randf_range(area.position.x, area.end.x), area.position.y - randf_range(0, 140))
		r.rotation = randf_range(0, TAU)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.z_index = 95
		parent.add_child(r)
		var dur := randf_range(1.2, 2.1)
		var tw := r.create_tween()
		tw.tween_property(r, "position:y", r.position.y + randf_range(300, 560), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(r, "rotation", r.rotation + randf_range(-7, 7), dur)
		tw.parallel().tween_property(r, "modulate:a", 0.0, 0.4).set_delay(dur - 0.4)
		tw.tween_callback(r.queue_free)

## 界面入场：整体淡入（可叠 delay 做错落感）
func animate_in(c: Control, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ---------------- 音色合成 ----------------

func _pcm(dur: float, gen: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = clampf(float(gen.call(float(i) / RATE)), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _build_sounds() -> void:
	_bank["click"] = _pcm(0.06, _tone_click)
	_bank["tick"] = _pcm(0.05, _tone_tick)
	_bank["dice"] = _pcm(0.1, _tone_dice)
	_bank["cash"] = _pcm(0.24, _tone_cash)
	_bank["pay"] = _pcm(0.28, _tone_pay)
	_bank["card"] = _pcm(0.3, _tone_card)
	_bank["jail"] = _pcm(0.5, _tone_jail)
	_bank["win"] = _pcm(0.75, _tone_win)
	_bank["pop"] = _pcm(0.12, _tone_pop)
	_bank["bad"] = _pcm(0.3, _tone_bad)
	_bank["bust"] = _pcm(0.55, _tone_bust)

func _tone_click(t: float) -> float:
	return sin(TAU * 1800.0 * t) * exp(-t * 80.0) * 0.7

func _tone_tick(t: float) -> float:
	return sin(TAU * 1400.0 * t) * exp(-t * 70.0) * 0.6

func _tone_dice(t: float) -> float:
	return (randf() * 2.0 - 1.0) * exp(-t * 26.0) * 0.8

func _tone_cash(t: float) -> float:
	var f := 950.0 if t < 0.1 else 1420.0
	var tt := t if t < 0.1 else t - 0.1
	return (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)) * exp(-tt * 18.0) * 0.6

func _tone_pay(t: float) -> float:
	var f := 700.0 - 240.0 * t / 0.28
	return sin(TAU * f * t) * exp(-t * 9.0) * 0.7

func _tone_card(t: float) -> float:
	return (randf() * 2.0 - 1.0) * (0.35 + 0.65 * sin(PI * t / 0.3)) * exp(-t * 5.0) * 0.5

func _tone_jail(t: float) -> float:
	var vib := sin(TAU * 6.0 * t) * 18.0
	return signf(sin(TAU * (130.0 + vib) * t)) * 0.4 * exp(-t * 3.2)

func _tone_win(t: float) -> float:
	var notes := [523.0, 659.0, 784.0, 1047.0]
	var i := mini(int(t / 0.16), 3)
	var tt: float = t - i * 0.16
	var f: float = notes[i]
	return (sin(TAU * f * tt) + 0.35 * sin(TAU * f * 2.0 * tt)) * exp(-tt * 7.0) * 0.55

func _tone_pop(t: float) -> float:
	var f := 500.0 + 1800.0 * t / 0.12
	return sin(TAU * f * t) * exp(-t * 26.0) * 0.7

func _tone_bad(t: float) -> float:
	var f := 300.0 - 130.0 * t / 0.3
	return sin(TAU * f * t) * 0.7 * exp(-t * 7.0)

func _tone_bust(t: float) -> float:
	var f := 110.0 - 45.0 * t / 0.55
	var saw := 2.0 * fposmod(f * t, 1.0) - 1.0
	return saw * 0.55 * exp(-t * 4.0)
