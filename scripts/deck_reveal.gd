class_name DeckReveal
extends Control
## 「机会卡」抽卡演出的**屏幕层大字卡**（批次 8，见 doc/game-design/设计决策留痕.md §八）。
##
## 为什么搬到屏幕层：原先演在桌垫画布（`BoardView._world`）里，靠把 **2D 相机**拉近 2 倍
## （旧 `DECK_PUSH_FACTOR`）才读得出字 —— 那一推会让**印在桌垫上的图案**整体放大滑动，而手牌
## 是"不跟 2D 相机"的实物 ⇒ 两者明显错位（用户 ① 报的"画面聚集导致 3D 物品错位"）。
## 本组件把卡改到屏幕层以固定大尺寸演出，**相机全程不动**，错位从根上消失。
##
## 唯一失去的是"从桌上那摞抽起"的实体感（用户选的就是这一档，已接受）⇒ **本组件不依赖
## board / table3d**（不再需要起点供给 `deck_top_provider`，那一路已随本批删除）。
##
## 四段相位与时长与旧版（`BoardView.play_deck_card`）一字不差。
##
## **批次 12 C2 起 HOLD 之后不再自动收回**：停在那里等「确定」（`request_close()` 才走 BACK）。
## 因此 `CARD_TIME` 重新定义为 **前三段之和**（"演出到停住为止"），房主的等待不再挂在它上面，
## 改走 `game._await_card_confirm()`（`_await_turn_window("card", …)`：超时 / 机器人 / 休眠托管
## 自动确认）。`CARD_TIME` 现在只剩"何时该让「确定」按钮出镜"这一个语义，摆拍与测试仍读它。

## 本机玩家按下「确定」（`game` 接手：房主直接放行 / 客户端回 `c_card_ok`）。
signal confirmed

## 抉择卡：本机玩家挑了第 `idx` 个分支（`game._on_card_choice` 接手：房主直接记下 /
## 客户端回 `c_choice`）。**只有抽卡者那一端会有按钮**，见 `game.s_card_choices`。
signal choice_picked(idx: int)

## 小抄置底询问（2026-10-10 M1）：本机玩家挑了「塞到底」(true) / 「算了」(false)。
## `game._on_bury_picked` 接手：房主本机直写、客户端回 `c_bury_ok`（同 `confirmed` 那一套分叉）。
signal bury_picked(bury: bool)

## 卡的屏幕尺寸（2:3 —— 与旧 `BoardView.CARD_SIZE`(260×390) 同比例，放大到"大字"档）。
const CARD_SIZE := Vector2(320.0, 480.0)
## 四段相位时长（秒）：抽出 → 翻面 → 停留 → 收回。数值与旧版一字不差。
const OUT := 0.34
const FLIP := 0.30
const HOLD := 1.50
const BACK := 0.28
## 演出到「停住等确定」为止的时长（= 前三段之和）。**BACK 只在 `request_close()` 之后走**。
const CARD_TIME := OUT + FLIP + HOLD
## 抉择卡那排分支按钮的单枚尺寸（横向排一排、整排居中，见 `_place`）。
const CHOICE_BTN := Vector2(168.0, 42.0)
## 小抄置底那两枚（「塞到底 / 算了」）的单枚尺寸。
const BURY_BTN := Vector2(140.0, 42.0)
## 文字卡卡面那两枚徽章的基准尺寸（**不是**相位常量：改它不影响任何时长，`hud_test` 的
## `CARD_TIME` 断言照绿）。`ItemCard` 那两枚是 `size.y * 0.15` = 72px，在 320×480 这档相当抢眼；
## 文字卡只有一枚文字标题、放两枚 72px 会盖掉版面 ⇒ 取 36（见 doc/development/plans/卡面美化.md
## §二 A.2）。
const BADGE_SIZE := 36.0
## 卡面那层 `layer` 被 `card` 的 stylebox 内缩掉的**内容边距**（`UIKit.card_stylebox` 走
## `_sbt` 的默认值：左右 12 / 上下 8 —— 实测 `layer.position` 就是 `(12, 8)`）。
## 徽章挂在 `layer` 上，而落点要按**卡片**的边算 ⇒ 得先把这层减掉（见 `_add_card_badges`）。
## ⚠ 改动卡面 stylebox 的 content_margin 时这里要跟着改（`chance_test._test_card_face` 钉着）。
const CARD_CONTENT_MARGIN := Vector2(12.0, 8.0)

