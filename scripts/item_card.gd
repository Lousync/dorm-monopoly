class_name ItemCard
extends Panel
## 道具卡片模板（规格：doc/game-design/道具系统.md §九「卡片规格」，二版已确认）
## 竖版卡：左上/右上外挂圆徽章（半出卡外）+ 图区 + 名称条 + 描述 + 底部品质条
## 价格不上卡片（货架界面随货架展示）；图画区 = 道具的 `icon` 图（2026-10-10 起 68 件全有图），缺素材才回退占位
## 三档尺寸共用：道具栏（小）/ 货架（中）/ 发现与使用展示（大）

const SIZE_SMALL := Vector2(96, 132)    # 道具栏
const SIZE_MEDIUM := Vector2(150, 210)  # 货架 / 黑市
const SIZE_LARGE := Vector2(220, 300)   # 发现三选一 / 使用飞出

# ---- 角标几何：**唯一一份数字**（2026-10-12 抽出来）----
#
# 角徽章是**半出卡外**画的（设计如此，见 `doc/game-design/道具系统.md` §九）：左上那枚 ⚡ / 被动
# 探出左、上各一截，右上那枚（计数 / 冷却预览 / **「一次性」胶囊**）探出右边一截。凡是**会裁边**
# 的容器（手牌正面的 `SubViewport`、背包与图鉴的 `ScrollContainer`）都得按"最多探出多少"留白。
#
# 为什么抽成常量：这两个数**必须同源**。2026-10-11 手牌那次翻车就是留白只算到圆角标、
# 漏了更宽的「一次性」胶囊（右半截被硬切）；2026-10-12 背包那次是压根没留白。谁再手算一份，
# 下次改尺寸时就会再漂开一次 —— 要留白请调 `badge_overhang()`。
const BADGE_SIDE_R := 0.15      # 圆角标边长 = size.y × 本比例（下限 BADGE_SIDE_MIN）
const BADGE_SIDE_MIN := 20.0
const BADGE_SHADOW := 2.0       # 角标投影半径（`UIKit.stylebox` 的 shadow，偏移 (0, 2)）
const BADGE_LEFT_OFF := 0.42    # 左上徽章：position = (−bs × 本值, −bs × 本值)
const BADGE_RIGHT_X := 0.58     # 右上徽章：position.x = size.x − bs × 本值
const BADGE_TOP_OFF := 0.42     # 右上徽章：position.y = −bs × 本值
const PILL_W_R := 2.1           # 「一次性」胶囊：宽 = bs × 本值
const PILL_H_R := 0.9           # 高 = bs × 本值
const PILL_X := 0.6             # 胶囊 position.x = size.x − pw × 本值（右端因此探出 pw × 0.4）
const PILL_Y := 0.42            # 胶囊 position.y = −ph × 本值

var id := ""
var state := {}

## 圆角标的边长（`make()` 的落点与 `badge_overhang()` 共用，别各算一份）。
static func badge_side(size: Vector2) -> float:
	return maxf(size.y * BADGE_SIDE_R, BADGE_SIDE_MIN)

