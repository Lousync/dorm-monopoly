class_name ItemCard
extends Panel
## 道具卡片模板（规格：docs/gameplay/道具系统.md §12，二版已确认）
## 竖版卡：左上/右上外挂圆徽章（半出卡外）+ 图区 + 名称条 + 描述 + 底部品质条
## 价格不上卡片（货架界面随货架展示）；图画区为占位，正式素材归美术对话
## 三档尺寸共用：道具栏（小）/ 货架（中）/ 发现与使用展示（大）

const SIZE_SMALL := Vector2(96, 132)    # 道具栏
const SIZE_MEDIUM := Vector2(150, 210)  # 货架 / 黑市
const SIZE_LARGE := Vector2(220, 300)   # 发现三选一 / 使用飞出

var id := ""
var state := {}

static func make(id: String, size: Vector2, state: Dictionary = {}) -> ItemCard:
	var card := ItemCard.new()
	card.id = id
	card.state = state
	card.custom_minimum_size = size
	card.size = size
	card.clip_contents = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var d := ItemData.def(id)
	var q: String = d.get("quality", "白")
	var qc: Color = ItemData.QUALITY_COLORS.get(q, UIKit.TEXT)
	var passive: bool = String(d.get("type", "")) == "passive"
	var cost := int(d.get("cost", 0))

	var bg := qc.darkened(0.72)
	bg.a = 0.97
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(bg, int(size.y * 0.05), qc, 2, 6))

	var pad := size.y * 0.035
	var art_h := size.y * 0.40
	var name_h := size.y * 0.10
	var qual_h := size.y * 0.082
	var gap := size.y * 0.022

	# 图区（占位）
	var art := Panel.new()
	art.position = Vector2(pad, pad)
	art.size = Vector2(size.x - pad * 2.0, art_h)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_theme_stylebox_override("panel", UIKit.stylebox(qc.darkened(0.55), 6, Color(qc.r, qc.g, qc.b, 0.3), 1))
	card.add_child(art)
	var art_l := UIKit.label("图画占位", maxi(int(size.y * 0.055), 8), Color(qc.r, qc.g, qc.b, 0.5))
	art_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(art_l)
	if bool(state.get("melt", false)):
		var melt := ColorRect.new()
		melt.color = Color(0.72, 0.87, 1.0, 0.3)
		melt.position = Vector2(0, art.size.y * 0.42)
		melt.size = Vector2(art.size.x, art.size.y * 0.58)
		melt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(melt)

	# 名称条
	var name_bar := Panel.new()
	name_bar.position = Vector2(pad, pad + art_h + gap)
	name_bar.size = Vector2(size.x - pad * 2.0, name_h)
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bar.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0, 0, 0, 0.42), 4))
	card.add_child(name_bar)
	var name_l := UIKit.label(id, maxi(int(size.y * 0.072), 9), qc.lightened(0.32))
	name_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bar.add_child(name_l)

	# 描述
	# 描述框：带边框 + 裁剪，文本先开换行再定尺寸（顺序反了会被长文本钳住不换行）
	var desc_box := Panel.new()
	desc_box.position = Vector2(pad * 1.2, pad + art_h + name_h + gap * 1.8)
	desc_box.size = Vector2(size.x - pad * 2.4, size.y - art_h - name_h - qual_h - pad * 4.2)
	desc_box.clip_contents = true
	desc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_box.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0, 0, 0, 0.32), 4,
		Color(qc.r, qc.g, qc.b, 0.28), 1))
	card.add_child(desc_box)
	var desc_l := UIKit.label(String(d.get("desc", "")), maxi(int(size.y * 0.042), 7), UIKit.TEXT_DIM)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.position = Vector2(5, 4)
	desc_l.size = desc_box.size - Vector2(10, 8)
	desc_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_box.add_child(desc_l)

	# 底部品质条
	var qbar := Panel.new()
	qbar.position = Vector2(size.x * 0.18, size.y - qual_h - pad * 0.7)
	qbar.size = Vector2(size.x * 0.64, qual_h)
	qbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qbar.add_theme_stylebox_override("panel", UIKit.stylebox(Color(qc.r, qc.g, qc.b, 0.2), 4,
		Color(qc.r, qc.g, qc.b, 0.55), 1))
	card.add_child(qbar)
	var ql := UIKit.label(String(ItemData.QUALITY_NAMES.get(q, q)), maxi(int(size.y * 0.048), 8), qc)
	ql.set_anchors_preset(Control.PRESET_FULL_RECT)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qbar.add_child(ql)

	# 左上徽章：⚡消耗 / 被动标
	var bs := maxf(size.y * 0.15, 20.0)
	var lb := _badge(bs, Color(0.15, 0.17, 0.26), Color(1.0, 0.85, 0.3))
	lb.position = Vector2(-bs * 0.42, -bs * 0.42)
	card.add_child(lb)
	var lb_text := "被动"
	if not passive:
		lb_text = "⚡%d" % maxi(cost, 0)
	var lb_l := UIKit.label(lb_text, int(bs * 0.38), Color(1.0, 0.85, 0.3))
	lb_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.add_child(lb_l)

	# 右上徽章：计数位（冷却剩余 / 黑卡次数 / 香皂回合）
	var count := int(state.get("count", -1))
	var rb := _badge(bs, Color(0.15, 0.17, 0.26), Color(0.7, 0.9, 1.0))
	rb.position = Vector2(size.x - bs * 0.58, -bs * 0.42)
	card.add_child(rb)
	if count >= 0:
		var rb_l := UIKit.label(str(count), int(bs * 0.46), Color(0.7, 0.9, 1.0))
		rb_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		rb_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rb_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(rb_l)
	else:
		rb.visible = false

	# 状态表现：是否冷却必须显式给出。count 同时承载「剩余次数(黑卡)/融化回合(香皂)/
	# 冷却回合」，单看 count > 0 会把还有次数的黑卡也画成冷却中（见 fix/v0.0.2）。
	if bool(state.get("cooling", false)):
		card.modulate = Color(0.6, 0.62, 0.7)  # 冷却中：画面压暗
	if bool(state.get("dim", false)):
		card.modulate = Color(0.46, 0.46, 0.5)  # 买不起
	if bool(state.get("selected", false)):
		card.add_theme_stylebox_override("panel", UIKit.card_stylebox(bg, int(size.y * 0.05),
			Color(1.0, 0.86, 0.4), 3, 10, Color(1.0, 0.86, 0.4, 0.35)))
	return card

static func _badge(side: float, bg: Color, border: Color) -> Panel:
	var b := Panel.new()
	b.size = Vector2(side, side)
	b.add_theme_stylebox_override("panel", UIKit.stylebox(bg, int(side * 0.5), border, 2, 2))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b
