extends SceneTree
## HUD 回归：右栏名册 + 底部操作坞**已拆**的反向契约 + 桌上实体入口（含「客户端视角」这一段）
##
## **v0.8.0 第三次改版**：**名册条（`game.roster_strip` / `game.roster_strip_rows`）整体删除**，
## 它承载的四件事搬到**桌面立牌**（"立在每名对手那一侧木纹带上、正对相机"的小方牌）。
## ⚠ **第四次复核：牌面改回原生 3D 画法** —— 用户 2026-10-06 否掉了"烘贴图"那条路
##（「人物铭牌不要这个贴图，一是尺寸不对，二是文字模糊」）⇒ 名册格那块 Control
##（`TableHud.make_chip`）/ 离屏 `SubViewport` / `set_placard_faces` **整体删除**，
## 牌面上的色片 / 名次 / 昵称 / 倒计时改由 `table_props._make_placard` 用
## `PlaneMesh` + `Label3D` 画（`game._refresh_placards` 只推数据）。
## ⇒ 本文件里**一切"量名册条在屏幕上怎么摆"的断言整段删除**（`roster_strip` 已经不是成员，
## 留着就是恒假的红条）；那部分覆盖新建在 **`tests/placard_test.gd`**（①~⑩）。
## 本文件从此只钉「我」那一条身家条（`corner_bars` 就剩它一条）。
##
## 为什么要有「客户端视角」：`s_state` 是 call_local，房主与客户端跑的是同一个处理函数，
## 差别只在「谁算出的状态」和 `my_peer`。所以喂一份状态、把 my_peer 设成客户端，
## 走的就是客户端那条路——比在本机拉两个实例更可靠（本机 UDP 端口常被环境拦掉）。
## godot --headless --path . --script tests/hud_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 房子薄牌的节点（按 **meta("tile")** 找，不按节点名 —— 同棋子的 `meta("peer")` 约定）。
func _house_node(houses_root: Node, idx: int) -> Node3D:
	if houses_root == null:
		return null
	for ch in houses_root.get_children():
		if (ch as Node).has_meta("tile") and int((ch as Node).get_meta("tile")) == idx:
			return ch as Node3D
	return null

## 房子薄牌的**正面**（贴等级纹理的那张方片）。
func _house_face(houses_root: Node, idx: int) -> MeshInstance3D:
	var h := _house_node(houses_root, idx)
	return h.get_node_or_null("Face") as MeshInstance3D if h != null else null

## 玩家弹窗里**渲染出来的 `ItemCard`**（批次 12 B2：背包一件 = 一张卡）。按**前序**返回，与背包顺序一致。
## `ic_script` 由调用方**运行时 `load`** 传进来 —— 静态写 `ItemCard` 会把 item_card.gd（→ ui_kit.gd，
## 引用了 autoload `Fx`）拽进本脚本的静态依赖链，在 `--script` 入口下整链编译失败（见上面那段说明）。
func _popup_item_cards(popup: Node, ic_script: GDScript) -> Array:
	var out: Array = []
	if popup == null:
		return out
	for n in popup._body.find_children("*", "", true, false):
		if n.get_script() == ic_script:
			out.append(n)
	return out

## 弹窗里所有 Label 的 text（前序）—— 找"名字 / 标签"这类文字的最强可观察量。
func _popup_labels(popup: Node) -> Array:
	var out: Array = []
	if popup == null:
		return out
	for n in popup._body.find_children("*", "Label", true, false):
		out.append(String((n as Label).text))
	return out

func _fresh_tiles() -> Array:
	var out := []
	for i in GameData.TILES.size():
		out.append({"owner": GameData.NO_OWNER, "level": 0})
	return out

## 一份 4 人、身家互不相同的状态：甲(最富) 乙 丙 丁(最穷)，轮到我(=乙) 行动
## 棋盘上第一格小卖部（进店状态需要一个真实格号：shop_open 必须 >= 0）
func _shop_tile() -> int:
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			return i
	return -1

func _state(turn_peer: int, with_shop: bool) -> Dictionary:
	var tiles := _fresh_tiles()
	var shop_idx := _shop_tile()
	var shops_d := {}
	if with_shop:
		shops_d[shop_idx] = {"slots": ["作弊器", "", ""]}
	# 给甲一块最贵的地（宿舍楼），让身家顺序与现金顺序不同 —— 名次必须按身家排
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].name) == "一号楼":
			tiles[i].owner = 1
			break
	return {
		"phase": "playing", "turn": turn_peer, "await": "roll", "await_peer": turn_peer,
		"roll_epoch": 1, "round": 3, "max_rounds": 30,
		"players": [
			{"peer": 1, "name": "甲", "color": 0, "bot": false, "money": 12000, "pos": 0,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 2, "name": "乙", "color": 1, "bot": false, "money": 20000, "pos": 3,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 3, "name": "丙", "color": 2, "bot": false, "money": 8000, "pos": 6,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 4, "name": "丁", "color": 3, "bot": false, "money": 100, "pos": 9,
				"alive": false, "skip": 0, "sleep": 0, "stamina": 0, "items": [{"id": "招财猫", "cd": 0}]},
		],
		"tiles": tiles, "shops": shops_d, "shop_open": shop_idx if with_shop else -1,
		"shop_peer": 2 if with_shop else 0, "black_peer": 0, "refresh_price": 500,
	}

## 房主侧名册（4 家，字段与 `game._build_hp` 对齐）。两个用途：
##  ① 房主 `_host_setup` 在开局 1.5 秒后会自己 `_broadcast_state()` 一次（见 game.gd:382），
##     而 `_broadcast_state` 要读 `hp[turn_i].peer` —— 名册为空时它抛
##     `SCRIPT ERROR: Out of bounds`（本批之前就挂着的噪声）。给一份**与 `_state()` 同形**的
##     名册（peer 顺序与 `_state()` 一致），那次自动广播就与测试自己喂的状态一致。
##  ② 「点手中牌」段要走真房主路径 `_use_item`，它读的就是这份名册（不是 st）。
func _host_roster() -> Array:
	var out := []
	var seeds := [[1, "甲", 0, 12000, 0, true], [2, "乙", 1, 20000, 3, true],
		[3, "丙", 2, 8000, 6, true], [4, "丁", 3, 100, 9, false]]
	for s in seeds:
		out.append({
			"peer": int(s[0]), "name": String(s[1]), "color": int(s[2]), "bot": false,
			"money": int(s[3]), "pos": int(s[4]), "alive": bool(s[5]), "skip": 0, "sleep": 0,
			"stamina": 3, "items": [], "item_used": false, "item_used_n": 0,
			"cheat_roll": -1, "hot_chain": 0, "cost_pen": [], "first_used": false,
			"roll_bonus": 0, "reroll_next": false, "silence": 0, "silence2": 0, "shield": 0,
			"charm_used": false, "emg_used": false, "loan_left": 0, "rework": 3,
		})
	return out

## 按 peer 找**「我」那条身家条**。**v0.8.0 第三次改版起 `corner_bars` 只剩这一条**
##（左/右/上三条四角条与后来的名册条都已删；其余人的信息搬上桌 ⇒ 桌面立牌，见
## `tests/placard_test.gd`）⇒ 这里只遍历 `corner_bars`。**不能按下标找**：条挂的是
## `_seat_peers()[0]`，自己不在名册里时会轮转到别人身上。
## 有意**不走 `game._hl_bars()`** —— 用生产代码那份清单来找，"高亮贴到了别的树上"这种错就查不出来了。
func _bar_of(g, peer: int) -> Dictionary:
	for b in g.corner_bars:
		if int((b as Dictionary).get("peer", GameData.NO_PEER)) == peer:
			return b
	return {}

