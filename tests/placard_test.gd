extends SceneTree
## 桌面立牌（v0.8.0 第三次改版：**名册条从屏幕搬上桌**）。
## godot --headless --path . --script tests/placard_test.gd
##
## **为什么要这个套件**：名册条（`game.roster_strip` / `game.roster_strip_rows`）被**整体删除**，
## 它在 `tests/hud_test.gd` 里承载的四件事（名次徽章 / 棋子色小片 / 昵称 / 行动者倒计时）
## 搬到了**桌面立牌**。`hud_test` 里那些断言**整段删掉**了（量的是一棵已经不存在的 Control，
## 留着就是恒假的红条），这里逐条补回来 —— 那边删掉的地方都留了指向本文件的注释。
##
## **立牌到底是什么形的载体**（这一版是最终接口）：牌面**不是 3D 侧画的** ——
## 它是**旧名册格那一块 Control**（`table_hud.make_chip`）装进一个**离屏 `SubViewport`**
## 烘成贴图（`game._refresh_placards`），再交给 `table_props.set_placard_faces` 贴到 3D 立牌上。
## ⇒ **内容（昵称 / 名次徽章 / 棋子色小片 / 倒计时 / 金边）一律从 `game.placard_chips` 那份字典上读**
##（与 `corner_bars` 那条逐项同形），3D 那侧只剩一张贴图、读不出文字。
##
## 覆盖（编号与 `hud_test` 里那段"搬去哪了"的索引一一对应）：
##   ① 三个人各一块立牌、**没有「我」那块**（`slot 0` 不摆）；
##   ② **棋子色小片随 `p.color` 走**、**不随座位序号**（喂进来的座位序里"色号"与"座位号"处处不等）；
##   ③ 昵称文本 == 喂进去的 name；名次徽章 == 喂进去的 rank；
##   ④ **落点在自己那一侧的木纹带里**：侧向（右 x>0 / 对面 z<0 / 左 x<0）+ 牌面四角折回画布像素后
##      **每一角都在地块环之外、且在木桌外沿之内**（同时挡住"压地块"与"飘出桌子"）；
##   ⑤ **整块正对相机**（billboard）：`root.basis` 与 `camera.basis` 逐项相等；3D 端牌心抬
##      `半高 × camera.basis.y.y`、2D 端正俯视时落回桌面（"平躺"的可执行版）；
##      另有一条**不读实现写法**的判据：牌面法线 · 指向相机的方向；
##   ⑥ **金边走 game 那一侧**：`_push_peer_highlight([peer])` 之后那一块 chip 的
##      `root.get_theme_stylebox("panel")` 换成"可选中"那张金框（判据同 `hud_test._corner_bar_hot`）；
##   ⑦ **倒计时同理**：推进 `_op_owner / _op_left / _op_total` 再 `_refresh_corner_timer()`；
##   ⑧ 命中链 `placard_hit`；⑨ `_on_table_click` 真的开该玩家的道具弹窗；
##   ⑩ 幂等（同一份 rows 再来一次 = 同一批节点实例）+ 状态里少一个 peer ⇒ 那一块被收掉。
##
## **场景怎么搭**：与 `hud_test` 同一套 —— `load("res://scenes/game.tscn").instantiate()`。
## 立牌的落点靠 `_t3.board.tile_screen_pos`（地块环）与 `_t3.canvas_px_to_world` 算，
## 裸 `table_3d`（`chars_test` 那种没有 `board`）⇒ 三块会塌到同一点上，④ 量不出来。
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

## 立牌面那一块 chip（`game.placard_chips` 里 peer 等于 `peer` 的那一项）。
## **按 peer 找、不按下标** —— 清单是身家倒序排出来的，人一换顺序就变。
## `chip_vp` 是这一块**独有**的键（四角身家条没有）⇒ 也用它认"这是不是立牌面"。
func _chip_of(g, peer: int) -> Dictionary:
	for c in g.placard_chips:
		var chip: Dictionary = c
		if chip.get("chip_vp") != null and int(chip.get("peer", GameData.NO_PEER)) == peer:
			return chip
	return {}

## 名次徽章上的数字（读徽章里那个 Label 的文本；没徽章给 -1）。同 `hud_test.rank_of` 的取法。
func _rank_of(chip: Dictionary) -> int:
	var badge = chip.get("badge")
	if badge == null or not is_instance_valid(badge):
		return -1
	for c in (badge as Control).get_children():
		if c is Label:
			return int(String((c as Label).text))
	return -1