## 摆拍用：强制让「确定」按钮出镜（`--shot` 的 card / itemreveal 分支置真，`_close()` 复位）。
var dev_force_confirm := false

var _card: Control            # 卡片本体（正反两面铺满它；翻面 = 绕竖轴压扁再张开）
var _back: Control            # 卡背（抽出阶段显示）
var _front: Control           # 卡面（正文 / 道具卡面）
var _t := 0.0                 # 相位计时（_process 驱动，见项目约定"持续动画手写 _process 相位"）
var _bob := 0.0               # 停留段的上下浮动（屏幕像素）
var _showing := false
var _closing := false         # 已收到关闭请求，正在走 BACK 相位
var _close_t := 0.0           # BACK 相位计时
var _can_confirm := false     # 本机玩家是"该确认的人"（由 game 按操作窗口归属推）
var _btn: Button              # 「确定」（停住之后才出镜；非抽卡者不给可用的按钮）
# 抉择卡（批次 2 §三）：卡面下方那排分支按钮。空数组 = 不在抉择态 ⇒ 照旧走「确定」那一条。
var _choice_labels: Array = []   # 房主发下来的分支文案（`s_card_choices`）
var _choice_btns: Array = []     # 按 `_choice_labels` 建出来的那几枚（1~3 枚）
var _built_labels: Array = []    # `_choice_btns` 是按哪一份标签建的（用来免掉每帧重建）
## 小抄置底询问（2026-10-10 M1）：「要把牌堆顶这张塞到底部吗？」那块面板（含两枚按钮）。
## 与抽卡演出**互不相干** —— 小抄没有卡面（它只往私密战报写一行），所以这一块不能挂在 `_showing` 上。
var _bury_box: PanelContainer
## 当前这张卡的**家族色**（`show_card` 派生 family 后立刻写上；默认白 = 没演过卡时的干净值）。
## 生产侧**无人读它** —— 外框 / 标题 / 分隔线 / 光晕各自当场从 `CARD_FAMILIES` 取 `fam["edge"]`；
## 唯一的读者是 `tests/chance_test.gd` 的 `_test_card_style()`：拿它当**可观察量**钉住那三行
## 家族键派生（`deck`→chance / `item_id`→item / `kind=aberr`→aberr），不看像素。
var _fam_edge := Color(1, 1, 1)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 「确定」按钮是**本组件唯一吃点击的东西**（卡片自己全程 IGNORE，点击穿过去落到它身上）。
	# 先建它、卡片后加 ⇒ 卡片画在按钮之上；两者位置不重叠（按钮在卡片正下方）。
	_btn = UIKit.button("确定", 18, "primary")
	_btn.custom_minimum_size = Vector2(150, 46)
	_btn.size = Vector2(150, 46)
	_btn.visible = false
	_btn.pressed.connect(func() -> void: confirmed.emit())
	add_child(_btn)
	# 小抄置底询问（2026-10-10 M1）：一块小面板 + 两枚按钮。**自己独立显示**，不等 `_showing`
	#（小抄没有卡面，见 `show_bury_ask`）；卡演出的开 / 收也不会顺手把它收掉（见 `_close`）。
	_bury_box = UIKit.panel_container(Color(0.045, 0.05, 0.078, 0.94), 14,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 2, 18)
	_bury_box.visible = false
	add_child(_bury_box)
	var bm := UIKit.margins(18, 18, 14, 14)
	_bury_box.add_child(bm)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 10)
	bm.add_child(bcol)
	var bhint := UIKit.label("（小抄）把牌堆顶这张塞到底部？", 15, UIKit.TEXT)
	bhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcol.add_child(bhint)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
	bcol.add_child(brow)
	var b_bury := UIKit.button("塞到底", 16, "primary")
	b_bury.custom_minimum_size = BURY_BTN
	b_bury.size = BURY_BTN
	b_bury.pressed.connect(func() -> void: bury_picked.emit(true))
	brow.add_child(b_bury)
	var b_keep := UIKit.button("算了", 16, "normal")
	b_keep.custom_minimum_size = BURY_BTN
	b_keep.size = BURY_BTN
	b_keep.pressed.connect(func() -> void: bury_picked.emit(false))
	brow.add_child(b_keep)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 压在棋盘 / 四角身家条之上、**模态带之下**（暂停菜单 / 结算 50 / 弹问 60 / 小卖部 70）。
	# 40 < 模态带里最低的 50 ⇒ 卡绝不压在模态面板之上（模态面板也绝不被卡盖住）。
	# **不能只靠树序**：`z_as_relative` 默认为真，本组件挂在 `hud`(z 0) 里 ⇒ 实效 z 就是 40；
	# 而 `menu_layer` 挂在 `game` 下（也是 0）—— 靠树序时谁在上取决于建/搬节点的顺序，
	# 所以模态层自己也**显式**设了 z（见 `table_hud.build_menu_ui` 的 `menu_layer.z_index`）。
	z_index = 40
	visible = false
	resized.connect(_place)

