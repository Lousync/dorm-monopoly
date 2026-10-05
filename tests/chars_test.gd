extends SceneTree
## 二期 Task 2：**四个座位（3 个角色）+ 座位 ↔ peer 固化**
## godot --headless --path . --script tests/chars_test.gd
##
## Task 1 立的判据一条不丢（①~⑤ 与"不投影"），**逐条按三个角色重述**（原来只有 slot 1 一个），
## 另加本任务的两条：
##   ① `slot 1/2/3` 各坐一个人、**`slot 0`（近侧 = 「我」，相机就在那儿）一个人都没有**；
##   ② 每个人都站在**自己那把椅子**的锚点上（xz 与朝向都读一期 `seat_anchor(slot)`，不另算）；
##   ③ **脚底落在 `FLOOR_Y`、髋落在座面**（手摆坐姿对不对的唯一硬判据）；
##   ④ 角色**不与桌子相交** —— 逐件、对桌子的**实体体积**（底座 ∪ 桌面那一层）量体积相交；
##   ⑤ 材质**不是 `SHADING_MODE_UNSHADED`**、**底色只被压暗过**、**贴图还是自己那张**；
##   ⑥ **角色不许是画面里最亮的东西**（Ruling E2 的 J1）：三人的有效 albedo × 照度，
##      最亮那个也不许高过桌面那一笔（同一把尺子）；
##   ⑦ 三个人**两两不相交**（各在各自椅子上，互相不穿）；
##   ⑧ 不投影（房间的纪律：全场唯一投影源是那盏吊灯）。
##   **【本轮新增】** ⑨ **模型按棋子色选**（`CHAR_MODELS_BY_COLOR`）——喂进来的座位序里
##      **"色号"与"座位号"处处不等** ⇒ 按椅子号取模型的话这条必红；
##      ⑩ **同一个 peer 换椅子坐仍是同一张脸**（座位序轮转一格后逐家比对）；
##      ⑪ **同样的座位序再来一次 = 同一批节点实例**（`set_chars` 的早退；
##      去掉早退这条立刻红 —— 每次广播都把三个人整套重建）。
##   **【Task 3 新增】** ⑫ **待机 `idle` 在播、且 `loop_mode` 真的是 `LOOP_LINEAR`**
##      （导入器给的是 `LOOP_NONE` ⇒ "导入成功就会循环"是个会静默出错的假设）；
##      ⑬ **真的在动**（同一分件在两个动画相位上的世界位置必须不同 —— 只拍一帧什么都证明不了）；
##      ⑭ **随取景淡出并停播**（走真接口 `snap_dolly` / `snap_view`：拉远端在、推近端与 2D 端
##      **全隐 + `is_playing() == false`**，推回默认档又活过来）；
##      ⑮ **`set_fade(t)` 的阈值契约**（`FADE_SOLID_T` / `FADE_GONE_T` 四个点）；
##      ⑯ 淡出用的推拉近端与一期 `DOLLY_MIN` 同值；⑰ **当前行动者靠 `idle` 提速**（"轮到我了"）。
##   **【fix round 新增】** ⑱ **淡出档上的反应一律丢掉**（`react()` 的早退）：淡到"全隐 + 停播"
##      之后三条一次性动作各来一次（人仍全隐、播放器仍未在播，等过标称时长后仍然如此），
##      `die` 再单独打一次（还要多钉一条"破产记忆没被种下"）——
##      ⑭(b)(c) **抓不到它**（那两条在淡出与断言之间没有任何事件，这正是终审 findings ① 的由来）。
##
## 坐姿不是包里的 `sit`（腿是一整块刚体、无膝关节，`sit` 把腿平举 ⇒ 会捅进桌子 1.66 世界），
## 是**手摆**（普查 §5.2）：整体下移 `SEAT_ROOT_Y` + 腿竖直压到 `LEG_SQUASH`
## ⇒ 脚底回到地面、髋回到座面。下移**放在角色之上的外套节点**上（`idle` 有一条 `root`
## 常值轨道，一播就把 `root.position.y` 顶回 0）。

var fails := 0

## 本任务有人的三个座位（**0 号不算**：那是「我」）。
const CHAR_SLOTS := [1, 2, 3]
## 「我」的座位：0 号 = 近侧 = 相机这一侧 ⇒ **不渲染**（spec §5.1）。
const MY_SLOT := 0
## 一期椅子座面离地（`room.gd` 的比例表：座面 = `FLOOR_Y + 2.25` = 真实 0.45 m 座高）。
## **不是**本文件的实现常量 —— 它是房间那边的既有事实，这里拿它当坐姿的外尺。
const SEAT_H := 2.25

## 破产姿态的**实测读数**（判据同一把尺子量两次：刚破产时 / 淡出往返之后）。返回：
##   * `top` / `low`：全部分件的世界 AABB 的最高点 / 最低点（"人还在座位上、看得见"靠它）；
##   * `head_y`：头分件的世界 y（**在桌面上方** = 从相机看没被桌子挡掉）；
##   * `hits` / `worst`：逐分件与**桌子实体体积**（底座 ∪ 桌面那一层）的相交件数 / 最近净空
##     —— 与 Task 1 立的判据 ③ **同一口径**（合并 AABB 不算数，那 5 mm 是浮在桌上的头）。
func _death_pose(w: Node3D, t3: Node) -> Dictionary:
	var out := {"top": -INF, "low": INF, "head_y": -INF, "hits": 0, "worst": INF}
	if w == null:
		return out
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	var tmat: MeshInstance3D = t3.get("table_mesh")
	if tbase == null or tbase.mesh == null or tmat == null or tmat.mesh == null:
		return out
	var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
	var tma: AABB = tmat.global_transform * tmat.mesh.get_aabb()
	var slab := AABB(Vector3(tma.position.x, tb.end.y, tma.position.z),
		Vector3(tma.size.x, tma.position.y - tb.end.y, tma.size.z))
	var head := w.find_child("head", true, false) as Node3D
	if head != null:
		out.head_y = head.global_position.y
	for n in w.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null or g.mesh == null:
			continue
		var a: AABB = g.global_transform * g.mesh.get_aabb()
		out.top = maxf(out.top, a.end.y)
		out.low = minf(out.low, a.position.y)
		var gp: float = maxf(_aabb_gap(a, tb), _aabb_gap(a, slab))
		out.worst = minf(out.worst, gp)
		if gp <= 0.0:
			out.hits = int(out.hits) + 1
	return out

## **角色的"被照亮的 albedo"相对桌面那一笔的比值上限**（Task 1 的 J1，`CHAR_LIT_RATIO_MAX`）。
##
## **为什么是 1.0**：本档要的就是那句大白话 —— **角色不许亮过桌面**。
## ⚠ **与 phase 1 那条的唯一分歧，是故意的**：`layout_test` 拿**桌面最暗那个角**去比（从严），
## 可它两边**贴的是同一张木纹**（家具与木桌都用 `wood_floor.jpg`）⇒ 贴图在比值里**约掉了**，
## 它比的是"色调对色调"。角色**换了一张贴图**、约不掉 ⇒ 只能把贴图算进来；而一旦算进来，
## "最暗那个角"就变成"角色必须比**屋里最暗的那块木头**还暗"（实测要 `CHAR_TINT` 降到 0.25 才过），
## 那会把脸一起压黑 —— 与 spec §十 F8「不靠名牌、**靠角色本身认人**」直接冲突。
## ⇒ 这里对桌面取**最亮那个采样点**（"桌面自己的亮度"），是两边都公平的那一档。
const CHAR_LIT_RATIO_MAX := 1.0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 一棵子树里所有几何实例的世界 AABB 的并集（口径同 `layout_test._subtree_world_aabb`）。
func _subtree_world_aabb(root: Node) -> AABB:
	var out := AABB()
	var got := false
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null or g.mesh == null:
			continue
		var a: AABB = g.global_transform * g.mesh.get_aabb()
		out = a if not got else out.merge(a)
		got = true
	return out

## 两个世界 AABB 之间的**净空**（>0 = 分开多远；<0 = 重叠多深）。按"分得最开的那一维"量
## —— 与 `intersects()` 同一口径（只要有一维分得开就不相交），但能给一个可读的数。
func _aabb_gap(a: AABB, b: AABB) -> float:
	var g := -INF
	for k in 3:
		g = maxf(g, maxf(b.position[k] - a.end[k], a.position[k] - b.end[k]))
	return g

## 一棵子树里**逐实例透明度**的最大值（`GeometryInstance3D.transparency`；0 = 全亮、1 = 全隐）。
## 用它核"淡出真的落到画面上"—— 不读 `GameChars` 里的实现常量（读常量等于把实现重述一遍）。
func _max_transparency(root: Node3D) -> float:
	var mx := 0.0
	if root == null:
		return mx
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi != null:
			mx = maxf(mx, gi.transparency)
	return mx