## 这一条 chip 此刻"亮着"（可被选中）吗：读它**真的贴上去的那张样式盒**，判据是"这张描边图是不是
## UIKit 按『可选中』那套参数（2px 金边 + 底色提亮一档）生成的那张"。`UIKit._rounded_tex` 按**参数**
## 缓存 ⇒ 同参必得同一个 `Texture2D` 实例，所以身份比较成立。**不读任何内部标志**（那会在
## "高亮坏了但标志还对"时骗过断言）。与 `hud_test._corner_bar_hot` 逐条同源。
func _chip_hot(chip: Dictionary, UK) -> bool:
	var root: Control = chip.get("root")
	if root == null or not is_instance_valid(root):
		return false
	var sb := root.get_theme_stylebox("panel")
	if not (sb is StyleBoxTexture):
		return false
	var bg := Color(0.085, 0.095, 0.138, 0.82).lightened(0.10)
	var border := Color(UK.ACCENT.r, UK.ACCENT.g, UK.ACCENT.b, 0.9)
	var hot_sb: StyleBoxTexture = UK.card_stylebox(bg, 10, border, 2, 4)
	return (sb as StyleBoxTexture).texture == hot_sb.texture

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

## 一块立牌**牌面的八个角**折回画布像素。两种折法各有各的用途（`via_ray` 选）：
##
##   * `via_ray = true`：**看得见的那块投影足迹** —— 走与 `placard_hit` 同一条链
##     （`unproject_position` → 屏幕 → 射线打回桌面平面 → 画布）。问的是"从相机看过去，
##     这一角压在桌面的哪一点" ⇒ **"压不压地块"问的就是它**（玩家看到牌盖在格子上 = 点不到那格）。
##   * `via_ray = false`：`world_to_canvas_px`，**忽略高度** ⇒ "这一角正下方桌面上是哪一点"，
##     也就是这块牌**站在桌面的哪儿**。问"它在不在桌子里"该用它：立着的牌会往镜头这一侧
##     "倒"出去一点（实测最外那颗角越过木桌外沿 ~13 画布像素 ≈ 1 cm 真实），那是**牌自己站着的
##     那一小块地**之上的一角、不是"站到桌子外面去了"。
func _face_corners_px(t3, pl: Dictionary, t_half: float, via_ray: bool) -> Array:
	var out: Array = []
	var face: MeshInstance3D = pl["face"]
	var pm: PlaneMesh = face.mesh as PlaneMesh
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				var w: Vector3 = face.global_transform * Vector3(
					pm.size.x * float(sx), pm.size.y * float(sy), t_half * 2.0 * float(sz))
				if via_ray:
					var px = t3.screen_to_viewport(t3.camera.unproject_position(w))
					if px != null:
						out.append(px as Vector2)
				else:
					out.append(t3.world_to_canvas_px(w))
	return out