func _process(delta: float) -> void:
	if _showing:
		tick(delta)

## 屏幕正中亮出一张卡。重复调用先把上一张收掉（幂等）。
##
## **卡源有两种**（批次 12 C3）：`item_id` 非空 = 演**该道具的卡面**（⑪ 失物招领，直接挂一张
## `ItemCard` —— 屏幕层是 2D，不需要手牌那套 SubViewport 纹理）；否则演**文字卡**（机会卡 / 畸变公告），
## 其标题由 `deck` 给 —— 它是**卡类名 / 演出标题**，2026-10-09 起不再是牌堆名（牌堆已删）。
func show_card(deck: String, kind: String, text: String, item_id := "") -> void:
	_close()
	var item_face := item_id != ""
	# ---- 家族键派生（2026-10-10 卡面美化，见 doc/development/plans/卡面美化.md §4.1）----
	# `deck` 从此**只担"标题 / 演出标题"一个角色**，配色键归 `family`。三档依据（今天完整且无歧义）：
	#   ① 道具卡面（道具卡 / 失物招领）：一律带 `item_id`；
	#   ② 畸变公告：`s_card` 那一路 deck = "🌀 畸变 · 名"、kind 恒为 "aberr"；
	#   ③ 其余 = 机会卡（`_run_chance` 传 deck = "机会"）。
	# ⚠ **不要再加 `deck.begins_with("🌀")` 那种判法** —— 那只是"另一种拿标题当键"，标题一改配色就坏。
	var family := "chance"
	if item_face:
		family = "item"
	elif kind == "aberr":
		family = "aberr"
	# 第四类文字卡冒出来时**在这里当场叫**：否则它静默落进 chance —— 配色错、还不报错。
	# 口径同步写在 `doc/development/联机协议.md` 的 `s_card` 行（T6）。
	assert(family != "chance" or deck == "机会",
		"DeckReveal: 未登记的文字卡标题「%s」—— 家族键派生要补一行（见 卡面美化.md §4.1）" % deck)
	var fam: Dictionary = GameData.CARD_FAMILIES[family]
	_fam_edge = fam["edge"]
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE * 0.5        # 绕自己中心压扁 / 缩放
	add_child(card)
	# 卡背 / 卡面都按**家族键**取色取纹（不再吃卡型色、也不再拿标题当键）
	_back = _card_face_back(family)
	card.add_child(_back)
	# 道具卡面那一路仍是**那张 `ItemCard`**（与货架 / 手牌 / 弹窗同一张卡，`hud_test` 按脚本类型数
	# 节点、断言恰好 1 张）；文字卡走 `_card_face_front`。两路的家族痕记见各自函数。
	_front = ItemCard.make(item_id, CARD_SIZE) if item_face else _card_face_front(family, kind, deck, text)
	_front.visible = false
	card.add_child(_front)
	card.modulate = Color(1, 1, 1, 0.0)
	card.scale = Vector2(0.55, 0.55)
	card.rotation = -0.05
	_card = card
	_bob = 0.0
	_t = 0.0
	_showing = true
	_btn.visible = false
	visible = true
	_place()