## 「半出卡外」的角标最多探出卡面多少：**(左, 上, 右, 下)**，已含投影。
## 会裁边的容器照它留白（手牌 `HAND_FACE_PAD` / 背包 `PlayerPopup` 的网格留白 / 图鉴道具页）。
## 下沿恒为 0：两枚角标都挂在卡面上沿之外，除了圆角标下半截在卡内、没有任何东西探出下沿。
static func badge_overhang(size: Vector2) -> Vector4:
	var bs := badge_side(size)
	var pw := bs * PILL_W_R
	# 右：圆角标右端 = bs × (1 − BADGE_RIGHT_X)，胶囊右端 = pw × (1 − PILL_X) —— 取大的那个
	#（大档下胶囊更宽，正是 2026-10-11 漏掉的那一枚）
	var right := maxf(bs * (1.0 - BADGE_RIGHT_X), pw * (1.0 - PILL_X))
	return Vector4(bs * BADGE_LEFT_OFF + BADGE_SHADOW, bs * BADGE_TOP_OFF + BADGE_SHADOW,
		right + BADGE_SHADOW, 0.0)

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
	var qc: Color = CardDB.category_color(CardDB.FAMILY_ITEM, q)
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
	var icon_name := String(d.get("icon", ""))
	var icon_path := "res://assets/icons/%s.png" % icon_name
	if icon_name != "" and ResourceLoader.exists(icon_path):
		# 图案：Twemoji 烘焙的 256px PNG（美术管线见 doc/game-design/道具系统.md §九「卡片规格」）
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var inset := art.size.y * 0.10
		tr.position = Vector2(inset, inset)
		tr.size = art.size - Vector2(inset * 2.0, inset * 2.0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(tr)
	else:
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
	var ql := UIKit.label(CardDB.category_label(CardDB.FAMILY_ITEM, q), maxi(int(size.y * 0.048), 8), qc)
	ql.set_anchors_preset(Control.PRESET_FULL_RECT)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qbar.add_child(ql)

	# 左上徽章：⚡消耗（§十六：显示**生效值**，> 基础红、< 基础绿）/ 被动标
	var bs := badge_side(size)
	var cost_eff := int(state.get("cost_eff", cost))
	var cost_dir := 0
	if cost_eff > cost:
		cost_dir = 1
	elif cost_eff < cost:
		cost_dir = -1
	var lc := _delta_color(cost_dir, Color(1.0, 0.85, 0.3))
	var lb := _badge(bs, Color(0.15, 0.17, 0.26), lc)
	lb.position = Vector2(-bs * BADGE_LEFT_OFF, -bs * BADGE_LEFT_OFF)
	card.add_child(lb)
	var lb_text := "被动"
	if not passive:
		lb_text = "⚡%d" % maxi(cost_eff, 0)
	var lb_l := UIKit.label(lb_text, int(bs * 0.38), lc)
	lb_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.add_child(lb_l)

	# 右上徽章（用户 §六 #22）：**一次性** → 「一次性」文字标；**冷却中** → 沙漏 + 剩余回合；
	# 其余计数位（黑卡剩余次数 / 香皂融化回合）→ 数字。
	var count := int(state.get("count", -1))
	var cooling: bool = bool(state.get("cooling", false))
	# §十六：未使用时显示**生效冷却预览**（红升绿降）；冷却中（count>=0）显示剩余、照旧压暗。
	var cd_preview := int(state.get("cd_preview", -1))
	var cd_dir := 0
	if state.has("cd_base"):
		var cb := int(state.get("cd_base", cd_preview))
		if cd_preview > cb:
			cd_dir = 1
		elif cd_preview < cb:
			cd_dir = -1
	var is_once: bool = String(d.get("type", "")) == "consumable"
	if is_once:
		var pw := bs * PILL_W_R
		var ph := bs * PILL_H_R
		var ob := _pill(Vector2(pw, ph), Color(0.34, 0.19, 0.48), Color(0.72, 0.55, 1.0))
		ob.position = Vector2(size.x - pw * PILL_X, -ph * PILL_Y)
		card.add_child(ob)
		var ol := UIKit.label("一次性", int(ph * 0.5), Color(0.92, 0.84, 1.0))
		ol.set_anchors_preset(Control.PRESET_FULL_RECT)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ob.add_child(ol)
	elif count >= 0:
		var rb := _badge(bs, Color(0.15, 0.17, 0.26), Color(0.7, 0.9, 1.0))
		rb.position = Vector2(size.x - bs * BADGE_RIGHT_X, -bs * BADGE_TOP_OFF)
		card.add_child(rb)
		var txt := ("⏳%d" % count) if cooling else str(count)
		var rb_l := UIKit.label(txt, int(bs * 0.42), Color(0.7, 0.9, 1.0))
		rb_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		rb_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rb_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(rb_l)
	elif cd_preview >= 0:
		# 未使用的主动件：显示生效冷却预览（不压暗，区别于「冷却中」）
		var cdc := _delta_color(cd_dir, Color(0.7, 0.9, 1.0))
		var pb := _badge(bs, Color(0.15, 0.17, 0.26), cdc)
		pb.position = Vector2(size.x - bs * 0.58, -bs * 0.42)
		card.add_child(pb)
		var pb_l := UIKit.label("⏳%d" % cd_preview, int(bs * 0.42), cdc)
		pb_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		pb_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pb_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pb_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_child(pb_l)

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

## §十六 红绿：变高红、变低绿、不变用默认色。
static func _delta_color(dir: int, base: Color) -> Color:
	if dir > 0:
		return Color(1.0, 0.45, 0.42)
	if dir < 0:
		return Color(0.5, 0.92, 0.55)
	return base

## 圆形 / 胶囊徽章：**语言住在 `UIKit`**（文字卡要借同一套，免得各写第二份）。
## 2026-10-10 卡面美化时**纯搬移**（外观零变化）—— 落点仍写在本文件的调用点里，所以"看哪去"没变。
static func _badge(side: float, bg: Color, border: Color) -> Panel:
	return UIKit.badge_round(side, bg, border)

static func _pill(sz: Vector2, bg: Color, border: Color) -> Panel:
	return UIKit.badge_pill(sz, bg, border)
