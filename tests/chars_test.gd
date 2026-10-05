extends SceneTree
## 二期 Task 1：角色接入 + 手摆坐姿（**一个人坐对 —— slot 1**）
## godot --headless --path . --script tests/chars_test.gd
##
## 判据四条（brief Step 1）+ 本轮 fix round 加的一条：
##   ① `slot 1` 坐着一个人、`slot 0`（近侧 = 「我」，相机就在那儿）**一个人都没有**；
##   ② **脚底落在 `FLOOR_Y`**（容差 ≤0.05 —— **手摆坐姿对不对的唯一硬判据**）；
##   ③ 角色**不与桌子相交** —— **逐件**对桌子的**实体体积**（底座 ∪ 桌面那一层）量体积相交。
##      【本轮重述】旧口径是"合并 AABB 与 `TableBase` 不相交"，实得净空 0.025 世界（5 mm）。
##      那个数**没有意义**：离桌子最近的那一件是**浮在桌面上方 1.08~3.33 的头**，而合并盒把
##      脚下的 y 一路并到头顶 ⇒ 那 5 mm 量的是"头的近侧边 vs 底座的远侧边"，两者在 y 上差
##      1 米以上、根本不可能相交。**真要求是"人不许穿进桌子"** ⇒ 逐件按真实世界 AABB 量。
##   ④ 角色材质**不是 `SHADING_MODE_UNSHADED`**、**贴图还在**（普查 §7.2：包自带
##      `KHR_materials_unlit`，照抄 `room.gd` 的整片覆盖会**抹掉贴图**）；
##   ⑤ **【本轮新增】角色不许是画面里最亮的东西**（Ruling E2 的 J1）：角色的有效 albedo
##      （色调 ⊙ 贴图那一块的平均色）× 照度，不许高过桌面那一笔（同一把尺子）。
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