## 请求收尾（房主广播的 `s_card_close` / 机器人托管 / 摆拍兜底）：走完 BACK 相位后自己 `_close()`。
func request_close() -> void:
	if not _showing or _closing:
		return
	_closing = true
	_close_t = 0.0
	_btn.visible = false
	# 抉择按钮同理：收尾相位里 `tick` 不再过 `_update_btn`，得在这里先收掉（`_choice_labels`
	# 不动 —— 它还记着"这一张是抉择卡"，重开演时由 `show_card → _close` 清）
	_sync_choice_btns([])

## 本机玩家是不是"该点确定的人"（由 `game` 按操作窗口归属 `_op_owner` 推）。
## 非抽卡者看到同一张卡，但**没有可用的按钮**（按钮整枚不出镜）。
func set_can_confirm(v: bool) -> void:
	_can_confirm = v
	_update_btn()

## 演出是否停在"等确定"上（测试与摆拍读它）。
func is_awaiting_confirm() -> bool:
	return _showing and not _closing and _t >= CARD_TIME

## 「确定」按钮此刻是不是亮着（测试读它）。
func is_confirm_visible() -> bool:
	return _btn.visible

## 抉择卡：卡面下方给 N 个分支按钮（1~3 个）。`labels` 为空 = 退出抉择态（按钮整排收掉）。
##
## 与「确定」是**同一次演出里互斥的两种作答方式**：抉择态一进，那枚单按钮就不出镜
##（见 `_update_btn`）—— 一次只留一种点法，免得"点了确定到底算不算答完"要两处判。
func show_choices(labels: Array) -> void:
	_choice_labels = labels.duplicate()
	_update_btn()

## 抉择按钮此刻是不是亮着（测试读它）。
func is_choice_visible() -> bool:
	for b in _choice_btns:
		if (b as Button).visible:
			return true
	return false

## 按钮该不该出镜。两条**互斥**：
##   * 抉择态（`_choice_labels` 非空）→ 按它建 N 枚分支按钮，整组等卡停住才出镜；
##   * 否则 —— 「确定」那一条**一字未改**（停住之后、且本机是"该确认的人"或摆拍强制）。
func _update_btn() -> void:
	var settled := _showing and not _closing and _t >= CARD_TIME
	_sync_choice_btns(_choice_labels if settled else [])
	_btn.visible = settled and _choice_labels.is_empty() and (_can_confirm or dev_force_confirm)

## 按 `labels` 重建那排分支按钮（`labels` 为空 = 全收掉）。
## 每帧都会被 `_update_btn` 调到 ⇒ 先比一遍标签，没变就原样留着，别每帧重建节点。
func _sync_choice_btns(labels: Array) -> void:
	if labels == _built_labels:
		return
	for b in _choice_btns:
		(b as Button).queue_free()
	_choice_btns = []
	_built_labels = labels.duplicate()
	for i in labels.size():
		var b := UIKit.button(String(labels[i]), 16, "normal")
		b.custom_minimum_size = CHOICE_BTN
		b.size = CHOICE_BTN
		# 捕的是**这一枚自己的下标**：GDScript 的闭包按值捕获 ⇒ 每轮的 `i` 各自快照，
		# 不会三枚一起报同一个数
		b.pressed.connect(func() -> void: choice_picked.emit(i))
		add_child(b)
		_choice_btns.append(b)
	_place()

