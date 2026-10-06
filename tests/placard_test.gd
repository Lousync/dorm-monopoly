extends SceneTree
## 桌面立牌（v0.8.0 第四次复核：**牌面改回原生 3D 画法**）。
## godot --headless --path . --script tests/placard_test.gd
##
## **为什么要这个套件**：名册条（`game.roster_strip` / `game.roster_strip_rows`）被**整体删除**，
## 它在 `tests/hud_test.gd` 里承载的四件事（名次 / 棋子色小片 / 昵称 / 行动者倒计时）
## 搬到了**桌面立牌**。`hud_test` 里那些断言**整段删掉**了（量的是一棵已经不存在的 Control，
## 留着就是恒假的红条），这里逐条补回来 —— 那边删掉的地方都留了指向本文件的注释。
##
## ⚠ **第三次改版走过"烘贴图"那条路**（旧名册格那块 Control 装进**离屏 `SubViewport`**
## 烘成贴图、交给 `table_props.set_placard_faces` 贴上去）—— **用户 2026-10-06 否掉了**：
## 「人物铭牌不要这个贴图，一是尺寸不对，二是文字模糊，你自己重新做一个吧（在木桌尺寸不变的
## 基础上重新设计铭牌显示）」。⇒ 牌面现在由 `table_props._make_placard` 用**原生 3D 元素**画：
## `BoxMesh` 牌身 + 一圈 `Border` + `PlaneMesh` 棋子色小片 + 两个 `Label3D`（名次 / 昵称）+
## 一条 `PlaneMesh` 倒计时（底轨 `Track` + 进度条 `Bar`）。**文字是矢量渲染的，缩到多小都清楚**，
## 每一维都自己定，不跟任何 Control 的比例走。
##
## ⇒ **`game` 上已经没有 `placard_chips` 了**（离屏 SubViewport 那一套整体删除），
## **内容的唯一来源就是 `table_props._placards` 那份字典**（`game._refresh_placards` 只推数据，
## 见那里的注释）。本套件一律从它上面读，不再有"烘好的一块 Control"这条中间层。
##
## 覆盖（编号与 `hud_test` 里那段"搬去哪了"的索引一一对应）：
##   ① 三个人各一块立牌、**没有「我」那块**（`slot 0` 不摆）；
##   ② **棋子色小片随 `p.color` 走**、**不随座位序号**（喂进来的座位序里"色号"与"座位号"处处不等）；
##   ③ 昵称文本 == 喂进去的 name（出局的挂「（破产）」后缀 —— `_fill_placard` 的既有契约）；
##      名次 == 喂进去的 rank；
##   ④ **落点在自己那一侧**：侧向（右 x>0 / 对面 z<0 / 左 x<0）；**"压不压地块"用射线足迹**
##     （八角投影，全在地块环之外）；**"在不在桌内"量的是"落桌点"**（牌心折回画布像素，落在
##      木桌外沿之内）—— 牌面宽 0.80 与木纹带（≈0.92）同量级，外沿那排角会略微探出桌沿，
##      **那是设计**（用户要求「木桌尺寸不变」⇒ 0.92 是几何上限，见 `table_props.PLACARD_W`）；
##   ⑤ **整块正对相机**（billboard）：`root.basis` 与 `camera.basis` 逐项相等；3D 端牌心抬
##      `PROPS_Y + PLACARD_H/2 × camera.basis.y.y`、2D 端正俯视时落回桌面；另有一条**不读实现
##      写法**的判据：牌面法线 · 指向相机的方向（对照"完全不转"那一档）；
##   ⑥ 金边：`set_placard_hot([p])` ⇒ **只有那一块牌身朝金偏**（比另一块更接近金即可）；
##      换人跟着换；空数组全灭；
##   ⑦ 行动者倒计时：只有行动者那一块露 `Track` / `Bar`、`Bar.scale.x` 跟着剩余比例；
##      `NO_PEER` 全收。既走 game 那条真入口（`_op_*` → `_refresh_corner_timer`），
##      也直接量 `set_placard_timer` 本身；
##   ⑧ 命中链 `placard_hit`；⑨ `_on_table_click` 真的开该玩家的道具弹窗；
##   ⑩ 幂等（同一份 rows 再来一次 = 同一批节点实例）+ 状态里少一个 peer ⇒ 那一块被收掉。
##
## **场景怎么搭**：与 `hud_test` 同一套 —— `load("res://scenes/game.tscn").instantiate()`。
## 立牌的落点靠 `_t3.board.tile_screen_pos`（地块环）算，裸 `table_3d`（`chars_test` 那种
## 没有 `board`）⇒ 三块会塌到同一点上，④ 量不出来。
## 一律**运行时 load**（同 `hud_test` / `chars_test` 文件头说明）：`--script` 入口下 autoload
## 还没注册，静态写 `UIKit.X` 这类会把依赖链拽进来、整链编译失败。
##
## **竞态提醒**：房主 `_host_setup` 在开局 1.5 秒后会自己 `_broadcast_state()` 一次
##（`hud_test` 那条"已知竞态"同源）。本套件的断言一律**紧跟在 `g.s_state(...)` 之后同步读**
##（中间不 await）⇒ 那次广播挤不进来。

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _fresh_tiles() -> Array:
	var out := []
	for i in GameData.TILES.size():
		out.append({"owner": GameData.NO_OWNER, "level": 0})
	return out