## 一张贴图在**某个面真正贴上去的那一块**上的平均色（在该面的 UV 区域上打 8×8 网格取样）。
##
## 为什么不取整张图集的平均：Kenney 的图集里**大片是没用到的背景** —— 实测角色-a 的整图平均亮度
## 只有 0.262，而"手臂"那一块是 **0.578** ⇒ 取整图平均会把角色量成"很暗"，判据就成了空转。
## **不翻 V**：glTF 的 UV 原点在左上，与本项目 `Image.get_pixel` 的取向一致
##（实测：翻 V 会把"头"那一块取成躯干那一块）。
func _surf_tex_avg(gi: MeshInstance3D, s: int, m: BaseMaterial3D) -> Variant:
	if gi == null or gi.mesh == null or m == null or m.albedo_texture == null:
		return null
	var img: Image = m.albedo_texture.get_image()
	if img == null:
		return null
	var arr := gi.mesh.surface_get_arrays(s)
	if arr.size() <= Mesh.ARRAY_TEX_UV or arr[Mesh.ARRAY_TEX_UV] == null:
		return null
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return null
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for uv in uvs:
		var u := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))   # 这个包的 UV 会超出 1（repeat）
		lo = lo.min(u)
		hi = hi.max(u)
	var acc := Vector3.ZERO
	var n := 0
	for iy in 8:
		for ix in 8:
			var u := Vector2(lerpf(lo.x, hi.x, (float(ix) + 0.5) / 8.0),
				lerpf(lo.y, hi.y, (float(iy) + 0.5) / 8.0))
			var px := img.get_pixel(
				clampi(int(u.x * float(img.get_width())), 0, img.get_width() - 1),
				clampi(int(u.y * float(img.get_height())), 0, img.get_height() - 1))
			acc += Vector3(px.r, px.g, px.b)
			n += 1
	return acc / float(maxi(n, 1))

## 一棵子树**最亮那一件的有效 albedo 亮度** = `albedo_color`（色调）⊙ 它那一块贴图的平均色。
##
## **从材质上读，不读 `GameChars.CHAR_TINT`**（同 `layout_test._subtree_albedo_lum` 那条理由）：
## 读常量等于把实现重述一遍，色调改成什么值都照样过 —— 那正是要避免的永真断言。
func _subtree_lit_albedo_lum(root: Node) -> Dictionary:
	var mx := -1.0
	var log := ""
	var n_surf := 0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as MeshInstance3D
		if gi == null or gi.mesh == null:
			continue
		for s in gi.mesh.get_surface_count():
			var m := gi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			n_surf += 1
			var avg = _surf_tex_avg(gi, s, m)
			var eff: Color = m.albedo_color
			if avg != null:
				eff = Color(m.albedo_color.r * avg.x, m.albedo_color.g * avg.y, m.albedo_color.b * avg.z)
			mx = maxf(mx, eff.get_luminance())
			log += "%s:%.3f " % [gi.name, eff.get_luminance()]
	return {"lum": mx, "log": log, "n": n_surf}

## 一点吃到的**相对照度**（口径与 `layout_test._mat_sample_irradiance` **逐项相同** ——
## 「尺子只能用一把」：GLES3 的 `max(1 − (d/range)^4, 0)^2 × d^(−衰减指数) × 能量 × N·L` + 环境光那一份）。
func _irradiance(light: OmniLight3D, p: Vector3, ambient: float) -> float:
	var d: float = light.global_position.distance_to(p)
	d = maxf(d, 0.0001)
	var nd: float = d / light.omni_range
	nd = nd * nd
	nd = nd * nd
	var shape: float = maxf(1.0 - nd, 0.0)
	shape = shape * shape
	var decay: float = pow(maxf(d, 0.0001), -light.omni_attenuation)
	var cos_i: float = clampf((light.global_position.y - p.y) / d, 0.0, 1.0)
	return light.light_energy * shape * decay * cos_i + ambient

## 喂进去的座位序（**故意让"色号"与"座位号"处处不等** —— 见断言 ⑨：
## 按椅子号取模型的话，slot 1 会拿到 `model_for_color(1)` = g，与期望的 **p** 不同 ⇒ 必红
## —— 调色板现在是 `k / g / n / p`，slot 1 的色号是 3 ⇒ 期望 `p`）。
func _seats() -> Array:
	return [
		{"peer": 2, "color": 1, "name": "乙"},   # slot 0 = 我（近侧，不渲染）
		{"peer": 3, "color": 3, "name": "丙"},   # slot 1 右
		{"peer": 4, "color": 0, "name": "丁"},   # slot 2 远（**居中、正对镜头**那把）
		{"peer": 5, "color": 2, "name": "戊"},   # slot 3 左
	]

## 同一批人**换椅子坐**（把 1/2/3 号座位上的人轮转一格）：用来验"同一 peer 仍是同一张脸"。
func _seats_rotated() -> Array:
	return [
		{"peer": 2, "color": 1, "name": "乙"},
		{"peer": 5, "color": 2, "name": "戊"},
		{"peer": 3, "color": 3, "name": "丙"},
		{"peer": 4, "color": 0, "name": "丁"},
	]