## **角色的"被照亮的 albedo"相对桌面那一笔的比值上限**（本轮 J1 新增，口径照
## `layout_test.FURN_LIT_RATIO_MAX`：`albedo 亮度 × 照度`，两边同一把尺子）。
##
## **为什么是 1.0**：本档要的就是那句大白话 —— **角色不许亮过桌面**。实测 **0.83**（留 1.2 倍余量）；
## **把 `CHAR_TINT` 改回 `Color(1,1,1)`（= 不压暗）立刻红**（实测 2.65）。
##
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

	# ③ 角色**不与桌子相交** —— 逐件、对桌子的**实体体积**（本轮重述，见文件头 ③）。
	#    **为什么必须逐件**：合并 AABB 的头尾把"脚下的 y"与"头顶的 y"并成一个盒子，
	#    于是"离桌子最近"变成"头（浮在桌面上方 1.08~3.33）的近侧边离底座多远" —— 那不是要求。
	#    **为什么必须带桌面那一层**：底座顶面（y = −0.012）到桌面上表面（y = 0）那一段
	#    也是实木；不带它，"从桌面上方捅进去"这种穿法量不出来。
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
		for n in c1.find_children("*", "GeometryInstance3D", true, false):
			var g := n as MeshInstance3D
			if g == null or g.mesh == null:
				continue
			var a: AABB = g.global_transform * g.mesh.get_aabb()
			var bad: bool = a.intersects(tb) or a.intersects(slab)
			if bad:
				hits += 1
			# 净空只在 x 上量（slot 1 在 +x 侧、人朝桌心 ⇒ 唯一可能靠近桌子的一维是 x）
			worst = minf(worst, a.position.x - tb.end.x)
			p_log += "%s:%+.3f%s " % [g.name, a.position.x - tb.end.x, "∩" if bad else ""]
		print("  [实测] 逐件净空（x，正 = 在底座之外）：%s" % p_log)
		_check(got_geo and hits == 0,
			"**角色不与桌子相交**：逐件世界 AABB 与桌子实体体积（底座 x∈[%.3f, %.3f] y∈[%.3f, %.3f] + "
				% [tb.position.x, tb.end.x, tb.position.y, tb.end.y]
				+ "桌面那一层 y∈[%.3f, %.3f]）都不相交（相交 %d 件；最近那件在 x 上还差 %+.3f 世界 = 真实 %.1f mm）—— "
				% [slab.position.y, slab.end.y, hits, worst, worst * 200.0]
				+ "旧口径量的是合并 AABB 的 5 mm，那个数由浮在桌面上方的头贡献、不代表会不会穿模")

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
			# **底色只许是"自己那份 × 一个压暗系数"**（本轮 fix round 改了这条的口径）。
			#
			# 原先这条比的是"`albedo_color` 与模型自带那份**逐字节相等**"，当年用它兜住
			# `room.gd._paint()` 那一手整片覆盖。**本轮 J1 起角色的底色被**故意**乘上了
			# `CHAR_TINT`（把角色收进房间的暗色调）⇒ 那条"相等"口径不再成立、会误报。
			# "材质本体没被换掉"这半件事**由下面那条贴图断言守着**（房间那份家具材质自己也带贴图，
			# 但**不是角色这一张** ⇒ `tex_own` 拦得住，这正是它当初加进来的理由）。
			# 这条留下的是**新行为的可执行版**：底色必须是**压暗**（三维都 ≤ 自己那份），
			# 且是"乘一个系数"而不是被换成别人的色。**把 `CHAR_TINT` 改成 >1（提亮）这条立刻红。**
			if own != null and (m.albedo_color.r > own.albedo_color.r + 0.001
					or m.albedo_color.g > own.albedo_color.g + 0.001
					or m.albedo_color.b > own.albedo_color.b + 0.001):
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
		"角色材质**不是 UNSHADED**、且**底色只被压暗过**（%d 个面：UNSHADED %d / 底色不是压暗 %d —— "
			% [surfaces, unshaded, foreign]
			+ "包自带 KHR_materials_unlit，不调就不响应一期的光照契约；整片覆盖会被贴图那条拦下）")
	_check(surfaces > 0 and tex_own == surfaces,
		"角色**贴图还在、而且是自己那张**（%d/%d 个面的贴图与模型自带的同一张；任意贴图 %d/%d —— "
			% [tex_own, surfaces, textured, surfaces]
			+ "照抄 room.gd 的整片覆盖会把脸 / 衣服换成房间的木地板，那样「有贴图」那一栏仍是有的、只有这条拦得住）")

	# ⑤ **角色不许是画面里最亮的东西**（本轮 J1 的核心判据，Ruling E2）。
	#
	# 病（出图实证）：角色的贴图是 Kenney 展示用的高饱和亮色，有效 albedo 亮度 **0.58**，
	# 而屋里木头外框 0.16、家具 0.08 ⇒ 角色是画面上唯一发亮的东西，读作"桌上摆了个玩偶"。
	# 判据 = **同一把尺子**（同 `layout_test` 的照度代理式）× 同一把 albedo 尺子
	#（色调 ⊙ 贴图那一块的平均色）：角色的那笔必须 ≤ `CHAR_LIT_RATIO_MAX` × 桌面那笔。
	#
	# albedo **从材质上读**（不读 `GameChars.CHAR_TINT`）—— 读常量等于把实现重述一遍。
	# 采样点：角色 = 自己世界 AABB 的形心（同 `layout_test` 量家具那一套）；桌面 = 桌垫四角 + 中心
	#（同一组点、同一把尺子），取**最亮**那个 —— 理由见 `CHAR_LIT_RATIO_MAX` 那段。
	var lamp: OmniLight3D = t3.get("lamp_light")
	var wenv: WorldEnvironment = null
	for c in t3.get_children():
		if c is WorldEnvironment:
			wenv = c
	var amb := 0.0
	if wenv != null:
		amb = wenv.environment.ambient_light_energy * wenv.environment.ambient_light_color.get_luminance()
	var cl = _subtree_lit_albedo_lum(c1)
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
	print("  [实测] 角色有效 albedo（色调 ⊙ 贴图那一块的平均色，逐件）：%s⇒ 最亮 %.3f"
		% [cl["log"], cl["lum"]])
	print("  [实测] 木头外框有效 albedo 亮度 %.3f（色调 %s ⊙ 贴图那一块 %s）/ 环境光那一份 %.4f"
		% [wood_lum, wm.albedo_color if wm != null else "无", wavg, amb])
	var char_lit := -1.0
	var tab_lit := -1.0
	if lamp != null and got_geo and cl["lum"] >= 0.0 and wood_lum >= 0.0:
		char_lit = cl["lum"] * _irradiance(lamp, ab.get_center(), amb)
		for p in corners:
			tab_lit = maxf(tab_lit, wood_lum * _irradiance(lamp, p, amb))
	_check(lamp != null and got_geo and cl["lum"] >= 0.0 and wood_lum >= 0.0,
		"（前提）角色的 albedo、木桌的 albedo、吊灯都量得到（角色 %.3f / 木桌 %.3f / 灯 %s）"
			% [cl["lum"], wood_lum, "在" if lamp != null else "缺"])
	if lamp != null and char_lit >= 0.0 and tab_lit >= 0.0:
		var ratio: float = char_lit / maxf(tab_lit, 0.0001)
		_check(ratio <= CHAR_LIT_RATIO_MAX,
			"**角色不再是画面里最亮的东西**：角色 albedo × 照度 %.4f ≤ %.2f × 桌面那一笔 %.4f"
				% [char_lit, CHAR_LIT_RATIO_MAX, tab_lit]
				+ "（实得比值 %.3f；形心 %s 照度 %.3f）—— 把 `CHAR_TINT` 改回 (1,1,1) 这条立刻红"
				% [ratio, ab.get_center(), _irradiance(lamp, ab.get_center(), amb)])

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