## 相位推进（`_process` 每帧调；测试与摆拍可直接快进）。
func tick(delta: float) -> void:
	if not _showing or _card == null or not is_instance_valid(_card):
		return
	var c: Control = _card
	# 收尾：`request_close()` 之后的 BACK 相位，走完自己收掉
	if _closing:
		_close_t += delta
		var k4 := clampf(_close_t / BACK, 0.0, 1.0)
		c.modulate = Color(1, 1, 1, 1.0 - k4)
		var sc4 := 1.0 - 0.42 * k4
		c.scale = Vector2(sc4, sc4)
		_bob = 0.0
		if _close_t >= BACK:
			_close()
			return
		_place()
		return
	_t += delta
	var t := _t
	if t < OUT:
		var k: float = _ease_out_back(t / OUT)
		c.scale = Vector2(0.55 + 0.45 * k, 0.55 + 0.45 * k)
		c.rotation = -0.05 * (1.0 - k)
		c.modulate = Color(1, 1, 1, clampf(t / 0.16, 0.0, 1.0))
		_bob = 0.0
	elif t < OUT + FLIP:
		var k2 := (t - OUT) / FLIP
		c.rotation = 0.0
		c.scale = Vector2(maxf(1.0 - k2 * 2.0, 0.02), 1.0 + 0.06 * k2)
		if k2 >= 0.5:
			_show_deck_face(false)             # 压到最扁的一瞬换面，看不出来
			var k3 := (k2 - 0.5) * 2.0
			c.scale = Vector2(maxf(k3, 0.02), 1.06 - 0.06 * k3)
		var flash := 1.0 + 0.4 * (1.0 - absf(k2 * 2.0 - 1.0))   # 换面点附近提亮，模拟翻牌反光
		c.modulate = Color(flash, flash, flash, 1.0)
		_bob = 0.0
	elif t < OUT + FLIP + HOLD:
		var h := t - OUT - FLIP
		c.scale = Vector2.ONE
		c.rotation = 0.0
		_bob = sin(h * 2.4) * 3.0
		var breath := 1.0 + 0.03 * (0.5 + 0.5 * sin(h * 3.2))   # 呼吸微光，别像钉在屏幕上
		c.modulate = Color(breath, breath, breath, 1.0)
	else:
		# 停住等「确定」：姿态与 HOLD 段一字不差（呼吸微光 + 上下浮动），
		# 到点不再自动收 —— 由 `s_card_close`（或超时 / 托管）推 `request_close()`。
		# **换面在这里兜一道**：翻面那一跳藏在 FLIP 分支里（压到最扁的一瞬才换），
		# 只要有一跳的 delta 跨过了整段 FLIP（掉帧 / 摆拍直接 `tick` 快进到这一档），
		# 就永远换不过来、卡背一直亮着。这一步幂等，正常路径上写的是同一个值。
		_show_deck_face(false)
		var h2 := t - OUT - FLIP - HOLD
		c.scale = Vector2.ONE
		c.rotation = 0.0
		_bob = sin(h2 * 2.4) * 3.0
		var breath2 := 1.0 + 0.03 * (0.5 + 0.5 * sin(h2 * 3.2))
		c.modulate = Color(breath2, breath2, breath2, 1.0)
	_place()
	_update_btn()

## 演出是否进行中（`dev_tools` 的摆拍等待与测试都读它）。
func is_showing() -> bool:
	return _showing

## 把卡摆到本层正中（+ 停留段的浮动），「确定」按钮摆在卡的正下方。
## 本层是 FULL_RECT ⇒ 屏幕一改尺寸这里跟着重摆。
func _place() -> void:
	# 置底询问那块与卡各摆各的：它不依赖 `_card`，卡不在时照样摆（早退放在它后面）
	_place_bury()
	if _card == null or not is_instance_valid(_card):
		return
	_card.position = (size - CARD_SIZE) * 0.5 + Vector2(0.0, _bob)
	var y := (size.y + CARD_SIZE.y) * 0.5 + 18.0
	_btn.position = Vector2((size.x - _btn.size.x) * 0.5, y)
	# 抉择按钮组：与「确定」同一个纵坐标（卡正下方），横向排一排、整排居中。
	# 宽度按**各自的实际 size**（文案长短不一，Control 会把 size 撑到不小于文字宽）⇒ 不会互相压住。
	var n := _choice_btns.size()
	if n > 0:
		var total := float(n - 1) * 12.0
		for b in _choice_btns:
			total += (b as Button).size.x
		var x := (size.x - total) * 0.5
		for b in _choice_btns:
			var bb := b as Button
			bb.position = Vector2(x, y)
			x += bb.size.x + 12.0