## 一份 4 人状态（与 `hud_test._state` 同形）：甲（名下有"一号楼"）/ 乙（**我**）/ 丙 / 丁（已出局）。
## 身家 = 现金 + 地产 ⇒ 乙 20000 > 甲 12000+一号楼 > 丙 8000 > 丁 100。
## **色号 = peer − 1**，而座位序（`_seat_peers()`，自己打头）= [2,3,4,1] ⇒ 三家分到的座号是
## 丙 1（右）/ 丁 2（对面）/ 甲 3（左）⇒ **色号与座位号处处不等**（② 靠这一条才有杀伤力）。
func _state(turn_peer: int) -> Dictionary:
	var tiles := _fresh_tiles()
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].name) == "一号楼":
			tiles[i].owner = 1
			break
	var players := [
		{"peer": 1, "name": "甲", "color": 0, "bot": false, "money": 12000, "pos": 0,
			"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
		{"peer": 2, "name": "乙", "color": 1, "bot": false, "money": 20000, "pos": 3,
			"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
		{"peer": 3, "name": "丙", "color": 2, "bot": false, "money": 8000, "pos": 6,
			"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
		{"peer": 4, "name": "丁", "color": 3, "bot": false, "money": 100, "pos": 9,
			"alive": false, "skip": 0, "sleep": 0, "stamina": 0,
			"items": [{"id": "招财猫", "cd": 0}]},
	]
	var shops_d := {}
	var st := {
		"phase": "playing", "turn": turn_peer, "await": "roll", "await_peer": turn_peer,
		"roll_epoch": 1, "round": 3, "max_rounds": 30,
		"players": players, "tiles": tiles, "shops": shops_d, "shop_open": -1,
		"shop_peer": 0, "black_peer": 0, "refresh_price": 500,
	}
	return st

## 房主侧名册（字段与 `game._build_hp` 对齐）。**只为让房主开局 1.5 秒后那次自动
## `_broadcast_state()` 成立** —— 它要读 `hp[turn_i].peer`，名册为空时抛
## `SCRIPT ERROR: Out of bounds`（同 `hud_test._host_roster` 那段说明）。
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

## 一块立牌的节点池（`table_props._placards` 里 peer 等于 `peer` 的那一项）。
## **按 peer 找、不按下标** —— 池子的键就是 peer。找不到给空字典（调用方自己判空）。
func _pl(tp, peer: int) -> Dictionary:
	var d = tp._placards.get(int(peer), {})
	return d as Dictionary

## 一块立牌**牌身**（`Body`）的节点 —— 它是 `BoxMesh`，尺寸就是牌面尺寸，
## 所以"八角折回画布像素"与 `placard_hit` 走的是同一份几何（**不写死尺寸常量**）。
func _body(pl: Dictionary) -> MeshInstance3D:
	return pl.get("body") as MeshInstance3D

## 一块立牌**牌面八角**折回画布像素。两种折法各有各的用途（`via_ray` 选）：
##
##   * `via_ray = true`：**看得见的那块投影足迹** —— 走与 `placard_hit` 同一条链
##     （`unproject_position` → 屏幕 → 射线打回桌面平面 → 画布）。问的是"从相机看过去，
##     这一角压在桌面的哪一点" ⇒ **"压不压地块"问的就是它**（玩家看到牌盖在格子上 = 点不到那格）。
##   * `via_ray = false`：`world_to_canvas_px`，**忽略高度** ⇒ "这一角正下方桌面上是哪一点"，
##     也就是这块牌**站在桌面的哪儿**。
func _body_corners_px(t3, pl: Dictionary, via_ray: bool) -> Array:
	var out: Array = []
	var body := _body(pl)
	if body == null or not is_instance_valid(body):
		return out
	var bm: BoxMesh = body.mesh as BoxMesh
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				var w: Vector3 = body.global_transform * Vector3(
					bm.size.x * float(sx), bm.size.y * float(sy), bm.size.z * float(sz))
				if via_ray:
					var px = t3.screen_to_viewport(t3.camera.unproject_position(w))
					if px != null:
						out.append(px as Vector2)
				else:
					out.append(t3.world_to_canvas_px(w))
	return out

## 一块立牌的**牌心**折成画布像素（同一条链）—— ⑧ / ⑨ 的命中采样点。
## 牌身在局部原点（中心锚定）⇒ 它的 `global_position` 就是牌心。
func _body_center_px(t3, pl: Dictionary) -> Variant:
	var body := _body(pl)
	if body == null or not is_instance_valid(body):
		return null
	return t3.screen_to_viewport(t3.camera.unproject_position(body.global_position))

## 牌身此刻离"金"（`PLACARD_HOT`）多远：`albedo_color` 到金的色距。⑥ 的判据。
## **不读 `pl["hot"]` 那个标志位**（那会在"标志对了但颜色没贴"时骗过断言）——
## 直接量**真的贴上去的那个色**。
func _body_dist(pl: Dictionary, hot: Color) -> float:
	var m: StandardMaterial3D = pl.get("body_mat")
	if m == null:
		return INF
	# `Color` 没有 `distance_to`（只有 `is_equal_approx`）⇒ 自己折成 `Vector3` 量欧氏距离。
	var c: Color = m.albedo_color
	return Vector3(c.r, c.g, c.b).distance_to(Vector3(hot.r, hot.g, hot.b))

## **地块环**的画布像素范围：56 格格心的包围盒，再往外加**半个格距**（格心不是格边）。
## 与 `table_props._placard_anchor_px` 量"环外沿"同一套算法 —— **不写死坐标**，
## 取景（`_zoom` / `_center`）一变它跟着变。
func _ring_rect(t3) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in 56:
		var p: Vector2 = t3.board.tile_screen_pos(i)
		mn = mn.min(p)
		mx = mx.max(p)
	var half: float = ((mx.x - mn.x) / 17.0) * 0.5      # 18 格 17 个格距 ⇒ 半个格距
	return Rect2(mn - Vector2(half, half), (mx - mn) + Vector2(half, half) * 2.0)

## **木桌外沿**的画布像素范围：桌垫采样窗口（`TEX_WINDOW_PX`）往外扩 `WOOD_FRAME` 折成的画布像素。
func _table_rect(t3) -> Rect2:
	var ppw: float = t3.TEX_WINDOW_PX.size.x / t3.TABLE_SIZE.x    # 画布像素 / 世界
	var fp: float = t3.WOOD_FRAME * ppw
	return Rect2(t3.TEX_WINDOW_PX.position - Vector2(fp, fp),
		t3.TEX_WINDOW_PX.size + Vector2(fp, fp) * 2.0)

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
	g.hp = _host_roster()
	g.turn_i = 0
	g.lab_mode = true
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout
	_check(g.table3d != null and g.table3d.table_props != null,
		"（前提）桌面实体层在（`table3d.table_props`）")
	if g.table3d == null or g.table3d.table_props == null:
		print("PLACARD TEST: 1 FAILURES（实体层缺了，下面整段跳过）")
		quit(1)
		return
	var t3 = g.table3d
	var tp = t3.table_props
	# 立牌的几何常量从**脚本常量表**取（不写死数字、也不假定它长什么样）
	var tp_consts: Dictionary = load("res://scripts/table_props.gd").get_script_constant_map()
	var P_W: float = float(tp_consts.get("PLACARD_W", 0.0))
	var P_H: float = float(tp_consts.get("PLACARD_H", 0.0))
	var P_T: float = float(tp_consts.get("PLACARD_T", 0.0))
	var P_HOT: Color = tp_consts.get("PLACARD_HOT", Color.WHITE)
	_check(P_W > 0.0 and P_H > 0.0 and P_T > 0.0,
		"立牌几何常量在（`PLACARD_W`=%.3f / `PLACARD_H`=%.3f / `PLACARD_T`=%.3f）"
			% [P_W, P_H, P_T])
	g.my_peer = 2
	# 喂状态 ⇒ `_refresh_players` → `_refresh_corner_bars` → `_refresh_placards`（真入口）
	g.s_state(_state(2))

	print("== ① 三个人各一块立牌、**没有「我」那块**（slot 0 不摆）==")
	var shown: Array = tp._placards.keys()
	shown.sort()
	_check(shown == [1, 3, 4], "三块立牌 = 其余三人（实得 %s）" % str(shown))
	_check(not tp._placards.has(2),
		"**没有「我」那块** —— 自己的信息在左下角那条身家条上（`slot 0` = 近侧，相机就在那儿）")
	_check(tp._placards_root != null and tp._placards_root.get_child_count() == 3,
		"`Placards` 父节点下就是这三块（实得 %d）"
			% (0 if tp._placards_root == null else tp._placards_root.get_child_count()))
	var slots := {}
	for p in shown:
		slots[int(p)] = int(_pl(tp, int(p)).get("slot", -1))
	_check(slots == {1: 3, 3: 1, 4: 2},
		"落位按 `game._seat_peers()` 反查：丙 slot1(右) / 丁 slot2(对面) / 甲 slot3(左)（实得 %s）" % str(slots))
	# 节点池的键与节点名：牌面是**原生 3D 元素**拼的（第四次复核），这六件缺一不可 ——
	# 缺了它牌面上就少一样东西，而"少一样"在颜色 / 文字那几条断言里可能看不出来。
	var keys_ok := true
	var nodes_ok := true
	for p in shown:
		var pl: Dictionary = _pl(tp, int(p))
		for k in ["root", "body", "body_mat", "border", "chip", "chip_mat", "rank", "name",
				"track", "bar", "bar_mat"]:
			if not pl.has(k):
				keys_ok = false
		var r: Node3D = pl.get("root")
		for nn in ["Body", "Border", "Chip", "Rank", "Name", "Track", "Bar"]:
			if r == null or r.get_node_or_null(nn) == null:
				nodes_ok = false
	_check(keys_ok, "每块牌的节点池键齐全（root/body/body_mat/border/chip/chip_mat/rank/name/track/bar/bar_mat）")
	_check(nodes_ok, "每块牌的子节点名齐全（Body/Border/Chip/Rank/Name/Track/Bar）")

	print("== ② 棋子色小片随各家的 `p.color` 走，**不随座位序号** ==")
	var col_bad: Array = []
	var col_log := ""
	for p in shown:
		var pl2: Dictionary = _pl(tp, int(p))
		var want_i := int(g._state_player(int(p)).get("color", 0))
		var want_c: Color = GameData.PLAYER_COLORS[
			clampi(want_i, 0, GameData.PLAYER_COLORS.size() - 1)]
		# 小片是**牌面上那一枚**（`Chip`，`PlaneMesh` 贴棋子色）—— 读它**真的贴上去的材质色**，
		# 比读哪个色号更硬（色号对了、材质贴错也照样红）。
		var got_c: Color = (pl2["chip_mat"] as StandardMaterial3D).albedo_color
		var by_slot_c: Color = GameData.PLAYER_COLORS[
			int(pl2.get("slot", 0)) % GameData.PLAYER_COLORS.size()]
		if not got_c.is_equal_approx(want_c) or by_slot_c.is_equal_approx(want_c):
			col_bad.append(int(p))
		col_log += "peer%d(色%d/座%d) chip=%s（期望 %s；按座号会是 %s） | " % [
			int(p), want_i, int(pl2.get("slot", 0)), str(got_c), str(want_c), str(by_slot_c)]
	print("  [实测] %s" % col_log)
	_check(col_bad.is_empty(),
		"**小片色 = `p.color`**（不是按座位序号取色；不符的 %s）" % str(col_bad))

	print("== ③ 昵称文本 == name（出局的带「（破产）」）/ 名次 == rank ==")
	# 期望名次在测试里**自己算一遍**（身家 = 现金 + 名下地皮地价，与 `game._state_worth` 同一公式），
	# 不写死数字（地价表一调就假红）。
	var worth := {}
	for p in [1, 2, 3, 4]:
		var v := int(g._state_player(p).get("money", 0))
		var st_w: Array = g.st.tiles
		for i in mini(st_w.size(), GameData.TILES.size()):
			if int(st_w[i].get("owner", GameData.NO_OWNER)) == p:
				v += int(GameData.TILES[i].price)
		worth[p] = v
	var order: Array = worth.keys()
	order.sort_custom(func(a, b): return int(worth[a]) > int(worth[b]))
	var name_bad: Array = []
	var rank_bad: Array = []
	for p in shown:
		var pl3: Dictionary = _pl(tp, int(p))
		var sp: Dictionary = g._state_player(int(p))
		# 昵称后面那截标记是**既定契约**（`table_props._fill_placard` 与 `_fill_peer_bar` 同一条）：
		# 出局的挂「（破产）」。
		var want_name := String(sp.get("name", "?")) \
			+ ("" if bool(sp.get("alive", true)) else "（破产）")
		var want_rank: int = order.find(int(p)) + 1
		var got_name := String((pl3["name"] as Label3D).text)
		var got_rank_s := String((pl3["rank"] as Label3D).text)
		var got_rank: int = int(got_rank_s) if got_rank_s != "" else -1
		if got_name != want_name:
			name_bad.append(int(p))
		if got_rank != want_rank:
			rank_bad.append(int(p))
		print("  [实测] peer%d 昵称「%s」(期望「%s」) / 名次「%s」(期望 %d，身家 %d)"
			% [int(p), got_name, want_name, got_rank_s, want_rank, int(worth[int(p)])])
	_check(name_bad.is_empty(), "昵称文本 == 喂进去的 name（不符的 %s）" % str(name_bad))
	_check(rank_bad.is_empty(), "名次 == 喂进去的 rank（身家倒序；不符的 %s）" % str(rank_bad))
	# 牌面高与文字高的关系：昵称的世界字高**不超过牌面高的三分之一**（否则字会溢出牌面）——
	# 与 `PLACARD_NAME_H` 那段"每一个字号都是按要读得出来倒推的"同一条口径。
	var size_ok := true
	for p in shown:
		var nm_l: Label3D = _pl(tp, int(p))["name"]
		if nm_l.pixel_size * float(nm_l.font_size) > P_H * 0.5:
			size_ok = false
	_check(size_ok, "昵称世界字高 ≤ 牌面高的 1/2（`Label3D.pixel_size × font_size`）")

	print("== ④ 落点在自己那一侧（牌面八角折回画布像素：足迹在环外、落桌点在桌内）==")
	var ring := _ring_rect(t3)
	var table_r := _table_rect(t3)
	var side_bad: Array = []
	var side_log := ""
	for p in shown:
		var gp: Vector3 = (_pl(tp, int(p))["root"] as Node3D).global_position
		var s := int(_pl(tp, int(p)).get("slot", 0))
		# 相机在 +z 这一侧（`_apply_camera` 把相机摆在 `(0, d·sinθ, d·cosθ)`）⇒
		# 对面（slot 2）在 −z、左（3）在 −x、右（1）在 +x。
		var ok: bool = (s == 2 and gp.z < 0.0) or (s == 3 and gp.x < 0.0) or (s == 1 and gp.x > 0.0)
		if not ok:
			side_bad.append(int(p))
		side_log += "peer%d(slot%d) 世界(%+.2f, %+.2f, %+.2f) | " % [int(p), s, gp.x, gp.y, gp.z]
	print("  [实测] %s" % side_log)
	_check(side_bad.is_empty(),
		"各自立在**自己那一侧**（右 x>0 / 对面 z<0 / 左 x<0；不符的 %s）" % str(side_bad))
	var in_bad: Array = []
	var corner_log := ""
	for p in shown:
		# 压不压地块：用**看得见的投影足迹**（射线折法，同 `placard_hit`）
		var cs: Array = _body_corners_px(t3, _pl(tp, int(p)), true)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for c in cs:
			mn = mn.min(c as Vector2)
			mx = mx.max(c as Vector2)
			if ring.has_point(c as Vector2):
				in_bad.append(int(p))
		corner_log += "peer%d 足迹(射线) %s..%s | " % [int(p), mn, mx]
	print("  [实测] %s" % corner_log)
	print("  [实测] 地块环 %s / 木桌外沿 %s" % [str(ring), str(table_r)])
	_check(in_bad.is_empty(),
		"**每一角都不压地块**（看得见的那块足迹八角逐个查，全在地块环之外；压到的 %s）" % str(in_bad))
	# ⚠ **牌面宽（0.80）与木纹带（≈0.92）同量级 ⇒ 外沿那一排角会探出木桌外沿** —— 这是**故意的**
	#（用户要求「木桌尺寸不变」⇒ 0.92 就是几何上限；立牌是悬空 billboard，不参与物理），
	# 见 `table_props.PLACARD_W` 那段。⇒ 判据是"**落桌点**（牌心投影）在木桌之内"，
	# 而不是"八个角都在桌内"：前者仍然拦得住"牌飘到屋子外面去了"，后者今天**挡的就是设计本身**。
	var anchor_out: Array = []
	var anchor_log := ""
	for p in shown:
		var root4: Node3D = _pl(tp, int(p))["root"]
		var apx: Vector2 = t3.world_to_canvas_px(root4.global_position)
		if not table_r.has_point(apx):
			anchor_out.append(int(p))
		anchor_log += "peer%d 落桌点 %s | " % [int(p), str(apx)]
	print("  [实测] 落桌点：%s" % anchor_log)
	_check(anchor_out.is_empty(),
		"**每块牌的落桌点都在木桌上**（牌心折回画布像素；飘出的 %s —— 探出桌沿那一圈是故意的，见注释）"
			% str(anchor_out))

	print("== ⑤ 整块正对相机（billboard）==")
	var cam: Camera3D = t3.camera
	_check(cam != null, "（前提）相机在")
	var basis_bad: Array = []
	for p in shown:
		var b: Basis = (_pl(tp, int(p))["root"] as Node3D).global_transform.basis
		var cb: Basis = cam.global_transform.basis
		var same := true
		for k in 3:
			if not b[k].is_equal_approx(cb[k]):
				same = false
		if not same:
			basis_bad.append(int(p))
	_check(basis_bad.is_empty(),
		"3D 端：每块牌的 `basis` 与**相机的 `basis` 逐项相等**（不符的 %s）" % str(basis_bad))
	var ty: float = t3.table_mesh.global_position.y
	var up_y3: float = cam.global_transform.basis.y.y
	var lift_bad: Array = []
	var lift_log := ""
	# 期望抬升 = `PROPS_Y + 半高 × camera.basis.y.y`（`_placard_world` + `_face_camera` 的式子）
	for p in shown:
		var root3: Node3D = _pl(tp, int(p))["root"]
		var gp3: Vector3 = root3.global_position
		# ⚠ 式子里还有 `PROPS_Y`（桌面实体层统一抬的那 0.02）：落点先抬到
		# `table_mesh.y + PROPS_Y`，再加 `半高 × up_y` ⇒ 差值应当是 `PROPS_Y + 半高 × up_y`。
		# 容差取 0.005（**比 PROPS_Y 本身小**）—— 容差写成 0.02 的话"漏掉 PROPS_Y"正好卡在边界上。
		if not (gp3.y > ty and absf((gp3.y - ty - tp.PROPS_Y)
				- (P_H * 0.5 * up_y3)) < 0.005):
			lift_bad.append(int(p))
		lift_log += "peer%d y=%.4f(桌面 %.4f，抬 %+.4f；半高 %.3f×up_y %.3f=%.4f) | " % [
			int(p), gp3.y, ty, gp3.y - ty, P_H * 0.5, up_y3, P_H * 0.5 * up_y3]
	print("  [实测] 3D 端牌心：%s（`PROPS_Y`=%.3f）" % [lift_log, tp.PROPS_Y])
	_check(lift_bad.is_empty(),
		"3D 端：牌心**在桌面之上**、抬的正是 `PROPS_Y + 半高 × camera.basis.y.y`（不符的 %s）"
			% str(lift_bad))
	# ---- 2D 端 ----
	t3.snap_view(1.0)
	basis_bad = []
	for p in shown:
		var b2: Basis = (_pl(tp, int(p))["root"] as Node3D).global_transform.basis
		var cb2: Basis = cam.global_transform.basis
		var same2 := true
		for k in 3:
			if not b2[k].is_equal_approx(cb2[k]):
				same2 = false
		if not same2:
			basis_bad.append(int(p))
	_check(basis_bad.is_empty(),
		"2D 端：同样是**逐项抄相机的 `basis`**（俯视到 88° 也不退化 —— 这正是「不写 `look_at()`」"
			+ "那一条的理由；不符的 %s）" % str(basis_bad))
	var up_y2: float = cam.global_transform.basis.y.y
	var flat_bad: Array = []
	var flat_log := ""
	for p in shown:
		var gp4: Vector3 = (_pl(tp, int(p))["root"] as Node3D).global_position
		# ① 式子照旧成立（抬升 = `PROPS_Y + 半高 × up_y`）；② 且这一档 `up_y ≈ 0` ⇒ 牌心落回桌面。
		if absf((gp4.y - ty - tp.PROPS_Y) - (P_H * 0.5 * up_y2)) > 0.005 or absf(gp4.y - ty) > 0.05:
			flat_bad.append(int(p))
		flat_log += "peer%d y=%.4f（桌面 %.4f，差 %+.4f） | " % [int(p), gp4.y, ty, gp4.y - ty]
	print("  [实测] 2D 端牌心：%s（camera.basis.y.y=%.4f）" % [flat_log, up_y2])
	_check(flat_bad.is_empty(),
		"**2D 端正俯视 ⇒ 牌心落回桌面**（`camera.basis.y.y`≈0 ⇒ 抬升那一项归零 = 平贴桌面；"
			+ "偏离 >0.05 或式子不符的 %s）" % str(flat_bad))
	# ---- 真正钉住"正对相机"：**不读实现写法，直接量"是不是真的朝着我"** ----
	# 判据：牌面法线（`root.basis.z` —— 相机的 +Z 就是"朝向观察者"那一维）与该牌**指向相机的方向**
	# 做点积。⚠ 阈值 **0.88** 而不是 1.0/0.99：实现抄的是**相机那一个全局姿态**（不是逐块
	# `look_at` —— 那条在 2D 端会退化，见 `_face_camera` 的说明），而两侧座位本来就偏离相机轴
	# 二十多度 ⇒ 点积**天生到不了 1**。实测量在下面那行；**对照读数**：同一批牌如果"干脆不转"
	#（法线 = `+Z`），点积会明显更低 —— 这条钉的就是"朝向到底跟不跟着相机走"。
	# **变红口子**：`_face_camera` 里不写 `camera.basis`、或把它换回"随视角后倾 25°"那条轨道，
	# 点积都会掉到 0.88 以下（后者在 2D 端只剩一条棱）。
	var FACING_MIN := 0.88
	var dot_min := 2.0
	var dot_fixed := 2.0
	var dot_log := ""
	for p in shown:
		var root5: Node3D = _pl(tp, int(p))["root"]
		var to_cam: Vector3 = (cam.global_position - root5.global_position).normalized()
		var d: float = root5.global_transform.basis.z.dot(to_cam)
		var d_fixed: float = Vector3(0.0, 0.0, 1.0).dot(to_cam)      # "完全不转"的对照读数
		dot_min = minf(dot_min, d)
		dot_fixed = minf(dot_fixed, d_fixed)
		dot_log += "peer%d %.4f（不转的话 %.4f） | " % [int(p), d, d_fixed]
	print("  [实测] 法线·指向相机的方向：%s（最小 %.4f；对照·不转 %.4f）" % [dot_log, dot_min, dot_fixed])
	_check(dot_min >= FACING_MIN,
		"**每块牌都真的朝着相机**（法线 · 指向相机的方向 ≥ %.2f，实得最小 %.4f —— 而"
			% [FACING_MIN, dot_min] + "「法线固定在 +Z」那一档只有 %.4f）" % dot_fixed)
	t3.snap_view(0.0)

	print("== ⑥ 金边：`set_placard_hot` ⇒ 只有那一块牌身朝金偏（判据在牌身材质上）==")
	# 起点：三块都不是金 —— 记下"普通牌身"的色距当基准（**不写死数字**：牌身底色一调就假红）。
	var d0 := {}
	for p in shown:
		d0[int(p)] = _body_dist(_pl(tp, int(p)), P_HOT)
	var d0_log := ""
	for p in shown:
		d0_log += "peer%d %.3f | " % [int(p), float(d0[int(p)])]
	print("  [实测] 起点色距（到 PLACARD_HOT）：%s" % d0_log)
	_check(float(d0[1]) > 0.3 and float(d0[3]) > 0.3 and float(d0[4]) > 0.3,
		"（起点）三块都还不是金（色距都 > 0.3，实得 %s）" % d0_log)
	g._push_peer_highlight([3])
	var d3: float = _body_dist(_pl(tp, 3), P_HOT)
	var d1a: float = _body_dist(_pl(tp, 1), P_HOT)
	var d4a: float = _body_dist(_pl(tp, 4), P_HOT)
	_check(d3 < float(d0[3]) * 0.7 and absf(d1a - float(d0[1])) < 0.001
			and absf(d4a - float(d0[4])) < 0.001,
		"`_push_peer_highlight([3])` ⇒ **只有丙那一块**朝金偏（%.3f → %.3f）、另两块一字未动（%s / %s）"
			% [float(d0[3]), d3, str(d1a), str(d4a)])
	g._push_peer_highlight([1])
	var d1b: float = _body_dist(_pl(tp, 1), P_HOT)
	var d3b: float = _body_dist(_pl(tp, 3), P_HOT)
	_check(d1b < float(d0[1]) * 0.7 and absf(d3b - float(d0[3])) < 0.001,
		"换成甲 ⇒ **金跟着换**（甲 %.3f → %.3f）、丙那一块还原（%.3f；只加不撤的话这条会红）"
			% [float(d0[1]), d1b, d3b])
	g._push_peer_highlight([])
	var back_ok := true
	var back_log := ""
	for p in shown:
		var dc: float = _body_dist(_pl(tp, int(p)), P_HOT)
		back_log += "peer%d %.3f | " % [int(p), dc]
		if absf(dc - float(d0[int(p)])) > 0.001:
			back_ok = false
	_check(back_ok,
		"传空数组 ⇒ **三块全灭**、各自回到普通牌身色（实得 %s）" % back_log)

	print("== ⑦ 行动者倒计时：推进 `_op_*` 再 `_refresh_corner_timer()` ==")
	g._op_kind = "roll"
	g._op_owner = 3
	g._op_left = 15.0
	g._op_total = 20.0
	g._refresh_corner_timer()
	var pl3t: Dictionary = _pl(tp, 3)
	_check((pl3t["track"] as MeshInstance3D).visible and (pl3t["bar"] as MeshInstance3D).visible,
		"行动者（丙）那一块露倒计时行（`Track` + `Bar`）")
	_check(absf((pl3t["bar"] as MeshInstance3D).scale.x - 0.75) < 0.02,
		"进度条长度跟着 `_op_left / _op_total` 走（期望 0.75，实得 %.4f）"
			% (pl3t["bar"] as MeshInstance3D).scale.x)
	var others_on := 0
	for p in [1, 4]:
		var oc: Dictionary = _pl(tp, int(p))
		if (oc["track"] as MeshInstance3D).visible or (oc["bar"] as MeshInstance3D).visible:
			others_on += 1
	_check(others_on == 0, "其余两块**不显示倒计时**（只出现在行动者那一块上；越界 %d 块）" % others_on)
	# 我那条身家条（屏幕层）此刻不该显示 —— 倒计时只落在一处
	_check(not (g.corner_bars[0].timer_kind as Label).visible,
		"窗口归属不是我 ⇒ 屏幕层那条身家条的倒计时内容收起（同一条判据、两处载体）")
	# 直接量 `set_placard_timer` 本身：`frac` 是唯一输入，条长应当严格跟着它走。
	tp.set_placard_timer(3, 0.5, true)
	_check(absf((pl3t["bar"] as MeshInstance3D).scale.x - 0.5) < 0.001,
		"`set_placard_timer(3, 0.5, true)` ⇒ `Bar.scale.x` ≈ 0.5（实得 %.4f）"
			% (pl3t["bar"] as MeshInstance3D).scale.x)
	# 条形**左端固定**：右端随 frac 缩 ⇒ 中心也要跟着挪（`-W/2 + W·f/2`）。f = 0.5 时中心在 -W/4。
	var TRACK_W: float = float(tp_consts.get("PLACARD_TRACK_W", 0.0))
	var bar_x: float = (pl3t["bar"] as MeshInstance3D).position.x
	_check(TRACK_W > 0.0 and absf(bar_x - (-TRACK_W * 0.5 + TRACK_W * 0.5 * 0.5)) < 0.005,
		"进度条**左端固定**（中心挪到 -W/4；期望 %.4f，实得 %.4f）" % [-TRACK_W * 0.25, bar_x])
	# ⚠ **不限时**（`timed = false`）不画底轨 —— 与屏幕层 `on and timed` **逐字对齐**
	#（黑市那种 `_op_total <= 0` 的操作：屏幕层连底轨都不画，立牌原先会画一条空底轨）。
	tp.set_placard_timer(3, 0.0, false)
	var untimed_bad: Array = []
	for p2 in [1, 3, 4]:
		var pl2: Dictionary = _pl(tp, p2)
		if (pl2["track"] as MeshInstance3D).visible or (pl2["bar"] as MeshInstance3D).visible:
			untimed_bad.append(p2)
	_check(untimed_bad.is_empty(),
		"不限时（`timed=false`）时**三块都不画底轨**（与屏幕层同判据；不对的 %s）" % str(untimed_bad))
	tp.set_placard_timer(GameData.NO_PEER, 0.0, false)
	var any_on := false
	for p in shown:
		var ac: Dictionary = _pl(tp, int(p))
		if (ac["track"] as MeshInstance3D).visible or (ac["bar"] as MeshInstance3D).visible:
			any_on = true
	_check(not any_on, "`NO_PEER` ⇒ 三块全收（一处都不显示）")
	# 窗口关闭（`_op_kind = ""`）⇒ 走 game 那条真入口，倒计时内容也全收
	g._op_kind = ""
	g._refresh_corner_timer()
	any_on = false
	for p in shown:
		var ac2: Dictionary = _pl(tp, int(p))
		if (ac2["track"] as MeshInstance3D).visible or (ac2["bar"] as MeshInstance3D).visible:
			any_on = true
	_check(not any_on, "窗口关闭（`_op_kind = \"\"`）⇒ 三块全收（一处都不显示）")

	print("== ⑧ 命中链：`placard_hit` ==")
	var hit_bad: Array = []
	for p in shown:
		var px = _body_center_px(t3, _pl(tp, int(p)))
		if px == null:
			hit_bad.append(int(p))
			continue
		var got_hit: int = tp.placard_hit(px as Vector2)
		print("  [实测] peer%d 牌心画布 %s ⇒ 命中 %d" % [int(p), str(px), got_hit])
		if got_hit != int(p):
			hit_bad.append(int(p))
	_check(hit_bad.is_empty(),
		"牌心折成的画布像素**命中它自己那一块**（错认 / 落空的 %s）" % str(hit_bad))
	# 离得远 ⇒ 哨兵。用棋盘的**格心**当"桌面上另一个地方"（那里只有地块、没有立牌）。
	var far_px: Vector2 = t3.board.tile_screen_pos(0)
	_check(tp.placard_hit(far_px) == GameData.NO_PEER,
		"离得远（0 号格格心 %s）⇒ `GameData.NO_PEER`（不是 -1、也不是随便哪一家）" % str(far_px))

	print("== ⑨ 点立牌 = 开该玩家的道具弹窗（后果函数与名册条时代一字未改）==")
	var px1 = _body_center_px(t3, _pl(tp, 1))
	_check(px1 != null, "（前置）甲的牌心可解算到画布像素")
	var p1c: Vector2 = px1 if px1 != null else Vector2(-9999.0, -9999.0)
	_check(tp.placard_hit(p1c) == 1, "（前置）这个点确实落在甲那块牌上（实得 %d）" % tp.placard_hit(p1c))
	_check(g._on_table_click(p1c, MOUSE_BUTTON_LEFT), "点它：这次点击被实体层消费（`_on_table_click`）")
	_check(g.player_popup != null and g.player_popup.is_open() and g.player_popup.open_peer() == 1,
		"**真的开了 peer 1 的道具弹窗**（实得 peer %s）"
			% str(g.player_popup.open_peer() if g.player_popup != null else -99999))
	g.player_popup.close()

	print("== ⑩ 幂等：同一份 rows 再来一次 = 同一批节点实例；少一个 peer ⇒ 那一块被收掉 ==")
	# 直接走 `set_placards`（同 `chars_test` ⑪ 直接调 `set_chars` 的写法）：走广播的话
	# `_refresh_corner_bars` 的签名缓存会把第二次早退掉，这条就变成"什么都没调用"的空转。
	# rows 的字段**就是生产代码存下来的那几位**（`_fill_placard` 读的同一份）——
	# 于是"再来一次"喂进去的是逐位相同的输入，幂等这条才有意义。
	var rows: Array = []
	for p in shown:
		var pld: Dictionary = _pl(tp, int(p))
		rows.append({"peer": int(p), "slot": int(pld.get("slot", 2)),
			"color": int(pld.get("color", 0)), "name": String(pld.get("name_text", "")),
			"rank": int(pld.get("rank_n", 0)), "alive": bool(pld.get("alive", true))})
	_check(rows.size() == 3, "三行 rows（实得 %d 行）" % rows.size())
	var before := {}
	for p in shown:
		before[int(p)] = _pl(tp, int(p))["root"]
	tp.set_placards(rows)
	var same := true
	for p in shown:
		# `is_same(a, b)` 是**全局函数**（Godot 4：比较是不是同一个实例），不是节点上的方法。
		if not is_same(_pl(tp, int(p)).get("root"), before[int(p)]):
			same = false
	_check(same and tp._placards.size() == 3,
		"同样的 rows 再来一次 ⇒ **同一批节点实例**（`set_placards` 的幂等；每次广播都调它）")
	tp.set_placards([rows[0], rows[1]])
	var after: Array = tp._placards.keys()
	after.sort()
	var want_after: Array = [int(rows[0]["peer"]), int(rows[1]["peer"])]
	want_after.sort()
	_check(after == want_after,
		"状态里少了的 peer ⇒ **那一块从池子里收掉**（实得 %s，期望 %s）" % [str(after), str(want_after)])
	await process_frame
	_check(tp._placards_root.get_child_count() == 2,
		"父节点下也真的少了一个（实得 %d）" % tp._placards_root.get_child_count())
	_check(not is_instance_valid(before[int(rows[2]["peer"])]),
		"被收掉那一块的节点已经**真的释放**（不是留成孤儿）")

	# 收尾：房主 `_host_setup` 里那条 `await _wait(1.5)` 是一条**挂起的协程**
	#（`GDScriptFunctionState`），退出时还挂着就会报 `ObjectDB instances leaked at exit`。
	# 断言全部跑完了 ⇒ 这里等它自然醒来一次（1.5 s 那条自动广播此时已无害）。
	await create_timer(1.3).timeout

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("PLACARD TEST: ALL PASS")
		quit(0)
	else:
		print("PLACARD TEST: %d FAILURES" % fails)
		quit(1)