## 某条身家条此刻"亮着"（可被选中）吗：读它**真的贴上去的那张样式盒**，判据是
## "这张描边图是不是 UIKit 按『可选中』那套参数（2px 金边 + 底色提亮一档）生成的那张"。
## `UIKit._rounded_tex` 按**参数**缓存 ⇒ 同参必得**同一个 Texture2D 实例**，所以身份比较成立。
## **不读任何内部标志**（那会在"高亮坏了但标志还对"时骗过断言），也不按文字 / 位置反推 ——
## 行动者那条（1px 金边）与它参数不同、纹理不同，不会被误判成亮着。
func _corner_bar_hot(_g, bar: Dictionary) -> bool:
	var root: Control = bar.get("root")
	if root == null or not is_instance_valid(root):
		return false
	var sb := root.get_theme_stylebox("panel")
	if not (sb is StyleBoxTexture):
		return false
	var UK = load("res://scripts/ui_kit.gd")
	var bg := Color(0.085, 0.095, 0.138, 0.82).lightened(0.10)
	var border := Color(UK.ACCENT.r, UK.ACCENT.g, UK.ACCENT.b, 0.9)
	var hot_sb: StyleBoxTexture = UK.card_stylebox(bg, 10, border, 2, 4)
	return (sb as StyleBoxTexture).texture == hot_sb.texture

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var net = root.get_node_or_null("Net")
	if net == null:
		printerr("  FAIL - 未找到 Net autoload")
		quit(1)
		return

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	# 名册为空时，房主 `_host_setup` 开局 1.5 秒后那次自动 `_broadcast_state()` 会读 `hp[turn_i]`
	# 越界（`SCRIPT ERROR: Out of bounds`，本批之前就有）。先种一份最小名册让那次广播成立。
	# `lab_mode` 只是让它的 `phase` 落在 "playing"（不跑回合循环的沙盒 = 道具试验场同一档），
	# 免得那一下被 `s_state` 当成对局结束、给 g 挂上结算层；`turn_i = 0`（peer 2 那份在 index 1，
	# 但后面几段会把 hp 换成 1 家的名册 —— 恒取 0 号位对两种规模都成立）。
	g.hp = _host_roster()
	g.turn_i = 0
	g.lab_mode = true
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	print("== 「我」的身家条（左下角，`corner_bars` 就剩这一条）==")
	# ⑩ 改结构：他人的**四角**身家条全删，只剩「我」这一条（左下角）。
	# **v0.8.0 第三次改版**：接手的**名册条也整体删除** —— 姓名 / 名次 / 棋子色小片 / 倒计时
	# 四件事搬到**桌面立牌**（3D 节点）。⇒ 本文件里"量名册条"的断言**整段删除**（那是恒假的红条），
	# 覆盖新建在 **`tests/placard_test.gd`**（逐块立牌 / 牌色 / 昵称 / 名次 / 落点 / 躺平 / 金边 /
	# 倒计时 / 命中链 / 点它开弹窗 / 幂等，见那边 ①~⑩）。**下面只钉「我」这一条**。
	# UIKit 一律**运行时 load**：静态写 `UIKit.X` 会把 ui_kit.gd 拽进本脚本的静态依赖链，
	# 而它引用了 autoload `Fx` —— 在 `--script` 入口下此时 autoload 还没注册，
	# 整链会以「Identifier not found: Fx」编译失败（同 layout_test 顶部那段说明）。
	var UK = load("res://scripts/ui_kit.gd")
	g.my_peer = 2
	g.s_state(_state(2, false))          # 走客户端真正跑的那个处理函数
	await process_frame

	# ---- 一期 Task 5：椅子顺序 == `game._seat_peers()`（**同一份顺序，别各写一份**）----
	# ① **必须放在 `g.s_state(...)` 之后**：座位是 `_refresh_players()` 喂进房间的，而它每次状态
	#    广播都跑（**不在 `_ready`** —— 那一刻 `st` 还空着、`_seat_peers()` 给空数组，
	#    名牌留成空且再没人重喂）。
	# ② **先断言 `_seat_peers()` 非空**：两边都是 `[]` 的话 `[] == []` 恒真，等于什么都没断言。
	# ③ 这条只能在**有 game 实例**的地方做（`layout_test` 是裸容器、没有 `st`）。
	print("== 一期 Task 5：椅子顺序 == game._seat_peers()（房间 ↔ 房主同一份顺序）==")
	var seat_peers: Array = g._seat_peers()
	_check(seat_peers.size() > 0, "（前提）房主的座位序非空（实得 %d 项）" % seat_peers.size())
	var room5: Node = g.table3d.get_node_or_null("Room") if g.table3d != null else null
	_check(room5 != null, "桌面上挂着 3D 房间（Room 节点）")
	# 牌面色取**各家的棋子色**（`p.color` → `GameData.PLAYER_COLORS`），**不是按座位序号取色**。
	# 这一份状态的 color 恰好等于 peer-1，而座位序是 [我, 下家, 对家, 上家] = [2,3,4,1]
	# ⇒ 座位 1 是 peer 3（color 2 → 绿）；**按序号取色**的话那块会是 PLAYER_COLORS[1]（蓝）⇒ 必红。
	# 【终审 F5】期望值必须**与实现同一条口径**：实现用的是 `clampi(color, 0, size-1)`，
	# 这里原先写的是 `% size` —— 今天 `p.color ∈ 0..3` 两者同值，但色号一旦越界，
	# 这条断言的期望色就与实现无关了（消息是给人看的，会误导下一个改色号的人）⇒ 照实现写钳位。
	#
	# **载体换过三次**：椅背名牌（一期）→ 头顶名牌（v0.8.0 三次改版）→ **桌面立牌**（四次改版；
	# 用户「人物顶部铭牌去掉」+「将屏幕左上角的玩家信息块移到桌面上」）。守的那件事
	# ——**色随 `p.color` 走、不随座位序号走**——**一次都没变**。今天它读的是
	# **牌面上那枚棋子色小片**（`table_props._placards[peer].chip_mat.albedo_color`）——
	# 第四次复核把"烘好的那块牌面（`game.placard_chips`）"整体删了，牌面改成原生 3D 元素，
	# 小片色是 `_fill_placard` 直接写进材质里的 ⇒ 读**真的贴上去的那个色**（比读色号更硬）。
	if room5 != null:
		var in_room: Array = room5.seat_peers()
		_check(in_room == seat_peers,
			"椅子顺序 == game._seat_peers()（房间 %s / 房主 %s —— 各写一份就会在二期坐错位）"
				% [str(in_room), str(seat_peers)])
		var colors_ok := true
		var got_colors: Array = []
		var n_chips := 0
		var placards: Dictionary = g.table3d.table_props._placards
		for i in seat_peers.size():
			if i == 0:
				continue                        # slot 0 =「我」⇒ 桌上没有我的牌（同"我那一侧不出人"）
			var pl5: Dictionary = g._state_player(int(seat_peers[i]))
			var want: Color = GameData.PLAYER_COLORS[
				clampi(int(pl5.get("color", 0)), 0, GameData.PLAYER_COLORS.size() - 1)]
			# ⚠ 小片的载体是 `Chip`（`PlaneMesh`），它的材质色由 `table_props._fill_placard`
			# 按 `clampi(color, 0, size-1)` 取 `GameData.PLAYER_COLORS` 写进去
			# ⇒ 这里比的是那个 `Color` 本身，而期望色**与实现同一条钳位口径**（【终审 F5】）。
			var got := Color(-1.0, -1.0, -1.0)
			var found := false
			var pl_d = placards.get(int(seat_peers[i]), {})
			if not (pl_d as Dictionary).is_empty():
				found = true
				got = ((pl_d as Dictionary)["chip_mat"] as StandardMaterial3D).albedo_color
			got_colors.append(str(got))
			n_chips += 1
			if not found or not got.is_equal_approx(want):
				colors_ok = false
		_check(n_chips == 3 and colors_ok,
			"桌面立牌的牌面按**各家的棋子色**上色（座位 1..3 → 实得 %s，期望与 `p.color` 同源；"
				% str(got_colors)
				+ "按座位序号取色的话座位 1 会是蓝、这里是绿）")

	# ---- 二期 Task 2：**角色顺序 == `game._seat_peers()`**（房间 ↔ 房主同一份顺序）----
	# ① **必须在 `g.s_state(...)` 之后**（同上一条）：角色是 `_refresh_players()` 喂进房间的
	#    （**不在 `_ready`** —— 那一刻 `st` 还空着、座位序给空数组）。
	# ② **先断言 `_seat_peers()` 非空**：两边都是 `[]` 的话 `[] == []` 恒真，等于什么都没断言
	#    （一期就踩过这个坑，所以这里连着断言两次）。
	# ③ 期望值 = 房主那份座位序**把第 0 位换成 `NO_PEER`**：`slot 0` 是「我」，**不渲染**（spec §5.1）
	#    ⇒ 角色层在那一格记的是"空位"。**除第 0 位外逐位相等**才是"没人坐错椅子"的可执行版。
	print("== 二期 Task 2：角色顺序 == game._seat_peers()（房间 ↔ 房主同一份顺序）==")
	_check(seat_peers.size() > 0, "（前提）房主的座位序非空（实得 %d 项）" % seat_peers.size())
	var chars5: Node = room5.get_node_or_null("Chars") if room5 != null else null
	_check(chars5 != null, "桌面的房间下挂着角色层（`Room/Chars`，二期）")
	if chars5 != null and seat_peers.size() > 0:
		var want: Array = seat_peers.duplicate()
		want[0] = GameData.NO_PEER          # slot 0 = 我 ⇒ 不出人
		var got: Array = chars5.char_peers()
		_check(got.size() > 0 and got == want,
			"**角色顺序 == `game._seat_peers()`**（房主 %s / 角色层 %s —— 第 0 位是「我」、记作空位；"
				% [str(seat_peers), str(got)]
				+ "各写一份顺序就会在二期坐错位）")
		# 每个座位上那个模型 = **那一家棋子色**对应的模型（`p.color` → `CHAR_MODELS_BY_COLOR`），
		# **不是按座位序号取模型**。这一份状态 color = peer-1、座位序 = [2,3,4,1] ⇒ 座位 1 是
		# peer 3（color 2 → 模型 n）；**按座位序号取**的话会是 `CHAR_MODELS_BY_COLOR[1]`（模型 g）⇒ 必红。
		var models_ok := true
		var got_models: Array = []
		for i in seat_peers.size():
			var pl: Dictionary = g._state_player(int(seat_peers[i]))
			var want_m: String = "" if i == 0 else chars5.model_for_color(int(pl.get("color", 0)))
			var got_m: String = chars5.char_model(i)
			got_models.append(got_m)
			if got_m != want_m:
				models_ok = false
		_check(models_ok,
			"每个座位上的角色 = **那一家的棋子色**对应的模型（逐座位实得 %s；slot 0 为空）"
				% str(got_models))

	var bars: Array = g.corner_bars
	_check(bars.size() == 1, "四角条**只剩「我」这一条**（实得 %d）" % bars.size())
	_check((bars[0].root as Control).visible, "我这条可见")
	# 「只剩一条」本身就是"他人的三条已删"的可观察证据：条数写死 1 之后，谁把四角条加回四条这里立刻红。
	# 批次 12 D 之前这条是 4（角位 = 桌位：自己打头、其余按行动序）—— 那是**别人的**信息，
	# 曾经改挂在名册条上，**v0.8.0 第三次改版起改挂桌面立牌**（见 `tests/placard_test.gd`）。
	_check(int(bars[0].peer) == 2, "我这条挂的是我（乙，实得 %d）" % int(bars[0].peer))
	# 反向契约：**三层载体**都必须从 game 上**删净**（同时留着就是重复：都挂"名次+名字+身家"）：
	#   * `roster_box` / `roster_rows` —— 最早的右栏名册（批次 5 Task 3 删）；
	#   * `roster_strip` / `roster_strip_rows` —— 后来的名册条（**v0.8.0 第三次改版删**，信息搬上桌）。
	# 一律用 `g.get()` 读 —— 成员真删掉时它返回 null（直接写 `g.roster_strip` 会因标识符不存在而报错）。
	_check(g.get("roster_box") == null and g.get("roster_rows") == null \
			and g.get("roster_strip") == null and g.get("roster_strip_rows") == null,
		"名册三层载体都已从 game 上删净（roster_box / roster_rows / roster_strip / roster_strip_rows）")

	# ---- 桌面立牌（v0.8.0 第三次改版：**名册条整体删除**，信息搬上桌）----
	# 立牌**可见的那一块**是 3D 节点、挂在 `table3d.table_props` 下（第四次复核起牌面是
	# `BoxMesh` + `Label3D` 画的原生 3D 元素，**不经过任何不上屏的 Control**）⇒ 屏幕上再没有
	# "一格名册行"可量。
	# 那部分覆盖**整段搬去 `tests/placard_test.gd`**：
	#   ① 三个人各一块立牌、没有「我」那块；② 牌色随 `p.color` 走（不随座位序号）；③ 昵称 / 名次；
	#   ④ 落点在自己那一侧、不压地块；⑤ 整块正对相机（billboard）；⑥ 金边（选目标）；
	#   ⑦ 行动者倒计时（`Track`/`Bar`）；⑧ 命中链（`placard_hit`）；⑨ 点它开弹窗；⑩ 幂等 / 收掉。
	# 本文件只保留**与"我这条身家条"同源**的那几条（名次徽章 / 身家 / 现金 / 能量 / 高亮）。
	# 名次徽章上的数字就是身家名次。身家 = 现金 + 地产；甲 12000 + 一号楼地价(3800) = 15800，
	# 于是 乙(20000) > 甲(15800) > 丙(8000) > 丁(100)。
	var rank_of := func(b: Dictionary) -> int:
		var badge = b.get("badge")
		if badge == null or not is_instance_valid(badge):
			return -1
		for c in (badge as Control).get_children():
			if c is Label:
				return int(String((c as Label).text))
		return -1
	_check(rank_of.call(bars[0]) == 1, "乙（我）身家最高 = 名次 1（实得 %d）" % rank_of.call(bars[0]))
	# 身家读数：期望值按**数据表**在测试里自己算一遍（与 game 的 `_state_worth` / 房主的
	# `_net_worth` 同一公式：现金 + 名下地皮的地价）。写死"20,000"会随地产价格调整假红。
	var worth_of := func(peer: int, cash: int) -> int:
		var v := cash
		var st_w: Array = g.st.tiles
		for i in mini(st_w.size(), GameData.TILES.size()):
			if int(st_w[i].get("owner", GameData.NO_OWNER)) == peer:
				v += int(GameData.TILES[i].price)
		return v
	_check(String(bars[0].worth_l.text) == GameData.fmt_money(worth_of.call(2, 20000)),
		"我这条的身家 = 现金 + 地产（实得「%s」）" % String(bars[0].worth_l.text))
	# 名册格那几条（有没有身家 / 现金行、徽章位、不标「我」、破产字样、非行动者不变金）**随载体一起删**：
	# 那些量的是一格已经不存在的 Control。名次徽章 / 昵称 / 棋子色小片现在长在**桌面立牌**上，
	# 覆盖见 `tests/placard_test.gd` ②③（牌色 / 昵称 / 名次）与 ⑥（金边 = 选目标高亮）。
	_check(String(bars[0].name_l.text).contains("乙") and String(bars[0].name_l.text).contains("（我）"),
		"自己那条标「（我）」（实得「%s」）" % String(bars[0].name_l.text))
	# 轮到谁行动：我这条的名字变金（"该你了"提示，与倒计时行同一件事）
	_check((bars[0].name_l as Label).get_theme_color("font_color") == UK.ACCENT,
		"行动者（我）那条名字变金")
	# 现金那一行（修复波 B）：身家 = 现金 + 地产，只报身家时买卖 / 付租看不到自己有多少现金。
	# 期望值同样按**数据表**算（写死金额会随起始资金调整假红）。
	var cash_of := func(peer: int) -> int:
		return int(g._state_player(peer).get("money", 0))
	_check(String(bars[0].money_l.text) == "现金 " + GameData.fmt_money(cash_of.call(2)),
		"我这条写了现金（实得「%s」，期望 %s）" % [String(bars[0].money_l.text),
			GameData.fmt_money(cash_of.call(2))])
	# ---- 能量行（⑩5：我这条加一行「能量」）----
	# 批次 7 删了桌上的体力件、批次 9 把它收进玩家道具弹窗之后，体力要"点开弹窗"才读得到；
	# 现在自己这条常驻条上直接读。视觉语言与弹窗那排小格同一套（亮金 / 熄灭 + 圆角）。
	_check(String(bars[0].energy_l.text) == "能量 3",
		"我这条写了能量读数（实得「%s」）" % String(bars[0].energy_l.text))
	var pips: Array = bars[0].pips
	_check(pips.size() == 5, "能量小格数 = 体力上限（5，实得 %d）" % pips.size())
	var lit := 0
	for pp in pips:
		var sb := (pp as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null and sb.bg_color.is_equal_approx(Color(0.95, 0.78, 0.35)):
			lit += 1
	_check(lit == 3, "点亮的小格数 = 当前体力（3，实得 %d）" % lit)
	# 能量跟着 st 走：喂 5 点 + 一件「充电宝」（上限 +1）⇒ 读数与小格数都要跟着变
	var s_en: Dictionary = _state(2, false)
	for p in s_en.players:
		if int(p.peer) == 2:
			p.stamina = 5
			p.items = [{"id": "充电宝", "cd": 0}]
	g.s_state(s_en)
	await process_frame
	_check(String(bars[0].energy_l.text) == "能量 5",
		"能量读数跟着 st 走（实得「%s」）" % String(bars[0].energy_l.text))
	_check((bars[0].pips as Array).size() == 6, "「充电宝」把上限提到 6 ⇒ 小格数跟着变（实得 %d）"
		% (bars[0].pips as Array).size())
	g.s_state(_state(2, false))
	await process_frame
	# ---- 批次 13 ⑥ 回归：飞钞终点必须用**当帧**的条绑定（不是上一次广播的旧绑定）----
	# 判据：喂一份"我这条金额变了"的状态 ⇒ 终点 = 我这条**当帧**的中心。旧实现把飞钞播在
	# `_refresh_corner_bars` **之前** ⇒ 终点取到的是**旧绑定**；修法挪到刷完之后 ⇒ 当帧。
	#（`_money_fly_goal` 是 `_spawn_money_fly` 写的观测点。）
	# **v0.8.0 第三次改版**：名册条删除后 `_corner_bar_screen_center` 只剩「我」这一条找得到
	#（别人的落点退回棋子那一点）⇒ 这条判据从"名次重排后的丙那一行"改指**我这一条**，
	# 接线本身（`_refresh_players` 里飞钞最后播）一个字没改。
	var s_fly: Dictionary = _state(2, false)
	for p in s_fly.players:
		if int(p.peer) == 2:
			p.money = 26000     # 我 20000 → 26000：金额变了 ⇒ 一次飞钞
	g.s_state(s_fly)
	await process_frame
	var want_fly = g._corner_bar_screen_center(2)
	_check(want_fly != null, "（前置）我这条可见、拿得到它的中心")
	_check(g._money_fly_goal.has(2) and want_fly != null
			and (g._money_fly_goal[2] as Vector2).is_equal_approx(want_fly as Vector2),
		"飞钞终点 = 我这条当帧的中心（实得 %s / 期望 %s）"
			% [str(g._money_fly_goal.get(2)), str(want_fly)])
	_check(int(_bar_of(g, 2).get("peer", 0)) == 2, "按 peer 仍找得到我这一条")
	g.s_state(_state(2, false))
	await process_frame
	# 写死的条尺寸必须装得下内容：内容更大会把面板撑大（并把它朝上顶）。
	# 常驻占位（倒计时行）保证条的行高恒定 —— 行动者换人时不会一开一合。
	var TH = load("res://scripts/table_hud.gd")
	var root_c: Control = bars[0].root
	# 量内容真实需要的高度：**把写死的那份先清零**再问 —— `get_combined_minimum_size()`
	# 会把 `custom_minimum_size` 也并进去，不清零就永远等于那个写死的数、看不出内容撑不撑破。
	var keep: Vector2 = root_c.custom_minimum_size
	root_c.custom_minimum_size = Vector2.ZERO
	var content_max: float = root_c.get_combined_minimum_size().y
	root_c.custom_minimum_size = keep
	_check(is_equal_approx(root_c.size.y, TH.CORNER_BAR_SIZE.y) \
			and is_equal_approx(root_c.size.x, TH.CORNER_BAR_SIZE.x),
		"我这条尺寸 = CORNER_BAR_SIZE（实得 %s）" % str(root_c.size))
	print("    [实测] 我这条内容最小高 %.1f / CORNER_BAR_SIZE %s" % [content_max, str(TH.CORNER_BAR_SIZE)])
	_check(content_max <= TH.CORNER_BAR_SIZE.y + 0.01,
		"写死的高度装得下内容（内容最小高 %.1f ≤ %.1f）" % [content_max, TH.CORNER_BAR_SIZE.y])
	# **名册行那一段整体删除**（逐行量最小高 / 行间不相交 / 与「暂停」同 y 带 / 整条在屏幕左半 /
	# 每一格在按钮右侧 / 横排同 y —— 量的都是一格已经不存在的 Control）。立牌是世界单位的 3D 节点、
	# 受木纹带宽度的几何约束（`table_props.PLACARD_SIZE` 那段），落点判据在
	# `tests/placard_test.gd` ④（自己那一侧的木纹带里、不压地块）。
	# 「我」这条不许挡住角按钮（左上暂停 / 右上战报 / 右上规则说明），也不许出屏。
	var overlap_bad := 0
	var off_screen := 0
	var r0: Rect2 = (bars[0].root as Control).get_global_rect()
	if r0.position.x < 0.0 or r0.position.y < 0.0 \
			or r0.end.x > g.size.x or r0.end.y > g.size.y:
		off_screen += 1
	for btn in [g.opt_btn, g.log_toggle, g.rules_btn]:
		if btn != null and is_instance_valid(btn) and r0.intersects((btn as Control).get_global_rect()):
			overlap_bad += 1
	print("    [实测] 身家条 peer %d：%s（面板 %s）" % [int(bars[0].peer), r0, root_c.size])
	print("    [实测] 角按钮：暂停 %s / 战报 %s / 规则 %s" % [
		(g.opt_btn as Control).get_global_rect(), (g.log_toggle as Control).get_global_rect(),
		(g.rules_btn as Control).get_global_rect()])
	_check(off_screen == 0, "我这条完整落在屏幕内（出屏 %d 条）" % off_screen)
	_check(overlap_bad == 0, "我这条没挡住角按钮（暂停/战报/规则说明，重叠 %d 处）" % overlap_bad)
	# 「我」那条身家条的底边与右下角「转动转盘」按钮的底边平齐（用户 ② 明写）
	_check(is_equal_approx((bars[0].root as Control).get_global_rect().end.y,
			(g.action_btn as Control).get_global_rect().end.y),
		"自身身家条底边与「转动转盘」按钮底边平齐（实得 %.0f / %.0f）"
			% [(bars[0].root as Control).get_global_rect().end.y,
				(g.action_btn as Control).get_global_rect().end.y])
	g.table3d.snap_view(0.0)
	await process_frame

	print("== 顶部控件：规则说明搬到战报旁 / 畸变横幅居中（批次 12 D2 + D3）==")
	# ⑩4：「规则说明」按钮从左上角搬到右上角、与「战报」并列
	var rb: Rect2 = (g.rules_btn as Control).get_global_rect()
	_check(rb.get_center().x > g.size.x * 0.5 and rb.position.y < g.size.y * 0.2,
		"「规则说明」按钮在**右上角**（实得 %s）" % str(rb))
	_check(absf(rb.get_center().y - g.log_toggle.get_global_rect().get_center().y) <= 2.0,
		"与「战报」同一条水平线（并列，实得 y %.1f / %.1f）"
			% [rb.get_center().y, g.log_toggle.get_global_rect().get_center().y])
	_check(not rb.intersects(g.log_toggle.get_global_rect()), "两枚按钮不重叠")
	# 展开战报栏 → 不许压住「我」那条身家条（⑩ 明写「身家条与展开的战报栏不许打架」）。
	# **名册条那半随载体退场**：立牌可见的那一块是 3D 节点（原生 3D 牌面，不在屏幕层）⇒ 与屏幕层的
	# 战报栏天然不同层。立牌不压地块 / 不飘出桌子由 `tests/placard_test.gd` ④ 守。
	g._toggle_log()
	await process_frame
	_check(g.log_panel.visible, "（前置）战报栏已展开")
	var lp: Rect2 = (g.log_panel as Control).get_global_rect()
	_check(not lp.intersects((bars[0].root as Control).get_global_rect()),
		"展开的战报栏不压「我」这条身家条（战报 %s / 条 %s）"
			% [str(lp), str((bars[0].root as Control).get_global_rect())])
	g._toggle_log()
	await process_frame
	_check(not g.log_panel.visible, "再点一次收起")
	# ⑫：畸变横幅从右上角搬到**顶部水平居中**（"中间" = 不再贴角，不是屏幕正中）
	var s_ab: Dictionary = _state(2, false)
	s_ab["aberrations"] = [{"id": "断网", "left": 3}]
	g.s_state(s_ab)
	await process_frame
	_check(g.ab_label.visible, "有畸变时横幅显示")
	var abr: Rect2 = (g.ab_label as Control).get_global_rect()
	_check(absf(abr.get_center().x - g.size.x * 0.5) <= 4.0,
		"横幅**水平居中**（中心 x %.1f / 屏心 %.1f）" % [abr.get_center().x, g.size.x * 0.5])
	_check(abr.position.y >= 0.0 and abr.end.y <= 52.0,
		"横幅在屏幕上方、战报气泡（y 从 52 起）之上（实得 y %.1f..%.1f）" % [abr.position.y, abr.end.y])
	# **名册条那两问随载体一起删**（`roster_strip` 不是成员了）：立牌可见的那一块是 3D 节点、
	# 顶部横幅是屏幕层控件 —— 两者不同层，不存在"重叠"这件事可言。
	var ab_hit := 0
	for other in [g.log_toggle, g.opt_btn, g.rules_btn]:
		if (other as Control).visible and abr.intersects((other as Control).get_global_rect()):
			ab_hit += 1
	_check(ab_hit == 0, "横幅不与三个角按钮重叠（重叠 %d 处）" % ab_hit)
	s_ab["aberrations"] = []
	g.s_state(s_ab)
	await process_frame
	_check(not g.ab_label.visible, "没有畸变时横幅收起")

	print("== 客户端视角：行动者不是我 ==")
	g.my_peer = 9                         # 观战/掉线后重连之类：自己不在名册里
	g.s_state(_state(1, false))
	await process_frame
	_check((g.corner_bars[0].root as Control).visible, "自己不在名册里也不崩、我这条仍在")
	# 「（我）」标记只挂在**自己那一条**上（`_fill_peer_bar` 的 `is_self`）：自己不在名册里时
	# 那一条轮转成了别人 ⇒ 屏幕上不该有任何「（我）」。名册条已删 ⇒ 只剩这一处可查。
	var marked: Array = ([g.corner_bars[0]] as Array).filter(
		func(b) -> bool: return String(b.name_l.text).contains("（我）"))
	_check(marked.is_empty(), "自己不在名册时没人被误标「（我）」")
	# 自己不在名册 ⇒ 从第 0 家起轮转：我这条挂甲
	_check(int(g.corner_bars[0].peer) == 1,
		"自己不在名册时从第 0 家起轮转（我这条 = 甲，实得 %d）" % int(g.corner_bars[0].peer))
	_check((g.corner_bars[0].name_l as Label).get_theme_color("font_color") == UK.ACCENT,
		"轮到甲时他的名字变金")

	print("== 身家条缓存：状态没变不重建 ==")
	var sig_before: String = g._corner_sig
	g.s_state(_state(1, false))
	await process_frame
	_check(g._corner_sig == sig_before, "同一状态重复广播不复算（签名不变）")

	print("== 底部操作坞已拆（批次 3 Task 6）：底栏没有，玩法入口还在 ==")
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	# 反向契约：坞的成员（含状态条）必须从 game 上**删净**，而不是留成一块不可见的空壳。
	# 一律用 g.get() 读 —— 成员真删掉时它返回 null；直接写 g.mat_bar 会因标识符不存在而报错。
	var gone: Array = []
	for n in ["mat_bar", "action_bar", "dock_plate", "roll_btn", "use_phase_btn", "item_btn_box",
			"status_label", "ph1_lab", "ph2_lab", "ph1_pill", "ph2_pill", "ph_arrow_l"]:
		if g.get(n) != null:
			gone.append(n)
	_check(gone.is_empty(), "底部操作坞的成员已删净（残留：%s）" % str(gone))
	# 另一半：坞拆了，**玩法入口**必须还在 —— 批次 7 起掷轮的落点是右下角动作按钮
	#（坞里的 roll_btn / use_phase_btn 早就 visible=false，牌垫上那两枚也已在批次 7 退场）。
	_check(g.action_btn != null and g.action_btn.visible \
			and String(g.action_btn.text) == "转动转盘",
		"右下角动作按钮仍在（掷轮入口，实得「%s」）"
			% ("无" if g.action_btn == null else String(g.action_btn.text)))
	# 陷阱：`_process` 原有一句 `if mat_bar == null: return` 的**提前返回**。只删构建、不删守卫的话，
	# `_process` 后半段（小卖部 / 黑市 / 操作倒计时 / 开发者面板）会**静默**不再执行。
	# 这里用「倒计时仍被推进到身家条」把后半段钉住（簇的推送在 `_process` 最末）。
	# **v0.8.0 第三次改版**：`_op_owner` 换成**我**（peer 2）—— 倒计时在屏幕上只剩「我」这条身家条
	# 一个落点（别人的那一条在**桌面立牌**上，判据见 `tests/placard_test.gd` ⑦）。
	g.s_op_timer("roll", 30.0, 30.0, 2)
	g._process(0.0)
	await process_frame
	var cbg2: Dictionary = _bar_of(g, 2)
	_check(not cbg2.is_empty() and (cbg2.timer_kind as Label).visible,
		"_process 的后半段仍在跑（倒计时没被提前返回吞掉）")
	g.s_op_timer("", 0.0, 0.0, -1)
	g._process(0.0)

	print("== 小卖部全屏层照旧（坞拆了与它无关）==")
	g.s_state(_state(2, true))            # shop_peer = 我
	g._process(0.0)
	await process_frame
	_check(g.shop_layer.visible, "小卖部全屏界面可见")

	print("== 战报：默认收起 + 消息在屏幕上方弹出 ==")
	_check(not g.log_panel.visible, "战报框默认收起")
	_check(String(g.log_toggle.text).contains("▾"),
		"收起时按钮显示「战报 ▾」（实得「%s」）" % String(g.log_toggle.text))
	_check(g.log_toast != null, "顶部弹出条容器已建")
	# 前面的几次 s_state 本身就产生过战报（走的是真实链路 _log → s_log），
	# 所以这里按「末条内容」断言，不依赖总数
	g._push_log_toast("[color=#74d188]甲 买下了便利店，花了 ¥1,600[/color]")
	await process_frame
	await process_frame
	var tn: int = g.log_toast.get_child_count()
	var last: Control = null
	var last_text := ""
	if tn > 0:
		last = g.log_toast.get_child(tn - 1)
		var rtls: Array = last.find_children("*", "RichTextLabel", true, false)
		if not rtls.is_empty():
			last_text = String((rtls[0] as RichTextLabel).text)
	_check(last_text.contains("便利店"),
		"战报消息会在屏幕上方弹出（末条 = 「%s」）" % last_text)
	# 宽度这条是防回归：RichTextLabel 的最小宽度默认是 0，若忘了关自动换行，
	# 气泡会被 SHRINK_CENTER 挤成一条几乎不可见的窄条（视觉上等于没有）。
	_check(last != null and last.size.x > 50.0,
		"弹出条裹得住文字而非被挤成窄条（实得 %.0f）" % (0.0 if last == null else last.size.x))
	for i in 6:
		g._push_log_toast("刷屏消息 %d" % i)
	await process_frame
	_check(g.log_toast.get_child_count() == 4,
		"连发刷屏时最多只留 4 条（实得 %d）" % g.log_toast.get_child_count())

	print("== 装修房子：4 级 + 等级配色 + 3D 薄牌（批次 11 Task 2） ==")
	_check(GameData.MAX_LEVEL == 4, "装修上限 4 级（实得 %d）" % GameData.MAX_LEVEL)
	_check(GameData.level_color(1) == Color(0.42, 0.80, 0.45), "1 级 = 绿")
	_check(GameData.level_color(2) == Color(0.36, 0.63, 0.94), "2 级 = 蓝")
	_check(GameData.level_color(3) == Color(0.68, 0.48, 0.92), "3 级 = 紫")
	_check(GameData.level_color(4) == Color(0.98, 0.80, 0.32), "4 级 = 金")
	_check(GameData.level_name(0) == "未装修" and GameData.level_name(4) == "金",
		"格详情卡的装修文案跟着等级走")
	_check(GameData.level_color(9) == GameData.level_color(4), "越界等级钳到 4 级（不越界崩）")
	# 2D 的 `HouseIcon` 整套已删（批次 11 Task 2 搬进 3D 的 `TableProps`）——这里改读**桌面上那块
	# 薄牌**：走真入口（`s_state` → 广播 → `_refresh_houses`），判据是"贴上去的材质/纹理"。
	var tpH = g.table3d.table_props
	if tpH == null or not tpH.has_method("set_houses"):
		_check(false, "TableProps 没有 set_houses（房子还没搬进来），本段整段跳过")
	else:
		var tiles_h: Array = _fresh_tiles()
		tiles_h[3].level = 3
		var st_h: Dictionary = _state(2, false)
		st_h.tiles = tiles_h
		g.s_state(st_h)
		await process_frame
		var hroot_h: Node = tpH.get_node_or_null("Houses")
		_check(hroot_h != null and hroot_h.get_child_count() == GameData.TILES.size(),
			"每格一块房子薄牌（实得 %d）"
				% (0 if hroot_h == null else hroot_h.get_child_count()))
		var h3: Node3D = _house_node(hroot_h, 3)
		var f3: MeshInstance3D = _house_face(hroot_h, 3)
		_check(h3 != null and h3.visible, "有等级的那格立起了房子薄牌")
		var m3: StandardMaterial3D = f3.material_override as StandardMaterial3D if f3 != null else null
		_check(m3 != null and m3.albedo_texture != null,
			"房子正面贴的是**烘出来的等级纹理**（读贴上去的材质，不是内部标志）")
		_check(m3 != null and m3.albedo_texture == tpH.house_tex(3),
			"贴的正是 3 级那一张（与 house_tex(3) 同源）")
		_check(m3 != null and m3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			"房子正面是 ALPHA_SCISSOR（透明边裁掉、仍在不透明队列里写深度/投影，实得 %s）"
				% str(m3.transparency if m3 != null else -1))
		# 等级归零 ⇒ 收起（无主 / 未装修不上房子）
		tiles_h[3].level = 0
		st_h.tiles = tiles_h
		g.s_state(st_h)
		await process_frame
		_check(h3 != null and not h3.visible, "等级归零后房子收起（无主/未装修不上房子）")

	print("== 收租飘字：红/绿两条不能叠在一起 ==")
	# 先把四位玩家的金额刷成基线（与 _state 一致），保证下一步的 diff 只来自这两家
	g.my_peer = 2
	g.s_state(_state(2, false))
	await process_frame
	# 模拟「甲 走到 乙 的地、付 500 租金」：同一帧里一个 -500、一个 +500，
	# 这正是当初两条飘字叠在一起的场景（都以各自棋子为中心，全景缩放下两棋子很近）
	var s2: Dictionary = _state(2, false)
	for p in s2.players:
		if int(p.peer) == 1:
			p.money = 11500
		elif int(p.peer) == 2:
			p.money = 20500
	g.s_state(s2)
	await process_frame
	var floats: Array = []
	for c in g.get_children():
		if c is Label and (c as Label).z_index == 90:
			floats.append(c)
	_check(floats.size() >= 2, "同一帧产生两条金额飘字（实得 %d）" % floats.size())
	if floats.size() >= 2:
		var fa := floats[floats.size() - 2] as Label
		var fb := floats[floats.size() - 1] as Label
		var dy: float = absf(fa.position.y - fb.position.y)
		_check(dy >= 30.0, "两条飘字纵向错开 ≥30px、不再叠住（实得 %.0f）" % dy)
	else:
		_check(false, "同一帧产生两条金额飘字（不足以比较位置）")

	print("== 抽卡演出：在屏幕层大字演、**相机全程不动**（批次 8）==")
	# 批次 8 的判据就一句：演出前后 2D 相机的缩放与注视点**完全相同**。
	# 旧版会把 `_zoom` 推到 ≥2× 全景（DECK_PUSH_FACTOR）—— 那一推让印在桌垫上的图案整体放大滑动，
	# 而手牌是不跟 2D 相机的实物 ⇒ 明显错位（用户 ① 报的就是它）。
	g.board.cam_locked = false
	g.board.fit_overview(true)
	await process_frame
	var z_before: float = g.board._zoom
	var c_before: Vector2 = g.board._center
	_check(g.deck_reveal != null, "屏幕层抽卡演出组件已建（TableHud.build_play_ui）")
	g.deck_reveal.show_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
	await process_frame
	_check(g.deck_reveal.is_showing(), "抽卡演出已开始")
	g.deck_reveal.tick(g.deck_reveal.HOLD * 0.5)   # 推进到停留段中途
	await process_frame
	_check(absf(g.board._zoom - z_before) < 0.001,
		"演出期间 2D 相机缩放一动不动（实得 %.3f / 演出前 %.3f）" % [g.board._zoom, z_before])
	_check(g.board._center.distance_to(c_before) < 0.001,
		"演出期间 2D 相机注视点一动不动（实得 %s / 演出前 %s）" % [g.board._center, c_before])
	# ---- 批次 12 C2：HOLD 之后**不再自动收**，停在"等确定"上 ----
	# `CARD_TIME` 的定义也一并改了口径（= 前三段之和，"停在哪儿"的判据），这里钉住它。
	_check(is_equal_approx(g.deck_reveal.CARD_TIME,
			g.deck_reveal.OUT + g.deck_reveal.FLIP + g.deck_reveal.HOLD),
		"CARD_TIME = 前三段之和（BACK 已移出，只留给收尾相位）")
	g.deck_reveal.tick(g.deck_reveal.CARD_TIME + 0.1)
	_check(g.deck_reveal.is_showing() and g.deck_reveal.is_awaiting_confirm(),
		"推过 CARD_TIME 后**不自动收**：停在「等确定」上")
	_check(not g.deck_reveal.is_confirm_visible(),
		"不是该确认的人（操作窗口归属不是我）→ 「确定」按钮不出镜")
	g.deck_reveal.set_can_confirm(true)
	_check(g.deck_reveal.is_confirm_visible(),
		"该确认的人 → 「确定」按钮出镜（观众看到同一张卡但没按钮）")
	# 收卡只有一条路：房主广播的 `s_card_close`（超时 / 托管同样汇到这里）
	g.deck_reveal.request_close()
	_check(not g.deck_reveal.is_confirm_visible(), "收到收卡请求后按钮先收掉")
	g.deck_reveal.tick(g.deck_reveal.BACK + 0.05)
	_check(not g.deck_reveal.is_showing(), "收到收卡请求 → 走完 BACK 相位后收回")
	# 设计 §6 的后半：不能只把 is_showing 置假 —— 节点要真回收、层要真隐藏。
	_check(g.deck_reveal._card == null and not g.deck_reveal.visible,
		"演出结束卡片已回收（不是只把 is_showing 置假：_card 已清、层已隐藏）")
	# ---- 批次 12 C3：卡源多认一种（道具卡面），其余一字不差 ----
	g.deck_reveal.show_card("失物招领", "good", "【失物招领】捡到了【招财猫】！", "招财猫")
	await process_frame
	_check(g.deck_reveal.is_showing(), "道具卡面也能演（show_card 收第 4 个参数 = 道具 id）")
	var IC = load("res://scripts/item_card.gd")
	var ic_found := 0
	for n in g.deck_reveal.find_children("*", "", true, false):
		if n.get_script() == IC:
			ic_found += 1
	_check(ic_found == 1, "卡面就是那张 `ItemCard`（与货架 / 手牌 / 弹窗同一张卡，实得 %d 张）" % ic_found)
	g.deck_reveal.request_close()
	g.deck_reveal.tick(g.deck_reveal.BACK + 0.05)
	_check(not g.deck_reveal.is_showing(), "道具卡面同一条收尾路径")

	# 反向契约：旧那套"演在画布上"的接口必须**真的没了**（不留空壳）
	_check(not g.board.has_method("play_deck_card"), "BoardView.play_deck_card 已退场")
	_check(not g.board.has_method("is_showing_deck_card"), "BoardView.is_showing_deck_card 已退场")
	_check(not g.board.has_method("focus_point_zoom"), "focus_point_zoom 已退场（唯一调用方是抽卡推近）")
	var B1 = load("res://scripts/board_view.gd")
	_check(not B1.get_script_constant_map().has("DECK_PUSH_FACTOR"), "DECK_PUSH_FACTOR 常量已删")
	# z 层级（批次 8 审查 R5）：卡绝不能盖在模态面板上 —— 房主暂停会把树 `paused`，
	# `DeckReveal._process` 随之停 ⇒ 卡收不掉、冻在暂停面板上。判据走**显式 z**，不看树序：
	# `z_as_relative` 默认为真，卡挂在 hud(0) 下、菜单挂在 game(0) 下，靠树序谁在上会漂。
	_check(g.deck_reveal.z_index < g.menu_layer.z_index,
		"抽卡大字卡在暂停菜单之下（z %d < %d）" % [g.deck_reveal.z_index, g.menu_layer.z_index])
	# 同类残留（批次 8 审查 R7）：非房主看到的「⏸ 房主已暂停 · 等待继续…」全屏遮罩也在模态带，
	# 客户机被房主暂停时卡会冻住 ⇒ 遮罩必须同样压在卡之上，否则那句提示被冻住的卡盖住。
	_check(g.deck_reveal.z_index < g.pause_mask.z_index,
		"抽卡大字卡在「房主已暂停」遮罩之下（z %d < %d）" % [g.deck_reveal.z_index, g.pause_mask.z_index])
	# 把"卡在**所有**模态层之下"钉住（不止菜单与暂停遮罩）：小卖部·赌场层(70) 也必须压住卡。
	_check(g.deck_reveal.z_index < g.shop_layer.z_index,
		"抽卡大字卡在小卖部·赌场层之下（z %d < %d）" % [g.deck_reveal.z_index, g.shop_layer.z_index])

	print("== 悬停信息条：挂在屏幕层、悬停出条 / 移开收起（批次 11 Task 3）==")
	# **R2 裁定**：2D 悬停条整套（`_token_tip` / `_token_at_view` / `_set_token_hover` /
	# `_ensure_token_tip` / `_place_token_tip`）随 Task 1 一起删 —— 它们的数据源就是 `_tokens`，
	# 那套一删整段必然解析失败。屏幕层的条由 **Task 3** 重建（本段就是它带回来的断言）。
	# **载体从画布搬到屏幕层**的原因就是用户报的那句「角度不对」：画布上的 Control 随桌垫一起
	# 倾斜、被透视缩小；屏幕层 Control 天然面向镜头。**内容 / 判据 / 数据源一字未改**。
	# 关键仍是「机器人 peer 是负数」—— 判据写成 `peer < 0` 就会把机器人全挡掉。
	var hs: Dictionary = _state(2, false)
	hs.players.append({"peer": -1, "name": "机器人A", "color": 0, "bot": true,
		"money": 20000, "pos": 1, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false})
	g.s_state(hs)
	await process_frame
	# **已知竞态（实测偶发，本批两次）**：房主开局那次定时广播（`_host_setup` 的 `await _wait(1.5)`）
	# 落在这一段时会把 `st` / `_peers_info` 换成房主自己的真实局面，紧接着这几条就全红。
	# `await process_frame` 正是广播能挤进来的那一格 ⇒ 取引用前**再喂一次**（`s_state` 是同步的，
	# 与下一行之间没有 await，广播挤不进来）。断言本身一字未改。
	g.s_state(hs)
	var pinfo: Dictionary = g.board._peers_info
	_check(pinfo.has(1) and String(pinfo[1].get("name", "")) == "甲",
		"悬停信息的数据源 `board._peers_info` 仍在（Task 3 读它）")
	_check(pinfo.has(-1) and String(pinfo[-1].get("name", "")) == "机器人A",
		"**负数 peer 的机器人也在 `_peers_info` 里**（判据别写成 peer < 0）")
	_check(int(pinfo[1].get("rank", 0)) > 0 and int(pinfo[1].get("worth", 0)) > 0,
		"`_peers_info` 里带着身家与名次（信息条的内容与它同源）")

	_check(g.token_tip != null, "屏幕层悬停信息条已建（TableHud.build_play_ui）")
	_check(g.token_tip.get_parent() == g.hud_layer,
		"条挂在**屏幕层容器**上（`get_parent() == g.hud_layer`，不是棋盘画布）")
	_check(not g.board.is_ancestor_of(g.token_tip),
		"条不在棋盘画布（SubViewport）里 ⇒ 不随桌垫倾斜（用户报的「角度不对」就是它）")
	# z 档（写代码前核对过，这里把核对结论钉住）：压在屏幕 HUD 那一整片 **0** 之上，
	# 又低于抽卡大字卡与所有模态 —— 不被四角条 / 动作按钮盖住，也不去盖演出 / 模态。
	_check(g.token_tip.z_index > g.action_btn.z_index,
		"条压在动作按钮之上（z %d > %d）" % [g.token_tip.z_index, g.action_btn.z_index])
	_check(g.token_tip.z_index > int((g.corner_bars[0] as Dictionary).root.z_index),
		"条压在四角身家条之上（z %d > %d）"
			% [g.token_tip.z_index, int((g.corner_bars[0] as Dictionary).root.z_index)])
	_check(g.token_tip.z_index < g.deck_reveal.z_index and g.token_tip.z_index < g.player_popup.z_index,
		"条低于抽卡大字卡(z %d)与玩家道具弹窗(z %d)"
			% [g.deck_reveal.z_index, g.player_popup.z_index])
	_check(not g.token_tip.visible, "还没悬停时条是收起的")

	# **R10-1**：`game.gd` 里那句 `table3d.on_table_hover = _on_table_hover` 是让悬停真正工作的
	# **唯一接线** —— 删掉它，全套件原先仍然全绿、而条永不出现。这里把它钉住：注入点必须非空、
	# 且**指回 game 自己**（否则 `TableView3D` 悬停时调的是别的对象 / 空 Callable）。
	_check(g.table3d.on_table_hover.is_valid() and g.table3d.on_table_hover.get_object() == g,
		"悬停注入点接上了 game._on_table_hover（删掉那行接线条就永不出现）")
	# 悬停到 peer 1（甲，pos 0 / 槽 0）那枚棋子上：走**真入口** —— 经注入点 `on_table_hover`
	# 调用（即 `TableView3D` 悬停时真正走的那条链），而不是直调 `g._on_table_hover`。
	g.table3d.snap_view(0.0)
	await process_frame
	var want_c: Vector2 = g.board.token_screen_pos(0, 0)
	_check(g.table3d.on_table_hover.call(want_c) == 1, "悬停甲那枚棋子：命中 peer 1（走注入点）")
	await process_frame
	await process_frame
	_check(g.token_tip.visible, "悬停到棋子上 ⇒ 条浮出")
	_check(String(g._tip_name.text) == "甲",
		"条上的昵称与数据源同源（实得 %s）" % g._tip_name.text)
	# 同一条竞态：`pinfo` 是上面那一步取的，两条 `await process_frame` 之间可能来过广播 ——
	# 那样条上写的是**旧**那份（悬停时读的），而 `pinfo` 是更早的一份，比出来是假红。
	# ⇒ 重喂状态 + **同 peer 再悬停一次**（会重读内容，见 R10-2）+ 当场读 `_peers_info`，
	# 三句之间没有 await。断言本身一字未改。
	g.s_state(hs)
	_check(g.table3d.on_table_hover.call(want_c) == 1, "（重取）仍悬停甲那枚棋子")
	var pinfo_now: Dictionary = g.board._peers_info
	var want_sub := "身家 %s · 第 %d 名" % [
		GameData.fmt_money(int(pinfo_now[1].worth)), int(pinfo_now[1].rank)]
	_check(String(g._tip_sub.text) == want_sub,
		"条上的身家 / 名次与 `_peers_info` 同源（实得 %s / 期望 %s）" % [g._tip_sub.text, want_sub])
	# 位置 = 棋子**屏幕坐标**的正上方（"屏幕层天然面向镜头"那条的可执行判据：条的位置是**屏幕**像素，
	# 不是画布像素 —— 两者差着 TableView3D 那次投影，给错坐标系会整体偏开一大截）。
	var tok_screen: Vector2 = g.table3d.camera.unproject_position(g.table3d.table_props.token_world_pos(1))
	var tip_cx: float = g.token_tip.position.x + g.token_tip.size.x * 0.5
	_check(absf(tip_cx - tok_screen.x) < 4.0,
		"条横向居中于棋子（条心 %.0f / 棋子 %.0f）" % [tip_cx, tok_screen.x])
	_check(g.token_tip.position.y + g.token_tip.size.y < tok_screen.y,
		"条在棋子**上方**（条底 %.0f < 棋子 %.0f）"
			% [g.token_tip.position.y + g.token_tip.size.y, tok_screen.y])
	_check(g.token_tip.position.x >= 6.0 and g.token_tip.position.y >= 6.0
		and g.token_tip.position.x + g.token_tip.size.x <= g.size.x
		and g.token_tip.position.y + g.token_tip.size.y <= g.size.y,
		"条完整落在屏幕内（位置 %s）" % g.token_tip.position)
	# **每帧重摆**：悬停期间镜头会动（自动跟随 / 滚轮推移视角 / 取景变化）—— 推一下 3D 视角，
	# 条要跟着那枚棋子走（少了每帧这一贴，条会留在旧位置、与棋子脱开）。
	var p1: Vector2 = g.token_tip.position
	g.table3d.snap_view(0.5)
	await process_frame
	await process_frame
	var tok_screen2: Vector2 = g.table3d.camera.unproject_position(g.table3d.table_props.token_world_pos(1))
	var tip_cx2: float = g.token_tip.position.x + g.token_tip.size.x * 0.5
	_check(p1.distance_to(g.token_tip.position) > 3.0,
		"镜头一动条就跟着重摆（%s → %s）" % [p1, g.token_tip.position])
	_check(absf(tip_cx2 - tok_screen2.x) < 4.0,
		"重摆后仍居中于棋子（条心 %.0f / 棋子 %.0f）" % [tip_cx2, tok_screen2.x])
	g.table3d.snap_view(0.0)
	# 移开（悬停到没有棋子的桌垫点）⇒ 收起。
	_check(g._on_table_hover(Vector2(30.0, 30.0)) == GameData.NO_PEER, "悬停到空处：谁都没悬停")
	await process_frame
	_check(not g.token_tip.visible, "移开 ⇒ 条收起")
	# 「已出局」那一支（判据一字未改）：悬停到丁（peer 4，pos 9 / 槽 3，alive=false）——
	# 条上要多一句「 · 已出局」。
	var got4: int = g._on_table_hover(g.board.token_screen_pos(9, 3))
	_check(got4 == 4, "悬停到丁那枚棋子：命中 peer 4（实得 %d）" % got4)
	if got4 == 4:
		await process_frame
		_check(String(g._tip_sub.text).ends_with(" · 已出局"),
			"已出局的玩家条上带「 · 已出局」（实得 %s）" % g._tip_sub.text)
	g._on_table_hover(Vector2(30.0, 30.0))      # 收尾：别把悬停态留给下一段
	await process_frame
	_check(not g.token_tip.visible, "（收尾）条已收起")

	print("== 悬停信息条：R10 三条审查（内容重读 / 隐藏路径不写目标 / 相机空守卫）==")
	# ---- R10-2：同一枚棋子上**要重读内容** ----
	# 旧写法同 peer 分支只重摆位置、不重写内容 ⇒ 悬停期间来了状态广播改了这个人的身家 / 名次时，
	# 条上的数字**陈旧**（要移开再回来才更新）。这里改 `_peers_info` 里的身家（广播重填的就是它）、
	# 再走同一次悬停，条上的数字必须跟上。
	var hc2: Vector2 = g.board.token_screen_pos(0, 0)
	_check(g._on_table_hover(hc2) == 1, "（R10-2 前置）悬停甲那枚棋子")
	await process_frame
	var before_txt := String(g._tip_sub.text)
	# `board.render` 每来一次广播就把 `_peers_info` 换成新字典 ⇒ 引用要**现取**（见 R10-3 同注）。
	var pinfo2: Dictionary = g.board._peers_info
	var worth_saved := int(pinfo2[1]["worth"])
	pinfo2[1]["worth"] = worth_saved + 123456
	_check(g._on_table_hover(hc2) == 1, "（R10-2）仍悬停同一枚（同 peer 分支）")
	# 内容刷新是**同步**的（`_fill_token_tip` 直写 label）⇒ 这里不 await：中间若又来一次广播
	# 会把测试手改的身家冲回原值，断言就假失败（host 有定时广播，实测偶发）。
	var want_new := "身家 %s · 第 %d 名" % [
		GameData.fmt_money(int(pinfo2[1]["worth"])), int(pinfo2[1]["rank"])]
	_check(String(g._tip_sub.text) != before_txt and String(g._tip_sub.text) == want_new,
		"同 peer 悬停期间状态变了 ⇒ 内容重读（旧 %s → 新 %s / 期望 %s）"
			% [before_txt, g._tip_sub.text, want_new])
	pinfo2[1]["worth"] = worth_saved                # 还原，别把加出来的身家留给后面几段
	g._on_table_hover(Vector2(30.0, 30.0))
	await process_frame

	# ---- R10-3：peer 在池里但名册尚未同步 ⇒ 隐藏，且**不写 `_tip_peer`**；名册补上后应能自己出现 ----
	# 旧写法在"判据不过"的分支就把 `_tip_peer` 写成这枚 peer ⇒ 名册填好了也不会自己出现（要移开再回来）。
	# `board.render` 每来一次广播就把 `_peers_info` **整个换成新字典**（`_peers_info = pinfo`），
	# 所以改它之前必须**重新取一次引用** —— 上面的 await 之间可能来过广播，旧引用会变成孤儿。
	var pinfo3: Dictionary = g.board._peers_info
	var hc3: Vector2 = g.board.token_screen_pos(3, 1)      # 乙（peer 2，pos 3 / 槽=color 1）的落点
	var saved2 = pinfo3.get(2)
	pinfo3.erase(2)                                       # 模拟"棋子已在池里、名册还没同步到"
	# `_on_table_hover` 返回的是**命中**（原始射线结果）；"名册没这号人"只影响条的显隐。
	_check(g._on_table_hover(hc3) == 2, "（R10-3）射线命中 peer 2（原始命中，不看名册）")
	_check(not g.token_tip.visible, "（R10-3）名册没这号人 ⇒ 条收起")
	_check(g._tip_peer == GameData.NO_PEER, "（R10-3）隐藏路径**没有**写 `_tip_peer`（写成它就卡住）")
	pinfo3[2] = saved2                                    # 名册补上（下一次广播）
	_check(g._on_table_hover(hc3) == 2, "（R10-3）名册补上后仍悬停同一枚（peer 2）")
	await process_frame
	_check(g.token_tip.visible and String(g._tip_name.text) == "乙",
		"（R10-3）名册补上后条**自己出现**、不必移开再回来（实得可见 %s / 名 %s）"
			% [g.token_tip.visible, g._tip_name.text])
	g._on_table_hover(Vector2(30.0, 30.0))
	await process_frame

	# ---- R10-4：`_place_token_tip` 解引用 `table3d.camera` 的空守卫 ----
	# 相机实际在 `TableView3D._init` 就建好、不可达空；但真为 null 时旧写法会**每帧**刷 SCRIPT ERROR
	#（`_process` 每帧调本函数）。把相机临时置空、**不 await**（免得 `_process` 在空相机下跑一帧），
	# 直调一次：必须安静地收起、清掉悬停目标，而不是抛。
	_check(g._on_table_hover(hc2) == 1, "（R10-4 前置）先悬停甲，让 `_tip_peer` 非哨兵")
	await process_frame
	var cam_saved: Camera3D = g.table3d.camera
	g.table3d.camera = null
	g._place_token_tip()
	var quiet: bool = (not g.token_tip.visible) and g._tip_peer == GameData.NO_PEER
	g.table3d.camera = cam_saved
	_check(quiet, "相机为 null 时 `_place_token_tip` 安静收起（不刷 SCRIPT ERROR）")

	print("== 格详情卡：悬浮在被点格子的上方 ==")
	g.board.cam_locked = false
	g.board.fit_overview(true)
	g._on_tile_clicked(27)
	await process_frame
	await process_frame
	_check(g.info_panel.visible, "点格子后详情卡显示")
	# 跨层断言（Task 3b）：期望位置必须走「棋盘画布坐标 → 屏幕坐标」的反变换 —— 这正是
	# game.gd 消费点做的事。旧写法两边都取自 board.tile_screen_pos，而棋盘搬进 SubViewport
	# 后那个值是 0..2048 的画布坐标，两边一起缩放：卡片被 clamp 钉死在屏幕边缘也照样成立。
	# 现在期望值走 TableView3D.viewport_to_screen（屏幕空间），卡片位置由屏幕层自己摆 ——
	# 少了反变换，两者会差出上百像素。
	var raw: Vector2 = g.board.tile_screen_pos(27)
	var anchored = g.table3d.viewport_to_screen(raw)
	_check(anchored != null, "27 号格的画布坐标 %s 可解算到屏幕坐标" % raw)
	var tc: Vector2 = anchored if anchored != null else Vector2(-9999.0, -9999.0)
	var pc: Vector2 = g.info_panel.position
	var pcz: float = pc.x + g.info_panel.size.x * 0.5
	_check(absf(pcz - tc.x) < 4.0, "卡片横向居中于该格（卡中心 %.0f / 格 %.0f）" % [pcz, tc.x])
	# 卡片**不得盖住被点的格子**。正常落在**上方**；格子太靠上、上方塞不下时
	# `_place_info_panel` 会**翻到下方**（`pos.y < 8` ⇒ `c.y + 20`）—— 这是它的既定行为，
	# 批次 12 A2b 把构图整体上移了一点之后，顶部那排格子正好会触发翻转，
	# 所以这里按「有地方放就放上面、放不下就翻下面」断言，而不是死钉"必须在上面"。
	var room_above: bool = (tc.y - g.info_panel.size.y - 20.0) >= 8.0
	if room_above:
		_check(pc.y + g.info_panel.size.y < tc.y, "卡片在格子上方（卡底 %.0f / 格 %.0f）"
			% [pc.y + g.info_panel.size.y, tc.y])
	else:
		_check(pc.y > tc.y, "上方放不下 ⇒ 翻到格子下方且不盖住它（卡顶 %.0f / 格 %.0f）"
			% [pc.y, tc.y])
	# 错位的旧症状正是「卡片贴死屏幕边缘」：卡片必须完整落在屏幕内，且横向居中不是靠
	# clamp 凑出来的（被夹住时 pcz 会偏离锚点 x，上面那条居中检查随之失败）。
	_check(pc.x >= 8.0 and pc.y >= 8.0 and pc.x + g.info_panel.size.x <= g.size.x
		and pc.y + g.info_panel.size.y <= g.size.y, "卡片完整落在屏幕内（位置 %s）" % pc)

	print("== 归属色条：谁的地都要有，颜色与该玩家的棋子一致 ==")
	var ts: Dictionary = _state(2, false)
	# 关键：必须覆盖**机器人**（peer 为负数，从 -1 起编号）。
	# 之前用 `owner_id >= 0` 判「有主」，把机器人买的地全部漏掉了 —— 真人自己买的地
	# 有色条、机器人买的全没有，正是玩家看到的现象。这个用例就是为了钉住它。
	ts.players.append({"peer": -1, "name": "机器人A", "color": 0, "bot": true,
		"money": 20000, "pos": 1, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false})
	var mine_t := -1
	var bot_t := -1
	var free_t := -1
	for i in ts.tiles.size():
		if String(GameData.TILES[i].get("type", "")) != "property":
			continue
		ts.tiles[i].owner = GameData.NO_OWNER
		if mine_t < 0:
			mine_t = i
			ts.tiles[i].owner = 2          # 乙 = 我（真人，正 peer）
		elif bot_t < 0:
			bot_t = i
			ts.tiles[i].owner = -1         # 机器人（负 peer）
		elif free_t < 0:
			free_t = i
	g.s_state(ts)
	await process_frame
	_check(g.board._strips[mine_t].visible, "我买的地：色条显示")
	_check(g.board._strips[bot_t].visible, "**机器人买的地：我这边也要显示色条（负 peer）**")
	_check(not g.board._strips[free_t].visible, "无主的地：不显示色条")
	_check(g.board._strip_cols[mine_t] == GameData.PLAYER_COLORS[1], "我的色条 = 我的棋子色")
	_check(g.board._strip_cols[bot_t] == GameData.PLAYER_COLORS[0], "机器人的色条 = 它的棋子色")
	_check(g.board._strips[mine_t].position == Vector2(3, 3), "色条贴在格子左上角（不在文字上）")
	_check(g.board._strips[mine_t].size.y <= 14.0,
		"色条只有顶带那么高（实得 %.0f）" % g.board._strips[mine_t].size.y)
	# 关键：光 visible=true 不代表看得见 —— 没有样式就是一块透明板
	var strip_sb = g.board._strips[mine_t].get_theme_stylebox("panel")
	_check(strip_sb is StyleBoxTexture,
		"色条挂着真正的卡样式（实得 %s）" % ("null" if strip_sb == null else strip_sb.get_class()))

	print("== 操作倒计时（D 方案）：屏幕上只剩「我」这条身家条一个落点（v0.8.0 第三次改版）==")
	# 倒计时簇原先立牌 / 四角条各一份；立牌随批次 9 退场、四角条只剩「我」一条，
	# **v0.8.0 第三次改版**名册条又删除 ⇒ 屏幕层只剩「我」这一条；**别人的那一份在桌面立牌上**
	#（`table_props.set_placard_timer`，判据见 `tests/placard_test.gd` ⑦）。
	# 数据链路一字未改（仍由 `_refresh_corner_timer` 逐帧推，同一份 `_op_left / _op_total`）。
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	g.s_op_timer("roll", 35.0, 35.0, 2)
	g._process(0.0)
	await process_frame
	var cb2: Dictionary = _bar_of(g, 2)        # 乙 = 行动者 = 我（屏幕上唯一那条）
	_check(not cb2.is_empty() and (cb2.timer_kind as Label).visible,
		"行动者的那一条上出现倒计时（环节名可见）")
	_check(String((cb2.timer_kind as Label).text) == "掷轮",
		"条上写环节名（实得「%s」）" % String((cb2.timer_kind as Label).text))
	_check(String((cb2.timer_left as Label).text) == "35 秒",
		"条上写剩余秒数（实得「%s」）" % String((cb2.timer_left as Label).text))
	var ctk2: ColorRect = cb2.timer_track
	var cfl2: ColorRect = cb2.timer_fill
	_check(ctk2.visible and cfl2.size.x > 0.9 * maxf(ctk2.size.x, 1.0),
		"条上的细进度条接近满格（%.1f / %.1f）" % [cfl2.size.x, ctk2.size.x])
	# 行常驻占位：倒计时**出现之后**那一条不许变高（我这条变了会朝上顶，与下面那条平齐的约束打架）。
	# 名册行那一半随载体删除（立牌的尺寸是世界单位，见 `table_props.PLACARD_*`）。
	var heights_ok := true
	var want_h: float = TH.CORNER_BAR_SIZE.y
	if not is_equal_approx((g.corner_bars[0].root as Control).size.y, want_h):
		heights_ok = false
		print("    [实测] 倒计时出现后我这条高 %.1f（应 %.1f）"
			% [(g.corner_bars[0].root as Control).size.y, want_h])
	_check(heights_ok, "倒计时出现后我这条仍一样高（= CORNER_BAR_SIZE.y，行常驻占位）")
	# 广播一秒一条，本机 _process 逐帧扣 delta 插值——喂剩 5 秒的道具窗口，
	# 等 1.5 秒（自然帧累积扣减），进度条应明显缩水、环节名跟着窗口走
	g.s_op_timer("item", 5.0, 12.0, 2)
	await create_timer(1.5).timeout
	g._process(0.0)
	var frac2: float = cfl2.size.x / maxf(ctk2.size.x, 1.0)
	_check(frac2 < 0.45 and frac2 > 0.15, "一秒多后进度条平滑缩水到中段（实得 %.2f）" % frac2)
	_check(String((cb2.timer_kind as Label).text).begins_with("道具"),
		"环节名跟着窗口走（实得「%s」）" % String((cb2.timer_kind as Label).text))
	# **窗口换人 ⇒ 我这条收起**（倒计时只出现在 `_op_owner` 那一条上；此刻 owner = 丙 ≠ 我）。
	# 「换人之后倒计时跟到新行动者那一块」那一半现在是**立牌**的事（`tests/placard_test.gd` ⑦）。
	g.s_op_timer("black", 15.0, 20.0, 3)
	g._process(0.0)
	await process_frame
	_check(not (cb2.timer_kind as Label).visible and not (cb2.timer_track as ColorRect).visible
			and not (cb2.timer_left as Label).visible,
		"窗口换到丙（≠ 我）⇒ 我这条的倒计时内容全部收起（只在行动者那一条上露面）")
	# 换回我：环节名 / 秒数都跟着走（同一条上的两件事）
	g.s_op_timer("black", 15.0, 20.0, 2)
	g._process(0.0)
	_check((cb2.timer_kind as Label).visible and String((cb2.timer_kind as Label).text) == "黑市",
		"环节名换到「黑市」（实得「%s」）" % String((cb2.timer_kind as Label).text))
	_check(String((cb2.timer_left as Label).text) == "15 秒",
		"剩余秒数跟着窗口走（实得「%s」）" % String((cb2.timer_left as Label).text))
	# 不限时：仍显示环节名，但不写"0 秒"、进度条整条收起（语义原在座位卡上："不限时"）
	g.s_op_timer("roll", 0.0, 0.0, 2)
	g._process(0.0)
	_check((cb2.timer_kind as Label).visible and String((cb2.timer_kind as Label).text) == "掷轮"
			and not (cb2.timer_left as Label).visible and not (cb2.timer_track as ColorRect).visible,
		"不限时窗口仍显示环节名但不写秒数、不画进度条")
	# 窗口关闭：kind="" 全部一起收
	g.s_op_timer("", 0.0, 0.0, -1)
	g._process(0.0)
	await process_frame
	var any_corner_timer := false
	for b in g.corner_bars:
		if (b.timer_kind as Label).visible or (b.timer_track as ColorRect).visible \
				or (b.timer_left as Label).visible:
			any_corner_timer = true
	_check(not any_corner_timer, "窗口关闭后我这条的倒计时内容全部收起（一处都不显示）")

	print("== 点转盘 = 掷轮入口（批次 3 Task 2）==")
	# 为什么挑 roll_received 当证据：底栏那个「转动转盘」按钮已随 Task 6 拆除，`roll_btn.disabled`
	# 早就不存在；而 roll_received 是**掷轮这件事本身** —— game.gd 的 _play_turn 正 await 它，
	# 房主侧玩家点不点转盘，最终都落到这一条信号上。这里跑的是房主侧分支（`--script` 下
	# multiplayer 是默认接口、unique_id = 1 ⇒ is_server() 恒真，同 casino_test 的说明）；
	# 客户端那条走 c_roll，是另一条路，本机不联机验不了。
	g.my_peer = 2
	g.s_state(_state(2, false))          # await="roll"、turn=2=我 ⇒ 正是我的掷轮窗口
	await process_frame
	# 房主侧「轮到谁掷」的权威值（_play_turn 里设）。本测试不跑对局循环，直接给。
	g._awaiting_roll = 2
	var rolls := [0]
	var on_roll := func() -> void: rolls[0] += 1
	g.roll_received.connect(on_roll)
	var wc: Vector2 = g.board.wheel_screen_pos()
	var wr: float = g.board.wheel_screen_radius()
	_check(g._on_table_click(wc), "点转盘圆心：返回 true（这次点击被实体消费）")
	_check(rolls[0] == 1, "点转盘圆心：掷轮路径走通（roll_received 发出，实得 %d 次）" % rolls[0])
	_check(g._on_table_click(wc + Vector2(wr * 0.5, 0.0)), "轮缘上（半径一半处）也算命中")
	_check(rolls[0] == 2, "轮缘上同样掷轮（实得 %d 次）" % rolls[0])
	# 转盘**只吃左键**（修复波）：右键落在转盘上**不消费** —— 落回棋盘 = 既有的取消。
	# 这条没有用例就是静默回归（右键又能掷轮）而所有套件仍然全绿：别的用例都不碰
	# `MOUSE_BUTTON_RIGHT` 的转盘分支。此处断言两件事：不消费 + 掷轮计数不变。
	_check(not g._on_table_click(wc, MOUSE_BUTTON_RIGHT),
		"右键落在转盘上不消费（落回棋盘 = 取消）")
	_check(not g._on_table_click(wc + Vector2(wr * 0.5, 0.0), MOUSE_BUTTON_RIGHT),
		"右键落在轮缘上同样不消费")
	_check(rolls[0] == 2, "右键落在转盘上**不掷轮**（掷轮计数没变，实得 %d 次）" % rolls[0])
	# 负路径一：不在掷轮环节 —— 点击仍被转盘消费（返回 true，不会漏给桌垫），但**不掷轮**
	var s_item: Dictionary = _state(2, false)
	s_item.await = "item"
	g.s_state(s_item)
	g._awaiting_roll = 2
	await process_frame
	_check(g._on_table_click(wc), "非掷轮环节（await=item）：点击仍被转盘消费")
	_check(rolls[0] == 2, "非掷轮环节：不掷轮（实得 %d 次）" % rolls[0])
	# 负路径二：不是我的回合 —— 同理不掷轮
	g.s_state(_state(1, false))
	g._awaiting_roll = 2
	await process_frame
	_check(g._on_table_click(wc), "不是我的回合：点击仍被转盘消费")
	_check(rolls[0] == 2, "不是我的回合：不掷轮（实得 %d 次）" % rolls[0])
	g.roll_received.disconnect(on_roll)

	print("== 右下角动作按钮（批次 7）：转动转盘 ↔ 结束回合 ↔ 隐藏 ==")
	_check(g.action_btn != null, "右下角动作按钮已建（TableHud.build_play_ui）")
	g.my_peer = 2
	g.s_state(_state(2, false))            # await="roll"、turn=2=我 ⇒ 我的掷轮窗口
	await process_frame
	g._process(0.0)
	_check(g.action_btn.visible and String(g.action_btn.text) == "转动转盘",
		"轮到我掷轮 → 按钮是「转动转盘」且可见（实得「%s」）" % String(g.action_btn.text))
	# 点它 = 掷轮（走既有的 _on_roll_pressed；本机是"服务端"路径，见文件头那段说明）
	var acted := [0]
	var on_act := func() -> void: acted[0] += 1
	g.roll_received.connect(on_act)
	g._awaiting_roll = 2
	g._on_action_pressed()
	_check(acted[0] == 1, "点「转动转盘」→ 走既有的掷轮入口（实得 %d 次）" % acted[0])
	g.roll_received.disconnect(on_act)
	# 掷完进道具阶段 → 变「结束回合」，点它 = 收尾道具阶段（_on_skip_pressed）
	var s_item2: Dictionary = _state(2, false)
	s_item2.await = "item"
	s_item2.await_peer = 2
	g._item_epoch = 7
	g.s_state(s_item2)
	await process_frame
	g._process(0.0)
	_check(g.action_btn.visible and String(g.action_btn.text) == "结束回合",
		"道具阶段 → 按钮变「结束回合」（实得「%s」）" % String(g.action_btn.text))
	g._on_action_pressed()
	_check(String(g._item_action.get("action", "")) == "skip",
		"点「结束回合」→ 走既有的跳过入口（实得「%s」）" % String(g._item_action.get("action", "")))
	# 不是我的窗口 → 隐藏
	g.s_state(_state(1, false))            # turn=1 ≠ 我
	await process_frame
	g._process(0.0)
	_check(not g.action_btn.visible, "不是我的回合 → 按钮隐藏")
	# 落位（批次 12 D2 改基准）：⑩ 把右下角那条身家条删了 ⇒ 动作按钮从"悬在身家条之上"
	#（旧基线 offset_bottom ≤ -160）改成**贴右下角**（下沿 -20）。**注意这条不再有"上面那条要避开"**，
	# 反向钉住"别再退回 -172"（退回就等于身家条又长出来了）。
	_check(is_equal_approx(g.action_btn.offset_bottom, -20.0)
			and is_equal_approx(g.action_btn.offset_right, -20.0),
		"动作按钮贴右下角（right=%.0f / bottom=%.0f）"
			% [g.action_btn.offset_right, g.action_btn.offset_bottom])
	# 贴底那条黑市操作条按屏宽居中（约 x 460..820），不许与右下角的动作按钮打架
	var ab_rect: Rect2 = (g.action_btn as Control).get_global_rect()
	_check(ab_rect.position.x > g.size.x * 0.5 and ab_rect.end.y > g.size.y * 0.9,
		"动作按钮在**右下角**（实得 %s）" % str(ab_rect))
	# 牌垫阶段按钮那一套必须**真的没了**（不是留成不可见空壳）
	_check(g.board.get_node_or_null("PhaseButtons") == null, "牌垫阶段按钮层已拆净")
	_check(not g.board.has_method("set_phase_buttons"), "set_phase_buttons 接口已退场")

	print("== 点手中牌：一次点击直出（批次 7）==")
	# 直出 = 点一张牌就出它，不再有"选中 → 再点确认"。走**真实**的 `_on_table_click` 链路。
	# 本机是默认 multiplayer（unique_id=1 ⇒ is_server() 恒真，见文件头），所以直接出牌走的是
	# 房主路径 `_use_item`（不是 RPC），可以安全地跑在无头测试里。
	# 关键：`_use_item` 的两条守卫是「房主名册（**hp**，不是 st）里有这个人」与「`_awaiting_item` == 我」
	# （game.gd:2371/2402）。名册 / 窗口归属不种齐，点击会在第二行就 return，牌根本没离手 ——
	# 只断言「点击被消费」就成了空转（空实现的 `_on_hand_clicked` 也能过）。第一张特意选
	# **效果只动现金、不走 await** 的 兼职中介，好让"真的执行了"有硬证据。
	g.my_peer = 2
	var hand_items: Array = [{"id": "兼职中介", "cd": 0}, {"id": "跑腿券", "cd": 0},
		{"id": "快递直达", "cd": 0}, {"id": "作弊器", "cd": 0}, {"id": "共享单车", "cd": 0}]
	var s_hand: Dictionary = _state(2, false)
	s_hand.await = "item"          # 轮到我、道具阶段
	s_hand.await_peer = 2
	for p in s_hand.players:
		if int(p.peer) == 2:
			p.items = hand_items.duplicate(true)
	g.s_state(s_hand)
	g.hp[1].items = hand_items.duplicate(true)   # 房主名册里 peer 2 那一份（_host_roster 的 index 1）
	g._awaiting_item = 2                          # 道具阶段窗口归属 = 我
	# `_awaiting_roll` 还留着上面「点转盘」段的 2：不清掉的话出牌后那次 `_broadcast_state`
	# 会把它当成掷轮窗口（`await` 先判 roll），下面 ②③④ 的 `_hand_clickable` 就整个不成立。
	g._awaiting_roll = 0
	await process_frame
	await process_frame
	g._process(0.0)
	var tph = g.table3d.table_props
	_check(tph.hand_count() == 5, "我的五件道具摆成五张手牌（满手，实得 %d）" % tph.hand_count())
	_check(g.selected_slot == -1, "初始未选中")

	# ① 不带目标的牌：点一下就出去了（不留在选中态、不进任何选目标态），**而且牌真的离手**：
	#    房主名册里那一件进了冷却、体力被扣、本回合计数 +1，现金真的到账（兼职中介 = 立刻 +¥800）。
	var money0: int = int(g._player_by_peer(2).money)
	var stam0: int = int(g._player_by_peer(2).stamina)
	var cost0: int = int(ItemData.def("兼职中介").cost)
	_check(g._on_table_click(tph.hand_rect(0).get_center()), "点第一张牌（不带目标）：点击被手牌消费")
	_check(int(g._player_by_peer(2).item_used_n) == 1 \
			and int(g._player_by_peer(2).items[0].cd) > 0 \
			and int(g._player_by_peer(2).stamina) == stam0 - cost0 \
			and int(g._player_by_peer(2).money) == money0 + 800,
		"不带目标的牌：**真的执行了 _use_item**（item_used_n=%d / 那件 cd=%d / 体力 %d→%d / 现金 %d→%d）"
			% [int(g._player_by_peer(2).item_used_n), int(g._player_by_peer(2).items[0].cd),
				stam0, int(g._player_by_peer(2).stamina), money0, int(g._player_by_peer(2).money)])
	_check(g.selected_slot == -1 and g._tgt_stage == "",
		"不带目标的牌：点一下直接出（selected_slot=%d / tgt_stage=「%s」）"
			% [g.selected_slot, g._tgt_stage])
	# 用完还原：别的段落不该有「道具阶段窗口」一直开着 —— 会让那几处点选目标后的
	# `_send_use_item` 真的走到 `_use_item`（本段只需它一次）。
	g._awaiting_item = 0

	# ② 需要选玩家的牌（跑腿券）：点一下**直接进**选目标态（不再需要第二次点击确认）
	_check(g._on_table_click(tph.hand_rect(1).get_center()), "点第二张（跑腿券）：点击被手牌消费")
	_check(g._tgt_stage == "peer", "点一下就跑腿券直接进选目标态（实得「%s」）" % g._tgt_stage)
	_check(g.selected_slot == -1, "进选目标态后 selected_slot 已清（不常驻）")
	g._cancel_target()
	_check(g._tgt_stage == "", "取消目标后回到无事态")

	# ③ 需要选格子的牌（快递直达）：同理，点一下直接进选地块态
	_check(g._on_table_click(tph.hand_rect(2).get_center()), "点第三张（快递直达）：点击被手牌消费")
	_check(g._tgt_stage == "tile", "点一下就快递直达直接进选地块态（实得「%s」）" % g._tgt_stage)
	g._cancel_target()

	# ④ 作弊器：点一下弹点数框（既不直接发也不进选目标态）
	_check(g._on_table_click(tph.hand_rect(3).get_center()), "点第四张（作弊器）：点击被手牌消费")
	_check(g.cheat_picker != null and g.cheat_picker.visible and g.cheat_slot == 3,
		"点作弊器 → 弹点数框、记下槽位 3（实得槽位 %d）" % g.cheat_slot)
	g._close_cheat_picker()

	print("== 近排格子不再被手牌压住（批次 5 Task 3：整排下移到木纹留白）==")
	# 批次 3 那条老问题（R38/R40）是「牌盒上沿咬住近排格子，只在格子顶部留下十几画布像素的
	# 可点缝；选中那张一抬起来，外侧两张的缝直接归零」。Task 3 把整排**放大 1.5 倍并下移到
	# 桌垫前沿的木纹留白（桌垫下沿之外、木桌之内）之后，牌与近排格子**完全不重叠** —— 这条钉住新结论。
	# 下面那段"牌底可点条带"的实测数值随之从 11~19 变成"整格皆可点"（报告与注释都按新值写）。
	var cell_of := func(i: int) -> Rect2:
		var p: Vector2 = g.board._view_from_world(g.board.tile_pos(i))
		var s: float = g.board.TILE * g.board._zoom
		return Rect2(p, Vector2(s, s))
	var near_row: Array = []
	for i in GameData.TILES.size():
		if g.board.tile_grid(i).y == GameData.BOARD_ROWS - 1:
			near_row.append(i)
	_check(near_row.size() == GameData.BOARD_COLS, "近排 %d 格都在（实得 %d）" % [GameData.BOARD_COLS, near_row.size()])
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var lowest_cell := 0.0
	for i in near_row:
		lowest_cell = maxf(lowest_cell, cell_of.call(i).end.y)
	var hand_top := INF
	var hand_bot := -INF
	var hand_x0 := INF
	var hand_x1 := -INF
	for k in tph.hand_count():
		var r: Rect2 = tph.hand_rect(k)
		hand_top = minf(hand_top, r.position.y)
		hand_bot = maxf(hand_bot, r.end.y)
		hand_x0 = minf(hand_x0, r.position.x)
		hand_x1 = maxf(hand_x1, r.end.x)
	_check(hand_top > lowest_cell,
		"手牌整排落在近排格子之下（牌上沿 %.1f > 格区下沿 %.1f）" % [hand_top, lowest_cell])
	# 逐格逐张验「真的不相交」（只看整体上沿是不够的：扇形外侧那两张更靠上）
	var cell_hits := 0
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		for k in tph.hand_count():
			if cell.intersects(tph.hand_rect(k)):
				cell_hits += 1
	_check(cell_hits == 0, "没有一格与任何一张牌相交（相交 %d 处）—— 批次 3 的 R38/R40 就此消失" % cell_hits)
	# 批次 7：牌垫上的两枚阶段按钮已退场 ⇒ 原来这条"手牌不与按钮交叠"作废。
	# 手牌与近排格子不相交那条（上面 `cell_hits == 0`）仍在，落位硬约束由它守着。

	# ① 手牌只在道具阶段吃点击：牌是常驻显示的（每次广播都摆一遍），但别的阶段点它没有意义，
	#    吃下点击就等于把本该落到格子上的一次点击吞成「什么都没发生」——那才是真正的死区。
	var s_roll: Dictionary = s_hand.duplicate(true)
	s_roll.await = "roll"          # 掷轮阶段（仍是我的回合），手牌照样摆在桌上
	g.s_state(s_roll)
	await process_frame
	var c0b: Vector2 = tph.hand_rect(0).get_center()
	_check(tph.hand_hit(c0b) == 0, "（对照）这个点确实落在第一张牌的命中盒里")
	_check(not g._on_table_click(c0b), "不是道具阶段：点手牌不消费点击（漏给桌垫）")
	_check(g.selected_slot == -1, "不是道具阶段：点了也不会选中")

	# ② 牌自己身上：三种情况各点一次。采样点一律取**牌面的中心**（真落在牌盒里，
	#    不是"格子下沿恰好也在盒里"那种巧合）——「不被吞」才不是空谈。
	#    取法走**真实的点击链路**：牌面八角的屏幕包围盒 → 盒心 → `screen_to_viewport` → 画布。
	#    （**不能**反过来用 `viewport_to_screen` 把画布点映回屏幕：批次 5 Task 3 起牌整排
	#     落在纹理窗口**之外**的木纹留白上，那个函数对窗口外的画布点一律返回 null。）
	var screen_box := func(k: int) -> Rect2:
		var mi := tph.get_node("Hand").get_child(k) as MeshInstance3D
		var bm: BoxMesh = mi.mesh as BoxMesh
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					var sp: Vector2 = g.table3d.camera.unproject_position(mi.global_transform * Vector3(
						bm.size.x * float(sx), bm.size.y * float(sy), bm.size.z * float(sz)))
					mn = mn.min(sp)
					mx = mx.max(sp)
		return Rect2(mn, mx - mn)
	var pts: Array = []              # [{card: int, pt: Vector2}]
	for k in tph.hand_count():
		var sp_c: Vector2 = (screen_box.call(k) as Rect2).get_center()
		var cv = g.table3d.screen_to_viewport(sp_c)
		pts.append({"card": k, "pt": cv if cv != null else Vector2(-9999.0, -9999.0),
			"screen": sp_c})

	# 2a 非道具阶段：这些点必须**不被吞**（漏给桌垫）—— 这才是阶段闸的功劳，去掉闸这里就红
	var blocked := 0
	var still_covered := 0
	for c in pts:
		g._cancel_target()
		if tph.hand_hit(c.pt) >= 0:
			still_covered += 1
		if g._on_table_click(c.pt):
			blocked += 1
	_check(still_covered == pts.size(),
		"（对照）这 %d 个点确实落在牌盒里（实得 %d）——「不被吞」不是空谈" % [pts.size(), still_covered])
	_check(blocked == 0, "不是道具阶段：牌面上这 %d 个点**全都不被吞**（被吞 %d）——阶段闸在干活"
		% [pts.size(), blocked])
	g._cancel_target()

	# 2b 道具阶段：这些点**被吞**，而且命中的正是**它自己那张**牌
	#（点取自"看得见的那块屏幕包围盒的中心"，判据走 hand_hit —— 两条链路对得上才算数）
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var eaten := 0
	var eaten_self := 0
	for c in pts:
		# 每次点之前先清空选中 / 选目标态：这样「点之前的手牌摆位」每次都一样，屏幕包围盒才在点之前算得准
		#（批次 7 起点下去 = 直接出牌，跑腿券 / 快递直达会进选目标态 —— 这里把上一跳的状态先收干净）。
		g._cancel_target()
		g._close_cheat_picker()
		var boxes: Array = []
		for k in tph.hand_count():
			boxes.append(screen_box.call(k))
		if g._on_table_click(c.pt):
			eaten += 1
			if tph.hand_hit(c.pt) == int(c.card) \
					and (boxes[c.card] as Rect2).has_point(c.screen as Vector2):
				eaten_self += 1
	g._cancel_target()
	_check(eaten == pts.size(), "道具阶段：牌面上这 %d 个点都被手牌接收（实得 %d）"
		% [pts.size(), eaten])
	_check(eaten_self == eaten, "被接收的点屏幕上确实画着**它自己那张**牌（%d / %d）"
		% [eaten_self, eaten])

	# 2c 实测取证：**牌底那几格还剩多少可点条带**（批次 5 Task 3 的验收点）。
	#    批次 3 的答案是"未选中 11~19、抬起后外侧两张归零"；今天牌整排下移到木纹留白，
	#    答案是**没有格子被盖住**：近排每格的整条高都能点。
	#    **量的是最坏档**（批次 5 Task 4 改）：**满手 5 张、抬起扇形最外侧那张** —— 外侧那张
	#    画布 y 最高（离格子最近），抬起又把它整体抬高，正是当年"归零"的那一档；
	#    3 张手牌量到的是另一个数（批次 5 是 201.5 / 188.8），钉不住最坏情况。
	#    **批次 10 重取：79.9 / 68.0**（批次 10 T1 是 77.0 / 63.4；批次 5 是 190.0 / 177.0）——
	#    T1 把整排上移到木纹带正中（HAND_BASE_PX 1862 → 1834）**同时** `fit_zoom` 从 0.9116
	#    涨到 0.96374（近排格子在画布上更大、下沿更靠下）⇒ 缝窄了 113 画布像素；T2 把相机
	#    从 5.2 收到 4.7 ⇒ 缝又**宽回来** 2.9 / 4.6 画布像素（`hand_rect` 是拿 3D 相机把牌
	#    投影回画布算的，相机一动它就跟动 —— 见 `table_props.hand_rect` 那段"相机变动会改
	#    你看到它的位置"）。**仍远大于 0**（这条断言要的就是"没盖住"）。
	#    **批次 12 A2 重取：67.0 / 56.7**（`CAM_DIST` 4.7 → 4.30 + 桌垫留白再收一档）——
	#    相机更近 ⇒ 牌的**投影盒更大**（+11% 量级）、近排格子的画布下沿也往下走了一点，
	#    两头一起把缝收窄了 12.9 / 11.3 画布像素。**仍然是可点的条带**（远大于 0），
	#    但比批次 10 薄了一档 —— 想再宽回来只能收手牌尺寸（不属于批次 A 的范围）。
	#    **批次 12 B1 重取：69.1 / 58.8**（手牌宽 0.46 → **0.404**）—— 缝反而**宽了 2.1 / 2.1**：
	#    牌窄了 12% ⇒ 扇形（±8°/±16°）每张的**进深脚印**小了一截（`W×sin(16°)` 那一项），
	#    整排的投影盒上沿往下走（离近排格子更远）。**方向是"变安全"的那一边**，
	#    所以 B1 收宽这条既保住了木纹带（进深 0.54 一字未动）、又没吃掉这条缝。
	#    **批次 12 A2b 重取：61.0 / 45.9**（`CAM_FOV` 55 → **39**、`CAM_DIST` 4.30 → **5.77**，
	#    见 `table_3d.CAM_FOV` 那段）—— 缝**窄了 8.1 / 12.9**：`hand_rect` 是拿 3D 相机把牌
	#    **投回画布**算的（见上面 `hand_rect` 那段"相机变动会改你看到它的位置"），
	#    换镜头这一档把整排的投影盒**上沿往格子那侧**挪了 8 画布像素量级。
	#    仍是**可点**的条带（远大于 0，按 3D 端 0.62 屏像素/画布像素折算 ≈ 28 屏像素），
	#    这条断言要的就是"没盖住"。
	#    **批次 13 辛 ⑤ 重取：28.5 / 12.7**（手牌两维一起 ×1.2：0.404/0.54 → **0.4848/0.648**，
	#    用户要"卡牌上的字看得清"；同时 `HAND_BASE_PX.y` 1834 → **1822**，见 `table_props` 那段
	#    —— 整排下沿在旧位置越出了**屏幕**下沿，`layout_test` 那条"整排手牌都在屏内"先红）。
	#    缝因此**窄了 32.5 / 33.2**，是全批次里最薄的一档：牌大了一圈、整排又往上挪了一截，
	#    两头都朝格子的方向压。**只要求不被压住**（`cell_hits == 0` / `hand_top > lowest_cell`
	#    两条一个字没动、也没放宽）；这两个数就是那条余量的当前值，**再放大手牌就会先红**。
	#    ⚠ 这两个数**跟着 3D 相机走**：改手牌尺寸 / 摆位 / **`CAM_DIST` / `CAM_FOV`** 都得回来重取，
	#    改不动就红。这两个数**钉进断言**（不只写在注释里）。
	#    **批次 7 起点击 = 直出**，一次点击不再**留在**选中态（抬起只在那一瞬间发生），
	#    所以这里走**保留的玩法侧选中入口** `_on_item_slot_clicked` 把那张牌抬起来 ——
	#    抬起的表现（`set_hand_selected`）与这条布局约束都还在，量到的仍是同一档。
	g._cancel_target()
	var gap_plain: float = hand_top - lowest_cell
	var sel_card := 0                 # 0 = 扇形最外侧（外侧两张对称，取哪张都一样）
	g._on_item_slot_clicked(g.my_peer, sel_card)
	# 先钉「真的抬起来了」：不然没抬时 gap_sel == gap_plain 也照样过，这条就白测了。
	_check(g.selected_slot == sel_card,
		"选中入口**真的抬起了一张**（selected_slot 期望 %d，实得 %d）" % [sel_card, g.selected_slot])
	var sel_top := INF
	for k in tph.hand_count():
		sel_top = minf(sel_top, tph.hand_rect(k).position.y)
	var gap_sel: float = sel_top - lowest_cell
	print("    [实测] 牌底可点条带：未选中 %.1f 画布像素、抬起（第 %d 张）后 %.1f —— 都不为 0"
		% [gap_plain, sel_card, gap_sel])
	# 整排的**屏幕包围盒**也打出来：`table_props.HAND_CARD_W` / `HAND_BASE_PX` 那两段注释里的
	# 数字就是从这里取的（改手牌尺寸 / 摆位 / 相机都得回来重取，见那两段）。
	print("    [实测] 手牌整排屏幕包围盒：y %.1f..%.1f / x %.1f..%.1f（近排格子下沿 %.1f、画布底 2048）"
		% [hand_top, hand_bot, hand_x0, hand_x1, lowest_cell])
	g._cancel_target()
	_check(gap_plain > 0.0 and gap_sel > 0.0,
		"选中 / 未选中两档下，近排格子都还有可点的条带（%.1f / %.1f 画布像素）" % [gap_plain, gap_sel])
	# **批次 13 辛 ⑤ 重取了这两个数**（手牌两维 ×1.2：0.404/0.54 → 0.4848/0.648）。
	# 容差仍是 ±1.0（没有放宽）：牌一变大，投影盒的上沿朝格子那侧挪，缝必然变窄 ——
	# 这两个数就是那条硬约束在"今天这一档尺寸"下的余量，改尺寸 / 相机就得回来重取。
	#
	# ---- **一期 Task 7 重取：28.5 / 12.7 → 33.4 / 13.3**（`CAM_DIST` 5.77 → **8.90**）----
	# 取景契约那次改动（判据回滚到木桌四角、默认档偏屋子）把相机**退远了 3.13**：
	# `hand_rect` 是拿 3D 相机把牌**投回画布**算的，**牌是抬起又倾斜的**（`HAND_TILT_DEG`）
	# ⇒ 它的投影脚印会随相机一起动。实测退远后这条缝**窄了 14 画布像素**、
	# **抬起最外侧那张直接压进近排格子 1.2px**（19.0 / **-1.2**）——
	# `gap_sel > 0` 那条**真的红了**（不是估算，是跑出来的）。
	# ⇒ 按 `table_props.HAND_BASE_PX` 那条既有约定（"改相机必须重取整排落点"）把整排**往外挪 14**
	# 画布像素（1822 → **1836**）：缝回到 **33.4 / 13.3**（比辛 ⑤ 那档还厚一点点）。
	# **为什么能挪**：辛 ⑤ 那个夹点的另一头是**屏幕下沿**（当时只剩 6.1 屏像素），
	# 相机一退远，整排的屏幕 y 从 666.5..793.9 收到 **565..637**（头 172 屏像素）⇒ 那一头松了，
	# 往外挪的空间就是从这里来的。**两条约束一个字没放宽**。
	_check(absf(gap_plain - 33.4) <= 1.0 and absf(gap_sel - 13.3) <= 1.0,
		"满手 5 张 + 选中外侧那张，实测值就是注释里那两个数（%.1f / %.1f，期望 33.4 / 13.3）"
			% [gap_plain, gap_sel])

	# ③ 下沿：近排**每一格**（不再需要"找没被盖住的那一格"—— 今天一格都没被盖住）的下沿都必须
	#    **不被消费**，并解算到它自己。这里验的是**下游那一半**（board._index_at 把它解算成这格
	#    → game._on_tile_clicked 打开详情卡）；上游那一半（BoardView 在鼠标松开时 emit
	#    tile_clicked）是既有代码、本任务没碰，`_on_table_click` 返回 false 意味着这次点击
	#    会照原样送进桌垫走到它。
	var idx_bad := 0
	var swallowed := 0
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		var low_pt := Vector2(cell.get_center().x, cell.end.y - 3.0)
		if g.board._index_at(low_pt) != i:
			idx_bad += 1
		if g._on_table_click(low_pt):
			swallowed += 1
	_check(idx_bad == 0, "近排每格的下沿采样点都解算到它自己（解错 %d 格）" % idx_bad)
	_check(swallowed == 0, "近排 %d 格的下沿全都能点（被手牌吞掉 %d 格）" % [near_row.size(), swallowed])
	var free_tile: int = near_row[mini(3, near_row.size() - 1)]
	var cell_f: Rect2 = cell_of.call(free_tile)
	var low_f := Vector2(cell_f.get_center().x, cell_f.end.y - 3.0)
	g.info_panel.visible = false
	g._on_tile_clicked(free_tile)          # 桌垫那一端（tile_clicked）接的就是它
	await process_frame
	_check(g.info_panel.visible, "该格（#%d）详情卡打开（_index_at → _on_tile_clicked 这一半打通）" % free_tile)

	print("== 手牌重排：抬起反馈不漂（每次广播都重摆一遍手牌）==")
	g.s_state(s_hand)
	await process_frame
	var y1_plain: float = tph.hand_rect(1).get_center().y      # 抬起前的第二张
	# 批次 7 起点击 = 直出（点一下就把 跑腿券 用掉），要钉「广播重摆不丢抬起反馈」就得走
	# **保留的玩法侧选中入口** —— 它写 selected_slot + set_hand_selected，是抬起反馈的唯一来源。
	g._on_item_slot_clicked(g.my_peer, 1)
	_check(g.selected_slot == 1, "选中第二张（实得 %d）" % g.selected_slot)
	g.s_state(s_hand)                    # 再来一次广播：手牌被重摆
	await process_frame
	_check(g.selected_slot == 1, "广播重摆手牌后选中态不漂（实得 %d）" % g.selected_slot)
	_check(tph.hand_rect(1).get_center().y < y1_plain - 4.0,
		"重摆后抬起反馈还在（抬起的第二张 %.0f，未抬起时是 %.0f）"
			% [tph.hand_rect(1).get_center().y, y1_plain])
	g._cancel_target()
	_check(g.selected_slot == -1, "收尾：选中态清空（实得 %d）" % g.selected_slot)

	print("== 悬停手牌：放大 + 抬起（批次 12 B3）==")
	# 悬停链（`TableView3D.on_table_hover` → `game._on_table_hover`）原先只看棋子，现在**手牌也进链**
	#（棋子优先）。悬停的那张：放大 1.12 + 抬起 0.06 世界单位，过渡是 0.12s 的 `Tween`（一次性过渡）。
	# 断言一律走**可观察量**：牌节点的 scale / 世界 y，以及 `hand_hover()` / `hand_hover_amt()`。
	# 走**真入口**（注入点 `on_table_hover`），不是直调 `g._on_table_hover`。
	g.table3d.snap_view(0.0)
	await process_frame
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var hcard1 := tph.get_node("Hand").get_child(1) as MeshInstance3D
	var hy0: float = hcard1.global_position.y
	_check(tph.hand_hover() == -1 and tph.hand_hover_amt(1) < 0.01,
		"（前提）还没悬停（实得 %d / %.2f）" % [tph.hand_hover(), tph.hand_hover_amt(1)])
	var hov_pt: Vector2 = tph.hand_rect(1).get_center()
	_check(int(g.table3d.on_table_hover.call(hov_pt)) == GameData.NO_PEER,
		"悬停在手牌上：它不是棋子（返回哨兵 NO_PEER，信息条不该为它冒出来）")
	_check(tph.hand_hover() == 1, "悬停链认出手牌那一张（实得 %d）" % tph.hand_hover())
	_check(not g.token_tip.visible, "悬停手牌不会让棋子信息条冒出来")
	# 幂等：同一张再来一次不重建补间（鼠标在牌上抖一下会连调几十次；重建会让放大停在起点）
	var htw1 = tph._hand_hover_tw
	g.table3d.on_table_hover.call(hov_pt)
	_check(tph._hand_hover_tw == htw1, "同一张重复悬停不重建补间（幂等）")
	# 等这 0.12s 的补间走完
	var t_b3 := Time.get_ticks_msec()
	while tph.hand_hover_amt(1) < 0.99 and Time.get_ticks_msec() - t_b3 < 3000:
		await process_frame
	_check(tph.hand_hover_amt(1) > 0.99, "悬停补间走完（实得 %.2f）" % tph.hand_hover_amt(1))
	_check(hcard1.scale.x > 1.10 and hcard1.scale.x < 1.14,
		"悬停那张**放大了**（scale %.3f，期望 1.12）" % hcard1.scale.x)
	_check(hcard1.global_position.y > hy0 + 0.04,
		"悬停那张**抬起来了**（世界 y %.3f → %.3f，期望 +0.06）" % [hy0, hcard1.global_position.y])
	# 邻居不受影响（放大只发生在悬停那一张身上）
	var hcard0 := tph.get_node("Hand").get_child(0) as MeshInstance3D
	_check(absf(hcard0.scale.x - 1.0) < 0.001 and tph.hand_hover_amt(0) < 0.01,
		"没悬停的那张纹丝不动（scale %.3f）" % hcard0.scale.x)
	# 移开：收回原状
	g.table3d.on_table_hover.call(Vector2.INF)      # 射线打不到桌面那一路 —— 悬停全清
	_check(tph.hand_hover() == -1, "移开后悬停目标清掉（实得 %d）" % tph.hand_hover())
	var t_b3b := Time.get_ticks_msec()
	# 阈值必须与下面那条断言**同量级**：`scale = 1 + 0.12 × amt`，而
	# `Vector3.is_equal_approx(Vector3.ONE)` 的相对容差只有 1e-5 ⇒ 等 `amt ≤ 0.01` 就断言，
	# 会在 amt 落在 (8e-5, 0.01] 时假红（实测 4 次里红 1 次）。等到**真的归零**再断言。
	while tph.hand_hover_amt(1) > 0.0001 and Time.get_ticks_msec() - t_b3b < 3000:
		await process_frame
	_check(hcard1.scale.is_equal_approx(Vector3.ONE)
			and absf(hcard1.global_position.y - hy0) < 0.002,
		"移开后收回原状（scale %.3f / 世界 y %.3f，原 %.3f）"
			% [hcard1.scale.x, hcard1.global_position.y, hy0])
	# **别把棋子的信息条改坏**：悬停棋子照旧出条，且同一次悬停里手牌不参与（棋子优先）
	var tok_pt: Vector2 = g.board.token_screen_pos(0, 0)
	_check(int(g.table3d.on_table_hover.call(tok_pt)) == 1, "悬停棋子照旧命中 peer 1")
	await process_frame
	_check(g.token_tip.visible, "棋子信息条照旧浮出（悬停链没被手牌改坏）")
	_check(tph.hand_hover() == -1, "棋子优先：这一动里手牌没被悬停（实得 %d）" % tph.hand_hover())
	g.table3d.on_table_hover.call(Vector2.INF)

	print("== 丢弃入口已回补：手牌右键 = 丢弃（两步确认，走既有 _discard_item）==")
	# 座位卡「✕」随牌位拆除后 `_on_discard_clicked` 一度**没有发射方**（终审 R1）；
	# 现在右键落在手牌上即丢弃：第一下进入待确认（牌身染红）、第二下真丢。
	# 证据必须落在**玩法侧**：房主侧背包真的少一件，且走的是既有 `_discard_item`（没绕开玩法）。
	# 走**真实**的 `_on_table_click`（按键由 TableView3D 的输入映射带进来）。
	g.my_peer = 2
	g.hp = [
		{"peer": 2, "name": "我", "color": 1, "bot": false, "alive": true, "money": 20000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "silence": 0, "shield": 0,
			"items": [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]},
	]
	var s_disc: Dictionary = _state(2, false)
	s_disc.await = "item"
	s_disc.await_peer = 2
	for p in s_disc.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_disc)
	await process_frame
	await process_frame
	g._process(0.0)
	_check(int(g._player_by_peer(2).items.size()) == 3, "前置：房主侧背包 3 件（实得 %d）"
		% int(g._player_by_peer(2).items.size()))
	var c1: Vector2 = tph.hand_rect(1).get_center()
	_check(g._on_table_click(c1, MOUSE_BUTTON_RIGHT), "右键点第二张牌：这次点击被手牌消费（丢弃入口回来了）")
	_check(g._discard_pending == 1, "第一下右键：进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == 3, "第一下右键：**还没**真丢（背包仍 3 件）")
	_check(tph._hand_disc == 1, "待确认那张牌身的红标已贴上（实得 _hand_disc=%d）" % tph._hand_disc)
	var dcol: Color = tph._hand_body_mats[1].albedo_color
	_check(dcol.r > dcol.g + 0.3 and dcol.r > dcol.b + 0.3, "牌身染红（实得 %s）" % str(dcol))
	_check(tph._hand_face_mats[1].albedo_color == Color.WHITE, "牌面贴图**没**被染（face 材质仍是原色）")
	_check(absf(tph.hand_rect(1).get_center().y - c1.y) < 3.0, "待确认**不**抬起（抬起是选中态的事）")
	# 广播后不丢：`_refresh_table_props` 会按 `_discard_pending` 重放红标（与 set_hand_selected 同款）
	g.s_state(s_disc)
	await process_frame
	g._process(0.0)
	_check(tph._hand_disc == 1 and g._discard_pending == 1, "广播重摆手牌后待确认态不漂（实得 %d / %d）"
		% [tph._hand_disc, g._discard_pending])
	# 第二下右键：真丢 —— 走既有 _discard_item（背包少一件、待确认清掉）
	_check(g._on_table_click(c1, MOUSE_BUTTON_RIGHT), "第二下右键：仍被手牌消费")
	_check(g._discard_pending == -1, "第二下右键：待确认清掉（实得 %d）" % g._discard_pending)
	var its_after: Array = g._player_by_peer(2).items
	_check(its_after.size() == 2, "第二下右键：房主侧背包真的少了一件（实得 %d）" % its_after.size())
	var ids_after: Array = []
	for it in its_after:
		ids_after.append(String(it.id))
	_check(not ids_after.has("跑腿券"), "丢掉的正是点中的那张（跑腿券）——走既有 _discard_item（剩 %s）" % str(ids_after))

	# 生效条件：非 playing 阶段 / 选目标中 → 右键手牌**不消费**（落回棋盘 = 既有取消）
	var s_not: Dictionary = s_disc.duplicate(true)
	s_not.phase = "ended"
	g.s_state(s_not)
	await process_frame
	g._process(0.0)
	var n_not: int = int(g._player_by_peer(2).items.size())
	_check(not g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT),
		"非 playing 阶段：右键手牌不消费（落回棋盘，那里右键仍是取消）")
	_check(g._discard_pending == -1 and int(g._player_by_peer(2).items.size()) == n_not,
		"非 playing 阶段：既不进待确认、也不丢")

	print("== 待确认丢弃不再永不解除（终审 Minor）==")
	# 背景：`_discard_pending` 原先 armed 之后**永不解除**，而 `_refresh_table_props` 每次广播
	# 会**无条件重放**它，于是 ① 道具阶段结束（跳过 / 超时 / 回合推进）红标整轮挂着，下一次右键
	# **一下**就把牌丢了（本该两步）；② armed 期间背包重排（交换生换牌 / 蛋蛋节发牌），下标指到
	# **另一张**牌 ⇒ 红标落到玩家从未 arm 过的那张上，一次右键就丢错东西。
	# 修法：重放前按两条判据核对这把待确认还作不作数 —— **arm 时的 (turn, await) 窗口**
	#（理由见 game.gd 的 `_discard_arm_turn`；`phase` 判据是恒假的，别退回去）+ **按 id 认牌**
	#（理由见 game.gd 的 `_discard_pending_id`）。这里三条各钉一次。
	g.my_peer = 2
	var s_re: Dictionary = _state(2, false)
	s_re.await = "item"
	s_re.await_peer = 2
	for p in s_re.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp = [
		{"peer": 2, "name": "我", "color": 1, "bot": false, "alive": true, "money": 20000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "silence": 0, "shield": 0,
			"items": [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]},
	]
	g.s_state(s_re)
	await process_frame
	g._process(0.0)

	# ① 背包重排：该下标的 **id 变了**（位置不变、内容变了 —— 交换生换牌就长这样）
	var cr: Vector2 = tph.hand_rect(1).get_center()
	_check(g._on_table_click(cr, MOUSE_BUTTON_RIGHT), "（前置）右键第二张：进待确认")
	_check(g._discard_pending == 1 and tph._hand_disc == 1,
		"（前置）待确认槽位 = 1、红标已贴（实得 %d / %d）" % [g._discard_pending, tph._hand_disc])
	var s_re2: Dictionary = s_re.duplicate(true)
	for p in s_re2.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "招财猫", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "招财猫", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_re2)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "重排后该下标的 id 变了：待确认自动解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "红标随之收掉（实得 _hand_disc=%d）" % tph._hand_disc)
	# 关键：解除之后下一次右键只**进入待确认**，不会一下就把牌丢出去
	var n_re: int = int(g._player_by_peer(2).items.size())
	_check(g._on_table_click(tph.hand_rect(1).get_center(), MOUSE_BUTTON_RIGHT), "解除后再右键：仍被手牌消费")
	_check(g._discard_pending == 1, "解除后再右键：只进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == n_re,
		"解除后再右键：**没有**真丢（背包仍 %d 件）——两步确认回来了" % n_re)
	g._cancel_target()

	# ② armed 之后**道具阶段结束**（「跳过」/ 超时 ⇒ `await` 变），而**背包一件没动**：
	#    待确认必须解除、红标不跨阶段挂着。守卫原先那条 `phase != "playing"` 是**恒假**的
	#   （`phase` 整局只有 "playing" / 整局结束才 "ended"，见 game.gd 的 `_discard_arm_turn`），
	#    所以这条路一直漏着：arm 一张牌 → 跳过 → 背包没变 → 红标整轮挂着 → 下一次右键**一下**
	#    就把牌丢了。现在按 **arm 时的 (turn, await) 窗口**核对（判据与理由见 `_discard_arm_turn`）。
	var s_re3: Dictionary = _state(2, false)
	s_re3.await = "item"
	s_re3.await_peer = 2
	for p in s_re3.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_re3)
	await process_frame
	g._process(0.0)
	_check(g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT), "（前置）右键第一张：进待确认")
	_check(g._discard_pending == 0 and tph._hand_disc == 0,
		"（前置）待确认槽位 = 0、红标已贴（实得 %d / %d）" % [g._discard_pending, tph._hand_disc])
	var s_re4: Dictionary = s_re3.duplicate(true)
	s_re4.await = "roll"                       # 道具阶段结束（跳过 / 超时后环节变了；背包不动）
	g.s_state(s_re4)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "道具阶段结束（await 变）时待确认解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "道具阶段结束后红标收掉（实得 _hand_disc=%d）" % tph._hand_disc)
	# 关键：解除之后下一次右键只**进入待确认**，不会一下就把牌丢出去（背包故意一件没动）
	var n_aw: int = int(g._player_by_peer(2).items.size())
	_check(g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT), "解除后再右键：仍被手牌消费")
	_check(g._discard_pending == 0, "解除后再右键：只进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == n_aw and n_aw == 3,
		"解除后再右键：**没有**真丢（背包仍 %d 件）——两步确认回来了" % n_aw)

	# ③ 另一半解除路径：**回合推进**（`turn` 变、`await` 不变）。窗口判据对两者一视同仁。
	var s_re5: Dictionary = s_re4.duplicate(true)
	s_re5.turn = 3
	g.s_state(s_re5)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "回合推进（turn 变）时待确认解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "回合推进后红标收掉（实得 _hand_disc=%d）" % tph._hand_disc)

	print("== 选目标期间：手牌对点击完全透明（终审 R2）==")
	# `_hand_clickable` 补上 `_tgt_stage == ""`：选目标时玩家**正要**点格子 / 四角条，手牌不能抢答成
	# 「改选另一张牌」。修完后手牌在选目标期间对点击**完全透明**：左键落回棋盘 = 选格、
	# 右键 = 既有取消。
	# **批次 5 Task 3 起这条闸仍然必须站岗**，虽然牌已不再盖住任何近排格子（见上一段）：
	# 玩家在选格时点到自己的牌上，那一下同样不能变成"换选另一张牌"。
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_disc)
	await process_frame
	g._process(0.0)
	var probe_pt: Vector2 = tph.hand_rect(0).get_center()
	_check(tph.hand_hit(probe_pt) == 0, "（对照）这个点确实落在第一张牌的命中盒里")
	g._begin_tile_target(0, [near_row[0]])
	_check(g._tgt_stage == "tile" and g._tgt_tiles.has(near_row[0]), "进了选地块态、该格可选")
	_check(not g._on_table_click(probe_pt, MOUSE_BUTTON_LEFT),
		"选目标期间：左键点手牌不消费（落回棋盘）")
	_check(not g._on_table_click(probe_pt, MOUSE_BUTTON_RIGHT),
		"选目标期间：右键手牌也不消费（落回棋盘 = 既有取消）")
	_check(g.selected_slot == -1, "选目标期间点牌不改选中态（实得 %d）" % g.selected_slot)
	# 该格的下沿仍照原样落回桌垫（手牌不消费 → 会进 tile_clicked）
	var cell_r0: Rect2 = cell_of.call(near_row[0])
	var low_r0 := Vector2(cell_r0.get_center().x, cell_r0.end.y - 3.0)
	_check(not g._on_table_click(low_r0, MOUSE_BUTTON_LEFT),
		"选目标期间：点近排格子的下沿也不被手牌消费")
	_check(g.board._index_at(low_r0) == near_row[0], "该点仍解算到这格（会照原样进桌垫 → tile_clicked）")
	g._on_tile_clicked(near_row[0])           # 桌垫那一端（tile_clicked）接的就是它
	_check(g._tgt_stage == "", "该格被选中 → 选目标态收尾（实得「%s」）" % g._tgt_stage)
	g._cancel_target()

	print("== 老的「四块立牌」（批次 9 的 `Standees`）已退场：接口与节点都不在（不留空壳） ==")
	# ⚠ 别与 v0.8.0 第三次改版那三块**桌面立牌**搞混：那是**另一样东西**
	#（`table_props._placards` / `Placards/Placard{peer}`，见 `tests/placard_test.gd`）；这里钉的是
	# 老 2D 版座位卡那一套（带公开背包 / 身家，批次 9 整体删除）。
	var tpS = g.table3d.table_props
	_check(tpS != null, "TableProps 在")
	if tpS != null:
		_check(not tpS.has_method("set_standees"), "set_standees 已退场")
		_check(not tpS.has_method("standee_hit"), "standee_hit 已退场")
		_check(not tpS.has_method("standee_screen_center"), "standee_screen_center 已退场")
		_check(not tpS.has_method("set_standee_timer"), "set_standee_timer 已退场")
		_check(not tpS.has_method("set_standee_highlight"), "set_standee_highlight 已退场")
		_check(tpS.get_node_or_null("Standees") == null, "桌上没有立牌父节点")
	_check(not g.has_method("_refresh_standees"), "game._refresh_standees 已退场")
	var TP1 = load("res://scripts/table_props.gd")
	var tp_consts: Dictionary = TP1.get_script_constant_map()
	_check(not tp_consts.has("STANDEE_SIZE") and not tp_consts.has("STANDEE_BASE_PX") \
			and not tp_consts.has("BACKPACK_MAX"),
		"立牌常量（STANDEE_* / BACKPACK_MAX）已删")

	print("== 身家条 / 立牌可点 → 玩家道具弹窗（批次 9；落点批次 12 D 到名册条、v0.8.0 第三次改版到桌面立牌）==")
	g.my_peer = 2
	var s_cb: Dictionary = _state(2, false)
	for p in s_cb.players:
		if int(p.peer) == 1:
			p.stamina = 4
			p.items = [{"id": "招财猫", "cd": 0}, {"id": "黑卡", "cd": 0, "charges": 3}]
	g.s_state(s_cb)
	await process_frame
	await process_frame
	g._process(0.0)
	_check(g.corner_bars[0].root.mouse_filter == Control.MOUSE_FILTER_STOP,
		"我这条吃点击（STOP）")
	# 名册行那三条（行根 STOP / 行根 meta / "peer 1 那一行在名册条里"）**随载体删除**：
	# 别人那一条现在是**桌面立牌**，点击入口换成 `_on_table_click → placard_hit`（3D 命中盒，
	# 没有 Control 根、也没有 meta）——见 `tests/placard_test.gd` ⑧⑨。
	# 后果函数一字未改，所以下面仍走同一个 `_on_corner_bar_clicked`。
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup != null and g.player_popup.is_open(), "点 peer 1 → 道具弹窗打开")
	_check(g.player_popup.item_count == 2, "弹窗里卡牌数与 st 一致（2 件，实得 %d）" % g.player_popup.item_count)
	_check(g.player_popup.stamina_text == "4", "弹窗里能量（体力）值与 st 一致（实得「%s」）" % g.player_popup.stamina_text)
	# 名次徽章（批次 12 D 的隐性回归点）：`_rank_of` 原先回头去 `corner_bars` 里翻 —— 四角条只剩
	# "我"一条之后，那条路只查得到自己，**别人的弹窗徽章会集体消失**。现在改读 `_standing_by_peer`。
	# fixture 里乙(我) 20000 > 甲 15800 ⇒ 甲排第 2。
	_check(g._rank_of(1) == 2, "名次表里甲排第 2（`_rank_of` 改读 `_standing_by_peer` 之后仍准，实得 %d）" % g._rank_of(1))
	var pop_labels: Array = _popup_labels(g.player_popup)
	_check(pop_labels.has("2"), "弹窗里画出了甲的名次徽章「2」（实测标签 %s）" % str(pop_labels))
	g.player_popup.close()
	_check(not g.player_popup.is_open(), "关闭后收起")
	# 反向：不存在的玩家不该开（人少了 / 自己不在名册时不崩）
	g._on_corner_bar_clicked(999)
	_check(not g.player_popup.is_open(), "点一个不存在的玩家：不开弹窗、也不崩")
	# **真链路那条（从名册行根发一次 `gui_input`）随载体删除**：立牌没有 Control 根、没有 meta、
	# 也没有"闭包捕获 peer"这个坑（peer 由 `placard_hit` 当场从节点上算出来）。
	# 对应覆盖搬去 `tests/placard_test.gd` ⑧⑨：`placard_hit(px)` 返回该家的 peer，
	# 且 `g._on_table_click(px, LEFT)` 真的开该玩家的道具弹窗。
	g.player_popup.close()

	print("== 弹窗关闭路径（终审 fix wave）==")
	# 三条真链路各钉一次 —— 此前只测了直调 `close()`，而"✕ / 点外部 / Esc 都能关"
	# 是本批写明的验收项（`hud_test.gd:1188` 那条 `gui_input` 真链路同风格）。
	# ① 点压暗底（`_dim` 上那条 gui_input lambda，**只认左键**）→ 关。
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.is_open(), "重开（准备测压暗底）")
	var left_ev := InputEventMouseButton.new()
	left_ev.button_index = MOUSE_BUTTON_LEFT
	left_ev.pressed = true
	g.player_popup._dim.gui_input.emit(left_ev)
	await process_frame
	_check(not g.player_popup.is_open(), "点压暗底（真 gui_input 链路）→ 弹窗关闭")
	# ② 非左键（滚轮 / 右键）**不该**关 —— 同一条 lambda 里那道按键判断。
	g._on_corner_bar_clicked(1)
	await process_frame
	var wheel_ev := InputEventMouseButton.new()
	wheel_ev.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_ev.pressed = true
	g.player_popup._dim.gui_input.emit(wheel_ev)
	await process_frame
	_check(g.player_popup.is_open(), "滚轮点压暗底：不关（只认左键）")
	# ③ Esc 走 `game._unhandled_input` 的**真分支**（不是直调 close）。前置：此刻没有选目标态 /
	# 未选中牌 —— 那两个也吃 Esc，且排在同一函数里更靠前的位置。
	_check(g._tgt_stage == "" and g.selected_slot < 0, "Esc 之前：无选目标态 / 未选中牌（前置）")
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.pressed = true
	g._unhandled_input(esc_ev)
	await process_frame
	_check(not g.player_popup.is_open(), "Esc（真 _unhandled_input 链路）→ 弹窗关闭")

	print("== 弹窗内容：（被动）标签（终审 fix wave）==")
	# 「完成标准」把"被动标记"列为弹窗内容之一，但此前没有断言钉它。招财猫 `type: passive`
	# ⇒ 它那一行后缀里应有「（被动）」。读**行内 Label 的 text**（最强可观察量），不读内部标志。
	# **批次 12 B2 改结构**：一行一件的"小图标 + 名字"换成**一整张 `ItemCard`**
	#（+ 卡下面的名字 / 标签），所以这里改成遍历**整棵弹窗控件树**找 Label
	#（不再假设"HBoxContainer 行"这种内部结构 —— 那个假设正是被本条目改掉的东西）。
	var s_pas: Dictionary = _state(3, false)
	for p in s_pas.players:
		if int(p.peer) == 1:
			p.items = [{"id": "招财猫", "cd": 0}]
	g.s_state(s_pas)
	await process_frame
	await process_frame
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.item_count == 1, "弹窗里 1 件（招财猫，实得 %d）" % g.player_popup.item_count)
	var row_texts := _popup_labels(g.player_popup)
	var has_passive := false
	for t in row_texts:
		if String(t).contains("（被动）"):
			has_passive = true
	_check(has_passive, "弹窗里那张卡下面含「（被动）」（招财猫是 passive；实得 %s）" % str(row_texts))
	g.player_popup.close()

	print("== 弹窗：道具是**一整张卡**（批次 12 B2）==")
	# 从"30×30 图标 + 名字"改成**真的 `ItemCard` 节点**（与商店货架同一份画法，弹窗本来就是 Control 树
	# ⇒ 直接挂，没有烘焙）+ 换行排布（`FlowContainer`）+ 超高滚动（`ScrollContainer`）。
	# 断言的强可观察量：**渲染出来的 `ItemCard` 节点数 == 道具数**、每张卡的 id/名字对得上。
	var IC_POP = load("res://scripts/item_card.gd")     # 静态写类名会拽进 ui_kit（引用 autoload Fx）
	var s_bag: Dictionary = _state(3, false)
	var bag_ids := ["招财猫", "作弊器", "黑卡", "包租婆", "共享单车"]
	for p in s_bag.players:
		if int(p.peer) == 1:
			p.stamina = 4
			p.items = []
			for bid in bag_ids:
				p.items.append({"id": String(bid), "cd": 0})
	g.s_state(s_bag)
	await process_frame
	await process_frame
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.item_count == bag_ids.size(),
		"弹窗记下 5 件（实得 %d）" % g.player_popup.item_count)
	var icards := _popup_item_cards(g.player_popup, IC_POP)
	_check(icards.size() == bag_ids.size(),
		"渲染出来的 `ItemCard` 数 == 道具数（%d 张，期望 %d）" % [icards.size(), bag_ids.size()])
	var ids_ok := true
	for k in mini(icards.size(), bag_ids.size()):
		if String(icards[k].id) != String(bag_ids[k]):
			ids_ok = false
	_check(ids_ok, "每张卡的 id 与该件道具一致（%s）"
		% str(icards.map(func(c): return String(c.id))))
	# 名字：卡**下面**那行大字（`_item_row` 补的那条）+ 卡面自带的名称条 —— 两条都要有名字。
	var labels := _popup_labels(g.player_popup)
	var names_ok := true
	for bid in bag_ids:
		var hit := false
		for t in labels:
			if String(t) == String(bid):
				hit = true
		if not hit:
			names_ok = false
	_check(names_ok, "5 件道具的名字都在弹窗里读得到（实测标签：%s）" % str(labels))
	# 布局容器：`FlowContainer` 装在 `ScrollContainer` 里（大背包换行 + 滚动，不把面板顶出屏幕）
	var sc_bag: Node = g.player_popup.find_child("BagScroll", true, false)
	var flow_bag: Node = g.player_popup.find_child("BagFlow", true, false)
	_check(sc_bag != null and flow_bag != null and (flow_bag as Control).get_parent() == sc_bag,
		"背包区是 `ScrollContainer` > `FlowContainer`（换行 + 超高滚动）")
	_check(sc_bag != null and (sc_bag as ScrollContainer).vertical_scroll_mode \
			== ScrollContainer.SCROLL_MODE_AUTO
			and (sc_bag as ScrollContainer).horizontal_scroll_mode \
			== ScrollContainer.SCROLL_MODE_DISABLED,
		"背包区只滚纵向（横向关掉，子节点才按容器宽度换行）")
	# ---- 批次 13 ⑤：按规则上限画**固定槽位数**（已拥有 = 卡，未拥有 = 空槽占位框）----
	# 断言的强可观察量：槽位总数 == `_bag_cap`（基础 5），且空槽也真的画出来了 ——
	# 用户 ⑤ 要的就是"看得出最多只能同时拥有 5 张"。
	var PP = load("res://scripts/player_popup.gd")
	_check((PP.ITEM_CARD_SIZE as Vector2).is_equal_approx(IC_POP.SIZE_LARGE),
		"弹窗卡面用大档 `ItemCard.SIZE_LARGE`（描述字号 12px；旧档 168 高只有 7px，用户报看不清）")
	# 注意：一个槽位是 `_item_row` 返回的 **VBox（卡 + 名字 + 标签）**、不是裸的 ItemCard，
	# 所以"这一格有没有卡"要往子树里找 —— 别拿 `get_script() == IC_POP` 直接判格根。
	var slot_has_card := func(cell: Node) -> bool:
		if cell.get_script() == IC_POP:
			return true
		for n in cell.find_children("*", "", true, false):
			if n.get_script() == IC_POP:
				return true
		return false
	var slot_cells: Array = (flow_bag as Control).get_children()
	_check(slot_cells.size() == 5,
		"背包区画出 5 个槽位（基础上限 5，实得 %d）" % slot_cells.size())
	var empty_l: int = 0
	for cell in slot_cells:
		if not slot_has_card.call(cell):
			empty_l += 1
	_check(empty_l == 0, "满包（5/5）时没有空槽（实得 %d）" % empty_l)
	# 面板没有被 5 件道具顶出屏幕（滚动的意义就在这条）
	_check(g.player_popup._panel.size.y <= g.size.y - 40.0,
		"5 件道具时面板仍在屏幕内（高 %.0f / 屏幕 %.0f）"
			% [g.player_popup._panel.size.y, g.size.y])
	# 高度公式要把**卡下面那行名字 / 标签**也算进去：只按卡高算的话 `ScrollContainer` 会矮一截、
	# 名字那一行被裁掉（出图逮到过）。判据：**一行装得下**时内容高度 ≤ 容器高度（根本不用滚）。
	var s_one: Dictionary = _state(3, false)
	for p in s_one.players:
		if int(p.peer) == 1:
			p.items = [{"id": "招财猫", "cd": 2}]
	g.s_state(s_one)
	await process_frame
	await process_frame
	g._on_corner_bar_clicked(1)
	await process_frame
	var sc1: Node = g.player_popup.find_child("BagScroll", true, false)
	var flow1: Node = g.player_popup.find_child("BagFlow", true, false)
	_check(sc1 != null and flow1 != null and (flow1 as Control).size.y <= (sc1 as Control).size.y + 1.0,
		"一件道具时背包区**不用滚**（内容高 %.0f ≤ 容器高 %.0f）—— 卡下面那行名字也算进了高度"
			% [(flow1 as Control).size.y if flow1 != null else -1.0,
				(sc1 as Control).size.y if sc1 != null else -1.0])
	# 批次 13 ⑤：一件道具 ⇒ 1 张卡 + **4 个空槽**（槽位总数仍是上限 5）。
	var cells1: Array = (flow1 as Control).get_children()
	var empties1: int = 0
	for cell in cells1:
		if not slot_has_card.call(cell):
			empties1 += 1
	_check(cells1.size() == 5 and empties1 == 4,
		"1 件道具时画出 1 张卡 + 4 个空槽（实得 %d 格 / %d 空槽）" % [cells1.size(), empties1])
	g.player_popup.close()
	await process_frame                              # `close()` 是 `queue_free`，本帧末才真删
	_check(g.player_popup._body.get_child_count() == 0, "关闭后背包区（含卡）整体清掉")

	# ---- 批次 13 ⑤ 修复：槽位数读的是**背包上限**（`_bag_cap`），不是体力上限（`_stamina_cap`）----
	# **上面那几段是假绿的温床**：那个 fixture 既没「置物架」也没「充电宝」⇒ 两个上限**都是 5**，
	# "槽位数读哪个键"根本分不出来（曾经就是拿**体力上限**去画的，上面几条照样全绿）。
	# 判据必须让两个上限**真的分叉**：给目标**同时**发「置物架」（`_bag_cap` 5 → **7**）与
	# 「充电宝」（`_stamina_cap` 5 → **6**），于是"槽位 7 / 能量小格 6"**只有各读各的键才同时成立**：
	#   * 把槽位数换回 `_stamina_cap` ⇒ 槽位变 6、空槽少一个、读数变「背包 2 / 6 格」（三处红）；
	#   * 把「能量」那排换成 `bag_cap` ⇒ 小格变 7（红）。
	# **持有件数必须少于两个上限**（这里只发 2 件）：`_fill` 里那句兜底
	# `maxi(items.size(), 1)` 会在"件数 ≥ 上限"时把错的槽位数**顶成件数**、把这条断言整个盖住
	#（实测：发 7 件、把槽位数换回 `_stamina_cap`，整套 hud_test 照样 ALL PASS）—— 所以这里发 2 件。
	var s_rack: Dictionary = _state(3, false)
	for p in s_rack.players:
		if int(p.peer) == 1:
			p.stamina = 4
			p.items = [
				{"id": "置物架", "cd": 0},   # 背包上限 5 → 7
				{"id": "充电宝", "cd": 0},   # 体力上限 5 → 6
			]
	g.s_state(s_rack)
	await process_frame
	await process_frame
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.item_count == 2, "（前置）置物架 + 充电宝那一份 = 2 件（实得 %d）"
		% g.player_popup.item_count)
	var flow_rack: Node = g.player_popup.find_child("BagFlow", true, false)
	_check(flow_rack != null, "（前置）这一份的背包区已建")
	# 三元兜底：`find_child` 落空时别直接解引用 —— 脚本错误会**打断协程**、整个 SceneTree 挂死。
	var cells_rack: Array = (flow_rack as Control).get_children() if flow_rack != null else []
	_check(cells_rack.size() == 7,
		"带「置物架」⇒ 画出 **7** 个槽位（背包上限 `_bag_cap` = 7；拿体力上限只画 6，实得 %d）"
			% cells_rack.size())
	var empty_rack: int = 0
	for cell in cells_rack:
		if not slot_has_card.call(cell):
			empty_rack += 1
	_check(empty_rack == 5,
		"2 件 ⇒ 5 个空槽（7 - 2；拿体力上限会只剩 4，实得 %d）" % empty_rack)
	var labels_rack := _popup_labels(g.player_popup)
	_check(labels_rack.has("背包 2 / 7 格"),
		"背包读数用的是**背包上限**（「背包 2 / 7 格」；若误用体力上限会写「背包 2 / 6 格」，实测标签：%s）"
			% str(labels_rack))
	# 对照：同一次填充里「能量」那排仍按**体力上限** 6 走 —— 两个键各司其职、不许互相顶替。
	var energy_row: Node = null
	for n in g.player_popup._body.get_children():
		if n is HBoxContainer and (n as HBoxContainer).get_child_count() > 0 \
				and (n as HBoxContainer).get_child(0) is Label \
				and String(((n as HBoxContainer).get_child(0) as Label).text).begins_with("能量"):
			energy_row = n
	_check(energy_row != null, "（前置）找到「能量」那一行")
	var pips_rack := 0
	if energy_row != null:
		for c in (energy_row as HBoxContainer).get_children():
			if c is Panel:
				pips_rack += 1
	_check(pips_rack == 6,
		"带「充电宝」⇒ 能量小格仍按**体力上限** 6 走（实得 %d；拿背包上限会得到 7）" % pips_rack)
	# 7 格是"两行、开始滚"的那一档（见 `player_popup.BAG_MAX_H` 的说明）—— 面板仍得留在屏幕里。
	_check(g.player_popup._panel.size.y <= g.size.y - 40.0,
		"7 个槽位（两行、开始滚）时面板仍在屏幕内（高 %.0f / 屏幕 %.0f）"
			% [g.player_popup._panel.size.y, g.size.y])
	g.player_popup.close()
	await process_frame

	print("== 选目标：高亮跟着搬到桌面立牌、点它 = 选中（v0.8.0 第三次改版）==")
	# 这段的**判据（`_hl_peers`）一个字没改**，换的只是"贴到哪一棵控件、哪一处落点上"：
	#   批次 9 落在四角条 → 批次 12 D 搬名册条 → **v0.8.0 第三次改版搬桌面立牌**（3D 节点）。
	# 「哪几块亮着」那半现在量的是立牌（`set_placard_hot`），**整段搬去 `tests/placard_test.gd` ⑥**。
	# 这里保留的是**屏幕层那一半**：我这条身家条从不参与选目标高亮（目标从不含自己），
	# 以及"点亮的那家被点 ⇒ 走既有 `_on_seat_clicked`"这条**载体无关的后果链**。
	# 用**强拆令**（两段式：只能选"名下有地"的玩家）—— 它的目标过滤天然分得出"有的亮、有的不亮"。
	g.my_peer = 2
	var s_tg: Dictionary = _state(2, false)
	for p in s_tg.players:
		if int(p.peer) == 2:
			p.items = [{"id": "强拆令", "cd": 0}]   # 给"我"一张两段式牌（`_target_item_id` 读的就是它）
	g.s_state(s_tg)
	await process_frame
	await process_frame
	g._begin_peer_target(0, false, true)           # 直接走入口：进入选玩家态
	await process_frame
	# fixture：`_state()` 的四家是 [1 甲(有一号楼) / 2 乙(我) / 3 丙(无地) / 4 丁(已出局)]，
	# `then_prop=true` 只留下"名下有地"的 ⇒ 可选目标**只有 peer 1 一个**。
	_check(g._hl_peers == [1], "选目标态下 `_hl_peers` 只有 peer 1（目标过滤生效，实得 %s）" % str(g._hl_peers))
	# 我那条四角条不在目标里（目标从不含自己）⇒ 它不该被点亮。
	_check(not _corner_bar_hot(g, g.corner_bars[0]),
		"我那条身家条不参与选目标高亮（目标从不含自己）")
	# 点亮的那家被点 → 真的进"选定后"的后果（走既有 _on_seat_clicked）
	g._on_corner_bar_clicked(1)                    # 强拆令这类需要再选一块地 ⇒ 转进选地块段
	_check(String(g._tgt_stage) == "tile" and int(g._tgt_peer) == 1,
		"点亮的那家被点 → 走既有选目标链（tgt_stage=「%s」/ tgt_peer=%d）" % [g._tgt_stage, g._tgt_peer])
	g._cancel_target()
	await process_frame
	_check(not _corner_bar_hot(g, g.corner_bars[0]),
		"取消选目标后我这条身家条仍是熄灭的（高亮只在可选中的那几家身上）")

	print("== 拖动指向（#24）：拖到对手的桌面立牌松手 = 选定；拖到别处松手 = 取消 ==")
	# 按下手牌 = 一次"拖动指向"的起点（`_drag_active`），配对松开由 `table3d.on_table_release`
	# 交给 `_on_table_release` 收尾：拖动超过阈值才结算，单击保留旧交互。
	g.my_peer = 2
	var s_drag: Dictionary = _state(2, false)
	s_drag.await = "item"
	s_drag.await_peer = 2
	for p in s_drag.players:
		if int(p.peer) == 2:
			p.items = [{"id": "强拆令", "cd": 0}, {"id": "跑腿券", "cd": 0}]
	g.s_state(s_drag)
	await process_frame
	await process_frame
	g._process(0.0)
	_check(g._on_table_click(g.table3d.table_props.hand_rect(0).get_center()),
		"拖动：按下强拆令被手牌消费")
	_check(g._tgt_stage == "peer" and g._drag_active,
		"拖动：按下后进选玩家态且 _drag_active 置真（tgt_stage=「%s」）" % g._tgt_stage)
	# 拖到 peer1 那块**桌面立牌**松手（起点假装在别处，> 阈值）。
	# ⚠ **落点换过**：同事写 #24 时用的是**屏幕层名册条里那一格**，而名册条已随 v0.8.0
	# 第四次改版整体删除、目标落点搬到了桌面立牌上（`table_props.placard_screen_center`，
	# 与点击那条链**同一个命中盒**）。不换这里的话 `_bar_of(g, 1)` 会给一个空字典 ⇒
	# 取 `.root` 当场报错、整段 `_run()` 中断（表现为**测试挂死**）。
	var dc: Vector2 = g.table3d.table_props.placard_screen_center(1)
	_check(is_finite(dc.x) and is_finite(dc.y),
		"（前提）peer1 那块桌面立牌能折出屏幕中心（实得 %s）" % str(dc))
	g._drag_press_pos = dc + Vector2(160, 160)
	g._on_table_release(dc, MOUSE_BUTTON_LEFT)
	await process_frame
	_check(g._tgt_stage == "tile" and g._tgt_peer == 1,
		"拖到 peer1 的立牌上松手 → 走既有选目标链（强拆令两段式 ⇒ 转选地块，实得「%s」/%d）"
			% [g._tgt_stage, g._tgt_peer])
	# 单击（移动 < 阈值）：不结算，保留选目标态（旧的"点卡再点目标"仍可用）
	g._drag_active = true
	g._drag_press_pos = Vector2(10, 10)
	g._on_table_release(Vector2(11, 11), MOUSE_BUTTON_LEFT)
	_check(g._tgt_stage == "tile", "单击（未拖动）不结算：保留选目标态")
	# 拖到非目标处松手 → 取消
	g._drag_active = true
	g._drag_press_pos = Vector2(10, 10)
	g._on_table_release(Vector2(400, 400), MOUSE_BUTTON_LEFT)
	_check(g._tgt_stage == "", "拖到非目标处松手 → 取消（tgt_stage 清空）")

	print("== 棋子动画（批次 11 Task 1）：走子抬 y、传送淡到看不见 ==")
	# 棋子那四样动作（逐格走 / 传送 / 弹入 / 光环）在 3D 里重写了（设计 §4.1）。走子与传送
	# 必须有**可观察量** —— 否则"传送看不见"这类事没法断言。这里量两个只读量：
	# `token_world_pos`（走子的 y 弧）与 `token_alpha`（传送的淡出）。
	g.my_peer = 2
	g.s_state(_state(2, false))
	await process_frame
	var tpA = g.table3d.table_props
	if tpA == null or not tpA.has_method("play_token_move"):
		_check(false, "TableProps 没有 play_token_move（棋子动画未接），本段整段跳过")
	else:
		await create_timer(0.5).timeout      # 等首次弹入（scale 0→1）落定
		# peer 3 的棋子节点（读世界位置与材质模式）：与 layout_test 同一条取法（节点池按 peer 命名）
		# 按 **meta("peer")** 找那枚棋子的节点（位置 / 材质模式）——**不按节点名**：同帧重建时
		# Godot 会把重名的子节点自动改名（table_props 已用 remove_child 规避，但测试不该依赖名字）。
		var trootA: Node = tpA.get_node_or_null("Tokens")
		var tk3: Node3D = null
		if trootA != null:
			for ch in trootA.get_children():
				if (ch as Node).has_meta("peer") and int((ch as Node).get_meta("peer")) == 3:
					tk3 = ch as Node3D
		_check(tk3 != null, "peer 3 的棋子节点在（下面几条要读它）")
		var p3 := int(g._state_player(3).get("pos", 0))
		var base_y: float = tpA.token_world_pos(3).y
		_check(base_y > 0.0, "棋子在桌面上（基准 y=%.3f）" % base_y)
		# 走子走**真入口** `s_move`（@rpc call_local：直调就是本机那一次）；两步、每步 0.4s。
		g.s_move(3, [p3 + 1, p3 + 2], 0.4)
		# 采样窗口覆盖整段动画（2 步 × 0.4s）还有余量；每步一个弧，取全程峰值与终值。
		var max_y := base_y
		for i in 36:
			await create_timer(0.03).timeout
			max_y = maxf(max_y, tpA.token_world_pos(3).y)
		_check(max_y > base_y + 0.03,
			"走子期间棋子的世界 y **抬升过**（%.3f → 峰值 %.3f —— 竖直小跳的弧）" % [base_y, max_y])
		_check(absf(tpA.token_world_pos(3).y - base_y) < 0.01,
			"走完落回桌面高度（%.3f，基准 %.3f）" % [tpA.token_world_pos(3).y, base_y])
		# 传送：`s_tp`（送监 / 传送类道具走的同一条）——淡出 → 瞬移 → 淡入。
		# **放慢 5 倍再采样**：`token_alpha` 只有逐帧采样才抓得住"淡到看不见"那一档，
		# 正常速度下每帧的 alpha 步长（≈0.075/帧）比判据还粗，采不到接近 0 的点。
		var before_tp: Vector3 = tpA.token_world_pos(3)
		Engine.time_scale = 0.2
		g.s_tp(3, 12)
		var min_a := 1.0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2600:
			await process_frame
			min_a = minf(min_a, tpA.token_alpha(3))
		Engine.time_scale = 1.0
		_check(min_a < 0.05, "传送期间棋子**淡到看不见**（alpha 最低 %.3f）" % min_a)
		_check(tpA.token_alpha(3) > 0.95, "传送完毕回到不透明（%.3f）" % tpA.token_alpha(3))
		_check(tpA.token_world_pos(3).distance_to(before_tp) > 0.1,
			"传送落点真的变了（%s → %s）" % [before_tp, tpA.token_world_pos(3)])
		# 材质**模式**也要恢复（批次 11 T1 审查 Minor #4）：只把 alpha 写回 1、模式留在 ALPHA 的
		# 实现照样能过上面那条 `token_alpha` —— 但那样的牌在**透明队列**里：不写深度、不投影
		# （批次 8/9 那条先例）。照 `hand` 那组既有断言（读材质、不读标志）。
		var pmat3: StandardMaterial3D = null
		var fmat3: StandardMaterial3D = null
		if tk3 != null:
			pmat3 = (tk3.get_node("Plate") as MeshInstance3D).material_override as StandardMaterial3D
			fmat3 = (tk3.get_node("Face") as MeshInstance3D).material_override as StandardMaterial3D
		_check(pmat3 != null and pmat3.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"传送后牌身回到**不透明档**（实得 %s）" % str(pmat3.transparency if pmat3 != null else -1))
		_check(fmat3 != null and fmat3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			"传送后正面回到 ALPHA_SCISSOR（实得 %s）" % str(fmat3.transparency if fmat3 != null else -1))

		print("== 传送被打断：材质与模式必须一并恢复（T1 审查 Important #2）==")
		# 走子补间只写 `global_position`/`scale` —— 它**不会**重新置位材质。所以走子若落在传送的
		# 0.38s 窗内（淡出中），被打断的传送会把牌留在**半透明 + 透明队列**（无深度写入、无影子）
		# 直到下一次传送。`_kill_token_tw` 现在无条件把材质恢复成不透明。
		g.s_tp(3, 13)                        # 开始传送：淡出 0.16s → 瞬移 → 淡入 0.22s
		# 停在**淡出中**：**等淡出真的写进第一帧**再断言 —— 原来是死等 0.08s，
		# 机器一忙（本机有周期 ≈0.5s 的长帧）那一拍就把 0.08s 跨过去了，而补间
		# 还没写第一帧（alpha 仍 ≈1）⇒ 前置断言**假红**（批次 12 实测 6 次里红 3 次，
		# 且批次 A 之前的提交同样红 ⇒ 与本批无关的既有 flaky）。改成按帧轮询、拿到就走。
		for _i in 8:
			if tpA.token_alpha(3) < 0.9:
				break
			await process_frame
		_check(tpA.token_alpha(3) < 0.9, "（前置）此刻确实在淡出中（alpha %.3f）" % tpA.token_alpha(3))
		g.s_move(3, [14], 0.3)               # 打断：走子落在传送窗内
		await create_timer(0.5).timeout
		_check(tpA.token_alpha(3) > 0.95,
			"被打断的传送把棋子留回了不透明（alpha %.3f）" % tpA.token_alpha(3))
		if pmat3 != null:
			_check(pmat3.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
				"被打断后牌身回到不透明档（实得 %s）" % str(pmat3.transparency))
		if fmat3 != null:
			_check(fmat3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"被打断后正面回到 ALPHA_SCISSOR（实得 %s）" % str(fmat3.transparency))

		print("== 走子进行中收到广播：棋子不被瞬回（T1 审查 Minor #7）==")
		# `set_tokens` 对正在走子的棋子**不抢位置**（`_moving` 那道闸，同 2D 的 `_animating`）。
		# 少了它，动画中途到达的状态广播会把棋子瞬回起点/落点。
		var p3b := int(g._state_player(3).get("pos", 0))
		g.s_move(3, [p3b + 1, p3b + 2], 0.5)
		await create_timer(0.2).timeout
		_check(tpA.token_moving(3), "走子期间 `token_moving` 为真（闸是开着的）")
		var mid_px := Vector2.ZERO
		if tk3 != null:
			mid_px = g.table3d.world_to_canvas_px(tk3.global_position)
		g.s_state(_state(2, false))          # 中途来一次完整广播（状态里的 pos 还是老格号）
		await process_frame
		if tk3 != null:
			var after_px: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			# 广播若抢了位置会瞬移到某格的落点上（≥ 几十画布像素）；这里只允许"补间又走了一帧"
			_check(after_px.distance_to(mid_px) < 20.0,
				"广播没把走子中的棋子瞬回（%s → %s，瞬回会是几十像素的跳）" % [mid_px, after_px])
		# 走完仍要落在**目的地**（闸不能把收尾也挡掉）
		await create_timer(1.0).timeout
		_check(not tpA.token_moving(3), "走完后 `token_moving` 落回假")
		if tk3 != null:
			var dest_px: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			var want_dest: Vector2 = g.board.token_screen_pos(p3b + 2, int(g._state_player(3).get("color", 0)))
			_check(dest_px.distance_to(want_dest) < 1.0,
				"走完落在目的地的印刷落点上（实得 %s / 期望 %s）" % [dest_px, want_dest])

		print("== 镜头平移（无广播）时，棋子与房子跟着印刷图案走（T1 审查 Important #1 / T2）==")
		# 2D 相机**逐帧**在动（`board._process` 的自动跟随 / 取景），而"跟图案"的实物原先只挂状态广播
		# ⇒ 镜头动过但没广播的那一段里，印在 `_world` 里的格子会滑动、实物不动（实测约半格、~1s 衰减；
		# 对旧 2D 棋子来说——它活在 `_world` 里、任何时刻都钉在格子上——那是**回归**）。
		# `game._process` 现在按"取景键"补推一次（`_refresh_followers_if_cam_moved`）。
		# **批次 11 Task 2 把房子也并进了这同一批**（房子压在格子上 ⇒ 同一条口径）——
		# 下面这段同时钉棋子与房子，就是"纳入逐帧补推"的可执行证据。
		g.board.cam_locked = false
		var st_cam: Dictionary = _state(2, false)    # 回一份干净状态：peer 3 落在老格号上
		var tiles_cam: Array = st_cam.tiles
		tiles_cam[3].level = 2                       # 顺带给 3 号格一棵房子（下面那条要用）
		g.s_state(st_cam)
		await process_frame
		var pcam := int(g._state_player(3).get("pos", 0))
		var slot3 := int(g._state_player(3).get("color", 0))
		var h3c: Node3D = null
		var h0c := Vector2.ZERO
		var h1c := Vector2.ZERO
		var h_want_c := Vector2.ZERO
		if tpH != null and tpH.has_method("set_houses"):
			h3c = _house_node(tpH.get_node_or_null("Houses"), 3)
			if h3c != null:
				h0c = g.table3d.world_to_canvas_px(h3c.global_position)
				h_want_c = g.board.house_screen_pos(3)
		_check(h3c != null and h3c.visible, "（前置）3 号格立着房子薄牌（下面那条要读它）")
		if tk3 != null:
			var w0: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			_check(w0.distance_to(g.board.token_screen_pos(pcam, slot3)) < 1.0,
				"（前置）广播推送后棋子已在印刷落点上")
			if h3c != null:
				_check(h0c.distance_to(h_want_c) < 1.0,
					"（前置）广播推送后房子也在它那条带的印刷落点上")
			g.board.focus_grid(pcam, 2.0, true)        # 只动 2D 镜头（**不广播**）
			await process_frame
			var want1: Vector2 = g.board.token_screen_pos(pcam, slot3)
			_check(want1.distance_to(w0) > 8.0,
				"（前置）镜头动过之后印刷落点确实移了（%.1f 画布像素）" % want1.distance_to(w0))
			if h3c != null:
				h_want_c = g.board.house_screen_pos(3)
				_check(h_want_c.distance_to(h0c) > 8.0,
					"（前置）镜头动过之后房子的印刷落点也移了（%.1f 画布像素）" % h_want_c.distance_to(h0c))
			g._process(0.0)                            # 真入口：game 的逐帧补推
			var w1: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			_check(w1.distance_to(want1) < 1.0,
				"镜头平移后棋子跟着印刷图案重推（实得 %s / 期望 %s）" % [w1, want1])
			if h3c != null:
				h1c = g.table3d.world_to_canvas_px(h3c.global_position)
				_check(h1c.distance_to(h_want_c) < 1.0,
					"**同一批补推里房子也重推了**（实得 %s / 期望 %s）" % [h1c, h_want_c])
			g._process(0.0)
			g._process(0.0)
			_check(g.table3d.world_to_canvas_px(tk3.global_position).is_equal_approx(w1),
				"镜头静止时补推早退（位置一字不变 —— 每帧只比三个浮点数）")
			if h3c != null:
				_check(g.table3d.world_to_canvas_px(h3c.global_position).is_equal_approx(h1c),
					"镜头静止时房子也不重摆（与棋子走同一条早退）")
		g.board.fit_overview(true)

	print("== 格详情卡兼作买地/装修面板（批次 12 C1 / ③）==")
	g.board.cam_locked = false
	g.board.fit_overview(true)
	await process_frame
	# 选**离屏幕中心最近**的那块地（与 dev_tools 的 `decision` 摆拍同一套挑法）：靠边的格子
	# 会被 `_place_info_panel` 的夹位推回来，那样"横向居中于该格"这条就量不准了。
	var prop_t := -1
	var best_pc := 1e18
	var first_prop := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) != "property":
			continue
		if first_prop < 0:
			first_prop = i
		var sp_c = g.table3d.viewport_to_screen(g.board.tile_screen_pos(i))
		if sp_c == null:
			continue
		var dc_c: float = (sp_c as Vector2).distance_to(g.size * 0.5)
		if dc_c < best_pc:
			best_pc = dc_c
			prop_t = i
	if prop_t < 0:
		prop_t = first_prop
	_check(prop_t >= 0, "（前置）找得到一块地产格（实得 %d）" % prop_t)
	var st_p: Dictionary = _state(2, false)
	for i in st_p.players.size():
		if int(st_p.players[i].peer) == 2:
			st_p.players[i].pos = prop_t
	st_p.await = "prompt"
	st_p.await_peer = 2
	g.my_peer = 2
	g._awaiting_prompt = 2          # 房主侧私有状态：提问对象是我
	g._prompt_tile = prop_t
	g.s_state(st_p)
	await process_frame
	# 走**真入口**：`s_prompt` → `_show_prompt` → `_arm_decision`（这条路上没有居中弹窗了）
	g.s_prompt(9001, "购买地产",
		"要买下【%s】吗？" % String(GameData.TILES[prop_t].name), "买下它！")
	await process_frame
	await process_frame
	g._process(0.0)
	_check(g.info_panel.visible, "有待决 → 格详情卡自己弹出来")
	_check(g.decision_area.visible, "决策区露面（买下它！/ 算了 + 倒计时条）")
	_check(String(g.decision_ok.text) == "买下它！" and String(g.decision_no.text) == "算了",
		"两枚按钮的文案来自询问内容（实得「%s」/「%s」）"
			% [String(g.decision_ok.text), String(g.decision_no.text)])
	_check(String(g.info_title.text).contains(String(GameData.TILES[prop_t].name)),
		"面板上同时有该格详情（标题「%s」）" % String(g.info_title.text))
	_check(g._prompt_token == 9001, "倒计时条已武装（token 记下了）")
	_check(g._prompt_bar != null and is_instance_valid(g._prompt_bar) and g._prompt_bar.visible,
		"倒计时条就在**这一块**里（不是第二个弹窗）")
	# 锚在该格上方：与「点格子」那条同一条换算（画布坐标 → 屏幕坐标）
	var raw_p: Vector2 = g.board.tile_screen_pos(prop_t)
	var anch = g.table3d.viewport_to_screen(raw_p)
	_check(anch != null, "（前置）该格可解算到屏幕坐标")
	var tcp: Vector2 = anch if anch != null else Vector2(-9999.0, -9999.0)
	var pcp: Vector2 = g.info_panel.position
	_check(absf((pcp.x + g.info_panel.size.x * 0.5) - tcp.x) < 4.0,
		"面板横向居中于**该格**（卡中心 %.0f / 格 %.0f）"
			% [pcp.x + g.info_panel.size.x * 0.5, tcp.x])
	_check(g.info_panel.size.y > 170.5,
		"决策区把面板撑高了（实得 %.0f > 170）—— 不是只换了个位置的空壳" % g.info_panel.size.y)
	_check(g.info_panel.size.x < g.size.x - 20.0,
		"面板**不是**屏幕居中的模态（宽 %.0f ≪ 屏宽 %.0f）" % [g.info_panel.size.x, g.size.x])
	_check(g.board.pending_tile() == prop_t,
		"待决格描着那圈脉冲高亮（实得 %d）" % g.board.pending_tile())
	_check(g.action_btn.visible and String(g.action_btn.text) == "回格上决定",
		"右下角动作按钮变「回格上决定」（实得「%s」）" % String(g.action_btn.text))
	# ✕ 关掉 = 暂缓，**不是放弃**
	var close_btn: Button = null
	for n in g.info_panel.find_children("*", "Button", true, false):
		if String((n as Button).text) == "✕":
			close_btn = n
	_check(close_btn != null, "（前置）找得到面板上的 ✕")
	if close_btn != null:
		close_btn.pressed.emit()
	_check(not g.info_panel.visible, "✕ 能把面板关掉")
	await process_frame
	g._process(0.0)
	_check(g._prompt_token == 9001, "**关掉面板不等于放弃**：决定仍在（token 未清）")
	_check(g.board.pending_tile() == prop_t, "关掉后待决格那圈高亮照旧亮着")
	_check(g.decision_area.visible, "决策区本身没被销毁（面板藏起来而已）")
	# 再点该格 → 面板回来
	g._on_tile_clicked(prop_t)
	await process_frame
	_check(g.info_panel.visible and g.decision_area.visible, "再点该格 → 面板与决策区都回来")
	# 点右下角动作按钮 → 同样把面板叫回来
	g.info_panel.visible = false
	g._on_action_pressed()
	await process_frame
	_check(g.info_panel.visible and g.decision_area.visible,
		"点「回格上决定」→ 面板与决策区都回来")
	# 作答：决策区收起、决定经既有的 _answer 落地
	g._on_decision_yes()
	_check(g._prompt_token == -1 and not g.decision_area.visible,
		"点「买下它！」→ 决策区收起、token 清掉")
	_check(int(g._decision.get("token", -1)) == 9001 and bool(g._decision.get("yes", false)),
		"走的是既有的 _answer 应答路径（房主侧直接记进 _decision）")
	_check(g._pending_tile_for_me() == -1, "决定落地后没人还待决")
	# 反向契约：旧的居中弹窗必须**真的没了**（不留第二条路径）
	_check(g.get("_prompt_dlg") == null, "旧居中弹窗的句柄 `_prompt_dlg` 已从 game 上删净")
	g._awaiting_prompt = 0
	g._prompt_tile = -1

	print("== 小卖部全员可见（批次 12 C2 / ⑧）：别人在逛，我看只读 ==")
	g.my_peer = 2
	var shop_i := _shop_tile()
	_check(shop_i >= 0, "（前置）找得到小卖部格")
	var st_w: Dictionary = _state(2, true)
	st_w.shop_peer = 3             # 正在逛的是丙，不是我
	g.s_state(st_w)
	g._process(0.0)
	await process_frame
	_check(g.shop_layer.visible, "**别人在逛，我也看得到小卖部**（门槛改成了 shop_open >= 0）")
	_check(String(g.shop_tile_l.text).begins_with("第 %d 号店" % g._shop_ordinal(shop_i)),
		"看到的是那一家的货架（实得「%s」）" % String(g.shop_tile_l.text))
	_check(g.shop_watch_l.visible and String(g.shop_watch_l.text).contains("丙"),
		"旁观说明条写着「谁在挑」（实得「%s」）" % String(g.shop_watch_l.text))
	var all_disabled := true
	for b2 in g.shop_btns:
		if (b2 as Button).visible and not (b2 as Button).disabled:
			all_disabled = false
	_check(all_disabled, "别人在逛时买按钮全灰（只读）")
	_check(g.shop_refresh_btn.disabled and g.shop_leave_btn.disabled,
		"刷新 / 离开也一并置灰（只有本人能操作）")
	st_w.shop_peer = 2             # 换成我自己在逛
	g.s_state(st_w)
	g._process(0.0)
	await process_frame
	_check(not g.shop_watch_l.visible, "自己逛时没有那条旁观说明")
	_check(not g.shop_refresh_btn.disabled, "自己逛时刷新按钮恢复可用（钱够就点亮）")
	_check(not g.shop_leave_btn.disabled, "自己逛时「离开」可用")
	g.s_state(_state(2, false))    # shop_open = -1 ⇒ 没人逛
	g._process(0.0)
	await process_frame
	_check(not g.shop_layer.visible, "没人逛 ⇒ 小卖部收起（与主人是不是我无关）")

	print("== 抽卡确认：房主侧（超时/托管 / 归属校验 / 两个新 RPC）==")
	# 机器人 / 休眠托管：不等人点，短暂延时后自己收卡（`_await_card_confirm` 里的托管分支）
	var bot_p := {"peer": -1, "name": "机器人A", "bot": true, "sleep": 0}
	g.deck_reveal.show_card("机会", "good", "测试：托管自动确认")
	await process_frame
	_check(g.deck_reveal.is_showing(), "（前置）演出已开演")
	await g._await_card_confirm(bot_p)
	_check(g._awaiting_card == 0, "托管（机器人）→ 走完就把等待归属清掉")
	_check(not g._card_ack, "托管路径不依赖 _card_ack（根本没人点）")
	_check(g.deck_reveal._closing or not g.deck_reveal.is_showing(),
		"托管也照样广播收卡（s_card_close → request_close，不是把卡晾在那儿）")
	_check(not g.deck_reveal.is_awaiting_confirm() or g.deck_reveal._closing,
		"托管路径不会把卡永久停在「等确定」上")
	_check(String(g.st.get("await", "")) != "card", "确认之后快照不再卡在 await=card")
	# 真人那一张走**真正的操作窗口**（不是托管分支）。这一条正是联机回归抓到过的那个 bug：
	# `alive` 谓词的极性写反（传了"已确认"而不是"还在等"）⇒ 窗口一次都不进 ——
	# `s_op_timer` 不发、超时不计、卡一闪而过，而托管分支照样是绿的，本地看不出来。
	var human_p := {"peer": 42, "name": "丙", "bot": false, "sleep": 0}
	g.deck_reveal.show_card("机会", "good", "测试：真人确认")
	g._card_ack = false
	g._op_kind = ""
	# `_await_turn_window` 的外圈是 `while running and …` —— 本套件开头把 `running` 关了，
	# 不打开它窗口一次都不进（会同步跑完、看起来"卡直接收了"）。这一步只影响本条断言：
	# `_run_game` 早在 `running == false` 时就返回了，之后不会再被这个标志唤起。
	g.running = true
	g._await_card_confirm(human_p)     # 不 await：跑到窗口那一句就挂住（同 `_at_auto_roll` 的写法）
	await process_frame
	_check(g._awaiting_card == 42, "等的是抽卡者本人（实得 %d）" % g._awaiting_card)
	_check(g._op_kind == "card" and g._op_owner == 42,
		"**操作窗口真开出来了**（s_op_timer kind=card / owner=42，实得 %s / %d）"
			% [g._op_kind, g._op_owner])
	_check(g._prompt_token == -1, "（不串台）抽卡窗口不会去动买地那个决策区")
	g._card_ack = true                 # 等价于抽卡者点了「确定」（房主侧就是这一句）
	await create_timer(0.4).timeout
	_check(g._awaiting_card == 0, "确认之后归属清掉（窗口关掉，实得 %d）" % g._awaiting_card)
	_check(g.deck_reveal._closing or not g.deck_reveal.is_showing(), "确认之后卡开始收")
	g.running = false                  # 还原（本套件本来就不跑回合循环）
	# 归属校验：只认抽卡者本人（与 `c_decision` 同一套做法）。headless 下本机不是任何人的
	# "远端"（`get_remote_sender_id()` = 0）⇒ 冒充他人的那一下必须被丢掉。
	g._awaiting_card = 999        # 假装正等着别人
	g._card_ack = false
	g.c_card_ok()
	_check(not g._card_ack, "不是抽卡者本人 → c_card_ok 被丢掉（与 c_decision 同款归属校验）")
	g._awaiting_card = 0
	g._card_ack = false
	# 两个新 RPC 的登记（方向是协议的一部分：c_* 必须是 any_peer，s_* 必须 authority + call_local）。
	# `Node.get_node_rpc_config()` 在这版上返回 null，RPC 表要**问脚本**（`Script.get_rpc_config()`）。
	var rcfg: Dictionary = g.get_script().get_rpc_config()
	_check(not rcfg.is_empty(), "（前置）拿得到 RPC 配置表（实得 %d 项）" % rcfg.size())
	var ck := StringName("c_card_ok")
	var sk := StringName("s_card_close")
	_check(rcfg.has(ck) and rcfg.has(sk), "c_card_ok / s_card_close 都登记在册")
	if rcfg.has(ck):
		_check(int((rcfg[ck] as Dictionary).get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_ANY_PEER,
			"c_card_ok 是 any_peer（客户端 → 房主）")
	if rcfg.has(sk):
		var sc: Dictionary = rcfg[sk]
		_check(int(sc.get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_AUTHORITY
			and bool(sc.get("call_local", false)),
			"s_card_close 是 authority + call_local（房主 → 全员，房主自己也收）")

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("HUD TEST: ALL PASS")
		quit(0)
	else:
		print("HUD TEST: %d FAILURES" % fails)
		quit(1)