## 收掉当前这张（重复开演 / 演出结束都走它）。
func _close() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_back = null
	_front = null
	_bob = 0.0
	_showing = false
	_closing = false
	_close_t = 0.0
	_can_confirm = false
	dev_force_confirm = false
	_btn.visible = false
	# 抉择态一并清干净：下一次开演若又是抉择卡，`s_card_choices` 会重新发标签过来；
	# 不留在上一张的标签上（留着的话，新卡停住时那排旧按钮会自己冒出来）
	_choice_labels = []
	_sync_choice_btns([])   # 走它 = 顺带把那几枚按钮节点真回收掉（不能只清数组，会留孤儿节点）
	# 置底询问**不归本函数管**：小抄没有卡面、那块面板与演出各自独立（见 `show_bury_ask`）——
	# 这里只按它自己的显隐决定整层收不收。无脑 `visible = false` 会把正等着的询问一起吞掉。
	visible = _bury_box != null and _bury_box.visible


## 小抄置底询问（2026-10-10 M1）：`ask=true` 亮出「塞到底 / 算了」；`ask=false` 收掉。
## `mine` = 本机就是该作答的人（房主只把按钮给它，同 `s_card_choices` / `s_card_target` 的口径）。
##
## 与抽卡演出**各自独立**：小抄只往私密战报写一行、**没有卡面**，所以这一块不能等 `_showing`
##（等它就永远不亮）；反过来，本层要自己亮起来 —— 卡不在演时 `show_card` 那条路走不到。
func show_bury_ask(ask: bool, mine: bool) -> void:
	if _bury_box == null:
		return
	_bury_box.visible = ask and mine
	if _bury_box.visible:
		visible = true
		_place_bury()
	elif not _showing:
		visible = false   # 收尾：没卡在演就把整层收回去（有卡在演则由它自己那一路收）

## 置底询问按钮此刻是不是亮着（`item_test` 的接线用例读它）。
func is_bury_visible() -> bool:
	return _bury_box != null and _bury_box.visible

## 把置底面板块摆到本层正中（本层 FULL_RECT ⇒ 屏幕一改尺寸跟着重摆）。
## 本层不是 Container，得自己算尺寸：`get_combined_minimum_size()` 再手动居中。
func _place_bury() -> void:
	if _bury_box == null:
		return
	var m := _bury_box.get_combined_minimum_size()
	_bury_box.size = m
	_bury_box.position = (size - m) * 0.5

## 翻面：true = 显示卡背，false = 显示卡面
func _show_deck_face(back: bool) -> void:
	if _back != null and is_instance_valid(_back):
		_back.visible = back
	if _front != null and is_instance_valid(_front):
		_front.visible = not back

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

## ---- 以下四个构建函数**从 board_view.gd 原样搬来**，只改两处：
## ① 正文锁宽用新的 `CARD_SIZE`（`CARD_SIZE.x - 104`）；② 字号放大（标题 24→30、正文 15→18、
##    行距 separation 6→8）。其余（plate 的配色与内缩）一字不改。
## **2026-10-10 卡面美化**又动了两处：卡背图案的 modulate / 描边 / 圆角改由**家族表**给
## （原先那个"是机会就用绿背"的三元判断已拆成家族键，见 §4.1）—— 机会族取到的 tint 与旧值同，
## 畸变族**不同**（旧值走的是"非机会"那一支）；圆角 16 → 18。

## 牌背图案按**家族键**取（家族表是唯一来源）。2026-10-10 之前这里是拿标题字符串比较当配色键
##（`deck` 是「机会」就用绿背），与"标题"这个角色撞在一起（见 卡面美化.md §4.1）。
func _deck_back_tex(family: String) -> Texture2D:
	return UIKit.tex(String(GameData.CARD_FAMILIES[family]["tex"]))