func _run() -> void:
	root.size = Vector2i(1280, 800)
	# 用运行时 load() 取 TableView3D（同 layout_test / hud_test）：`--script` 入口的静态依赖链
	# 在 autoload 注册之前编译，静态写类名会把 game/BoardView 那条链（依赖 `Fx`）拽进来。
	var t3 = load("res://scripts/table_3d.gd").new()
	root.add_child(t3)
	await process_frame
	await process_frame

	print("== 二期 Task 2：角色层（三个座位 1/2/3，slot 0 仍为空）==")
	var room: Node = t3.get_node_or_null("Room")
	_check(room != null, "房间在（一期：ROOM_ENABLED 的那一层）")
	var chars: Node = room.get_node_or_null("Chars") if room != null else null
	# 契约：`CHARS_ENABLED` 为 true 时角色层在；置 false 时**一个节点都不留**（变红口子）。
	_check(chars != null == GameChars.CHARS_ENABLED,
		"CHARS_ENABLED=%s 时角色层%s存在" % [GameChars.CHARS_ENABLED, "" if chars != null else "不"])
	if chars == null:
		_check(false, "角色层缺了（CHARS_ENABLED=false 时这是对的）⇒ 下面整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return
	# **先断言"还没喂座位序时一个角色都没有"**：摆人一律由 `set_chars()` 驱动（不在 `_ready`）——
	# 这条同时钉住了"不在 `_ready` 里摆人"这件事（否则房间一生出来就有人、状态还没来）。
	_check(chars.get_node_or_null("Char1") == null,
		"**没喂座位序时一个角色都没有**（摆人由 `set_chars()` 驱动，不在 `_ready` —— `_ready` 那刻还没有状态）")
	# 喂之前先记一下：`char_peers()` 在没喂过的时候应当是空的（没有半个座位的故事）。
	_check(chars.char_peers().is_empty() and chars.char_model(1) == "",
		"没喂过座位序时 `char_peers()` 为空、`char_model()` 为 \"\"（实得 %s / \"%s\"）"
			% [str(chars.char_peers()), chars.char_model(1)])

	# ---- 喂座位序（走 `game.gd:_refresh_players()` 喂的**同一个接口、同一份序**）----
	var seats := _seats()
	chars.set_chars(seats)
	await process_frame

	# ① 三个座位上有人、`slot 0` 没有人
	var c: Array = []          # c[i] = 第 i 把椅子上的外套节点（null = 没人）
	var missing: Array = []
	for i in seats.size():
		c.append(chars.get_node_or_null("Char%d" % i) as Node3D)
		if i != MY_SLOT and c[i] == null:
			missing.append(i)
	_check(missing.is_empty() and c.size() == 4,
		"`slot %s` 上各坐着一个人（缺 %s）" % [str(CHAR_SLOTS), str(missing)])
	_check(c[MY_SLOT] == null,
		"`slot %d`（近侧 =「我」）**一个人都没有** —— 相机就在那儿（spec §5.1）" % MY_SLOT)
	if not missing.is_empty():
		_check(false, "有座位空着 ⇒ 下面几条整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return

	# ② 每个人都站在**自己那把椅子**的锚点上（位置 + 朝向都读一期留的 `seat_anchor(slot)`）
	var pos_bad: Array = []
	var face_bad: Array = []
	var pos_log := ""
	for i in CHAR_SLOTS:
		var an: Transform3D = room.seat_anchor(i)
		var cp: Vector3 = c[i].global_position
		var to_center := Vector3(-an.origin.x, 0.0, -an.origin.z).normalized()
		var facing: Vector3 = (c[i].global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		var d: float = facing.dot(to_center)
		if absf(cp.x - an.origin.x) >= 0.001 or absf(cp.z - an.origin.z) >= 0.001:
			pos_bad.append(i)
		if d <= 0.95:
			face_bad.append(i)
		pos_log += "slot%d 人(%.3f,%.3f)/锚点(%.3f,%.3f) 朝向点积%+.3f | " % [i, cp.x, cp.z, an.origin.x, an.origin.z, d]
	print("  [实测] %s" % pos_log)
	_check(pos_bad.is_empty(),
		"三个人都站在**自己那把椅子**的座位锚点上（越位 %s —— 座位坐标全部来自一期接口 `seat_anchor(slot)`，不另算）"
			% str(pos_bad))
	_check(face_bad.is_empty(),
		"三个人都面朝桌心（正面 = `+Z`，与 `seat_anchor` 天然对齐、不用补 180°；点积 <0.95 的座位 %s）"
			% str(face_bad))

	# ③ 手摆坐姿：脚底落地面、髋落座面（**三个人逐个量**）
	var parts_bad: Array = []
	var feet_bad: Array = []
	var hip_bad: Array = []
	var pose_log := ""
	var ab: Array = []        # 每个人的世界 AABB
	for i in CHAR_SLOTS:
		var leg_l := c[i].find_child("leg-left", true, false) as Node3D
		var leg_r := c[i].find_child("leg-right", true, false) as Node3D
		if leg_l == null or leg_r == null or c[i].find_child("root", true, false) == null \
				or c[i].find_child("torso", true, false) == null:
			parts_bad.append(i)
		var a := _subtree_world_aabb(c[i])
		ab.append(a)
		var feet: float = a.position.y
		var hip: float = leg_l.global_position.y if leg_l != null else -9999.0
		var seat_y: float = GameRoom.FLOOR_Y + SEAT_H
		if absf(feet - GameRoom.FLOOR_Y) > 0.05:
			feet_bad.append(i)
		if leg_l == null or absf(hip - seat_y) > 0.05:
			hip_bad.append(i)
		pose_log += "slot%d 脚底%.4f(Δ%+.4f) 髋%.4f(Δ%+.4f) | " % [i, feet, feet - GameRoom.FLOOR_Y,
			hip, hip - seat_y]
	print("  [实测] %s（地板 %.4f / 座面 %.4f）" % [pose_log, GameRoom.FLOOR_Y, GameRoom.FLOOR_Y + SEAT_H])
	_check(parts_bad.is_empty(),
		"手摆坐姿要动的分件都在（`leg-left` / `leg-right` / `root` / `torso` —— 这个包没有 `Skeleton3D`；缺的座位 %s）"
			% str(parts_bad))
	_check(feet_bad.is_empty(),
		"**三个人的脚底都落在 FLOOR_Y**（差 >0.05 的座位 %s）—— 手摆坐姿对不对的唯一硬判据" % str(feet_bad))
	_check(hip_bad.is_empty(),
		"**三个人的髋枢轴都落回座面**（= 腿分件节点原点，一期座面离地 %.2f；越界座位 %s）" % [SEAT_H, str(hip_bad)])

	# ④ 角色**不与桌子相交** —— 逐件、对桌子的**实体体积**（Task 1 重述过的口径，见文件头 ④）。
	#    **为什么必须逐件**：合并 AABB 的头尾把"脚下的 y"与"头顶的 y"并成一个盒子，
	#    于是"离桌子最近"变成"头（浮在桌面上方）的近侧边离底座多远" —— 那不是要求。
	#    **为什么必须带桌面那一层**：底座顶面到桌面上表面那一段也是实木；不带它，
	#    "从桌面上方捅进去"这种穿法量不出来。
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	# 桌面那一片：走 `table_3d.table_mesh` 这个成员（它没起过节点名 ⇒ 不能按名字找；
	# `layout_test` 量"桌面各位置亮度"用的也是它）。
	var tmat: MeshInstance3D = t3.get("table_mesh")
	_check(tbase != null and tbase.mesh != null and tmat != null and tmat.mesh != null,
		"（前提）桌子底座 `TableBase` 与桌面 `table_mesh` 都在（一期）")
	if tbase != null and tbase.mesh != null and tmat != null and tmat.mesh != null:
		var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
		var tma: AABB = tmat.global_transform * tmat.mesh.get_aabb()
		# 桌面那一层：桌面的足迹 × [底座顶面, 桌面上表面]
		var slab := AABB(Vector3(tma.position.x, tb.end.y, tma.position.z),
			Vector3(tma.size.x, tma.position.y - tb.end.y, tma.size.z))
		var hits := 0
		var worst := INF
		var p_log := ""
		for i in CHAR_SLOTS:
			for n in c[i].find_children("*", "GeometryInstance3D", true, false):
				var g := n as MeshInstance3D
				if g == null or g.mesh == null:
					continue
				var a: AABB = g.global_transform * g.mesh.get_aabb()
				var bad: bool = a.intersects(tb) or a.intersects(slab)
				if bad:
					hits += 1
				# 净空 = 与"底座 ∪ 桌面那一层"里更近那一块的分开距离（负 = 重叠）
				worst = minf(worst, maxf(_aabb_gap(a, tb), _aabb_gap(a, slab)))
				p_log += "slot%d/%s:%+.3f%s " % [i, g.name, maxf(_aabb_gap(a, tb), _aabb_gap(a, slab)),
					"∩" if bad else ""]
		print("  [实测] 逐件净空（与世界单位；正 = 分开、负 = 重叠）：%s" % p_log)
		_check(hits == 0,
			"**三个人都不与桌子相交**：逐件世界 AABB 与桌子实体体积（底座 x∈[%.3f, %.3f] y∈[%.3f, %.3f] + "
				% [tb.position.x, tb.end.x, tb.position.y, tb.end.y]
				+ "桌面那一层 y∈[%.3f, %.3f]）都不相交（相交 %d 件；最近那件还差 %+.3f 世界 = 真实 %.1f mm）"
				% [slab.position.y, slab.end.y, hits, worst, worst * 200.0])

	# ⑤ 三个人**两两不相交**（各自在自己椅子上 —— 相邻两把椅子的盒子不许碰）
	var pair_bad: Array = []
	var pair_log := ""
	for x in CHAR_SLOTS.size():
		for y in range(x + 1, CHAR_SLOTS.size()):
			var i: int = CHAR_SLOTS[x]
			var j: int = CHAR_SLOTS[y]
			var gp := _aabb_gap(ab[x], ab[y])
			if gp <= 0.0:
				pair_bad.append("%d-%d" % [i, j])
			pair_log += "%d-%d:%+.3f " % [i, j, gp]
	print("  [实测] 两两净空：%s" % pair_log)
	_check(pair_bad.is_empty(),
		"三个人**两两不相交**（世界 AABB 分开着；相交的对 %s）—— 每人只占自己那把椅子" % str(pair_bad))

	# ⑥ 材质：**不是 UNSHADED**（会被房间的灯照亮）、**底色只被压暗过**、**贴图还在**（普查 §7.2）
	#    包自带 `KHR_materials_unlit` ⇒ Godot 导成 `SHADING_MODE_UNSHADED`。
	#    ⚠ **逐面两条各守一半**：整片覆盖（`room.gd._paint()` 那一手）换上去的材质**自己就受光**、
	#      也**自己带贴图**（木地板的木纹）⇒ 单看 `shading_mode` / "有没有贴图"照样绿。
	#      ⇒ 必须比**"底色是不是自己那份压暗来的" + "贴图还是不是自己那张"**。
	var surfaces := 0
	var missing_m := 0
	var unshaded := 0
	var textured := 0
	var tex_own := 0
	var foreign := 0
	var mat_log := ""
	for i in CHAR_SLOTS:
		for n in c[i].find_children("*", "GeometryInstance3D", true, false):
			var gi := n as MeshInstance3D
			if gi == null or gi.mesh == null:
				continue
			for s in gi.mesh.get_surface_count():
				surfaces += 1
				var m := gi.get_active_material(s) as BaseMaterial3D
				var own := gi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null:
					missing_m += 1
					continue
				if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					unshaded += 1
				if m.albedo_texture != null:
					textured += 1
				# 底色只许是"自己那份 × 一个压暗系数"：三维都 ≤ 自己那份（**改成 >1 立刻红**）
				if own != null and (m.albedo_color.r > own.albedo_color.r + 0.001
						or m.albedo_color.g > own.albedo_color.g + 0.001
						or m.albedo_color.b > own.albedo_color.b + 0.001):
					foreign += 1
				# **贴图还是角色自己那张**（不是"有贴图就行"）
				if own != null and own.albedo_texture != null and m.albedo_texture == own.albedo_texture:
					tex_own += 1
				mat_log += "s%d/%s:shade%d,tex%s,albedo%s " % [i, gi.name, m.shading_mode,
					"有" if m.albedo_texture != null else "无", m.albedo_color]
	print("  [实测] 角色材质（%d 个面）：%s" % [surfaces, mat_log])
	_check(surfaces > 0 and missing_m == 0,
		"（前提）三个角色的每个面都有材质可量（%d 个面，取不到材质 %d 个）" % [surfaces, missing_m])
	_check(surfaces > 0 and unshaded == 0 and foreign == 0,
		"角色材质**不是 UNSHADED**、且**底色只被压暗过**（%d 个面：UNSHADED %d / 底色不是压暗 %d —— "
			% [surfaces, unshaded, foreign]
			+ "包自带 KHR_materials_unlit，不调就不响应一期的光照契约；整片覆盖会被贴图那条拦下）")
	_check(surfaces > 0 and tex_own == surfaces,
		"角色**贴图还在、而且是自己那张**（%d/%d 个面的贴图与模型自带的同一张；任意贴图 %d/%d —— "
			% [tex_own, surfaces, textured, surfaces]
			+ "照抄 room.gd 的整片覆盖会把脸 / 衣服换成房间的木地板，那样「有贴图」那一栏仍是有的、只有这条拦得住）")

	# ⑦ **角色不许是画面里最亮的东西**（Task 1 的 J1 判据；本任务起**取三人里最亮的那个**）
	#
	# 判据 = **同一把尺子**（同 `layout_test` 的照度代理式）× 同一把 albedo 尺子
	#（色调 ⊙ 贴图那一块的平均色）：三人里最亮的那笔必须 ≤ `CHAR_LIT_RATIO_MAX` × 桌面那笔。
	# albedo **从材质上读**（不读 `GameChars.CHAR_TINT`）—— 读常量等于把实现重述一遍。
	var lamp: OmniLight3D = t3.get("lamp_light")
	var wenv: WorldEnvironment = null
	for ch in t3.get_children():
		if ch is WorldEnvironment:
			wenv = ch
	var amb := 0.0
	if wenv != null:
		amb = wenv.environment.ambient_light_energy * wenv.environment.ambient_light_color.get_luminance()
	var cl: Array = []
	var max_idx := 0
	for x in CHAR_SLOTS.size():
		cl.append(_subtree_lit_albedo_lum(c[CHAR_SLOTS[x]]))
		if cl[x]["lum"] > cl[max_idx]["lum"]:
			max_idx = x
	var wm := (t3.wood_mesh as MeshInstance3D).material_override as StandardMaterial3D
	var wavg = _surf_tex_avg(t3.wood_mesh, 0, wm)
	var wood_lum := -1.0
	if wm != null and wavg != null:
		wood_lum = Color(wm.albedo_color.r * wavg.x, wm.albedo_color.g * wavg.y,
			wm.albedo_color.b * wavg.z).get_luminance()
	var corners := [
		t3.table_mesh.global_transform * Vector3(-t3.TABLE_SIZE.x * 0.5, 0.0, -t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(t3.TABLE_SIZE.x * 0.5, 0.0, -t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(-t3.TABLE_SIZE.x * 0.5, 0.0, t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(t3.TABLE_SIZE.x * 0.5, 0.0, t3.TABLE_SIZE.y * 0.5),
		Vector3(0.0, t3.table_mesh.global_position.y, 0.0),
	]
	var char_lit := -1.0
	var tab_lit := -1.0
	var lit_log := ""
	if lamp != null and wood_lum >= 0.0:
		for x in CHAR_SLOTS.size():
			var l: float = cl[x]["lum"] * _irradiance(lamp, ab[x].get_center(), amb)
			lit_log += "slot%d albedo%.3f×照度%.3f=%.4f | " % [CHAR_SLOTS[x], cl[x]["lum"],
				_irradiance(lamp, ab[x].get_center(), amb), l]
			char_lit = maxf(char_lit, l)
		for p in corners:
			tab_lit = maxf(tab_lit, wood_lum * _irradiance(lamp, p, amb))
	print("  [实测] %s木头外框有效 albedo 亮度 %.3f / 环境光那一份 %.4f" % [lit_log, wood_lum, amb])
	_check(lamp != null and cl[max_idx]["lum"] >= 0.0 and wood_lum >= 0.0,
		"（前提）三人的 albedo、木桌的 albedo、吊灯都量得到（最亮那件 %.3f / 木桌 %.3f / 灯 %s）"
			% [cl[max_idx]["lum"], wood_lum, "在" if lamp != null else "缺"])
	if lamp != null and char_lit >= 0.0 and tab_lit >= 0.0:
		var ratio: float = char_lit / maxf(tab_lit, 0.0001)
		_check(ratio <= CHAR_LIT_RATIO_MAX,
			"**角色不再是画面里最亮的东西**：三人里最亮那笔 albedo × 照度 %.4f ≤ %.2f × 桌面那一笔 %.4f"
				% [char_lit, CHAR_LIT_RATIO_MAX, tab_lit]
				+ "（实得比值 %.3f；把 `CHAR_TINT` 改回 (1,1,1) 这条立刻红）" % ratio)

	# ⑦-b **最坏座位 × 调色板里的每一个模型**（本任务新增 —— 上一段只量了"这一份座位序上"的三个人，
	#     而哪家坐哪把椅子由各家的**棋子色**决定 ⇒ 判据必须对**每一个色号**都成立，不能靠这一份
	#     座位序恰好把最亮的那件模型放在了别处而侥幸过线）。
	#     **为什么是 slot 3**：吊灯在 `LAMP_LIGHT_POS.x = -4.13`（桌子偏左上方）⇒ 左座吃到的照度
	#     最大（实测 1.339，右座 0.967 —— 差 1.385 倍）。Task 1 只有右座那一个人，取值是按右座留的
	#     余量；三个座位一起来，左座才是判据要守的那一个。
	if lamp != null and wood_lum >= 0.0 and tab_lit > 0.0:
		var sweep_bad: Array = []
		var sweep_log := ""
		for color in GameData.PLAYER_COLORS.size():
			var trial: Array = [{"peer": 2, "color": 1, "name": "乙"}]
			for k in CHAR_SLOTS.size():
				# 让**色号 color** 正好坐在最亮的 slot 3 上，另两个座位填别的色号（凑齐三个人）。
				var cc: int = (color + 1 + k) % GameData.PLAYER_COLORS.size() if k < 2 else color
				trial.append({"peer": 10 + cc, "color": cc, "name": "试%d" % cc})
			chars.set_chars(trial)
			await process_frame
			var ct := chars.get_node_or_null("Char%d" % CHAR_SLOTS[2]) as Node3D
			if ct == null:
				sweep_bad.append(color)
				continue
			var clum: float = _subtree_lit_albedo_lum(ct)["lum"]
			var lit: float = clum * _irradiance(lamp, _subtree_world_aabb(ct).get_center(), amb)
			var rr: float = lit / tab_lit
			sweep_log += "色%d→%s albedo%.3f×照度=%.4f(比值%.3f) | " % [color, chars.char_model(CHAR_SLOTS[2]),
				clum, lit, rr]
			if rr > CHAR_LIT_RATIO_MAX:
				sweep_bad.append(color)
		print("  [实测] 最坏座位（slot %d）× 全部色号：%s" % [CHAR_SLOTS[2], sweep_log])
		_check(sweep_bad.is_empty(),
			"**每一个色号的模型放在最亮的座位上也不亮过桌面**（越线的色号 %s —— 判据要按最坏座位收敛："
				% str(sweep_bad) + "吊灯挂在桌子偏左上方，实测左座照度是右座的 1.385 倍）")
		chars.set_chars(seats)      # 复位（下面 ⑨~⑪ 与末段读数要的仍是这一份座位序）
		await process_frame
		c = []
		for i in seats.size():
			c.append(chars.get_node_or_null("Char%d" % i) as Node3D)

	# ⑧ 影子：**不投影**（房间的纪律：全场唯一投影源是那盏吊灯）
	var casting := 0
	for i in CHAR_SLOTS:
		for n in c[i].find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casting += 1
	_check(casting == 0, "三个角色都不投影（违规 %d 个 —— 吊灯仍是全场唯一投影源）" % casting)

	# ⑨ **模型按棋子色选**（本轮新增）：喂进来的座位序里色号与座位号**处处不等** ⇒
	#    按椅子号取模型的话，slot 1 会拿到 `model_for_color(1)`（g）而不是期望的 **p** ⇒ 必红
	#    —— 调色板是 `k / g / n / p`（没有 `d`，那是上一个调色板的残留），slot 1 色号 3 ⇒ `p`。
	#    另外比一下**真正实例化出来那个节点的名字**（不只是自己记的那个字符串）。
	var model_bad: Array = []
	var mm_log := ""
	var peer_model := {}      # peer -> 模型（给 ⑩ 用）
	for i in CHAR_SLOTS:
		var color := int((seats[i] as Dictionary).get("color", 0))
		var want: String = GameChars.model_for_color(color)
		var got: String = chars.char_model(i)
		# 真正加载进来那个 GLB 的根节点名（`character-a.glb` → `character-a`）
		var inst_name := String((c[i].get_child(0) as Node).name) if c[i].get_child_count() > 0 else ""
		var ok: bool = got == want and got != GameChars.model_for_color(i) \
			and inst_name.begins_with(want.get_basename())
		if not ok:
			model_bad.append(i)
		peer_model[int((seats[i] as Dictionary).get("peer", 0))] = got
		mm_log += "slot%d(色%d)→%s（按座位号会是 %s）/实例节点 %s | " % [i, color, got,
			GameChars.model_for_color(i), inst_name]
	print("  [实测] 模型：%s" % mm_log)
	_check(model_bad.is_empty(),
		"**模型按各家的棋子色选**（=`CHAR_MODELS_BY_COLOR[color]`，而且**不是**按椅子号取；"
			+ "实例化出来的 GLB 根节点名也与之一致；不符的座位 %s）" % str(model_bad))
	_check(chars.char_peers() == [GameData.NO_PEER, 3, 4, 5],
		"`char_peers()` 逐槽位给出 peer（slot 0 = `NO_PEER`，那是「我」）：实得 %s" % str(chars.char_peers()))

	# ⑩ **同一个 peer 换椅子坐仍是同一张脸**：座位序轮转一格（三个人的椅子全换了）后逐家比对。
	#    这条是"重广播 / 重连 / 换轮次不许换脸"的可执行版。
	var before := peer_model.duplicate()
	chars.set_chars(_seats_rotated())
	await process_frame
	var swapped: Array = []
	var f_log := ""
	for i in CHAR_SLOTS:
		var p := int((_seats_rotated()[i] as Dictionary).get("peer", 0))
		var got2: String = chars.char_model(i)
		if got2 != String(before.get(p, "")):
			swapped.append(p)
		f_log += "peer %d 换到 slot%d：%s → %s | " % [p, i, before.get(p, "?"), got2]
	print("  [实测] %s" % f_log)
	_check(swapped.is_empty(),
		"**同一个 peer 换椅子坐仍是同一张脸**（轮转座位序后逐家比对；换脸的是 peer %s —— "
			% str(swapped) + "模型按棋子色定，所以与坐哪把椅子无关）")
	_check(chars.char_peers() == [GameData.NO_PEER, 5, 3, 4],
		"轮转后 `char_peers()` 跟着座位序走（实得 %s）—— 人与椅子一起换，不是只换椅子"
			% str(chars.char_peers()))

	# ⑪ **早退**（本轮新增）：同样的座位序再来一次 ⇒ **同一批节点实例**（不重建）。
	#    `_refresh_players()` 每次状态广播都调 `set_chars()` —— 少了早退，每次广播都要
	#    重新 load + 实例化 + 复制材质。**去掉早退这条立刻红**（拿到的是新节点）。
	chars.set_chars(_seats())
	await process_frame
	var again: Array = []
	for i in seats.size():
		again.append(chars.get_node_or_null("Char%d" % i) as Node3D)
	# 轮转那一次本来就会重建（指纹变了）⇒ 这里先确认"确实换过一批"，再确认"同样的序不再换"。
	chars.set_chars(_seats())
	await process_frame
	var same := true
	for i in CHAR_SLOTS:
		var now := chars.get_node_or_null("Char%d" % i) as Node3D
		# `is_same(a, b)` 是**全局函数**（Godot 4 起：比较是不是同一个实例），不是节点上的方法。
		if now == null or not is_same(now, again[i]):
			same = false
	_check(same,
		"**同样的座位序再来一次 = 同一批节点实例**（`set_chars` 的早退：每次广播都调它，"
			+ "少了早退就会把三个人整套重建 —— 那条注释里写的成本）")

	# ================= 二期 Task 3：待机循环 / 当前行动者 / 随取景淡出并停播 =================
	#
	# 节点在前面 ⑩ ⑪ 里重建过 ⇒ 这里重新取一遍（旧引用已 `queue_free`）。
	var t: Array = []
	for i in seats.size():
		t.append(chars.get_node_or_null("Char%d" % i) as Node3D)

	# ⑫ **待机真的在循环** —— 这是本任务最锋利的一个坑（普查 §三 实测细节 1）：
	#    glTF **没有循环标记**，导入器给 27 条动画**逐条**都是 `LOOP_NONE`
	#    ⇒「导入成功 ⇒ 会自动循环」是个**会静默出错的假设**（表现只是"人动一下就僵住"）。
	#    断言**从引擎里那份动画上读** `loop_mode`（不读实现里的常量 —— 读常量等于把实现重述一遍）。
	#
	#    ⚠ **动画名按字面核 `"idle"`，不读 `GameChars.IDLE_ANIM`**（本轮 fix round，终审 findings ③）：
	#    名字那一半原先读实现里的常量 ⇒ 把它改成 `"sit"` / `"walk"`（包里都存在、都闭环）之后
	#    **这条仍然全绿**，而"坐着的人在呼吸"这个**内容决定**就悄悄没了 —— 与 Task 4 那四条
	#    按字面名字核的断言（`"interact-right"` / `"holding-left"` / `"emote-no"` / `"die"`）同一类。
	#    `ACTOR_SPEED` / `FADE_*_T` 那几个是**阈值**（本身就是契约），读常量是对的，不算同类问题。
	var play_bad: Array = []
	var loop_bad: Array = []
	var anim_log := ""
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		var a: Animation = ap.get_animation("idle") if ap != null else null
		if ap == null or not ap.is_playing() or ap.current_animation != "idle":
			play_bad.append(i)
		if a == null or a.loop_mode != Animation.LOOP_LINEAR:
			loop_bad.append(i)
		anim_log += "slot%d 播%s/在播%s/循环%d 时长%.4f | " % [i,
			(ap.current_animation if ap != null else "无"),
			("是" if (ap != null and ap.is_playing()) else "否"),
			(a.loop_mode if a != null else -1), (a.length if a != null else -1.0)]
	print("  [实测] %s" % anim_log)
	_check(play_bad.is_empty(),
		"**三个人都在播 `idle`**（按**字面名字**核；没在播的座位 %s —— 待机是常驻的，"
			% str(play_bad) + "`_place` 里 `play()`。把 `IDLE_ANIM` 指到 `sit` / `walk` 这条立刻红）")
	_check(loop_bad.is_empty(),
		"**`idle` 真的被设成了 `LOOP_LINEAR`**（没设上的座位 %s —— glTF 没有循环标记，"
			% str(loop_bad)
			+ "导入器给的是 `LOOP_NONE`；不自己设的话 1.3333 s 之后三个人齐刷刷僵在末帧、"
			+ "**而日志里一个字都不说**。把 `_loop_idle` 里那句设回 `LOOP_NONE` 这条立刻红；"
			+ "把 `IDLE_ANIM` 指到别的动画（循环标记就设到那条上去了）这条也红）")

	# ⑬ **真的在动**（"两帧比对" —— **只有一帧相同不能证明它在动，也不能证明它没在动**）。
	#    口径：把同一个分件（`head`，`idle` 动的 4 条轨道之一）在**两个动画相位**上各量一次
	#    世界位置，必须不同。用 `seek()` 而不是 `await` 若干帧：**相位是钉死的**
	#    （headless 下每帧的真实 delta 只有零点几毫秒，靠等帧量出来的位移会随机器而变 ⇒ 假红）。
	var still_bad: Array = []
	var move_log := ""
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		var head := t[i].find_child("head", true, false) as Node3D
		if ap == null or head == null:
			still_bad.append(i)
			continue
		ap.seek(0.0, true)
		await process_frame
		var p0: Vector3 = head.global_position
		ap.seek(0.4, true)
		await process_frame
		var p1: Vector3 = head.global_position
		var d: float = p0.distance_to(p1)
		if d <= 0.01:
			still_bad.append(i)
		move_log += "slot%d head 相位0.0→0.4 位移 %.4f 世界 | " % [i, d]
	print("  [实测] %s" % move_log)
	_check(still_bad.is_empty(),
		"**待机真的在动**（同一分件在两个动画相位上的世界位置必须不同；没动的座位 %s —— "
			% str(still_bad) + "只拍一帧既证明不了它在动、也证明不了它没在动）")

	# ⑭ **随取景淡出并停播**（走**真接口** `snap_dolly` / `snap_view`，不直调 `set_fade`）：
	#    判据按**取景档**，不按"是否落在视口内"—— 角色在 3D 端**恒在画内**（哪怕被画面边缘
	#    切掉一半）⇒ 视口判据永远为真、等于没判（spec §5.3 的前提已被 Task 1 出图更正）。
	#    **性能那一半**：读棋盘那几档 `is_playing() == false`（逐帧动画求值归零）+ 外套节点
	#    `visible = false`（三个角色的绘制调用一并省掉）—— 二期不许把主玩法档拖慢（spec §六）。
	var frames := 4
	var fade_log := ""

	# (a) 拉远端：**在、在播**
	t3.snap_view(0.0)
	t3.snap_dolly(t3.DOLLY_MAX)
	for k in frames:
		await process_frame
	var far_bad: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		var tr_hi := _max_transparency(t[i])
		if t[i] == null or not t[i].visible or tr_hi > 0.001 or ap == null or not ap.is_playing():
			far_bad.append(i)
		fade_log += "拉远端 slot%d 可见%s/透明度%.2f/在播%s | " % [i, ("是" if t[i].visible else "否"),
			tr_hi, ("是" if (ap != null and ap.is_playing()) else "否")]
	_check(far_bad.is_empty(),
		"**拉远端（看屋子那一档）角色还在、且在播**（不对的座位 %s）" % str(far_bad))

	# (b) 推近端（`DOLLY_MIN` = 0.7，"读棋盘"那一档）：**全隐 + 停播**
	t3.snap_dolly(t3.DOLLY_MIN)
	for k in frames:
		await process_frame
	var near_bad: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		if t[i].visible or ap == null or ap.is_playing():
			near_bad.append(i)
		fade_log += "推近端 slot%d 可见%s/在播%s | " % [i, ("是" if t[i].visible else "否"),
			("是" if (ap != null and ap.is_playing()) else "否")]
	_check(near_bad.is_empty(),
		"**推近端（读棋盘那一档）角色已淡出并停播**（不对的座位 %s —— "
			% str(near_bad) + "把 `_apply_fade` 里的 `ap.stop()` 去掉、或不隐藏外套节点，这条立刻红）")

	# (c) 2D 端（`view_t = 1`，也是读棋盘那一档）：**全隐 + 停播**
	t3.snap_dolly(1.0)
	t3.snap_view(1.0)
	for k in frames:
		await process_frame
	var v2d_bad: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		if t[i].visible or ap == null or ap.is_playing():
			v2d_bad.append(i)
		fade_log += "2D端 slot%d 可见%s/在播%s | " % [i, ("是" if t[i].visible else "否"),
			("是" if (ap != null and ap.is_playing()) else "否")]
	_check(v2d_bad.is_empty(),
		"**2D 端（读棋盘那一档）角色已淡出并停播**（不对的座位 %s）" % str(v2d_bad))

	# (d) 推回 3D 默认档：**又活过来**（淡出是可逆的，不是一次性的）
	t3.snap_view(0.0)
	t3.snap_dolly(1.0)
	for k in frames:
		await process_frame
	var back_bad: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		if not t[i].visible or ap == null or not ap.is_playing():
			back_bad.append(i)
	_check(back_bad.is_empty(),
		"**推回默认档（1.0）角色又回来、又在播**（不对的座位 %s —— 淡出必须可逆）" % str(back_bad))
	print("  [实测] 取景停播四档：%s（推拉 %.2f→%.2f / 视角 0.0→1.0→0.0）"
		% [fade_log, t3.DOLLY_MAX, t3.DOLLY_MIN])

	# ⑮ **`set_fade(t)` 的契约**（直接调接口，同步断言 —— 中间不 `await`，免得 `_process` 又把它按
	#    当前取景覆写回去）。四个阈值点：`0.0` / `FADE_SOLID_T` / `FADE_GONE_T` / `1.0`。
	var c0: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		c0.append(ap != null and ap.is_playing() and t[i].visible)
	chars.set_fade(GameChars.FADE_SOLID_T)
	var c_solid: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		c_solid.append(ap != null and ap.is_playing() and t[i].visible)
	chars.set_fade(GameChars.FADE_GONE_T)
	var c_gone: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		c_gone.append(ap != null and not ap.is_playing() and not t[i].visible \
			and _max_transparency(t[i]) >= 1.0)
	chars.set_fade(1.0)
	var c1: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		c1.append(ap != null and not ap.is_playing() and not t[i].visible)
	chars.set_fade(0.0)   # 复位（后面几段还要读）
	var c_back: Array = []
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		c_back.append(ap != null and ap.is_playing() and t[i].visible and _max_transparency(t[i]) <= 0.001)
	_check(c0.all(func(x): return x) and c_solid.all(func(x): return x),
		"`set_fade(t<=%.2f)` ⇒ **全亮 + 在播**（t=0 全亮 %s / t=%.2f 全亮 %s）"
			% [GameChars.FADE_SOLID_T, str(c0), GameChars.FADE_SOLID_T, str(c_solid)])
	_check(c_gone.all(func(x): return x) and c1.all(func(x): return x),
		"`set_fade(t>=%.2f)` ⇒ **全隐（透明度 1.0）+ 停播**（t=%.2f %s / t=1.0 %s）"
			% [GameChars.FADE_GONE_T, GameChars.FADE_GONE_T, str(c_gone), str(c1)])
	_check(c_back.all(func(x): return x),
		"`set_fade(0.0)` 之后**又全亮 + 在播**（淡出可逆，实得 %s）" % str(c_back))

	# ⑯ **`FADE_NEAR_DOLLY` 与一期的 `DOLLY_MIN` 是同一个数**（不静态引用、但也不许悄悄漂开）。
	_check(is_equal_approx(GameChars.FADE_NEAR_DOLLY, t3.DOLLY_MIN),
		"淡出用的「推拉近端」与一期的 `DOLLY_MIN` 是同一个数（`GameChars.FADE_NEAR_DOLLY=%.2f` "
			% GameChars.FADE_NEAR_DOLLY
			+ "vs `TableView3D.DOLLY_MIN=%.2f` —— 两边各写一份是为了不形成类名环，"
			% t3.DOLLY_MIN + "但那两份必须相等：哪天一期的档位改了、这里没跟，就是「该淡的那一档不淡」）")

	# ⑰ **当前行动者**（"轮到我了"）：包里没有第二条持续型动画（`walk`/`sprint` 是位移动作）
	#    ⇒ 只能靠**同一条 `idle` 提速**表达（普查 §5.4）。座位序里 slot1/2/3 = peer 3/4/5。
	var actor_peer := int((seats[CHAR_SLOTS[0]] as Dictionary).get("peer", 0))
	chars.set_actor(actor_peer)
	var sp: Array = []
	for i in CHAR_SLOTS:
		sp.append(chars.char_speed(i))
	var others: Array = [sp[1], sp[2]]
	_check(actor_peer == chars.actor_peer() and sp[0] >= others[0] + 0.2 and sp[0] >= others[1] + 0.2
			and sp[0] > GameChars.IDLE_SPEED,
		"**行动者的 `idle` 明显比其他人快**（行动者 peer %d 在 slot%d：速度 %.2f vs 其余 %.2f / %.2f；"
			% [actor_peer, CHAR_SLOTS[0], sp[0], others[0], others[1]]
			+ "把 `set_actor` 变成空函数这条立刻红）")
	# 换成另一个行动者：**上一个必须降回来**（不能只往上加）
	chars.set_actor(int((seats[CHAR_SLOTS[1]] as Dictionary).get("peer", 0)))
	var sp2: Array = []
	for i in CHAR_SLOTS:
		sp2.append(chars.char_speed(i))
	_check(sp2[1] > sp2[0] + 0.2 and sp2[1] > sp2[2] + 0.2 and sp2[0] <= GameChars.IDLE_SPEED + 0.001,
		"换一个行动者之后**上一个降回基准速**（实得 slot1 %.2f / slot2 %.2f / slot3 %.2f —— "
			% [sp2[0], sp2[1], sp2[2]] + "只在「谁快」上做加法、不把旧的降回来，这条会红）")
	chars.set_actor(GameData.NO_PEER)
	var sp3: Array = []
	for i in CHAR_SLOTS:
		sp3.append(chars.char_speed(i))
	_check(sp3.all(func(x): return x <= GameChars.IDLE_SPEED + 0.001),
		"没有行动者时**三个人都回到基准速**（实得 %s）" % str(sp3))

	# ================= 二期 Task 4：四个玩法事件的反应 =================
	#
	# **断言按动画名的字面值核**（**不读** `GameChars.REACT_ANIMS` —— 读那张表等于把实现重述一遍，
	# 改个名字永远绿）：名字写错 / 编一条不存在的都该红。四条名字全部是普查**实测存在**的
	#（普查 §三 的 27 条清单 + §5.4 建议表）：
	#   出牌 `interact-right` / 付钱 `holding-left` / 被抢地 `emote-no` / 破产 `die`。
	# 此时座位序仍是 `_seats()`：slot1=peer3（色3）/ slot2=peer4（色0）/ slot3=peer5（色2）。
	print("== 二期 Task 4：四个事件的反应（四个名字全部实测）==")

	# (a) 出牌 → `interact-right`（0.6667 s，幅度与时长都够、首尾闭合）
	chars.react(3, "play")
	await process_frame
	var ra1: AnimationPlayer = chars.char_player(1)
	_check(ra1 != null and ra1.current_animation == "interact-right",
		"**出牌 → `interact-right`**（实得 \"%s\" —— 名字写错 / 换一条不存在的，这条立刻红）"
			% (ra1.current_animation if ra1 != null else "<没有播放器>"))

	# (b) 付钱 → `holding-left`（0.1667 s，与既有**飞钞**演出同一拍）
	chars.react(4, "pay")
	await process_frame
	var ra2: AnimationPlayer = chars.char_player(2)
	_check(ra2 != null and ra2.current_animation == "holding-left",
		"**付钱 → `holding-left`**（实得 \"%s\" —— 与飞钞同拍；⚠ 换成 `pick-up` 会红："
			% (ra2.current_animation if ra2 != null else "<没有播放器>")
			+ "那一条**不闭合**、结束在弯腰姿态，是包里唯二不闭合的两条之一）")

	# (c) 被抢地 → `emote-no`（0.6667 s。**包里没有"后仰 / 拍桌"** ⇒ 摇头是可读的"不"）
	chars.react(5, "rob")
	await process_frame
	var ra3: AnimationPlayer = chars.char_player(3)
	_check(ra3 != null and ra3.current_animation == "emote-no",
		"**被抢地 → `emote-no`**（实得 \"%s\"）"
			% (ra3.current_animation if ra3 != null else "<没有播放器>"))

	# (c2) **三条小动作的姿态也不许插进桌子**（判据 ③ 的口径，逐件量）—— 它们动的都是手臂 / 头
	#      （躯干与腿不动），理论上够不到桌沿；但"理论上"不算数，量一次（人已经坐在桌前 23 cm 处）。
	var hit_log := ""
	var hit_slots: Array = []
	for i in CHAR_SLOTS:
		var dpi: Dictionary = _death_pose(t[i], t3)
		hit_log += "slot%d 相交%d 件(净空%+.3f) | " % [i, int(dpi.hits), float(dpi.worst)]
		if int(dpi.hits) > 0 or float(dpi.low) < GameRoom.FLOOR_Y - 0.001:
			hit_slots.append(i)
	print("  [实测] 反应姿态：%s" % hit_log)
	_check(hit_slots.is_empty(),
		"出牌 / 付钱 / 被抢地**三条动作也不与桌子实体体积相交、不掉到地板以下**（越界座位 %s）"
			% str(hit_slots))

	# (d) **幅度含蓄**：反应**不许动 `speed_scale`**（那是「当前行动者」的表达，`set_actor` 独占）。
	#     "放大一点看得清"正是要拦住的那一手 —— 本作调性克制，四家同时动要变马戏团。
	chars.set_actor(3)                       # 行动者 = slot1（peer 3）：速度 1.4
	var ra_sp: float = chars.char_speed(1)
	chars.react(3, "play")
	_check(is_equal_approx(chars.char_speed(1), ra_sp) and is_equal_approx(ra_sp, GameChars.ACTOR_SPEED),
		"**反应不动 `speed_scale`**（幅度含蓄 —— 行动者档 %.2f，实得 %.2f → %.2f；"
			% [GameChars.ACTOR_SPEED, ra_sp, chars.char_speed(1)]
			+ "「顺手放大一点」这条立刻红）")

	# (e) 三条一次性小动作**播完自己走回待机** —— 不回来的话人僵在末帧、再也不呼吸
	#    （0.6667 s，speed 1.4 ⇒ ≈0.48 s；等 1.2 s 足够，且不是"看一眼就算"）
	await create_timer(1.2).timeout
	var rae: AnimationPlayer = chars.char_player(1)
	_check(rae != null and rae.current_animation == GameChars.IDLE_ANIM and rae.is_playing(),
		"一次性动作播完**自己走回待机**（实得 \"%s\"/在播 %s —— 不回来人僵在末帧、再也不呼吸）"
			% [(rae.current_animation if rae != null else "<没有播放器>"),
				("是" if (rae != null and rae.is_playing()) else "否")])
	chars.set_actor(GameData.NO_PEER)

	# (f) 破产 → `die` + **停在末帧**。
	#     ⚠ **名字要读 `assigned_animation`**：实测 Godot 4.6 里 `current_animation` 在
	#     "暂停 / 播完停下"两种状态下都会被清成 `""`（`assigned_animation` 留得住）——
	#     拿 `current_animation` 核这条**必然假红**（第一版就是这么红的，探针量出来的）。
	#     两条一起核：① 名字对；② **真的停在末帧**（位置 ≈ 时长、已不在播）—— 只核名字的话，
	#     `play()` 之后直接 `pause()`（停在第 0 帧、还是坐姿）照样绿。
	var ra_top0: float = _subtree_world_aabb(t[2]).end.y    # 待机时的最高点（下面 f3 的参照）
	chars.react(4, "die")
	await process_frame
	var ra4: AnimationPlayer = chars.char_player(2)
	var ra4_a: Animation = null
	if ra4 != null:
		ra4_a = ra4.get_animation("die")
	var ra4_len: float = ra4_a.length if ra4_a != null else -1.0
	var ra4_pos: float = ra4.current_animation_position if ra4 != null else -1.0
	_check(ra4 != null and ra4.assigned_animation == "die" and ra4_a != null \
			and absf(ra4_pos - ra4_len) <= 0.001 and not ra4.is_playing(),
		"**破产 → `die`，并停在末帧**（实得 assigned=\"%s\" 在播 %s 位置 %.4f / 时长 %.4f —— "
			% [(ra4.assigned_animation if ra4 != null else "<没有播放器>"),
				("是" if (ra4 != null and ra4.is_playing()) else "否"), ra4_pos, ra4_len]
			+ "⚠ `play()` 之后直接 `pause()` 停在的是**第 0 帧**，必须先 `seek(时长)`）")

	# (f2) **破产的人留在座位上、看得见、不穿模** —— spec §九④ 定案的那一条
	#（"留在座位上"，明确否掉"消失：消失等于这家没了"）。
	# ⚠ **这一条正是简报那条"`die` 的末帧正是趴着"不成立的地方**（实测）：`die` 的末帧把
	# **整个人绕脚底转 −90°**（站着的人 = 倒在地上），可我们的人是**坐着**的 ⇒ 末帧实测：
	# 头落到 **y = −4.12**（地板 −3.70 以下）、躯干躺到 **z ∈ [−12.5, −5.2]**（椅子后面 1.5 m，
	# **远墙在 z = −9**）⇒ 出图看就是**对面那把椅子空了**。`chars.gd` 因此摘掉了那一条轨、
	# 改用手摆的**座位收势**（`_slump`，角度顶在"不与桌子实体体积相交"的几何上限附近）。
	# 这三条钉的就是"摘对了吗"：人还在锚点上 / 头在桌面上方 / 没有分件落地板以下或插进桌子。
	# **变红口子**：把 `_pose_die` 里那句 `_die_without_fall(ap)` 去掉（退回整体倒地），这三条一起红。
	var dp: Dictionary = _death_pose(t[2], t3)
	var an2: Transform3D = room.seat_anchor(2)
	var off: Vector2 = Vector2(t[2].global_position.x - an2.origin.x,
		t[2].global_position.z - an2.origin.z)
	_check(off.length() <= 0.001,
		"破产那家**还在自己那把座位上**（世界 xz 与 `seat_anchor(2)` 的偏差 %.4f —— "
			% off.length() + "倒地那一条会把整个人搬到椅子后面 1.5 m 去，这条立刻红）")
	_check(float(dp.head_y) > 0.0,
		"破产那家的头**在桌面上方（看得见）**（头 y=%.3f vs 桌面 y=0.000 —— 退回整体倒地时它是 −4.12）"
			% float(dp.head_y))
	_check(float(dp.low) >= GameRoom.FLOOR_Y - 0.001,
		"破产那家**没有落到地板以下**（最低分件 y=%.3f vs 地板 %.2f）" % [float(dp.low), GameRoom.FLOOR_Y])
	_check(int(dp.hits) == 0,
		"破产那家**不插进桌子的实体体积**（逐件、与判据 ③ 同一口径：相交 %d 件，最近净空 %+.3f 世界）"
			% [int(dp.hits), float(dp.worst)])
	# (f3) **`die` 自己的内容真的落在身上**：这条动画的收势是"举双手"（实测世界最高点由**手臂**
	#      撑着），与待机（最高点是头）不同 ⇒ 最高点必须抬起来。只核名字的话，
	#      "play 了 die 但一条轨都没生效"照样绿。
	_check(float(dp.top) > ra_top0 + 0.5,
		"**`die` 自己的动作真的落在身上**（世界最高点：待机 %.3f → 破产 %.3f，抬了 %.3f 世界 = %.0f cm"
			% [ra_top0, float(dp.top), float(dp.top) - ra_top0, (float(dp.top) - ra_top0) * 200.0]
			+ " —— `die` 里手臂转 180°（举双手），那是它自己的内容，不是我们摆的）")
	_check(chars.char_dead(2),
		"破产**被记住了**（`char_dead` —— 不记住的话，一次淡出往返 / 一次重建就把他**复活**了）")

	# 停住的那一帧**不许再往前跑**（真等一小段真实时间再量一次）：只比"位置==时长"的话，
	# 一条**没 pause、自己播完停在末帧**的实现也是绿 —— 这条把"停"这件事本身钉住。
	await create_timer(0.3).timeout
	var ra4_pos2: float = ra4.current_animation_position if ra4 != null else -1.0
	_check(ra4 != null and is_equal_approx(ra4_pos2, ra4_pos),
		"破产那家**定在末帧不动**（0.3 s 之后位置 %.4f，与刚播完时 %.4f 相同）" % [ra4_pos2, ra4_pos])

	# (g) **淡出往返之后仍然是"留在座位上"的那一副**（这是最容易漏的那一半：
	#     `_apply_fade` 从淡出档回来时会 `play(idle)`、`set_chars` 重建也会把人摆成待机）
	chars.set_fade(1.0)
	chars.set_fade(0.0)
	await process_frame
	var rag: AnimationPlayer = chars.char_player(2)
	var rag_pos: float = rag.current_animation_position if rag != null else -1.0
	var dpg: Dictionary = _death_pose(t[2], t3)
	_check(chars.char_dead(2) and rag != null and rag.assigned_animation == "die" \
			and absf(rag_pos - ra4_len) <= 0.001,
		"破产那家**一次淡出往返之后仍停在 die 末帧**（实得 assigned=\"%s\" 位置 %.4f / 时长 %.4f）"
			% [(rag.assigned_animation if rag != null else "<没有播放器>"), rag_pos, ra4_len])
	_check(float(dpg.top) > ra_top0 + 0.5 and int(dpg.hits) == 0 and float(dpg.low) >= GameRoom.FLOOR_Y - 0.001,
		"淡出往返之后**姿态也摆回来了**（最高点 %.3f vs 待机的 %.3f / 相交 %d 件 / 最低 %.3f —— "
			% [float(dpg.top), ra_top0, int(dpg.hits), float(dpg.low)]
			+ "只记住「名字」不够：`stop()` 会把姿态一起丢掉）")

	# (h) 已经破产的那家**不再做别的动作**（破产是终局表现，不能被后来的付钱 / 摇头顶掉）
	chars.react(4, "pay")
	await process_frame
	var rah: AnimationPlayer = chars.char_player(2)
	var rah_pos: float = rah.current_animation_position if rah != null else -1.0
	_check(rah != null and rah.assigned_animation == "die" and absf(rah_pos - ra4_len) <= 0.001,
		"已经破产的那家**不再做别的动作**（实得 assigned=\"%s\" 位置 %.4f —— 破产是终局表现）"
			% [(rah.assigned_animation if rah != null else "<没有播放器>"), rah_pos])

	# ================= 本轮 fix round：淡出档上的反应（终审 findings ①） =================
	#
	# **要钉住的契约**：读棋盘那一档（推近端 / 2D 端）的"停播"是**真停播** —— 事件在那一档到来时，
	# 反应必须被**丢掉**（不排队、不补播），不许把一个 `visible = false` 的播放器重新点着。
	# ⚠ **⑭(b)(c) 抓不到它**：那两条在"淡出"与"断言"之间**什么事都没发生**（这正是终审发现它的原因）。
	# ⇒ 这里补上"淡出**之后**再来一次事件"这一手：**三条一次性小动作**逐个断言"人仍全隐、
	#   播放器仍未在播"，等过最长那条的标称时长（`interact-right` / `emote-no` = 0.6667 s）再复核一次；
	#   **破产那一条单独再打一次**（它走的是另一支："停末帧 + 记进 `_dead_peers`"）。
	# **变红口子**：把 `react()` 开头那句 `if _faded_out(): return` 去掉 —— 前半段当场红
	#（`play()` 立刻把 `is_playing()` 翻成真，而 `set_fade` 在 `t` 没变时早退 ⇒ **再没人来停它**），
	# 后半段也红（0.17~0.67 s 后 `_react_finished` 把它接到 **`LOOP_LINEAR` 的 `idle`** 上 ⇒ 一直播下去），
	# 破产那一条则表现为"破产记忆被种下"（`char_dead` 翻真）。
	# ⚠ **为什么三条在前、`die` 单独放最后**：`die` 会**停在末帧**（`pause()`）—— 若把它排在三条中间，
	# 它的 `pause()` 会把"后面还播着"的证据一起盖掉（第一版就是这么写的，红线验证当场发现它盖住了
	# 后半段的变红口子 ⇒ 现在拆开打）。
	# **为什么走取景真接口、而不是直接 `set_fade()`**：`_process` 每帧都按当前取景覆写 `_fade_t`
	# ⇒ 只有把取景真的推到 2D 端，这一档才**稳得住**（⑮ 那种"不 `await` 的直接调用"撑不过一次等帧）。
	# **为什么用 slot 1（peer 3）**：它是这一档里唯一还没破产的那个（slot 2 的 peer 4 在 (f) 已趴下；
	# 破产那家单独走 `_apply_fade` 的趴着那一支）。
	print("== 本轮 fix round：淡出档上的反应一律丢掉（不排队）==")
	t3.snap_dolly(1.0)
	t3.snap_view(1.0)
	for k in frames:
		await process_frame
	var fr_bad: Array = []
	var fr_log := ""
	var fr_peer := int((seats[CHAR_SLOTS[0]] as Dictionary).get("peer", 0))
	for kind in ["play", "pay", "rob"]:
		chars.react(fr_peer, kind)
		await process_frame
		var ap: AnimationPlayer = chars.char_player(CHAR_SLOTS[0])
		var vis: bool = t[CHAR_SLOTS[0]].visible
		var playing: bool = ap != null and ap.is_playing()
		if vis or playing:
			fr_bad.append(kind)
		fr_log += "%s⇒可见%s/在播%s | " % [kind, ("是" if vis else "否"), ("是" if playing else "否")]
	print("  [实测] 淡出档上三条一次性事件（peer %d / slot %d）：%s" % [fr_peer, CHAR_SLOTS[0], fr_log])
	_check(fr_bad.is_empty(),
		"**淡到「全隐 + 停播」之后，事件一律被丢掉（不排队）**（人仍全隐、播放器仍未在播；漏掉的 kind %s —— "
			% str(fr_bad) + "去掉 `react()` 的早退，`play()` 会在一个 `visible = false` 的节点上重新开播）")
	# 等过最长那条的标称时长（0.6667 s；speed 1.0）再复核一次：**「没被点着」要经得起时间**
	#（前半段只证明"那一刻没被点着"；这一半证明"之后也没有自己播起来"）。
	await create_timer(1.0).timeout
	var fr2_bad: Array = []
	for i in CHAR_SLOTS:
		var ap2: AnimationPlayer = chars.char_player(i)
		if t[i].visible or (ap2 != null and ap2.is_playing()):
			fr2_bad.append(i)
	_check(fr2_bad.is_empty(),
		"反应名义时长过去之后**仍然是全隐 + 停播**（不听话的座位 %s —— 这一半钉住的是那条回位链："
			% str(fr2_bad) + "被点着一次之后，`_react_finished` 会把它接到循环的 `idle` 上，再也没人停它）")
	# 破产那一条**单独再打一次**（见上："停末帧 + 记住"是另一支）⇒ 除了"仍全隐 / 仍未在播"，
	# 再钉一条**「连破产记忆都没被种下」**：它同样必须先过那道早退。
	chars.react(fr_peer, "die")
	await process_frame
	var apd: AnimationPlayer = chars.char_player(CHAR_SLOTS[0])
	var die_hidden: bool = not t[CHAR_SLOTS[0]].visible
	var die_stopped: bool = apd == null or not apd.is_playing()
	var die_unmemorized: bool = not chars.char_dead(CHAR_SLOTS[0])
	_check(die_hidden and die_stopped and die_unmemorized,
		"**破产那一条在淡出档同样被丢掉**（仍全隐 %s / 仍未在播 %s / 破产记忆未种下 %s —— "
			% [("是" if die_hidden else "否"), ("是" if die_stopped else "否"),
				("是" if die_unmemorized else "否")]
			+ "`die` 这一支是「停末帧 + 记住」，所以除了停播，还要钉住「记忆没被种下」）")
	# 复位取景（后面的原始读数与收尾按默认档走）
	t3.snap_view(0.0)
	t3.snap_dolly(1.0)
	for k in frames:
		await process_frame

	# 供报告的原始读数。⚠ 节点在 ⑩ ⑪ 里**重建过**（那两条本来就要换一批实例）⇒ 这里重新取一遍，
	# 别用早先那批引用（旧引用已经 `queue_free` 了，读它会报 `previously freed`）。
	for i in CHAR_SLOTS:
		var cc := chars.get_node_or_null("Char%d" % i) as Node3D
		var aa := _subtree_world_aabb(cc)
		var leg := cc.find_child("leg-left", true, false) as Node3D
		print("  [实测] slot%d 模型 %s / 世界 AABB %s..%s（尺寸 %s）/ 腿 scale %s"
			% [i, chars.char_model(i), aa.position, aa.end, aa.size,
				leg.scale if leg != null else Vector3.ZERO])

	if fails == 0:
		print("CHARS TEST: PASS")
		quit(0)
	else:
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1)
