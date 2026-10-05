extends SceneTree
## 二期 Task 1：角色接入 + 手摆坐姿（**一个人坐对 —— slot 1**）
## godot --headless --path . --script tests/chars_test.gd
##
## 判据四条（brief Step 1）：
##   ① `slot 1` 坐着一个人、`slot 0`（近侧 = 「我」，相机就在那儿）**一个人都没有**；
##   ② **脚底落在 `FLOOR_Y`**（容差 ≤0.05 —— **手摆坐姿对不对的唯一硬判据**）；
##   ③ 角色 AABB **不与桌子相交**（`TableBase` 的足迹）；
##   ④ 角色材质**不是 `SHADING_MODE_UNSHADED`**、**贴图还在**（普查 §7.2：包自带
##      `KHR_materials_unlit`，照抄 `room.gd` 的整片覆盖会**抹掉贴图**）。
##
## 坐姿不是包里的 `sit`（腿是一整块刚体、无膝关节，`sit` 把腿平举 ⇒ 会捅进桌子 1.66 世界），
## 是**手摆**（普查 §5.2）：整体下移 `SEAT_ROOT_Y` + 腿竖直压到 `LEG_SQUASH`
## ⇒ 脚底回到地面、髋回到座面。下移**放在角色之上的外套节点**上（`idle` 有一条 `root`
## 常值轨道，一播就把 `root.position.y` 顶回 0）。

var fails := 0

## 本任务只放**一个人**：1 号座位（右侧）。
const CHAR_SLOT := 1
## 「我」的座位：0 号 = 近侧 = 相机这一侧 ⇒ **不渲染**（spec §5.1）。
const MY_SLOT := 0
## 一期椅子座面离地（`room.gd` 的比例表：座面 = `FLOOR_Y + 2.25` = 真实 0.45 m 座高）。
## **不是**本文件的实现常量 —— 它是房间那边的既有事实，这里拿它当坐姿的外尺。
const SEAT_H := 2.25

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