## 铺满整张牌的卡背图案（压成低透明度线纹）；色调按家族
func _make_card_art(family: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _deck_back_tex(family)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = GameData.CARD_FAMILIES[family]["tint"]
	return tr

## 卡面（正面）：同一张牌的图案 + 中央一块文字牌面。
## **家族认框、卡型认章**（2026-10-10 卡面美化）：外框 / 标题 / 分隔线 / 光晕吃**家族色**，
## 卡型色退到右上那枚徽章（色 + 图标 + 中文三通道 —— 比"只看框色猜"准，
## `jail` 的紫框与畸变卡的紫框那"两个几乎一样的紫"也就不再需要靠颜色去分）。
func _card_face_front(family: String, kind: String, deck: String, text: String) -> Control:
	var fam: Dictionary = GameData.CARD_FAMILIES[family]
	var edge: Color = fam["edge"]
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 圆角 16 → 18；描边 = 家族色 2px；光晕 = 家族色 0.14（原先这两处都吃卡型 accent）
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(
		fam["bg"], 18, edge, 2, 12, Color(edge.r, edge.g, edge.b, 0.14)))
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layer)
	layer.add_child(_make_card_art(family))
	# 深色 plate 的 1px 边框也跟家族
	var plate := UIKit.panel_container(Color(0.045, 0.05, 0.078, 0.88), 12,
		Color(edge.r, edge.g, edge.b, 0.5), 1, 0)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.offset_left = 34.0
	plate.offset_right = -34.0
	plate.offset_top = 34.0
	plate.offset_bottom = -34.0
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(plate)
	# 上留白 14 → 20：标题改贴顶之后，这 20px 就是它与卡上缘之间那口气。
	# 左右 16 **别改小**：`layer` 被卡的 stylebox 内缩了 `CARD_CONTENT_MARGIN` ⇒ plate 实宽 272、
	# 内宽 216，**正好**等于标题 / 正文的锁宽；再小一格，标题的 min 宽就把 plate 撑得更宽、
	# 连 plate 一起顶出卡外。
	var m := UIKit.margins(16, 16, 20, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(m)
	var v := VBoxContainer.new()
	# 契约是"绝不吃点击"：`STOP` 的后代不会被 `IGNORE` 的祖先屏蔽 ⇒ 这一层也要显式 IGNORE
	#（根 / card / plate / m / layer / rule 都已经是 IGNORE，别只漏这一层）。
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	# 2026-10-10：原先「标题 + 分隔线 + 正文**整块纵向居中**」⇒ 标题落点随正文长短浮动。
	# 实拍里那块文字只占卡面中间约 1/3、上下各空 ~230 / ~290 px（"大卡面、小内容"最扎眼）——
	# 改成**标题贴顶 + 上留白**是收掉这个观感最便宜的一刀（见 卡面美化.md §1.2(3) / §二 A.3）。
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(v)
	var title := UIKit.bold_label(deck, 30, edge)
	title.name = "card_title"
	# §十：标题按卡面内宽**锁宽换行 + 居中**。不锁的话 Label 的 min 宽 = 整串文字宽
	#（畸变标题「🌀 畸变 · xx」较长时会超出牌面内宽）⇒ 文字块被顶得向右偏、看着不在卡牌居中。
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(CARD_SIZE.x - 104, 0)
	title.size_flags_horizontal = Control.SIZE_FILL
	v.add_child(title)
	# 分隔线：1px 实心 ColorRect → **2px 两端渐隐**（`grad_rect` 的线性渐变，不落素材）。
	# ⚠ `grad_rect` 的 `from` / `to` 默认是**纵向**（`(0.5,0) → (0.5,1)`）—— 这条只有 2px 高，
	# 用默认值等于整条一个色、两端根本渐隐不了。**必须显式给横向端点**（判据也读真画出来的
	# `fill_from` / `fill_to`，见 tests/chance_test.gd 的 `_test_card_face`）。
	var rule := UIKit.grad_rect(
		[Color(edge.r, edge.g, edge.b, 0.0), Color(edge.r, edge.g, edge.b, 0.55),
			Color(edge.r, edge.g, edge.b, 0.0)], [0.0, 0.5, 1.0], false,
		Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	rule.name = "card_rule"
	rule.set_anchors_preset(Control.PRESET_TOP_LEFT)   # `grad_rect` 自带 FULL_RECT 锚点，进 VBox 前先归位
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rule)
	var body := UIKit.label(text, 18, UIKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_SIZE.x - 104, 0)   # 锁换行宽度（内宽 − 4）
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 标题贴顶之后，正文吃下**剩下**的高度、在那一块里垂直居中（长短文案各居各的，
	# 标题落点从此不动 —— 畸变那种长标题也就不会把标题顶下去）
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# 两枚徽章：**加在 `layer` 上，不是加在 `card` 上**（`PanelContainer` 会把直接子节点拉满整卡）
	_add_card_badges(layer, fam, kind)
	return card


## 卡面那两枚**骑在卡边外**的徽章（与 `ItemCard` 同一套语言）。**只给文字卡** ——
## 道具卡面不叠：它已经有"品质色外框 + ⚡消耗 / 被动 + 一次性 / ⏳计数"两套，再叠必打架
##（见 卡面美化.md §3.2；`hud_test` 也钉着"道具卡面前面恰好 1 张 `ItemCard`"）。
##
## ⚠ 只许加在 `layer`（普通 `Control`）上：`card` 是 `PanelContainer`，会把**每一个**直接子节点
## 拉满整卡 ⇒ 徽章的 `position` 当场被抹掉（两枚糊在卡正中）。`layer` 排在 `plate` 之后
## ⇒ 徽章画在正文之上。
func _add_card_badges(layer: Control, fam: Dictionary, kind: String) -> void:
	var bs := BADGE_SIZE
	var edge: Color = fam["edge"]
	# 落点按**卡片**的边算，而徽章挂在 `layer` 上 ⇒ 先把 `layer` 被内缩的那层抬回去。
	# 不减这一层（brief 原值直接摆）就等于把"卡的坐标"当成了"layer 的坐标"：左上那枚只探出
	# 卡外 3px、右上那枚却探出 43px —— 一左一右明显不对称（实测量过，见 CARD_CONTENT_MARGIN）。
	var org := -CARD_CONTENT_MARGIN
	# 左上 = **家族徽章**（圆，家族色，只有图标）
	var fb := UIKit.badge_round(bs, Color(0.15, 0.17, 0.26), edge)
	fb.name = "card_badge_family"
	fb.position = org + Vector2(-bs * 0.42, -bs * 0.42)   # 同 `ItemCard._badge` 的落点：约六成在卡内
	layer.add_child(fb)
	var fl := UIKit.label(String(fam["glyph"]), int(bs * 0.42), edge)
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fb.add_child(fl)
	# 右上 = **卡型徽章**（色 + 图标 + 中文三通道）。36px 的**圆**塞不下「🚨 查寝」（4 个字形
	# ≈ 39px）⇒ 用**胶囊**（圆角 = 半高，视觉上仍是同一枚圆角徽章，与 `ItemCard._pill` 同族），
	# `bs` 只约束它的高。这一处与设计稿 §二 A.2 的"圆徽章"略有出入，理由就在上一行。
	var kin: Dictionary = GameData.CARD_KINDS.get(kind, {})
	if kin.is_empty():
		# `kind` 不在 `card_kind()` 的五类里（今天只有畸变公告那一路、kind 恒为 "aberr"）——
		# 它**没有"卡型"这一维**，家族徽章已经说明是畸变族 ⇒ 不画右徽章。
		#（设计稿 §3.2 给畸变写的那枚 🚨 是把查寝那行抄了过来，照画会在畸变卡上写"查寝"。）
		return
	var kc: Color = kin["color"]
	var kw := bs * 2.05
	var kb := UIKit.badge_pill(Vector2(kw, bs), Color(0.15, 0.17, 0.26), kc)
	kb.name = "card_badge_kind"
	kb.position = org + Vector2(CARD_SIZE.x - kw * 0.58, -bs * 0.42)
	layer.add_child(kb)
	var kl := UIKit.label("%s %s" % [kin["glyph"], kin["label"]], int(bs * 0.36), kc)
	kl.set_anchors_preset(Control.PRESET_FULL_RECT)
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kb.add_child(kl)

## 卡背：整张铺 CC0 的 Atlas 牌卡背图案 + **家族色**的底色 / 描边 / 光晕。
## ⚠ **卡背没有那块深色 `plate`**（它整张就是满铺格纹）—— 与卡面本来就不同，别"顺手统一"。
func _card_face_back(family: String) -> Control:
	var fam: Dictionary = GameData.CARD_FAMILIES[family]
	var edge: Color = fam["edge"]
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(
		fam["bg"], 18, edge, 3, 12, Color(edge.r, edge.g, edge.b, 0.12)))
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layer)
	layer.add_child(_make_card_art(family))
	return card