## 一块立牌的**牌心**折成画布像素（同一条链）—— ⑧ / ⑨ 的命中采样点。
func _face_canvas_px(t3, pl: Dictionary) -> Variant:
	var face: MeshInstance3D = pl["face"]
	return t3.screen_to_viewport(t3.camera.unproject_position(face.global_position))

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
	var P_T: float = float(tp_consts.get("PLACARD_T", 0.0))
	_check(P_W > 0.0 and P_T > 0.0,
		"立牌几何常量在（`PLACARD_W`=%.3f / `PLACARD_T`=%.3f）" % [P_W, P_T])
	g.my_peer = 2
	# 喂状态 ⇒ `_refresh_players` → `_refresh_corner_bars` → `_refresh_placards`（真入口，含烘图）
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
		slots[int(p)] = int(tp._placards[p]["slot"])
	_check(slots == {1: 3, 3: 1, 4: 2},
		"落位按 `game._seat_peers()` 反查：丙 slot1(右) / 丁 slot2(对面) / 甲 slot3(左)（实得 %s）" % str(slots))
	# 牌面那块 chip（离屏烘图的那一份）与立牌**同一位家**，且带着 `chip_vp`（这一项只有立牌面有）
	var chips_shown: Array = []
	for c in g.placard_chips:
		if c.get("chip_vp") != null and int(c.get("peer", GameData.NO_PEER)) != GameData.NO_PEER:
			chips_shown.append(int(c.peer))
	chips_shown.sort()
	_check(chips_shown == shown,
		"`game.placard_chips` 与 3D 立牌**同步**（逐位同家，实得 %s）" % str(chips_shown))

	print("== ② 棋子色小片随各家的 `p.color` 走，**不随座位序号** ==")
	var UK = load("res://scripts/ui_kit.gd")
	var col_bad: Array = []
	var col_log := ""
	for p in shown:
		var chip: Dictionary = _chip_of(g, int(p))
		var want_i := int(g._state_player(int(p)).get("color", 0))
		var got_i := int(chip.get("chip_color", -999))
		# 小片是"棋子贴图 + 棋子色"那一枚（`UIKit.chip`）：贴图按色号选 ⇒ 读它贴了哪张，
		# 比读那个色号本身更硬（色号对了、贴图贴错也照样红）。
		var ctrl: Control = chip.get("chip")
		var got_path := ""
		if ctrl != null and ctrl.get_child_count() > 0 and ctrl.get_child(0) is TextureRect:
			var tr := ctrl.get_child(0) as TextureRect
			if tr.texture != null:
				got_path = String(tr.texture.resource_path)
		var want_path := "res://assets/pieces/piece%s_05.png" % UK.PIECE_COLORS[
			clampi(want_i, 0, UK.PIECE_COLORS.size() - 1)]
		var by_slot: int = int(tp._placards[p]["slot"]) % GameData.PLAYER_COLORS.size()
		if got_i != want_i or got_path != want_path or want_i == by_slot:
			col_bad.append(int(p))
		col_log += "peer%d(色%d/座%d) chip_color=%d 贴图=%s（期望 %s；按座号会是色%d） | " % [
			int(p), want_i, int(tp._placards[p]["slot"]), got_i, got_path, want_path, by_slot]
	print("  [实测] %s" % col_log)
	_check(col_bad.is_empty(),
		"**小片色 = `p.color`**（贴图也是那一张；不是按座位序号取色；不符的 %s）" % str(col_bad))

	print("== ③ 昵称文本 == name / 名次徽章 == rank ==")
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
		var chip2: Dictionary = _chip_of(g, int(p))
		var pl2: Dictionary = g._state_player(int(p))
		# 昵称后面那截标记是**既定契约**（`_fill_peer_bar`）：出局的挂「（破产）」。
		var want_name := String(pl2.get("name", "?")) \
			+ ("" if bool(pl2.get("alive", true)) else "（破产）")
		var want_rank: int = order.find(int(p)) + 1
		var got_name := String((chip2.get("name_l") as Label).text)
		var got_rank: int = _rank_of(chip2)
		if got_name != want_name:
			name_bad.append(int(p))
		if got_rank != want_rank:
			rank_bad.append(int(p))
		print("  [实测] peer%d 昵称「%s」(期望「%s」) / 名次徽章 %d(期望 %d，身家 %d)"
			% [int(p), got_name, want_name, got_rank, want_rank, int(worth[int(p)])])
	_check(name_bad.is_empty(), "昵称文本 == 喂进去的 name（不符的 %s）" % str(name_bad))
	_check(rank_bad.is_empty(), "名次徽章 == 喂进去的 rank（身家倒序；不符的 %s）" % str(rank_bad))

	print("== ④ 落点在自己那一侧的木纹带里（牌面四角折回画布像素：环之外、桌沿之内）==")
	var ring := _ring_rect(t3)
	var table_r := _table_rect(t3)
	var side_bad: Array = []
	var side_log := ""
	for p in shown:
		var gp: Vector3 = (tp._placards[p]["root"] as Node3D).global_position
		var s := int(tp._placards[p]["slot"])
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
	var out_bad: Array = []
	var corner_log := ""
	for p in shown:
		# 压不压地块：用**看得见的投影足迹**（射线折法，同 `placard_hit`）
		var cs: Array = _face_corners_px(t3, tp._placards[p], P_T * 0.5, true)
		# 在不在桌内：用**落在桌面的那一块地**（忽略高度）—— 见 `_face_corners_px` 那段说明
		var fs: Array = _face_corners_px(t3, tp._placards[p], P_T * 0.5, false)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		var mn2 := Vector2(INF, INF)
		var mx2 := Vector2(-INF, -INF)
		for c in cs:
			mn = mn.min(c as Vector2)
			mx = mx.max(c as Vector2)
			if ring.has_point(c as Vector2):
				in_bad.append(int(p))
		for c in fs:
			mn2 = mn2.min(c as Vector2)
			mx2 = mx2.max(c as Vector2)
			if not table_r.has_point(c as Vector2):
				out_bad.append(int(p))
		corner_log += "peer%d 足迹(射线) %s..%s / 落桌 %s..%s | " % [int(p), mn, mx, mn2, mx2]
	print("  [实测] %s" % corner_log)
	print("  [实测] 地块环 %s / 木桌外沿 %s" % [str(ring), str(table_r)])
	_check(in_bad.is_empty(),
		"**每一角都不压地块**（看得见的那块足迹八角逐个查，全在地块环之外；压到的 %s）" % str(in_bad))
	# ⚠ **牌面宽（1.15）比木纹带（≈0.92）宽 ⇒ 外沿那一排角会探出木桌外沿** —— 这是**故意的**
	#（用户 2026-10-06：「减小桌面边缘宽度」；立牌是悬空 billboard，不参与物理），
	# 见 `table_props.PLACARD_W` 那段。⇒ 判据改成"**落桌点**（牌心投影）在木桌之内"，
	# 而不是"八个角都在桌内"：前者仍然拦得住"牌飘到屋子外面去了"，后者今天**挡的就是设计本身**。
	var anchor_out: Array = []
	for p in shown:
		var apx: Vector2 = t3.world_to_canvas_px((tp._placards[p]["root"] as Node3D).global_position)
		if not table_r.has_point(apx):
			anchor_out.append(int(p))
	_check(anchor_out.is_empty(),
		"**每块牌的落桌点都在木桌上**（牌心折回画布像素；飘出的 %s —— 探出桌沿那一圈是故意的，见注释）"
			% str(anchor_out))

	print("== ⑤ 整块正对相机（billboard）==")
	var cam: Camera3D = t3.camera
	_check(cam != null, "（前提）相机在")
	var basis_bad: Array = []
	for p in shown:
		var b: Basis = (tp._placards[p]["root"] as Node3D).global_transform.basis
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
	# 期望抬升 = `半高 × camera.basis.y.y`（`_face_camera` 的式子；半高 = 牌面高的一半，随宽高比走）
	for p in shown:
		var pl: Dictionary = tp._placards[p]
		var root3: Node3D = pl["root"]
		var hh: float = ((pl["face"] as MeshInstance3D).mesh as PlaneMesh).size.y * 0.5
		var gp3: Vector3 = root3.global_position
		# ⚠ 式子里还有 `PROPS_Y`（桌面实体层统一抬的那 0.02）：`_face_camera` 先把落点抬到
		# `table_mesh.y + PROPS_Y`，再加 `半高 × up_y` ⇒ 差值应当是 `PROPS_Y + 半高 × up_y`。
		if not (gp3.y > ty and absf((gp3.y - ty - tp.PROPS_Y) - (hh * up_y3)) < 0.02):
			lift_bad.append(int(p))
		lift_log += "peer%d y=%.4f(桌面 %.4f，抬 %+.4f；半高 %.3f×up_y %.3f=%.4f) | " % [
			int(p), gp3.y, ty, gp3.y - ty, hh, up_y3, hh * up_y3]
	print("  [实测] 3D 端牌心：%s" % lift_log)
	_check(lift_bad.is_empty(),
		"3D 端：牌心**在桌面之上**、抬的正是 `半高 × camera.basis.y.y`（不符的 %s）" % str(lift_bad))
	# ---- 2D 端 ----
	t3.snap_view(1.0)
	basis_bad = []
	for p in shown:
		var b2: Basis = (tp._placards[p]["root"] as Node3D).global_transform.basis
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
		var gp4: Vector3 = (tp._placards[p]["root"] as Node3D).global_position
		if absf(gp4.y - ty) > 0.05:
			flat_bad.append(int(p))
		flat_log += "peer%d y=%.4f（桌面 %.4f，差 %+.4f） | " % [int(p), gp4.y, ty, gp4.y - ty]
	print("  [实测] 2D 端牌心：%s（camera.basis.y.y=%.4f）" % [flat_log, up_y2])
	_check(flat_bad.is_empty(),
		"**2D 端正俯视 ⇒ 牌心落回桌面**（`camera.basis.y.y`≈0 ⇒ 抬升那一项归零 = 平贴桌面；"
			+ "偏离 >0.05 的 %s）" % str(flat_bad))
	# ---- 真正钉住"正对相机"：**不读实现写法，直接量"是不是真的朝着我"** ----
	# 判据：牌面法线（`root.basis.z` —— 相机的 +Z 就是"朝向观察者"那一维）与该牌**指向相机的方向**
	# 做点积。⚠ 阈值 **0.88** 而不是 1.0/0.99：实现抄的是**相机那一个全局姿态**（不是逐块
	# `look_at` —— 那条在 2D 端会退化，见 `_face_camera` 的说明），而两侧座位本来就偏离相机轴
	# 二十多度 ⇒ 点积**天生到不了 1**。实测（打印在下面）：两侧 ≈0.89、对面 ≈0.94；
	# **对照读数**：同一批牌如果"干脆不转"（法线 = `+Z`），点积只有 ≈0.62 —— 这条钉的就是
	# "朝向到底跟不跟着相机走"。**变红口子**：`_face_camera` 里不写 `camera.basis`、
	# 或把它换回"随视角后倾 25°"那条轨道，点积都会掉到 0.6~0.87 那一档。
	var FACING_MIN := 0.88
	var dot_min := 2.0
	var dot_fixed := 2.0
	var dot_log := ""
	for p in shown:
		var root5: Node3D = tp._placards[p]["root"]
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

	print("== ⑥ 金边：`_push_peer_highlight` 之后那一块 chip 换成金框（判据仍在 game 那侧）==")
	var hot_pre := []
	for p in shown:
		hot_pre.append(_chip_hot(_chip_of(g, int(p)), UK))
	_check(not hot_pre[0] and not hot_pre[1] and not hot_pre[2], "（起点）三块都还不是金框（实得 %s）" % str(hot_pre))
	g._push_peer_highlight([3])
	var hot_after := {}
	for p in shown:
		hot_after[int(p)] = _chip_hot(_chip_of(g, int(p)), UK)
	_check(hot_after[3] and not hot_after[1] and not hot_after[4],
		"`_push_peer_highlight([3])` ⇒ **只有丙那一块**换成「可选中」那张金框（实得 %s）" % str(hot_after))
	g._push_peer_highlight([1])
	var hot_after2 := {}
	for p in shown:
		hot_after2[int(p)] = _chip_hot(_chip_of(g, int(p)), UK)
	_check(hot_after2[1] and not hot_after2[3] and not hot_after2[4],
		"换成甲 ⇒ **金框跟着换**、丙那一块还原（只加不撤的话这条会红，实得 %s）" % str(hot_after2))
	g._push_peer_highlight([])
	var hot_after3 := {}
	for p in shown:
		hot_after3[int(p)] = _chip_hot(_chip_of(g, int(p)), UK)
	var hot_all: Array = []
	for p in shown:
		hot_all.append(hot_after3[int(p)])
	_check(hot_all.all(func(x): return not x),
		"传空数组 ⇒ **三块全灭**、各自回到普通卡样式（实得 %s）" % str(hot_after3))

	print("== ⑦ 行动者倒计时：推进 `_op_*` 再 `_refresh_corner_timer()` ==")
	g._op_kind = "roll"
	g._op_owner = 3
	g._op_left = 15.0
	g._op_total = 20.0
	g._refresh_corner_timer()
	var chip3: Dictionary = _chip_of(g, 3)
	_check((chip3.get("timer_track") as ColorRect).visible and (chip3.get("timer_left") as Label).visible,
		"行动者（丙）那一块露倒计时行（进度条 + 秒数）")
	_check(String((chip3.get("timer_left") as Label).text) == "15 秒",
		"秒数跟着 `_op_left` 走（实得「%s」）" % String((chip3.get("timer_left") as Label).text))
	_check((chip3.get("timer_kind") as Label).visible and String((chip3.get("timer_kind") as Label).text) == "掷轮",
		"环节名跟着 `_op_kind` 走（实得「%s」）" % String((chip3.get("timer_kind") as Label).text))
	var others_on := 0
	for p in [1, 4]:
		var oc: Dictionary = _chip_of(g, int(p))
		if (oc.get("timer_track") as ColorRect).visible or (oc.get("timer_left") as Label).visible:
			others_on += 1
	_check(others_on == 0, "其余两块**不显示倒计时**（只出现在行动者那一块上；越界 %d 块）" % others_on)
	# 我那条身家条（屏幕层）此刻不该显示 —— 倒计时只落在一处
	_check(not (g.corner_bars[0].timer_kind as Label).visible,
		"窗口归属不是我 ⇒ 屏幕层那条身家条的倒计时内容收起（同一条判据、两处载体）")
	# 限时窗口关掉（`_op_kind = ""`）⇒ 倒计时内容全收
	g._op_kind = ""
	g._refresh_corner_timer()
	var any_on := false
	for p in shown:
		var ac: Dictionary = _chip_of(g, int(p))
		if (ac.get("timer_track") as ColorRect).visible or (ac.get("timer_kind") as Label).visible:
			any_on = true
	_check(not any_on, "窗口关闭（`_op_kind = \"\"`）⇒ 三块全收（一处都不显示）")

	print("== ⑧ 命中链：`placard_hit` ==")
	var hit_bad: Array = []
	for p in shown:
		var px = _face_canvas_px(t3, tp._placards[p])
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
	var px1 = _face_canvas_px(t3, tp._placards[1])
	_check(px1 != null, "（前置）甲的牌心可解算到画布像素")
	var p1c: Vector2 = px1 if px1 != null else Vector2(-9999.0, -9999.0)
	_check(tp.placard_hit(p1c) == 1, "（前置）这个点确实落在甲那块牌上（实得 %d）" % tp.placard_hit(p1c))
	_check(g._on_table_click(p1c, MOUSE_BUTTON_LEFT), "点它：这次点击被实体层消费（`_on_table_click`）")
	_check(g.player_popup != null and g.player_popup.is_open() and g.player_popup.open_peer() == 1,
		"**真的开了 peer 1 的道具弹窗**（实得 peer %s）"
			% str(g.player_popup.open_peer() if g.player_popup != null else -99999))
	g.player_popup.close()

	print("== ⑩ 幂等：同一份 rows 再来一次 = 同一批节点实例；少一个 peer ⇒ 那一块被收掉 ==")
	# 直接走 `set_placard_faces`（同 `chars_test` ⑪ 直接调 `set_chars` 的写法）：走广播的话
	# `_refresh_corner_bars` 的签名缓存会把第二次早退掉，这条就变成"什么都没调用"的空转。
	var rows: Array = []
	for p in shown:
		var pl: Dictionary = tp._placards[p]
		rows.append({"peer": int(p), "slot": int(pl["slot"]),
			"tex": (pl["face_mat"] as StandardMaterial3D).albedo_texture,
			"w": float(pl["w"]), "h": float(pl["h"])})
	var tex_ok := true
	for r in rows:
		if not (r["tex"] is Texture2D):
			tex_ok = false
	_check(tex_ok and rows.size() == 3, "每一行的 `tex` 都是一张 `Texture2D`（实得 %d 行）" % rows.size())
	# 贴的那张就是那一块 chip 自己烘出来的那张（同一份 `SubViewport` 的 render target）
	var tex_same := true
	for r in rows:
		var c2: Dictionary = _chip_of(g, int(r["peer"]))
		if c2.is_empty() or r["tex"] != (c2["chip_vp"] as SubViewport).get_texture():
			tex_same = false
	_check(tex_same, "立牌贴的 `tex` == 那一块 chip 自己 `SubViewport` 的 `get_texture()`（同一份烘图）")
	var before := {}
	for p in shown:
		before[int(p)] = tp._placards[p]["root"]
	tp.set_placard_faces(rows)
	var same := true
	for p in shown:
		# `is_same(a, b)` 是**全局函数**（Godot 4：比较是不是同一个实例），不是节点上的方法。
		if not is_same(tp._placards[p]["root"], before[int(p)]):
			same = false
	_check(same and tp._placards.size() == 3,
		"同样的 rows 再来一次 ⇒ **同一批节点实例**（`set_placard_faces` 的幂等；每次广播都调它）")
	tp.set_placard_faces([rows[0], rows[1]])
	var after: Array = tp._placards.keys()
	after.sort()
	_check(after == [int(rows[0]["peer"]), int(rows[1]["peer"])] or after.size() == 2,
		"状态里少了的 peer ⇒ **那一块从池子里收掉**（实得 %s）" % str(after))
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