func _run() -> void:
	root.size = Vector2i(1280, 800)
	# 用运行时 load() 取 TableView3D（同 layout_test / hud_test）：`--script` 入口的静态依赖链
	# 在 autoload 注册之前编译，静态写类名会把 game/BoardView 那条链（依赖 `Fx`）拽进来。
	var t3 = load("res://scripts/table_3d.gd").new()
	root.add_child(t3)
	await process_frame
	await process_frame

	print("== 二期 Task 1：角色层（一个人坐在 1 号座位）==")
	var room: Node = t3.get_node_or_null("Room")
	_check(room != null, "房间在（一期：ROOM_ENABLED 的那一层）")
	var chars: Node = room.get_node_or_null("Chars") if room != null else null
	# 契约：`CHARS_ENABLED` 为 true 时角色层在；置 false 时**一个节点都不留**（Step 5.1 的变红口子）。
	_check(chars != null == GameChars.CHARS_ENABLED,
		"CHARS_ENABLED=%s 时角色层%s存在" % [GameChars.CHARS_ENABLED, "" if chars != null else "不"])
	if chars == null:
		_check(false, "角色层缺了（CHARS_ENABLED=false 时这是对的）⇒ 下面整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return

	var c1: Node3D = chars.get_node_or_null("Char%d" % CHAR_SLOT) as Node3D
	var c0: Node3D = chars.get_node_or_null("Char%d" % MY_SLOT) as Node3D
	# ①-前半：1 号座位上有人
	_check(c1 != null, "slot %d（右侧那把椅子）坐着一个人" % CHAR_SLOT)
	_check(c0 == null,
		"slot %d（近侧 =「我」）**一个人都没有** —— 相机就在那儿（spec §5.1）" % MY_SLOT)
	if c1 == null:
		_check(false, "1 号座位上没人 ⇒ 坐姿那几条整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return

	# ---- 坐在**那把椅子**上（位置 + 朝向都读一期留的 `seat_anchor(slot)`）----
	var an: Transform3D = room.seat_anchor(CHAR_SLOT)
	var cp: Vector3 = c1.global_position
	_check(absf(cp.x - an.origin.x) < 0.001 and absf(cp.z - an.origin.z) < 0.001,
		"人就站在 slot %d 的座位锚点上（实得 xz=(%.3f, %.3f) / 锚点 (%.3f, %.3f) —— 座位坐标全部来自一期接口，不另算）"
			% [CHAR_SLOT, cp.x, cp.z, an.origin.x, an.origin.z])
	# 朝向：角色正面 = `+Z`（普查 §4.3 实测）⇒ 与椅子一样朝桌心，**不用补 180°**。
	var to_center := Vector3(-an.origin.x, 0.0, -an.origin.z).normalized()
	var facing: Vector3 = (c1.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_check(facing.dot(to_center) > 0.95,
		"人面朝桌心（正面 %s · 指向桌心 %s = %.3f > 0.95 —— 正面 = `+Z`，与 `seat_anchor` 天然对齐）"
			% [facing, to_center, facing.dot(to_center)])

	# ---- 手摆坐姿：脚底落地面、髋落座面（分件节点先核对在不在）----
	var leg_l := c1.find_child("leg-left", true, false) as Node3D
	var leg_r := c1.find_child("leg-right", true, false) as Node3D
	_check(leg_l != null and leg_r != null,
		"分件 `leg-left` / `leg-right` 在（手摆坐姿要压的就是它们；这个包没有 `Skeleton3D`）")
	_check(c1.find_child("root", true, false) != null and c1.find_child("torso", true, false) != null,
		"分件层级与普查 §三 一致（`root` / `torso` 都在）")

	# ② **脚底落在 `FLOOR_Y`** —— 手摆坐姿对不对的唯一硬判据
	var ab := _subtree_world_aabb(c1)
	var got_geo: bool = ab.size != Vector3.ZERO
	_check(got_geo, "（前提）角色量得到几何（世界 AABB %s..%s）" % [ab.position, ab.end])
	var feet: float = ab.position.y
	var feet_off: float = feet - GameRoom.FLOOR_Y
	_check(got_geo and absf(feet_off) <= 0.05,
		"**脚底落在 FLOOR_Y**（脚底 y=%.4f / 地板 %.4f ⇒ 差 %+.4f，容差 0.05 —— 手摆坐姿对不对的唯一硬判据）"
			% [feet, GameRoom.FLOOR_Y, feet_off])
	# 第二条外尺：**髋枢轴 = 腿分件的节点原点**，它应当落在座面上（普查 §5.2 的实测结论：
	# 手摆之后 `hip = 0.800` 模型单位 × `CHARS_SCALE` = 2.25 = 一期座面高）。
	var hip_y := leg_l.global_position.y if leg_l != null else -9999.0
	var seat_y: float = GameRoom.FLOOR_Y + SEAT_H
	_check(leg_l != null and absf(hip_y - seat_y) <= 0.05,
		"髋枢轴落回**座面**（髋 y=%.4f / 座面 %.4f ⇒ 差 %+.4f，容差 0.05 —— 一期座面离地 %.2f）"
			% [hip_y, seat_y, hip_y - seat_y, SEAT_H])

	# ③ 角色 AABB **不与桌子相交**（`TableBase` 的足迹）
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	_check(tbase != null and tbase.mesh != null, "（前提）桌子底座 `TableBase` 在（一期）")
	if tbase != null and tbase.mesh != null:
		var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
		# 座位这一侧的净空（slot 1 在 +x 侧；人朝桌心 ⇒ 与桌子最近的那一维是 x）
		var gap: float = ab.position.x - tb.end.x
		_check(got_geo and not ab.intersects(tb),
			"角色 AABB 不与桌子相交（人 x∈[%.3f, %.3f] / 桌子底座 x∈[%.3f, %.3f] ⇒ 净空 %+.3f 世界 = 真实 %.1f mm）"
				% [ab.position.x, ab.end.x, tb.position.x, tb.end.x, gap, gap * 200.0])

	# ④ 材质：**不是 UNSHADED**（会被房间的灯照亮）、**贴图还在**（普查 §7.2）
	#    包自带 `KHR_materials_unlit` ⇒ Godot 导成 `SHADING_MODE_UNSHADED`。
	#    ⚠ **两条各守一半，缺一就会被 `room.gd._paint()` 那一手骗过去**：
	#       * 它盖上去的 `_furn_mat` **自己就是受光的** ⇒ 单看 `shading_mode` 照样绿；
	#       * 它**自己也带贴图**（木地板的木纹）⇒ 单看"有没有贴图"也照样绿。
	#    ⇒ 两条都必须比**"材质本体 / 贴图还是角色自己的那份"**，不是比自己有没有值。
	var surfaces := 0
	var missing := 0
	var unshaded := 0
	var textured := 0
	var tex_own := 0
	var foreign := 0
	var mat_log := ""
	for n in c1.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as MeshInstance3D
		if gi == null or gi.mesh == null:
			continue
		for s in gi.mesh.get_surface_count():
			surfaces += 1
			var m := gi.get_active_material(s) as BaseMaterial3D
			var own := gi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				missing += 1
				continue
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				unshaded += 1
			if m.albedo_texture != null:
				textured += 1
			# **材质本体仍是角色自己的那份**：底色与模型自带那份一致。
			# 这一条量的是"改的是光照参数、不是把材质整个换掉" —— 少了它，上面那条
			# `unshaded == 0` 是能被 `room.gd` 那套覆盖**骗过去**的（换成家具材质后就"受光"了）。
			if own != null and not m.albedo_color.is_equal_approx(own.albedo_color):
				foreign += 1
			# **贴图还是角色自己那张**（不是"有贴图就行"）：房间那份家具材质**自己也带贴图**
			# （木地板的木纹）⇒ 只查 `albedo_texture != null` 会被整片覆盖骗过去 ——
			# 贴图确实还在，只不过角色被贴成了木地板（实测：tex 那一栏仍是"有"）。
			if own != null and own.albedo_texture != null and m.albedo_texture == own.albedo_texture:
				tex_own += 1
			mat_log += "%s/s%d:shade%d,tex%s,自带贴图%s,albedo%s " % [gi.name, s, m.shading_mode,
				"有" if m.albedo_texture != null else "无",
				"有" if own != null and own.albedo_texture != null else "无", m.albedo_color]
	print("  [实测] 角色材质：%s" % mat_log)
	_check(surfaces > 0 and missing == 0,
		"（前提）角色的每个面都有材质可量（%d 个面，取不到材质 %d 个）" % [surfaces, missing])
	_check(surfaces > 0 and unshaded == 0 and foreign == 0,
		"角色材质**不是 UNSHADED**、且**只调了光照参数**（%d 个面：UNSHADED %d / 底色被换成别人的 %d —— "
			% [surfaces, unshaded, foreign]
			+ "包自带 KHR_materials_unlit，不调就不响应一期的光照契约；整片覆盖则会把材质换成房间的暗木）")
	_check(surfaces > 0 and tex_own == surfaces,
		"角色**贴图还在、而且是自己那张**（%d/%d 个面的贴图与模型自带的同一张；任意贴图 %d/%d —— "
			% [tex_own, surfaces, textured, surfaces]
			+ "照抄 room.gd 的整片覆盖会把脸 / 衣服换成房间的木地板，那样「有贴图」那一栏仍是有的、只有这条拦得住）")

	# 影子：**不投影**（房间的纪律：全场唯一投影源是那盏吊灯）。这不是"顺手" ——
	# `layout_test` 那条「房间物件一律不投影」扫的正是 `Room` 整棵子树，角色一投影那条立刻红。
	var casting := 0
	for n in c1.find_children("*", "GeometryInstance3D", true, false):
		if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casting += 1
	_check(casting == 0, "角色不投影（违规 %d 个 —— 吊灯仍是全场唯一投影源）" % casting)

	# 供报告的原始读数
	print("  [实测] 角色世界 AABB %s..%s（尺寸 %s）" % [ab.position, ab.end, ab.size])
	print("  [实测] 脚底 y=%.4f（地板 %.4f，差 %+.4f）/ 髋 y=%.4f（座面 %.4f，差 %+.4f）"
		% [feet, GameRoom.FLOOR_Y, feet_off, hip_y, seat_y, hip_y - seat_y])
	print("  [实测] 腿分件 scale = %s（`LEG_SQUASH` = %.2f）"
		% [leg_l.scale if leg_l != null else Vector3.ZERO, GameChars.LEG_SQUASH])
	print("  [实测] 座位锚点 %s / 人 %s" % [an.origin, cp])

	if fails == 0:
		print("CHARS TEST: PASS")
		quit(0)
	else:
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1)
