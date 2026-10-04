extends SceneTree
## 2.5D 桌面几何单测：平面求交 + 世界↔UV↔SubViewport 往返一致性
## godot --headless --path . --script tests/layout_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 棋子薄牌的节点（按 **meta("peer")** 找，不按节点名 —— 同帧重建时 Godot 会把重名的子节点
## 自动改名）。找不到给 null。
func _token_node(tokens_root: Node, peer: int) -> Node3D:
	if tokens_root == null:
		return null
	for ch in tokens_root.get_children():
		if (ch as Node).has_meta("peer") and int((ch as Node).get_meta("peer")) == peer:
			return ch as Node3D
	return null

## 某个距离上「能量 × 衰减」估出的相对照度（光池亮度 × 形状的**代理式**，见 C3 那段注释）。
## `pow` 的底夹到 0：射程之外照度为 0（Godot 的 omni 光在射程外也确实是 0）。
func _corner_irradiance(light: OmniLight3D, dist: float) -> float:
	return light.light_energy * pow(maxf(1.0 - dist / light.omni_range, 0.0), light.omni_attenuation)

## 灯罩在**屏幕**上的包围盒（近似：把它当成一个"底口半径 × 罩高"的盒子，八个角过 3D 相机
## 的真投影再取包围）。灯罩本身是斜的 —— 取的是**旋转后的盒子**的角，够给"有没有被画面裁掉"用。
func _shade_screen_bbox(t3, shade: MeshInstance3D) -> Rect2:
	var cm := shade.mesh as CylinderMesh
	var r: float = maxf(cm.top_radius, cm.bottom_radius) if cm != null else 0.4
	var hh: float = cm.height * 0.5 if cm != null else 0.25
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for sx in [-r, r]:
		for sy in [-hh, hh]:
			for sz in [-r, r]:
				var p: Vector2 = t3.camera.unproject_position(
					shade.global_transform * Vector3(sx, sy, sz))
				mn = mn.min(p)
				mx = mx.max(p)
	return Rect2(mn, mx - mn)

## 一格在**屏幕**上的包围盒宽度（批次 10 T2 的"字更大"判据）。
##
## 格坐标是**桌垫口径**（`tile_pos` 活在 BOARD_OFFSET 那一系里），不是画布像素 —— 送进
## `canvas_px_to_world` 之前必须先过 BoardView 的取景变换。走的就是 `tile_screen_pos` 那条链：
## `global_position + _view_from_world(...)`（私有方法 + 那一项 `global_position` 都别漏，
## 见本文件 :1318-1324 那段）。把 `tile_pos` 直接当画布像素喂进去会量到桌面上并不存在的一格。
func _tile_screen_w(t3, idx: int) -> float:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var tp: Vector2 = t3.board.tile_pos(idx)
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var canvas_pt: Vector2 = t3.board.global_position \
				+ t3.board._view_from_world(tp + Vector2(sx, sy) * t3.board.TILE)
			var sp: Vector2 = t3.camera.unproject_position(t3.canvas_px_to_world(canvas_pt))
			mn = mn.min(sp)
			mx = mx.max(sp)
	return (mx - mn).x

func _run() -> void:
	# 无头下根窗口是退化的 64×64，内容缩放 0.05 —— push_input 进去的鼠标坐标会被
	# 放大 20 倍（640,640 → 12800,12800），事件投递类断言永远不成立。
	# 同 hud_test.gd：先给根窗口一个真实尺寸，坐标链路才是真实的那条。
	root.size = Vector2i(1280, 800)
	print("== 射线与水平地面求交 ==")
	var hit = TableGeometry.hit_floor(Vector3(0, 5, 0), Vector3(0, -1, 0))
	_check(hit != null and (hit as Vector3).is_equal_approx(Vector3.ZERO), "垂直下射打中地面原点")
	_check(TableGeometry.hit_floor(Vector3(0, 5, 0), Vector3(0, 1, 0)) == null,
		"向上的射线打不到地面（返回 null）")

	print("== 世界 ↔ UV 往返 ==")
	# 尺寸是 Vector2（宽 × 进深），函数对任意矩形都成立。（今天桌面**不是**正方形：进深由
	# 贴图窗口的宽高比派生，见 table_geometry.gd 类头。）下面用 8×8 与 8×4 两份尺寸，
	# 钉住「进深按自己的边长折算」—— 少了这条，窗口与桌面比例一旦脱钩、贴图就被拉伸。
	var side := Vector2(8.0, 8.0)
	for uv in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75),
			Vector2(0.75, 0.75), Vector2(0.5, 0.5), Vector2(0.0, 1.0)]:
		var w := TableGeometry.uv_to_world(uv, side)
		var back := TableGeometry.world_to_uv(w, side)
		_check(back.distance_to(uv) < 0.0001, "UV %s → 世界 %s → UV %s" % [uv, w, back])
	_check(TableGeometry.uv_to_world(Vector2(0.25, 0.25), side).is_equal_approx(Vector3(-2, 0, -2)),
		"UV(0.25,0.25) 落在远左（z 负）")
	_check(TableGeometry.uv_to_world(Vector2(0.25, 0.25), Vector2(8.0, 4.0)).is_equal_approx(Vector3(-2, 0, -1)),
		"非正方形桌面：进深按自己的边长折算（8×4 → z=-1）")

	print("== UV ↔ SubViewport 像素往返（贴图窗口）==")
	# 窗口是画布上的一块矩形（px）。恒等窗口（0,0,2048,2048）= 铺满整张画布的老行为。
	var vp := Rect2(0.0, 0.0, 2048.0, 2048.0)
	for uv in [Vector2(0.0, 0.0), Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(1.0, 1.0)]:
		var px := TableGeometry.uv_to_viewport(uv, vp)
		var back := TableGeometry.viewport_to_uv(px, vp)
		_check(back.distance_to(uv) < 0.0001, "UV %s → px %s → UV %s" % [uv, px, back])
	_check(TableGeometry.uv_to_viewport(Vector2(0.5, 0.5), vp) == Vector2(1024, 1024), "中心映射到像素中心")
	var half := Rect2(400.0, 300.0, 1000.0, 800.0)
	_check(TableGeometry.uv_to_viewport(Vector2(0.5, 0.5), half) == Vector2(900.0, 700.0),
		"窗口不铺满画布时，UV 中心映射到窗口中心")
	_check(TableGeometry.viewport_to_uv(Vector2(400.0, 300.0), half) == Vector2.ZERO,
		"窗口左上角 = UV 原点")

	print("== TableView3D 容器结构 ==")
	# 用运行时 load() 取 TableView3D，而不是写类名：--script 入口脚本的静态依赖链在
	# autoload 全局标识符注册之前就编译，而 TableView3D 依赖的 BoardView 内部用了 Fx
	#（autoload）→ 静态引用会以「Identifier not found: Fx」整链编译失败。
	# 本仓库既有约定同此：需要 game/BoardView 的测试都在运行时 load（见 hud_test.gd）。
	var t3 = load("res://scripts/table_3d.gd").new()
	root.add_child(t3)
	_check(t3.board != null, "容器内有 BoardView")
	_check(t3.viewport != null and t3.board.get_parent() == t3.viewport,
		"BoardView 挂在容器自己的 SubViewport 下")
	_check(t3.camera != null and t3.camera.current, "3D 相机已就位并 current")
	_check(t3.camera.global_position.y > 0.0, "相机在桌面之上（实得 y=%.2f）" % t3.camera.global_position.y)
	# 俯角 = 相机位置矢量（相对注视点）与竖直方向的夹角余角。
	# 必须用 Vector3.UP：angle_to 是无符号夹角，位置矢量与 DOWN 的夹角 = 180° − 俯角
	# （50° 配置实测得 140°，`90 - 140` 是 −50°，永远过不了）；与 UP 的夹角才是 90° − 俯角。
	var tilt := 90.0 - rad_to_deg(t3.camera.global_position.angle_to(Vector3.UP))
	_check(absf(tilt - t3.CAM_TILT_DEG) < 8.0,
		"俯角接近配置值 %.0f°（实得 %.1f°）" % [t3.CAM_TILT_DEG, tilt])

	# ---- 批次 6 Task 1：房间剪影 + 台灯（唯一主光源） ----
	# 观感的主角是**光**：近黑的屋子里只有一盏台灯亮着，四周落进剪影。可执行的判据只有四条：
	#   ① 剪影**近黑、高粗糙、不透明**（不吃灯就走不进画面）；② 全场**只有一盏灯**（台灯）；
	#   ③ 环境光压到很低、背景近黑；④ 灯杆 / 灯罩**不在桌垫窗口内**（它不该挡棋盘）。
	# 位置 / 范围 / 衰减是对着出图调的估值，测试只钉「关系」不钉「数值」
	# （否则每次对图微调都要改测试）。
	print("== 批次 6：房间剪影（近黑、不吃灯就走不进画面） ==")
	var room: Node = t3.get_node_or_null("Room")
	_check(room != null, "容器带房间层 Room")
	if room == null:
		_check(false, "房间层缺了，房间 / 台灯断言整段跳过")
	else:
		var boxes: Array = []
		for ch in room.get_children():
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh is BoxMesh:
				boxes.append(mi)
		# 至少：三面墙 + 书架（几块板）+ 床架（几块板）
		_check(boxes.size() >= 8, "房间剪影都用 BoxMesh 拼（实得 %d 块）" % boxes.size())
		# **三面墙各查一遍**（批次 6 Task 3 补回）：上面那条只钉"块数 ≥ 8"而实际 13
		# ⇒ 少一面墙照样过（删后墙那条断言时把 `WallBack != null` 也一起删掉了）。
		# 三面墙是房间的骨架，缺一面就"漏"到背景色外面去了，这里逐面点名。
		var walls_ok := true
		for wn in ["WallBack", "WallLeft", "WallRight"]:
			var wmi := room.get_node_or_null(wn) as MeshInstance3D
			if wmi == null or not (wmi.mesh is BoxMesh):
				walls_ok = false
		_check(walls_ok, "三面墙都在（WallBack / WallLeft / WallRight —— 块数断言盖不住少一面）")
		var dark := true
		var matte := true
		var opaque := true
		var one_mat: StandardMaterial3D = null
		var shared := true
		var off_table := 0
		var casting := 0
		var half_w_r: float = t3.TABLE_SIZE.x * 0.5 + t3.WOOD_FRAME
		var half_d_r: float = t3.TABLE_SIZE.y * 0.5 + t3.WOOD_FRAME
		for b in boxes:
			var mi2 := b as MeshInstance3D
			var bm2 := mi2.mesh as BoxMesh
			var m2 := mi2.material_override as StandardMaterial3D
			if m2 == null or m2.albedo_color.get_luminance() > 0.12:
				dark = false
			if m2 == null or m2.roughness < 0.8:
				matte = false
			if m2 == null or m2.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				opaque = false
			if one_mat == null:
				one_mat = m2
			elif m2 != one_mat:
				shared = false
			# 剪影一律落在木桌之外（不许压在桌面上 / 遮棋盘）
			var bp2: Vector3 = mi2.global_position
			if absf(bp2.x) - bm2.size.x * 0.5 < half_w_r \
					and absf(bp2.z) - bm2.size.z * 0.5 < half_d_r:
				off_table += 1
			# 剪影不投影：它们又大又远，投影纯是每帧白跑一张阴影图（性能是本批次点名的）
			if mi2.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casting += 1
		_check(dark, "剪影材质近黑（亮度 ≤ 0.12 —— 底色压到近黑，抬起来的是下面那条自发光底光）")
		_check(matte, "剪影材质高粗糙（roughness ≥ 0.8，不吃镜面高光）")
		_check(opaque, "剪影是不透明档（写深度、能彼此遮挡，不是透明队列）")
		_check(shared, "所有剪影共用一份材质（不为每件单建 —— 本批次点名要避免的浪费）")
		_check(off_table == 0, "房间剪影都落在木桌之外（压到桌子上的 %d 块）" % off_table)
		_check(casting == 0, "剪影都不投影（开着投影的 %d 块 —— 白跑阴影图）" % casting)

	print("== 批次 6：台灯 = 唯一主光源 ==")
	var lamp_n: Node = t3.get_node_or_null("Lamp")
	# 用 get("lamp_light") 而不是 t3.lamp_light：**红跑**（还没实现）时前者给 null、
	# 后者是 "Invalid access to property" 的脚本错误，会把 _run() 打断在半路、
	# 后面的断言一条都跑不到（红跑还会挂住不退）。
	var lamp_l = t3.get("lamp_light")
	_check(lamp_n != null and lamp_l != null, "容器带台灯（Lamp 节点 + lamp_light）")
	if lamp_n == null or lamp_l == null:
		_check(false, "台灯缺了，台灯断言整段跳过")
	else:
		var pole := lamp_n.get_node_or_null("Pole") as MeshInstance3D
		var shade := lamp_n.get_node_or_null("Shade") as MeshInstance3D
		_check(pole != null and pole.mesh is CylinderMesh, "灯杆是细柱（CylinderMesh）")
		var sm: CylinderMesh = null
		if shade != null and shade.mesh is CylinderMesh:
			sm = shade.mesh as CylinderMesh
		_check(sm != null and sm.top_radius < sm.bottom_radius,
			"灯罩是上小下大的锥（top %.3f < bottom %.3f）"
				% [sm.top_radius if sm != null else -1.0, sm.bottom_radius if sm != null else -1.0])
		# 台灯四件也一律**不透明档**（**固定波 C**：上面剪影那条只覆盖房间材质，管不到灯自身）。
		# 这条比剪影那边更要紧：透明件进透明队列、不写深度之外，**还吃不到自己的逐像素光照** ——
		# 手滑写成 ALPHA，画面上是"灯还在、光没了"，归因比剪影那个坑更难。
		var lamp_parts: Array = []
		var lamp_opaque := true
		for nm in ["Base", "Pole", "Arm", "Shade"]:
			var pnd := lamp_n.get_node_or_null(nm) as MeshInstance3D
			lamp_parts.append(pnd)
			var pmat: StandardMaterial3D = null
			if pnd != null:
				pmat = pnd.material_override as StandardMaterial3D
			if pmat == null or pmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				lamp_opaque = false
		var parts_ok := true
		for pnd2 in lamp_parts:
			if pnd2 == null:
				parts_ok = false
		_check(parts_ok, "台灯四件都在（Base / Pole / Arm / Shade）")
		_check(lamp_opaque, "台灯四件都是不透明档（进透明队列会静默杀死光照）")
		# **半径**也要钉（**固定波 C**）：原来只查了各件的**中心位置**，半径写多大没人管 ——
		# 底座半径 0.30 时外缘 = -5.20，**正好压在木桌外沿上**（`TABLE_W*0.5 + WOOD_FRAME`），
		# 零余量。两条：① 整座灯连半径一起**站在木桌里**；② 底座外缘离木桌外沿有 ≥ 0.05 余量。
		#
		# **批次 10 核过 —— 计划 Step 3 要"补一条'底座外缘不越木桌外沿'"，它其实早就在这里了**
		#（下面这两条正是那个判据：读 `Base` 的 `global_position` 与它的 `CylinderMesh.bottom_radius`，
		#  比 `TABLE_W*0.5 + WOOD_FRAME`），所以**不重复再加一条** —— 等价的判据只该有一处。
		# 木纹框 1.2 → 0.7 之后它是台灯这一族**最紧**的一条：实测余量 **0.11**（旧框宽下是 0.06）。
		#（灯罩那半条同样吃紧：`LAMP_ARM_LEN` 从 0.60 收到 0.20 就是被它 + 上面那条"平面落点必须
		#  在桌垫之外"两头夹出来的，见 `table_3d.LAMP_ARM_LEN`。）
		var half_w_wood: float = t3.TABLE_W * 0.5 + t3.WOOD_FRAME
		var half_d_wood: float = t3.TABLE_D * 0.5 + t3.WOOD_FRAME
		var base_mi := lamp_parts[0] as MeshInstance3D
		var base_r := 0.0
		if base_mi != null and base_mi.mesh is CylinderMesh:
			base_r = (base_mi.mesh as CylinderMesh).bottom_radius
		var in_table := true
		if base_mi != null and (absf(base_mi.global_position.x) + base_r > half_w_wood
				or absf(base_mi.global_position.z) + base_r > half_d_wood):
			in_table = false
		if shade != null and sm != null and (absf(shade.global_position.x) + sm.bottom_radius > half_w_wood
				or absf(shade.global_position.z) + sm.bottom_radius > half_d_wood):
			in_table = false
		_check(in_table, "整座灯（含底座 / 灯罩的半径）都站在木桌里")
		# **判空再用**（批次 6 Task 3）：`Base` 缺失时上面那条 `parts_ok` 已经红过，
		# 这里若再空访问一次，`_run()` 会**因脚本错误中止**、静默掉其后所有断言
		#（本文件 `:135-137` 正写着这个坑）。缺失时给 -INF ⇒ 这一条也红（不留假绿）。
		var base_gap := -INF
		if base_mi != null:
			base_gap = half_w_wood - (absf(base_mi.global_position.x) + base_r)
		_check(base_gap >= 0.05,
			"底座外缘离木桌外沿有余量（%.2f ≥ 0.05 —— 零余量时底座就悬在桌沿上）" % base_gap)
		# 全场唯一的 Light3D：**别留下第二盏会投影的灯**（第二盏 = 多一张阴影图 + 氛围被拆开）
		var lights: Array = []
		for n in t3.find_children("*", "Light3D", true, false):
			lights.append(n)
		_check(lights.size() == 1 and lights[0] == lamp_l,
			"全场只有台灯这一盏灯（实得 %d 盏）" % lights.size())
		_check(lamp_l.shadow_enabled, "台灯开着阴影（手牌 / 牌堆才投得出影子）")
		_check(lamp_l.light_color.r > lamp_l.light_color.b + 0.1, "台灯是暖色（r 明显大于 b）")
		_check(lamp_l.light_energy > 0.5, "台灯有能量（实得 %.2f）" % lamp_l.light_energy)
		var lp: Vector3 = lamp_l.global_position
		_check(lp.y > t3.table_mesh.global_position.y + 1.0,
			"主光源吊在桌面上方（实得 y=%.2f）" % lp.y)
		# 光池要够到棋盘（远端那半块不能是死黑、读不出字），但**不许漫到整间屋子**。
		# 尺子用**桌垫四角**（不是木桌四角 —— 批次 10 T2 的灯位下桌垫四角到灯 3.92~9.02、
		# 木桌四角是 4.48~9.88，别把两者混起来）。
		#
		# **固定波 B：原来那两条不可判别，已换掉。** 原话是"四角都在射程内 ⇒ 不落死黑"，
		# 但（当时：杆 2.3 / 衰减 1.15）远端角在 12.5 射程的 9.6 处只剩近端约两成强度 ——
		# 出图量到远端那两列只有 **0.008（3D）/ 0.012（2D）**，字读不出来，「在射程内」**必要而不充分**，单独拿它当
		# "不是死黑"的证据等于没测（本批次审查用像素采样打掉了这条结论）。换成三条**真管用**的：
		#   ① **余量**：远端角要落在 0.9×射程 以内（只判"在射程内"时，射程被收到 10 也照过）；
		#   ② **形状**：远端角到灯 ≤ 近端角 × 4（灯偏在桌子一侧、池子拉成长条时这条红）；
		#   ③ **衰减**：指数不许比 1.0 更陡 —— 1.15 → 0.72 那一次实测：能量只 +11%，远端列却从
		#      0.017 涨到 0.074（左列只涨 1.34 倍）⇒ 指数越大掉得越快，1.15 正是上面那次实测的成因。
		#      量测表见 `.superpowers/sdd/v0.5.0-批次6-实施计划/fix-wave-report.md`。
		#   ④ **亮度 × 形状耦合**（批次 6 Task 3 补）：上面 ①②③ 全是**形状 / 相对关系**，
		#      没有任何一条管"够不够亮" ⇒ 把 `LAMP_ENERGY` 单独退回 2.6（衰减仍是 0.72）时
		#      三条一条都不红，而那次实测的桌面均值只有 0.0566（批次 5 的一半，观感是"把桌子调暗了"）。
		#      ④ 把能量与衰减合起来估一个**远端角的相对照度**并钉下限 —— 它同时管亮度与形状，
		#      是"能量退回 2.6 / 衰减回到 1.15"两种回归都能红的那一条。
		var corners: Array = []
		for sx in [-t3.TABLE_SIZE.x * 0.5, t3.TABLE_SIZE.x * 0.5]:
			for sz in [-t3.TABLE_SIZE.y * 0.5, t3.TABLE_SIZE.y * 0.5]:
				corners.append(Vector3(sx, t3.table_mesh.global_position.y, sz))
		var d_near := INF
		var d_far := 0.0
		for cw in corners:
			var dd: float = lp.distance_to(cw)
			d_near = minf(d_near, dd)
			d_far = maxf(d_far, dd)
		_check(d_far <= lamp_l.omni_range * 0.9,
			"远端角落在射程的 0.9 以内（远端 %.2f ≤ %.2f，射程 %.1f）"
				% [d_far, lamp_l.omni_range * 0.9, lamp_l.omni_range])
		_check(d_far <= d_near * 4.0,
			"光池不拉成长条（远端 %.2f ≤ 近端 %.2f × 4）" % [d_far, d_near])
		_check(lamp_l.omni_attenuation <= 1.0,
			"衰减不比线性更陡（attenuation %.2f ≤ 1.0 —— 更陡时远端角只剩近端约两成、字读不出）"
				% lamp_l.omni_attenuation)
		# ④ 亮度 × 形状耦合（见上面那段注释）。**代理式**：把 Godot 的 omni 衰减近似成
		# `pow(clamp(1 - d/range, 0, 1), attenuation)`，再乘能量 —— 它不必与渲染器逐位一致
		#（判的是"能量与衰减合起来够不够把远端托起来"，不是复现某一张图的像素）。
		# 下限 1.1 的来历是**实测**（批次 6 的灯位）：能量 3.9 / 衰减 0.72 时远端角 1.355
		#（出图桌垫均值 0.1202），而能量退回 2.6 时只有 0.903（均值 0.0566 = 判红的那一档）；
		# 照抄审查者建议的 3.5 / 0.85 恰好在 1.00（那一组实测 0.0988、两条目标都在界外）⇒ 取 1.1
		# 把它也挡在外面。**批次 10 T2 重取**：灯挪到 z=0 之后 d_far 9.38 → 9.02 ⇒ 远端角 **1.552**
		#（出图棋盘整块均值 0.1266、左列 0.250 —— 变亮了，离下限更远、更安全）。
		var i_far: float = _corner_irradiance(lamp_l, d_far)
		var i_near: float = _corner_irradiance(lamp_l, d_near)
		_check(i_far >= 1.1,
			"远端角吃到的相对照度够亮（能量 %.2f × 衰减 %.2f ⇒ %.3f ≥ 1.1 —— 只把能量退回 2.6 时 0.90）"
				% [lamp_l.light_energy, lamp_l.omni_attenuation, i_far])
		_check(i_far >= i_near * 0.25,
			"远端角没塌成近端的零头（远端照度 %.3f ≥ 近端 %.3f × 0.25 —— 与②同源、按亮度加权）"
				% [i_far, i_near])
		# 【删掉的那条】原来这里断言「`omni_range` < 到后墙的距离」，错在两处：
		#   ① **量错了地方**：拿的是墙的**中心**（距灯 13.15），而不是**包围盒最近面**（~11.8）——
		#      墙其实**本来就在射程内**，那条断言在管一件不存在的事；
		#   ② 就算收紧到最近面，"射程止于墙"也**不是**房间明暗的成因：三面墙在这两个摆拍视角里
		#      **都出画**，房间里看到的是**背景色**（`background_color` 直出、不过光照）。
		# ⇒ **别用 `LAMP_RANGE` 去调房间明暗**（调不动，只会连桌子一起改）。房间的黑由本文件
		#   「背景色近黑」那条断言 + 剪影材质近黑那条钉住，这里不再留一条假判据。
		# 台灯是**桌上的实物**，但它不该挡棋盘：灯杆 / 灯罩落在**桌垫窗口之外**
		#（窗口 = 棋盘 + 一圈留白；压在窗口里就是"站在棋盘上"）。
		var on_board := 0
		for nd in [pole, shade, lamp_l]:
			if nd == null:
				continue
			if t3.TEX_WINDOW_PX.has_point(t3.world_to_canvas_px((nd as Node3D).global_position)):
				on_board += 1
		_check(on_board == 0, "灯杆 / 灯罩 / 光源都不在桌垫窗口内（压在棋盘上的 %d 个）" % on_board)
		# 台灯站在木桌上（真实的桌上物），不是浮空
		_check(absf(lamp_n.global_position.y - t3.table_mesh.global_position.y) < 0.05,
			"台灯坐在桌面上（y=%.3f）" % lamp_n.global_position.y)
		# 台灯要**看得见**（掉出画外就等于没有），而且**不许压在棋盘上**。
		# 这两条只能在**屏幕**上量：50° 俯角下，"在桌垫窗口之外"（上面那条）并不自动等于
		# "不在棋盘上" —— 灯是高处的实物，抬高 / 挪位会把它在屏幕上的落点顶进棋盘范围里。
		# （本任务实测过：底座挪到近端桌角那个位置时，灯罩在屏幕上正好盖住棋盘左下角。）
		t3.snap_view(0.0)
		await process_frame
		if shade != null:
			var vpr: Rect2 = t3.get_viewport().get_visible_rect()
			var sp_shade: Vector2 = t3.camera.unproject_position(shade.global_position)
			# **查包围盒、不查中心**（批次 6 Task 3）：抬杆到 2.8 之后灯罩中心就已经很贴画面左沿
			#（当时实测 **17px**），而灯罩的屏幕包围盒**左沿已被裁掉一大块**（当时相交占比
			# **0.55** —— 灯罩横向 214px 里有约 97px 在画外）—— 只查中心的话它照样"在画面内"，
			# 而注释承诺的是"掉出画外就等于没有"。改量**包围盒与视口的相交占比**：
			# **掉出画外的部分超过一半就红**（那时它已经看不出是盏灯了）。
			# **批次 10 重取：中心离画面左沿 38.6px（T1）→ 22.8px（T2）、相交占比 0.65 → 0.57**
			#（T2 把相机从 5.2 收到 4.7：这一条正是 T2 **最紧的约束** —— 灯留在 z=1.0 时占比跌到
			#  0.22、直接红；按设计 §4.5 把 `LAMP_BASE.z` 挪到 0.0 才回到 0.57，比批次 6 定案时的
			#  0.55 还宽一点）。**别再调小 `CAM_DIST` 而不重取灯位**，先红的就是这一条。
			# 阈值 0.5 与实测之间留的余量是**如实记的**：灯罩左沿出画是"灯座不许站上桌垫"这条
			# 硬约束（`LAMP_BASE` 那段）的既定代价，批次 6 Task1 修复波已如实留痕
			#（`fix-wave-report.md` §八 顾虑 2）—— 批次 10 挪灯走的是**另一条**约束（木纹带变窄 / 相机推近），
			# 这条断言与它的阈值一个字没动。这条断言管的是**别更糟**：再抬杆 / 再往左挪 / 再推近，它就红。
			var sbb := _shade_screen_bbox(t3, shade)
			var inter: Rect2 = sbb.intersection(vpr)
			var cov: float = (inter.size.x * inter.size.y) / maxf(sbb.size.x * sbb.size.y, 0.0001)
			_check(cov >= 0.5,
				"3D 端看得见台灯（灯罩屏幕包围盒 %s 与画面 %s 的相交占比 %.2f ≥ 0.5；中心 %s）"
					% [sbb, vpr, cov, sp_shade])
			# 桌垫的屏幕四边形 = 桌垫四角（`TABLE_SIZE`）投影出来的凸四边形（按环序取角）。
			# 点在凸多边形内用"同侧"判据；灯罩的屏幕中心一旦落在里面就是"压在棋盘上"。
			var hw_q: float = t3.TABLE_SIZE.x * 0.5
			var hd_q: float = t3.TABLE_SIZE.y * 0.5
			var quad: Array = []
			for cn in [Vector2(-hw_q, -hd_q), Vector2(hw_q, -hd_q), Vector2(hw_q, hd_q),
					Vector2(-hw_q, hd_q)]:
				quad.append(t3.camera.unproject_position(Vector3(cn.x, 0.0, cn.y)))
			var sgn := 0
			var outside := false
			for i in 4:
				var a2: Vector2 = quad[i]
				var b2: Vector2 = quad[(i + 1) % 4]
				var cr := (b2.x - a2.x) * (sp_shade.y - a2.y) - (b2.y - a2.y) * (sp_shade.x - a2.x)
				if absf(cr) < 0.0001:
					continue
				var s2 := 1 if cr > 0.0 else -1
				if sgn == 0:
					sgn = s2
				elif sgn != s2:
					outside = true         # 跨到了另一侧 ⇒ 在四边形之外
			# **固定波 C：这条的名字原来叫"灯罩的投影不压在棋盘上"，名不副实** —— 灯罩
			# `cast_shadow = OFF`，**根本没有投影**；下面查的是"灯罩的**屏幕位置**落在棋盘
			# 屏幕四边形之外"，即**屏幕重叠**（检查本身有效，只是名字会把人带偏）。
			# 顺带记下这个设计后果：灯罩不投影 ⇒ 光池**没有锥形边界**，池子的形状全靠
			# `LAMP_ATTEN` 衰减铺出来（射程内是均匀外溢，不是"被罩子挡出的一个圆"）——
			# 想改池子的软硬，改衰减，不要指望灯罩去切边。
			_check(outside, "灯罩的屏幕位置不落在桌垫上（屏幕 %s / 桌垫四角 %s；灯罩不投影，这里查的是屏幕重叠）"
				% [sp_shade, quad])

	print("== 批次 6：环境光与背景压到近黑 ==")
	var wenv: WorldEnvironment = null
	for c in t3.get_children():
		if c is WorldEnvironment:
			wenv = c
	_check(wenv != null, "容器带 WorldEnvironment")
	if wenv != null:
		var en := wenv.environment
		_check(en.ambient_light_energy < 0.25,
			"环境光压到很低（energy %.2f < 0.25 —— 四周近不近黑就看它）"
				% en.ambient_light_energy)
		_check(en.background_color.get_luminance() < 0.03,
			"背景色近黑（亮度 %.3f）" % en.background_color.get_luminance())
		# ---- 批次 6 终审修复波 D：剪影**不许比背景更暗** ----
		# 见 `table_3d.gd` 的 `ROOM_EMISSION` 那段：台灯照不到最远的床架（出图实测 1/255，
		# 而它身后的近黑背景是 4~6/255），"剪影可辨"靠的是共用材质上那层自发光底光。
		# 无头下渲染不出图，这里按**同一口径的数据**估一个代理式：
		#   剪影 ≈ 自发光（不过光照、与距离无关）+ 环境光给它的那一层（albedo × 环境能量 × 环境色）
		#   背景 = `background_color`（直出、不过光照）
		# 两者都是"直达画面"的量，可以直接比。**台灯那一项故意不计**（保守：剪影即使一点灯都
		# 没吃到也应当亮于背景 —— 正是"床架那一坨看不见的黑"要治的病）。这个顺序已由出图核对：
		# 床架 18/255 > 背景 4~6/255。少了底光这一条就反过来（环境那层只有 0.006，背景是 0.014）。
		var rmat = t3.get("room_mat") as StandardMaterial3D
		_check(rmat != null, "剪影材质可读（room_mat）")
		if rmat != null:
			var e_lum := 0.0
			if rmat.emission_enabled:
				e_lum = rmat.emission.get_luminance() * rmat.emission_energy_multiplier
			var a_lum: float = rmat.albedo_color.get_luminance() * en.ambient_light_energy \
				* en.ambient_light_color.get_luminance()
			var bg_lum: float = en.background_color.get_luminance()
			_check(e_lum > 0.0,
				"剪影带自发光底光（能量 %.4f —— 台灯够不到最远那件，见 ROOM_EMISSION）" % e_lum)
			_check(e_lum + a_lum > bg_lum,
				"剪影亮于背景（底光 %.4f + 环境 %.4f > 背景 %.4f —— 没有底光时反过来：床架实测 1/255 < 背景 4~6/255）"
					% [e_lum, a_lum, bg_lum])
			# ---- 收尾：**光够不够亮**这一条必须与出图夹逼挂钩 ----
			# 上面那条 `e_lum + a_lum > bg_lum` 的算术门槛只到 ~0.009（bg_lum 0.014 - a_lum 0.006），
			# 而夹逼里**被否掉的 0.021 那档 e_lum ≈ 0.0185 照样过** ⇒ 采用量级根本没被守住，
			# 将来退回"测得出但看不见"的发光也会绿。夹逼事实见 `table_3d.ROOM_EMISSION` 那段：
			#   0.021 ⇒ 出图 1/255（等于没发光，否掉）；0.11 ⇒ 床架 18/255（采用）。
			# 把下限钉在**采用量级（0.11 ⇒ e_lum ≈ 0.097）的约一半**：`e_lum >= 0.05`。
			# 于是 0.03（e_lum ≈ 0.026）与 0.021 都必红，采用的 0.11 仍有近 2× 余量。
			_check(e_lum >= 0.05,
				"剪影底光够亮（e_lum %.4f ≥ 0.05 —— 下限与夹逼挂钩：0.021 那档实测仅 1/255，必须红）" % e_lum)

	print("== 贴图窗口 = 桌垫（棋盘 + 一圈留白），不再铺满整张画布 ==")
	# 批次 5 Task 2：座位栏退场，画布不再需要为它们预留 —— 窗口从"整张画布"
	# 收到"桌垫"（`BoardView.MAT_RECT`）。批次 2 的 T4c 之所以把窗口恢复成整张画布，
	# 是因为当时上家座位栏会落到窗口之外、既看不见也点不到；座位栏一走，这条约束随之解除。
	# 窗口是否覆盖了该覆盖的东西，由下面「两条牌堆都在窗口内」那段钉住。
	var win: Rect2 = t3.TEX_WINDOW_PX
	_check(win.position.x >= 0.0 and win.position.y >= 0.0
			and win.position.x + win.size.x <= 2048.0 and win.position.y + win.size.y <= 2048.0,
		"贴图窗口落在画布内（窗口 %s）" % win)
	_check(win != Rect2(Vector2.ZERO, Vector2(t3.VP_SIZE)),
		"窗口已收到桌垫区（不再 = 整张画布 %s）" % win)
	# 窗口与桌垫（`BoardView.MAT_RECT`）是同一块地方的两种口径。两条必须同时成立：
	#   ① 比例一致 —— 否则贴图被拉伸；② 都居中 —— 取景（fit_overview）就是把桌垫铺成
	#      "画布正中、窗口那么大" 这一块，两边一旦错开，画面与命中就悄悄脱钩。
	# 这条是**跨类**的一致性断言（画布口径 vs 世界口径），改窗口或改桌垫都得两边一起改。
	var matr: Rect2 = t3.board.MAT_RECT
	_check(absf(win.size.x / win.size.y - matr.size.x / matr.size.y) < 0.001,
		"窗口比例 = 桌垫比例（%.4f vs %.4f —— 否则贴图会被拉伸）"
			% [win.size.x / win.size.y, matr.size.x / matr.size.y])
	_check(absf(win.get_center().x - 1024.0) < 1.0 and absf(win.get_center().y - 1024.0) < 1.0,
		"窗口在画布正中（中心 %s）" % win.get_center())
	# 桌面宽仍是 8 世界单位；进深由窗口比例派生（窗口比画布矮 ⇒ 桌面不再是正方形）。
	# 不写死当前进深（5.63；批次 9 是 6.15 —— 写哪个数都是把窗口尺寸抄一遍、改窗口就得改这里），
	# 只钉"进深与窗口同比例"。
	_check(absf(t3.TABLE_W - 8.0) < 0.001 and absf(t3.TABLE_D - 8.0 * win.size.y / win.size.x) < 0.001,
		"桌面宽 8、进深按窗口比例（宽 %.2f / 进深 %.2f）" % [t3.TABLE_W, t3.TABLE_D])
	# 材质取样窗口必须与输入映射同源：只改几何不改材质 → 看到的是整张桌子、点到的却是窗口那块。
	# （本任务实现时真踩过这个坑：出图「变好」了、点击却整体错位。）
	var canvas := Vector2(t3.VP_SIZE)
	var want_scale := Vector2(win.size.x / canvas.x, win.size.y / canvas.y)
	var want_offset := Vector2(win.position.x / canvas.x, win.position.y / canvas.y)
	_check(Vector2(t3.table_mat.uv1_scale.x, t3.table_mat.uv1_scale.y).is_equal_approx(want_scale)
			and Vector2(t3.table_mat.uv1_offset.x, t3.table_mat.uv1_offset.y).is_equal_approx(want_offset),
		"桌面材质取样窗口 = 输入映射的窗口（scale %s / offset %s）"
			% [t3.table_mat.uv1_scale, t3.table_mat.uv1_offset])

	print("== 暗角贴片 ==")
	# 暗角由 build_vignette(parent) 造出来并挂到**屏幕层**（容器自己不管挂载），
	# 所以这里要自己给一个父 Control —— 裸容器上 vignette 恒为 null（计划原文那三条
	# 断言在裸容器上不可能通过，见 Ruling 2）。
	var vig_parent := Control.new()
	vig_parent.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 别让测试自己建的父层吃掉后面注入的点击
	root.add_child(vig_parent)
	t3.build_vignette(vig_parent)
	_check(t3.vignette != null, "容器带暗角贴片")
	_check(t3.vignette.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"暗角不吃鼠标（否则整屏点不动）")
	_check(t3.vignette.color.a > 0.0, "暗角有可见的暗度")
	_check(t3.vignette.get_parent() == vig_parent, "暗角挂在调用方给的屏幕层上")
	# 光钉 null / mouse_filter / alpha 不够：一个默认尺寸（0×0、右上角在原点）的 ColorRect
	# 也能全过，而那样等于整屏没有暗角。必须钉住它真的铺满屏。
	_check(t3.vignette.anchor_right == 1.0 and t3.vignette.anchor_bottom == 1.0,
		"暗角铺满整屏（anchor 右下 = 1.0，实得 %.2f / %.2f）"
			% [t3.vignette.anchor_right, t3.vignette.anchor_bottom])
	_check(t3.vignette.material is ShaderMaterial and (t3.vignette.material as ShaderMaterial).shader != null,
		"暗角是 shader 画的四周压暗（不是一块死黑）")

	# ---- 输入映射（Task 3）：相机与视口要真的入树、布局过一帧 ----
	await process_frame
	await process_frame
	print("== 屏幕点 → 桌面 → SubViewport 往返 ==")
	for uv in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
		var world: Vector3 = t3.table_mesh.global_transform * TableGeometry.uv_to_world(uv, t3.TABLE_SIZE)
		var screen_pt: Vector2 = t3.camera.unproject_position(world)
		var got = t3.screen_to_viewport(screen_pt)
		var want := TableGeometry.uv_to_viewport(uv, win)
		_check(got != null and (got as Vector2).distance_to(want) < 2.0,
			"UV %s：屏幕 %s → SubViewport %s（期望 %s）" % [uv, screen_pt, got, want])
	# 「打不到桌面」在视口内不可达：俯角 50° − 垂直半 FOV 27.5° = 22.5° > 0，
	# 于是屏幕内每条射线都朝下、必与无限大的水平桌面相交（只是可能落在桌面之外）。
	# 所以用视口正上方足够高的点（射线翻过水平线）来钉住 hit_floor 的 null 路径。
	var vr: Rect2 = t3.get_viewport().get_visible_rect()
	_check(t3.screen_to_viewport(Vector2(vr.size.x * 0.5, -vr.size.y * 2.0)) == null,
		"射向天空的点（视口上方两屏高）返回 null")
	# 反之：桌面之外的屏幕点仍给坐标，只是落在 SubViewport 矩形之外（设计稿 §6.2 的
	# 平面是无界的），SubViewport 内的 2D 控件自己会忽略越界点。
	var off = t3.screen_to_viewport(Vector2(2.0, 2.0))
	_check(off != null and not win.has_point(off as Vector2),
		"桌面之外的屏幕点返回贴图窗口外的坐标（实得 %s）" % off)

	# ---- 反变换（Task 3b）：棋盘画布坐标 → 屏幕坐标 ----
	# 为什么必须单独钉：BoardView 搬进 SubViewport 后，tile/token/wheel_screen_pos 返回的是
	# 0..2048 的画布坐标，而消费它们的屏幕层 HUD 活在窗口空间（1280×800）。少了这条反变换，
	# 格详情卡会被 clamp 到屏幕边缘、两处飘字错位（正是 Task 3 实测到的现象）。
	print("== 屏幕 ↔ SubViewport 往返（反变换）==")
	for uv in [Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(0.75, 0.75)]:
		var screen_pt: Vector2 = t3.camera.unproject_position(
			t3.table_mesh.global_transform * TableGeometry.uv_to_world(uv, t3.TABLE_SIZE))
		var vp_pt = t3.screen_to_viewport(screen_pt)
		_check(vp_pt != null, "正变换可解 UV %s" % uv)
		if vp_pt == null:
			continue
		var back = t3.viewport_to_screen(vp_pt)
		_check(back != null and (back as Vector2).distance_to(screen_pt) < 2.0,
			"反变换来回一致：屏幕 %s → vp %s → 屏幕 %s" % [screen_pt, vp_pt, back])
	# 负路径：桌面之外的 SubViewport 坐标（画布矩形外）不算「桌面上的点」，返回 null。
	_check(t3.viewport_to_screen(Vector2(-50.0, -50.0)) == null,
		"画布外的坐标返回 null（不是无限平面上的任意点）")

	print("== 视角推移：端点、夹取与单调平滑 ==")
	# 0 = 3D 第一人称（50°、手里有牌），1 = 2D 桌面（88°、只看地图）。取代批次 2 的滚轮推拉
	#（`dolly` 已整个删除，见设计稿 §四）—— 滚轮现在改的是**目标值**，相机沿一条轨道连续推移。
	t3.snap_view(0.0)
	_check(is_equal_approx(t3.view_t, 0.0), "3D 端 view_t = 0")
	# 俯角 = 相机位置矢量（相对注视点）与竖直方向的夹角余角，口径同上面容器结构那条。
	var tilt3d := 90.0 - rad_to_deg(t3.camera.global_position.angle_to(Vector3.UP))
	_check(absf(tilt3d - t3.CAM_TILT_DEG) < 1.0,
		"3D 端俯角 = %.0f°（实得 %.1f°）" % [t3.CAM_TILT_DEG, tilt3d])
	t3.snap_view(1.0)
	_check(is_equal_approx(t3.view_t, 1.0), "2D 端 view_t = 1")
	var tilt2d := 90.0 - rad_to_deg(t3.camera.global_position.angle_to(Vector3.UP))
	_check(absf(tilt2d - t3.CAM_TILT_2D_DEG) < 1.0,
		"2D 端俯角 = %.0f°（实得 %.1f°）" % [t3.CAM_TILT_2D_DEG, tilt2d])
	# 整条轨道桌面都要留在画面里：把桌子的四个角投影到屏幕，全部落在视口内、且**留有余量**。
	# 屏幕尺取**真实可见矩形**（同下面 T-a），不写死 1280×800 —— 视口尺寸一旦与假设不符，
	# 写死的数字就变成"拿错了尺子"，量出来的结论没有意义。
	#
	# **采样加密到 21 档**（view_t 从 0 到 1 每 0.05 一档），不是只取 0 / 0.5 / 1 三点：
	# **批次 10 T2 收到相机之后，最紧的一档落在 3D 端**（wt=0.00、余量 **81.6px**，两端 81.6 / 112.1px）
	# —— 相机一近，3D 端自己成了全轨最紧处；"中段最紧"是批次 5~9 的形态（当时 3D 端离得远，
	# 中段被那笔"俯角与距离一起插值"压得最紧：批次 10 T1 相机仍 5.2 时是 wt=0.40、余量 124.2px）。
	# 3 点采样距真实最差点只差一点 —— 那是运气好，不是被钉住了。
	# （注：**取景判据 = 桌垫四角**（`TABLE_SIZE`），不是木桌四角。木桌四角（±4.7/±3.513）在 3D 端
	#   **只有近端两个出画**（实测 -74.6px）、**远端两个一直在画面内**（+183.9px，整条轨道最紧仍
	#   +50.7px）—— "四角全出画"是被**远端那两个还在画面内**证伪的，**不是**被"最紧 -108.1px"
	#   证伪的（"最紧"= 最小余量，为负与"四角全出画"可以并存）；四角全出画从来不成立。
	#   见 `table_3d.CAM_DIST` 那段。）
	# 加密 + 断言「每一档的最小余量 > 5 屏幕像素」才真正把最紧的一档钉住：
	# 一旦把 VIEW_DIST_2D 调小到贴边，这里必红。余量 = 四角到视口四边距离的最小值。
	var min_margin := INF
	var min_margin_wt := -1.0
	var margin_log := ""
	# 四角一律从**桌垫**（TABLE_SIZE）现取，不写死 ±4：桌面不再是正方形（进深由窗口比例定）。
	# 为什么是桌垫而不是外圈木纹：木纹是"桌子本身"，第一人称下桌子伸出画面是自然的；
	# 要全程入画的是**看得见的棋面**（桌垫）。
	var hw: float = t3.TABLE_SIZE.x * 0.5
	var hd: float = t3.TABLE_SIZE.y * 0.5
	for i in 21:
		var wt := i * 0.05
		t3.snap_view(wt)
		var m := INF
		for sx in [-hw, hw]:
			for sz in [-hd, hd]:
				var sp: Vector2 = t3.camera.unproject_position(Vector3(sx, 0.0, sz))
				m = minf(m, minf(minf(sp.x, vr.size.x - sp.x), minf(sp.y, vr.size.y - sp.y)))
		margin_log += "%.0f " % m
		if m < min_margin:
			min_margin = m
			min_margin_wt = wt
	_check(min_margin > 5.0,
		"整条轨道 21 档都留有余量（最小 %.1f px @ view_t=%.2f，须 > 5px；每档余量 %s）"
			% [min_margin, min_margin_wt, margin_log])
	# 【R42】只钉「四个角都在画面内」是能被骗过去的：把 VIEW_DIST_2D 调大让桌面整体变小，
	# 四角照样落在画面内，而 2D 端就成了一张小图 —— 验收要求是「始终在画面内**且大小接近**」。
	# 所以再钉一条：两端桌面投影**包围盒的面积比**必须落在 [0.6, 1.6]（用 unproject_position
	# 把四角投影出来算包围盒）。少了这条，"把桌面缩小"这种退化会全绿通过。
	var boxes: Array = []
	for wt in [0.0, 1.0]:
		t3.snap_view(wt)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for sx in [-hw, hw]:
			for sz in [-hd, hd]:
				var sp: Vector2 = t3.camera.unproject_position(Vector3(sx, 0.0, sz))
				mn = mn.min(sp)
				mx = mx.max(sp)
		boxes.append(Rect2(mn, mx - mn))
	var area_ratio: float = (boxes[1] as Rect2).get_area() / (boxes[0] as Rect2).get_area()
	_check(area_ratio > 0.6 and area_ratio < 1.6,
		"两端桌面投影大小接近（面积比 %.2f，须在 [0.6,1.6]；3D 端 %s / 2D 端 %s）"
			% [area_ratio, boxes[0], boxes[1]])
	# ---- 批次 10 T2：钉住"字更大"的可执行判据 = 一格的**屏幕宽度** ----
	# 前面两条（余量 / 面积比）只保证「整块桌垫在画面里、两端大小接近」——**只把相机往后退**
	# 就照样全绿，而桌子在屏幕里整体缩小、"字更大"这个本批目标恰恰落空。
	#（**别拿"桌垫与相机等比一起往外挪"来推这条**：那是自相似变换，两条守卫与格子屏幕宽
	#  都不会变 —— 那种挪法说明不了任何事。这条拦的是**只动相机**那一档。）
	# 补一条**绝对尺寸**：
	# 取**最不利**的一格（远端正中：50° 俯角下它被透视压得最扁），量它四角投影的包围盒宽。
	t3.snap_view(0.0)
	await process_frame
	t3.board.fit_overview(true)      # 量格宽要 BoardView 的取景变换（_view_from_world）是当前态
	await process_frame
	var probe_idx: int = t3.board.grid_to_index(GameData.BOARD_COLS / 2, 0)   # 远端正中那格
	var probe_w3: float = _tile_screen_w(t3, probe_idx)
	t3.snap_view(1.0)
	await process_frame
	var probe_w2: float = _tile_screen_w(t3, probe_idx)
	t3.snap_view(0.0)
	print("    格子屏幕宽（批次 10 T2）：3D 端 %.1fpx / 2D 端 %.1fpx（收相机前基线 34.5 / 37.9）"
		% [probe_w3, probe_w2])
	# **下限按实测基线修正，不是许愿值**（计划 Step 1 的注 + Ruling R3）：计划初稿写的 70px
	# 是"许愿值"（作者估的基线 ~63px 并未实测）。量出来的起点是 **34.5px（3D）/ 37.9px（2D）**
	# ⚠ **这一对是【几何改完、相机还没动】时的值**（T2 的 BASE = T1 之后），**不是批次 9 的基线**；
	# 批次 9 的基线只能**推算** ≈ 32.6 / 35.9px（= 34.5/1.0572、37.9/1.0572 —— 批次 9 没量过格宽）。
	# ⇒ 门槛取 `ceil(b × 1.10)`（本批目标是"确实变大了"，取 10% 作保守门槛），到得了就钉它、
	# 到不了（几何上限）就钉 `m × 0.98`（只拦回退）并如实写明"只到 Xpx"。
	#   * **2D 端到得了**：m = 42.8px ≥ ceil(37.9×1.10) = **42** ⇒ 钉 42。
	#   * **3D 端到不了**：受**台灯可见**那条（`layout_test` 台灯段：灯罩屏幕包围盒与画面
	#     相交占比 ≥ 0.5）顶住 —— 相机再近、灯罩再往左出画就红（4.60 时已跌到 0.48）。
	#     收完的 m = **37.6px**，比 38（= ceil(34.5×1.10)）差 0.4px ⇒ 按 R3 后半支钉 **36.8**。
	# **两条前提写在这里，免得后人把这条当"字的大小"本身读**：
	#   ① 这是**代理量**：`_tile_screen_w` 量的是**格子的屏幕包围盒宽**，它只在 **`TILE` 与格内
	#      字号都不变**时才与"屏幕上那格字"成比例（本批**两者都没动** —— 动任何一个，这条就得重取）；
	#   ② 探针只守**远端正中**那一格（`probe_idx = grid_to_index(BOARD_COLS/2, 0)`）—— **远端
	#      【角】格没被覆盖**（角格通常投影更宽 ⇒ 这条偏保守，宁可漏也不误红）。
	_check(probe_w3 >= 36.8,
		"3D 端格子屏幕宽 ≥ 36.8px（实得 %.1f；收相机前 34.5，目标 38 因台灯可见那条顶住只到 37.6）"
			% probe_w3)
	_check(probe_w2 >= 42.0,
		"2D 端格子屏幕宽 ≥ 42px（实得 %.1f；收前 37.9，门槛 = ceil(37.9×1.10)）" % probe_w2)
	# 滚轮改的是目标值，不是硬切
	t3.snap_view(0.0)
	t3.set_view(1.0)
	_check(is_equal_approx(t3.view_t, 0.0) and is_equal_approx(t3.view_target, 1.0),
		"set_view 只改目标、当前值不动（不是硬切）")
	# 逐帧平滑：单调逼近且不发散（每帧采一次样）
	var prev: float = t3.view_t      # t3 是运行期 load 出来的（Variant），这里得写明类型
	var all_monotone := true
	for i in 60:
		await process_frame
		if t3.view_t < prev - 0.0001:
			all_monotone = false
		prev = t3.view_t
	_check(all_monotone, "60 帧内 view_t 单调不回头")
	# 「基本到位」按**真实时间**判，不按帧数：VIEW_SNAP 是帧率无关的指数逼近（e^-6 每秒），
	# 而无头下 60 帧只走了 0.4 秒上下（一帧跑多快由机器决定）—— 按帧数等会随机器快慢假红。
	# e^-6 ≈ 0.25%，1 秒足够到位；上限 3 秒兜底，免得万一不动时把测试挂死。
	var t0 := Time.get_ticks_msec()
	while absf(t3.view_t - 1.0) > 0.005 and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	_check(absf(t3.view_t - 1.0) < 0.05,
		"约 1 秒内基本到位（实得 %.3f，用时 %d ms）" % [t3.view_t, Time.get_ticks_msec() - t0])
	t3.snap_view(0.0)

	print("== 滚轮 → 视角推移（事件注入端到端）==")
	# 本批次头号特性是「滚轮驱动视角推移」，但全 tests 里此前**没有任何一处注入过滚轮事件**
	# （只有 LEFT / RIGHT）—— 方向接反、或滚轮分支漏掉 `set_input_as_handled`，都会静默通过。
	# 夹具与下面事件注入块同源：`root.push_input` 一个真实 `InputEventMouseButton`。
	# **不 await 就断言**：滚轮走的是 `set_view`（改目标），若它错走成"当场改 view_t"，
	# 这条会红 —— 这正是「是推移不是硬切」在真输入链路上的那半。
	t3.snap_view(0.0)
	var step: float = t3.VIEW_STEP
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	root.push_input(wheel_up)
	_check(is_equal_approx(t3.view_target, step) and is_equal_approx(t3.view_t, 0.0),
		"滚轮向前一格 ⇒ 目标 +VIEW_STEP（实得 %.2f），当前值仍 0（推移不是硬切）" % t3.view_target)
	await process_frame
	_check(t3.view_t > 0.0 and t3.view_t <= step + 0.0001,
		"注入后当前值朝目标走且不过冲（实得 %.3f，目标 %.2f）" % [t3.view_t, t3.view_target])
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	root.push_input(wheel_down)
	_check(is_equal_approx(t3.view_target, 0.0),
		"滚轮向后一格 ⇒ 目标减回 3D 端（实得 %.2f）" % t3.view_target)
	await process_frame
	# 连推到端点：4 格到 1.0，再补 6 格 —— 目标必须**夹在 [0,1]**，不会累积出"过冲"
	# （VIEW_STEP=0.25 ⇒ 10 格名义上是 2.5；少了 clampf 这里就是 2.5）。
	t3.snap_view(0.5)
	for i in 10:
		root.push_input(wheel_up)
		await process_frame
	_check(is_equal_approx(t3.view_target, 1.0) and t3.view_t <= 1.0 + 0.0001,
		"连推 10 格到 2D 端 ⇒ 目标夹在 1.0 不过冲（实得目标 %.2f / 当前 %.3f）"
			% [t3.view_target, t3.view_t])
	t3.snap_view(0.5)
	for i in 10:
		root.push_input(wheel_down)
		await process_frame
	_check(is_equal_approx(t3.view_target, 0.0) and t3.view_t >= -0.0001,
		"连推 10 格到 3D 端 ⇒ 目标夹在 0.0 不过冲（实得目标 %.2f / 当前 %.3f）"
			% [t3.view_target, t3.view_t])
	t3.snap_view(0.0)

	print("== 事件注入端到端：屏幕点 → 3D 映射 → SubViewport 内的 2D 控件 ==")
	# 先用**真接口**把视角推离默认档再点（review 指出的结构缺口：只验"默认视角下点得中"
	# 是不够的 —— 相机一旦被摆到桌面之下（y<0），射线与桌面交于 t<0 被 Plane.intersects_ray
	# 拒绝 ⇒ screen_to_viewport 对所有屏幕点返回 null ⇒ 下面这几条必红）。
	t3.snap_view(0.4)
	# 在 SubViewport 里挂一个铺满的探针控件（后加 = 盖在 BoardView 之上），
	# 验证整条链：屏幕点 push 进根视口 → 3D 容器算出 SubViewport 坐标 → push_input 送达 2D 控件。
	var probe := Control.new()
	probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	probe.mouse_filter = Control.MOUSE_FILTER_STOP
	t3.viewport.add_child(probe)
	var got_events: Array = []
	probe.gui_input.connect(func(ev: InputEvent) -> void: got_events.append(ev))
	await process_frame
	var mid_world: Vector3 = t3.table_mesh.global_transform * TableGeometry.uv_to_world(Vector2(0.5, 0.5), t3.TABLE_SIZE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = t3.camera.unproject_position(mid_world)
	root.push_input(click)
	await process_frame
	_check(got_events.size() == 1, "SubViewport 内的 2D 控件收到 1 个点击（实得 %d）" % got_events.size())
	if got_events.size() == 1:
		var ev_mb := got_events[0] as InputEventMouseButton
		var got_pos: Vector2 = ev_mb.position if ev_mb != null else Vector2(-9999.0, -9999.0)
		_check(got_pos.distance_to(win.get_center()) < 2.0,
			"控件收到的坐标是贴图窗口中心（棋盘中心，实得 %s）" % got_pos)
	# 悬停同理（InputEventMouseMotion）
	got_events.clear()
	var mm := InputEventMouseMotion.new()
	mm.position = click.position
	root.push_input(mm)
	await process_frame
	_check(got_events.size() == 1 and (got_events[0] as InputEventMouseMotion) != null,
		"悬停（MouseMotion）同样送到 2D 控件（实得 %d）" % got_events.size())

	# ---- 批次 3 Task 1：实体物件先于桌垫内容消费点击 ----
	# 这是本任务唯一的新运行时行为：on_table_click 返回 true = 这次点击落在实体上，2D 棋盘
	# 不该知道它发生过。三条覆盖：消费 / 放行 / 默认态。夹具沿用上面那套（真坐标 push_input
	# 进根视口 → 3D 映射 → SubViewport 内的探针控件）。
	print("== 实体物件先消费点击（on_table_click）==")
	var seen_px: Array = []
	var seen_btn: Array = []
	var at_center := func(_px: Vector2, _btn: int) -> bool:
		seen_px.append(_px)
		seen_btn.append(_btn)
		return true
	t3.on_table_click = at_center
	var pc := InputEventMouseButton.new()
	pc.button_index = MOUSE_BUTTON_LEFT
	pc.pressed = true
	pc.position = click.position        # 与上面同一条链：屏幕点 → 桌面中心
	got_events.clear()
	root.push_input(pc)
	await process_frame
	_check(got_events.is_empty(), "回调返回 true：按下被消费，棋盘收不到（实得 %d）" % got_events.size())
	# 回调拿到的必须是**画布像素**：实体层的命中判定（转盘半径、手牌矩形）全在画布坐标系里做，
	# 这里给错了坐标系，命中就会整体错位 —— 而这在"收到没收到事件"上完全看不出来。
	_check(seen_px.size() == 1 and (seen_px[0] as Vector2).distance_to(win.get_center()) < 2.0,
		"回调收到的是画布像素坐标（实得 %s，期望 ≈%s）" % [seen_px, win.get_center()])
	# 按键也要原样带过去：实体层靠它分辨语义（手牌左键选中 / 右键丢弃、转盘只吃左键）。
	# 少传这个参数会让回调签名对不上（Invalid call）—— 这条钉住「传了、且传对了」。
	_check(seen_btn.size() == 1 and int(seen_btn[0]) == MOUSE_BUTTON_LEFT,
		"回调收到的是按键（实得 %s，期望 LEFT=%d）" % [str(seen_btn), MOUSE_BUTTON_LEFT])

	# 配对的松开也要吞掉。反例（review 实测过的那条）：先在桌垫上左键按下（转发，2D 侧
	# `_dragging = true`）→ 再在转盘上右键按下（被实体消费，不转发）→ 右键松开：此时左键还
	# 按着，`board_view.gd:902` 不会清 `_dragging`，于是松开走到 `:900-901` 的 cancel_clicked
	# —— 一次明明被实体吃掉的点击，却给 2D 板子送了个取消。
	got_events.clear()
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pc.position
	root.push_input(rel)
	await process_frame
	_check(got_events.is_empty(), "被消费按下的配对松开也被吞掉（实得 %d）" % got_events.size())

	# 放行：返回 false = 没落在实体上，照旧送进 SubViewport。
	t3.on_table_click = func(_px: Vector2, _btn: int) -> bool: return false
	got_events.clear()
	var pc2 := InputEventMouseButton.new()
	pc2.button_index = MOUSE_BUTTON_LEFT
	pc2.pressed = true
	pc2.position = click.position
	root.push_input(pc2)
	await process_frame
	_check(got_events.size() == 1, "回调返回 false：照旧转发进 SubViewport（实得 %d）" % got_events.size())

	# 默认态：没接回调（批次 3 Task 1 的常态）时一行都不拦 —— 上面所有 2D 交互因此零回归。
	t3.on_table_click = Callable()
	got_events.clear()
	var pc3 := InputEventMouseButton.new()
	pc3.button_index = MOUSE_BUTTON_LEFT
	pc3.pressed = true
	pc3.position = click.position
	root.push_input(pc3)
	await process_frame
	_check(got_events.size() == 1, "回调为空（Callable()）：默认不拦任何点击（实得 %d）" % got_events.size())

	# 旗标的生命期：只该覆盖「被消费的按下 → 它的松开」这一段。两条边界分别钉住：
	# （a）同一个键又按下 = 上一次配对早就断了（松开的事件没送到），旗标必须让位给新的一次，
	#     否则新按下的**松开**会被误吞 —— 而新按下的按下是转发过的，2D 侧正等着那个松开。
	t3.on_table_click = func(_px: Vector2, _btn: int) -> bool: return true
	var pa := InputEventMouseButton.new()
	pa.button_index = MOUSE_BUTTON_LEFT
	pa.pressed = true
	pa.position = click.position
	root.push_input(pa)                       # 被消费 → 旗标 = 左键
	await process_frame
	t3.on_table_click = func(_px: Vector2, _btn: int) -> bool: return false
	var pa2 := InputEventMouseButton.new()
	pa2.button_index = MOUSE_BUTTON_LEFT
	pa2.pressed = true
	pa2.position = click.position
	got_events.clear()
	root.push_input(pa2)                      # 同一个键又按下、这次转发
	await process_frame
	_check(got_events.size() == 1, "同键再次按下被转发（实得 %d）" % got_events.size())
	var ra := InputEventMouseButton.new()
	ra.button_index = MOUSE_BUTTON_LEFT
	ra.pressed = false
	ra.position = click.position
	got_events.clear()
	root.push_input(ra)
	await process_frame
	_check(got_events.size() == 1,
		"旧旗标不让位的话，这次松开会被误吞（实得 %d）" % got_events.size())

	# （b）别的键打不到桌面（射线翻过水平线）时**不能**清旗标：旗标按键记，只可能被同一个键
	#     的松开消费，顺手清掉就会让那个配对的松开漏进 2D。
	t3.on_table_click = func(_px: Vector2, _btn: int) -> bool: return true
	var pb := InputEventMouseButton.new()
	pb.button_index = MOUSE_BUTTON_LEFT
	pb.pressed = true
	pb.position = click.position
	root.push_input(pb)                       # 被消费 → 旗标 = 左键
	await process_frame
	var pmiss := InputEventMouseButton.new()
	pmiss.button_index = MOUSE_BUTTON_RIGHT
	pmiss.pressed = true
	pmiss.position = Vector2(vr.size.x * 0.5, -vr.size.y * 2.0)   # 打不到桌面
	root.push_input(pmiss)
	await process_frame
	got_events.clear()
	root.push_input(ra)                       # 左键的配对松开：仍须被吞掉
	await process_frame
	_check(got_events.is_empty(),
		"别的键打不到桌面也不清旗标：配对松开仍被吞（实得 %d）" % got_events.size())
	t3.on_table_click = Callable()

	# ---- 批次 3 Task 1：3D 物件层地基 ----
	# props 是实体物件（转盘 / 两摞牌堆 / 手牌）的父节点，与桌垫**共用同一套 UV 坐标系**：
	# 物件摆位一律走 canvas_px_to_world（画布像素 → 桌面世界），而不是另立一套坐标。
	# 这条往返就是"共用坐标系"的可执行定义 —— 两套坐标系一旦漂移，往返立刻对不上。
	# 同时钉住 y：画布中心落在桌面上、与桌垫齐平，物件才不会浮空或陷进桌子。
	print("== 物件层：画布像素 ↔ 桌面世界 往返 ==")
	_check(t3.props != null, "容器带 props 物件层")
	for px in [Vector2(200, 200), Vector2(1024, 1024), Vector2(1800, 1500)]:
		var w: Vector3 = t3.canvas_px_to_world(px)
		var back: Vector2 = t3.world_to_canvas_px(w)
		_check(back.distance_to(px) < 0.5, "往返一致 %s → %s → %s" % [px, w, back])
	_check(absf(t3.canvas_px_to_world(Vector2(1024, 1024)).y - t3.table_mesh.global_position.y) < 0.01,
		"画布中心落在桌面上（y 与桌垫齐平）")

	# ---- 批次 3 Task 2：可点转盘（桌面实体） ----
	# 这里是**裸 TableView3D**：game.gd 的接线（状态刷新时 _refresh_table_props）根本没跑过，
	# 所以测试自己先建一次，断言的才是「建好之后对不对」。中心与半径一律取 BoardView 的
	# **画布口径**（wheel_screen_pos / wheel_screen_radius）—— wheel_center() 是 _world 局部
	# 坐标，中间还要过 _view_from_world 那一跳，照它建会把转盘摆到错的位置。
	print("== 可点转盘：轮缘 + 命中判定 ==")
	_check(t3.table_props != null, "容器挂了 TableProps")
	if t3.table_props == null:
		# 红跑（TableProps 还没接进来）时这里就会红 —— 下面那些依赖它，跳过而不是崩掉挂死
		_check(false, "TableProps 未就绪，转盘断言整段跳过")
	else:
		var wheel_px: Vector2 = t3.board.wheel_screen_pos()
		var wheel_r: float = t3.board.wheel_screen_radius()
		# 画面半径要对得上**画出来的那个轮子**：拿轮心与轮子外沿（`_world` 局部 +200）
		# 各自过一遍镜头变换，两点距离就是它落在画布上的半径。不能拿 `200 × _zoom` 去比 ——
		# 那是把 wheel_screen_radius 的实现重述一遍，写成什么样都过。
		var wheel_center_w: Vector2 = t3.board.wheel_center()
		var drawn_r: float = t3.board._view_from_world(wheel_center_w + Vector2(200.0, 0.0)) \
			.distance_to(t3.board._view_from_world(wheel_center_w))
		_check(absf(drawn_r - wheel_r) < 0.5,
			"画面半径 == 画出来的轮子外沿到轮心的距离（%.1f vs %.1f 画布像素）" % [drawn_r, wheel_r])
		t3.table_props.build_wheel(wheel_px, wheel_r)
		_check(t3.table_props.wheel_hit(wheel_px), "转盘圆心算命中")
		_check(t3.table_props.wheel_hit(wheel_px + Vector2(wheel_r * 0.5, 0.0)), "半径内算命中")
		_check(not t3.table_props.wheel_hit(wheel_px + Vector2(900.0, 0.0)), "远处不算命中")
		# 实体真的立在那个画布位置上：位置算错（照 wheel_center 建）时这条回算对不上。
		_check(t3.table_props.get_child_count() == 1, "转盘实体已挂进 TableProps（实得 %d 个）"
			% t3.table_props.get_child_count())
		if t3.table_props.get_child_count() == 1:
			var wbody: Node3D = t3.table_props.get_child(0)
			var back_px: Vector2 = t3.world_to_canvas_px(wbody.global_position)
			_check(back_px.distance_to(wheel_px) < 1.0,
				"轮缘圆心落在转盘画布位置上（实得 %s，期望 %s）" % [back_px, wheel_px])
			_check(wbody.global_position.y > t3.table_mesh.global_position.y,
				"轮缘抬在桌垫之上（实得 y=%.3f）" % wbody.global_position.y)
			# 硬要求（review 判定的硬伤）：**中间必须透空** —— 盘面 / 13 个数字 / 转动动画
			# 是玩法反馈本身，不能被实体盖住。圆环才行，圆盘 / 实心圆柱一律不行。
			var tmesh: TorusMesh = null
			if wbody is MeshInstance3D and (wbody as MeshInstance3D).mesh is TorusMesh:
				tmesh = (wbody as MeshInstance3D).mesh as TorusMesh
			_check(tmesh != null, "转盘实体是圆环（不是圆盘 / 实心圆柱）")
			if tmesh != null:
				# 轮缘的径向范围**折回画布像素**再比 —— 走真反变换 world_to_canvas_px，
				# 而不是"世界半径 × 某个换算常数"。那样写等于把实现的常数反解回来
				#（out_r / wheel_r == RIM_OUTER_R 恒成立），比例因子错成什么值都照样过。
				# 这一条才是"表面对齐"的验证：换算错了就红。
				# 注意 TorusMesh 的两个半径是**环的径向范围**（孔洞边缘 / 外沿），不是管子半径。
				var rim_ax: Vector3 = wbody.global_transform.basis.x   # 无旋转时 = (1,0,0)
				var rim_o: Vector3 = wbody.global_position
				var out_px: float = t3.world_to_canvas_px(rim_o + rim_ax * tmesh.outer_radius) \
					.distance_to(wheel_px)
				var in_px: float = t3.world_to_canvas_px(rim_o + rim_ax * tmesh.inner_radius) \
					.distance_to(wheel_px)
				# 1.02 / 0.82 写字面量而不是读 RIM_OUTER_R / RIM_INNER_R：那同样是自指。
				# 这两条同时钉住"轮缘尺寸"这个决定（改动它就得改这里，是故意的）。
				_check(absf(out_px - wheel_r * 1.02) < 2.0,
					"轮缘外沿 == 画出来的轮子外沿 × 1.02（%.1f vs %.1f 画布像素）"
						% [out_px, wheel_r * 1.02])
				# WheelView：数字在 0.63R、扇区外沿 0.93R、金属外圈 0.91~1.0R（相对轮子半径）
				_check(in_px >= wheel_r * 0.63,
					"中间透空到数字之外（孔边缘 %.1f ≥ 数字半径 %.1f 画布像素）"
						% [in_px, wheel_r * 0.63])
				# 管子半径 = 半环宽（两个半径是径向范围，相减即环宽）
				_check((out_px - in_px) * 0.5 >= wheel_r * 0.05,
					"轮缘有可见的厚度、不是一根线（管子半径 %.0f ≥ %.0f 画布像素）"
						% [(out_px - in_px) * 0.5, wheel_r * 0.05])
			# 跟住画面半径：取景 / 抽卡推近都会改 _zoom（滚轮不改 _zoom，它推的是 3D 视角），实体必须跟着变。
			# 只改 transform 与 mesh 尺寸，**不重建节点**（状态广播很频繁）。
			var first_node: Node = t3.table_props.get_child(0)
			var first_mesh: TorusMesh = (first_node as MeshInstance3D).mesh as TorusMesh
			var r_before: float = first_mesh.outer_radius
			t3.table_props.build_wheel(wheel_px, wheel_r * 1.5)
			_check(t3.table_props.get_child_count() == 1 and t3.table_props.get_child(0) == first_node,
				"重复调用只重算尺寸、不重建节点（实得 %d 个）" % t3.table_props.get_child_count())
			_check(absf(first_mesh.outer_radius - r_before * 1.5) < 0.0001,
				"画面半径变大后轮缘跟着放大（%.4f → %.4f）" % [r_before, first_mesh.outer_radius])
			_check(t3.table_props.wheel_hit(wheel_px + Vector2(wheel_r * 1.4, 0.0)),
				"命中半径也跟着放大（%.0f 画布像素处仍算命中）" % (wheel_r * 1.4))

	# ---- 批次 7：筹码堆与体力件整体退场（读数归四角身家条 / 批次 9 的道具弹窗） ----
	# 反向契约：谁把这两条子系统加回来，这几条先红。
	print("== 筹码堆与体力件：接口与节点都已退场（不留空壳） ==")
	var tp3 = t3.table_props
	if tp3 == null:
		_check(false, "TableProps 未就绪，退场断言整段跳过")
	else:
		_check(not tp3.has_method("set_chips"), "set_chips 已退场")
		_check(not tp3.has_method("set_stamina"), "set_stamina 已退场")
		_check(tp3.get_node_or_null("Chips") == null, "桌上没有筹码堆节点")
		_check(tp3.get_node_or_null("Stamina") == null, "桌上没有体力件节点")
		# 常量经 load() 取（不静态写类名，理由见文件顶部那段）
		var S3 = load("res://scripts/table_props.gd")
		var consts3: Dictionary = S3.get_script_constant_map()
		_check(not consts3.has("CHIP_PER"), "CHIP_PER 常量已删")
		_check(not consts3.has("PIP_SIZE"), "PIP_SIZE 常量已删")

	# ---- 批次 3 Task 4：手中牌（显示） ----
	# 本步**只做显示**（点击是 Task 5），但 hand_count / hand_rect / hand_hit 是这一步的交付物。
	# 验收一律走**可观察量**：牌的几何取自节点自己的 mesh + 变换，命中判据走**真实的点击链路**
	#（相机 unproject → t3.screen_to_viewport，与 table_3d._unhandled_input 同一条），
	# 而不是把实现里的 hand_rect 推导再写一遍（那样写成什么样都过）。
	# 显式回 3D 端：本段的量（尤其「命中盒按抬起算」那段 ≥4 画布像素的余量）是在
	# 3D 端取景下量的 —— 前面事件注入那几段把视角推到了中段，不回来的话量的是另一套几何
	#（视角越陡，抬起来那段在屏幕上的错位越小，是几何使然、不是命中盒坏了）。
	t3.snap_view(0.0)
	print("== 手中牌：数量、厚度、品质色 ==")
	var tp4 = t3.table_props
	if tp4 == null:
		_check(false, "TableProps 未就绪，手牌断言整段跳过")
	else:
		var ID4 = load("res://scripts/item_data.gd")
		var vis4 := func(root: Node) -> int:
			var c := 0
			for ch in root.get_children():
				if (ch as Node3D).visible:
					c += 1
			return c
		tp4.set_hand([{"id": "招财猫", "cd": 0}, {"id": "黑卡", "cd": 0}])
		_check(tp4.hand_count() == 2, "两个道具 → 两张手牌（实得 %d）" % tp4.hand_count())
		var hr: Node = tp4.get_node_or_null("Hand")
		_check(hr != null, "手牌父节点在（set_hand 时建）")
		var many4 := []
		if hr != null:      # 父节点缺了（将来被改名 / 删）时只红这一段，别把整个测试带崩
			for i in 7:
				many4.append({"id": "共享单车", "cd": 0})
			tp4.set_hand(many4)
			_check(tp4.hand_count() == 5 and vis4.call(hr) == 5,
				"7 件道具 → 最多摆 5 张（实得 %d 张）" % tp4.hand_count())
			tp4.set_hand([])
			_check(tp4.hand_count() == 0 and vis4.call(hr) == 0, "清空 → 一张都不露")
			# 幂等：池子只建一次，重复 set_hand 不重建节点（每次状态广播都会调它）
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			var pool4: int = hr.get_child_count()
			var first4: Node = hr.get_child(0)
			tp4.set_hand([{"id": "饭卡"}, {"id": "雨伞"}, {"id": "包租婆"}])
			_check(hr.get_child_count() == pool4 and hr.get_child(0) == first4,
				"重复调用不重建手牌节点（%d → %d 张）" % [pool4, hr.get_child_count()])
			# 有厚度（能投影）与品质色：厚度取**节点自己的 mesh**（不比实现常量），
			# 品质色是数据契约（招财猫=白 / 黑卡=橙，取自 ItemData.QUALITY_COLORS）。
			tp4.set_hand([{"id": "招财猫"}, {"id": "黑卡"}])
			var thick4 := true
			var color4 := true
			var want_q := ["白", "橙"]
			for i in 2:
				var mi4 := hr.get_child(i) as MeshInstance3D
				var bm4: BoxMesh = null
				if mi4 != null and mi4.mesh is BoxMesh:
					bm4 = mi4.mesh as BoxMesh
				if bm4 == null or bm4.size.y < 0.01:
					thick4 = false
				var mat4 := mi4.material_override as StandardMaterial3D if mi4 != null else null
				if mat4 == null or not mat4.albedo_color.is_equal_approx(ID4.QUALITY_COLORS[want_q[i]]):
					color4 = false
			_check(thick4, "每张牌都是有厚度的盒子（BoxMesh，厚度 ≥ 0.01 世界单位）")
			_check(color4, "牌身用品质色（招财猫=白 / 黑卡=橙）")
			# 批次 5 Task 3 把牌**放大到 1.5 倍上下**（0.30×0.34 → 0.46×0.54）。
			# 尺寸取**节点自己的 mesh**（不是读常量），下界钉在 0.40/0.48：谁要是缩回批次 3 那档，
			# 这条先红（"明显比批次 3 更大"是本任务的验收项）。
			var size_ok := true
			var bm0 := (hr.get_child(0) as MeshInstance3D).mesh as BoxMesh
			if bm0 == null or bm0.size.x < 0.40 or bm0.size.z < 0.48:
				size_ok = false
			_check(size_ok, "牌比批次 3 明显更大（宽 ≥ 0.40 / 进深 ≥ 0.48，实得 %s）"
				% ("?" if bm0 == null else "%.2f×%.2f" % [bm0.size.x, bm0.size.z]))

			print("== 手中牌：命中盒盖住看得见的那张牌 ==")
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			# 「看得见的那张牌」= 牌**顶面中心**经真实点击链路折回的画布像素：
			# 射线先打到桌面平面、再换算成画布 —— 牌是抬起来、朝自己倾斜的实物，
			# 这个点与牌位在桌面上的落点**不是同一个点**（抬高 = 屏幕上更靠上）。
			var seen4 := func(i: int) -> Vector2:
				var mi := hr.get_child(i) as MeshInstance3D
				var bm: BoxMesh = mi.mesh as BoxMesh
				var top_c: Vector3 = mi.global_transform * Vector3(0.0, bm.size.y * 0.5, 0.0)
				var got = t3.screen_to_viewport(t3.camera.unproject_position(top_c))
				return got if got != null else Vector2(-9999.0, -9999.0)
			var hit_self := true
			var inside := true
			var spread_ok := true
			var centered := true
			for i in 3:
				var px: Vector2 = seen4.call(i)
				hit_self = hit_self and tp4.hand_hit(px) == i
				inside = inside and tp4.hand_rect(i).has_point(px)
				# 命中盒必须按「抬起来」算：整盒比牌位的桌面落点更靠远端。
				#（把矩形直接画在牌位上就会丢掉这一段 —— 玩家看着卡点下去就选不中。）
				var base_px: Vector2 = t3.world_to_canvas_px((hr.get_child(i) as Node3D).global_position)
				spread_ok = spread_ok and (base_px.y - tp4.hand_rect(i).get_center().y) > 4.0
				# 而且盒子得**正好套在**看得见的那张牌上（中心对中心），不是"够大就行" ——
				# 太大就会压住邻牌 / 压住自己那排格子（点过去选错东西）。
				centered = centered and tp4.hand_rect(i).get_center().distance_to(px) < 8.0
			_check(hit_self, "点每张牌看得见的那一面都命中它自己（三张各一次）")
			_check(inside, "牌顶面中心落在自己的命中盒里")
			_check(spread_ok, "命中盒按抬起算：整盒比牌位的桌面落点更靠远端")
			_check(centered, "命中盒的中心就是看得见的那张牌的中心（偏差 < 8 画布像素）")
			# 扇形里左右顺序不能翻：第 0 张在左、第 2 张在右（命中映射跟着牌走）
			_check(tp4.hand_rect(0).get_center().x < tp4.hand_rect(2).get_center().x,
				"命中盒的左右顺序与牌一致（左→右）")
			# 相机一变，实物的**世界位置不动**、可看到的画面全变了 —— 命中盒必须跟着重算，
			# 否则玩家在新视角下照着卡片点却点不中。这里走**真接口**把视角推到中段
			#（50° → 69°，正是滚轮推移与 `--shot` 的 tilt 摆拍会做的事；手搓相机的话，
			# 这段量到的是夹具自己摆的相机数学，而不是 `_apply_camera` 的那一版）来钉这条：
			# **命中盒不是写死的常数**。
			var wpos_before: Vector3 = (hr.get_child(1) as Node3D).global_position
			t3.snap_view(0.5)
			await process_frame
			_check(tp4.hand_hit(seen4.call(1)) == 1, "视角推到中段（50°→69°）后点同一张看得见的那面仍命中它")
			# 而且盒子要跟着**挪**到位（不只是"够宽容"）：缓存住旧视角的盒子会在这里露馅
			_check(tp4.hand_rect(1).get_center().distance_to(seen4.call(1)) < 8.0,
				"换俯角后命中盒重新对准看得见的那张牌（偏差 %.1f 画布像素）"
					% tp4.hand_rect(1).get_center().distance_to(seen4.call(1)))
			_check((hr.get_child(1) as Node3D).global_position.is_equal_approx(wpos_before),
				"换视角不改实物的世界位置（牌钉在固定桌位上）")
			# 再往 2D 端推一段（滚轮推移的同一件事，只是推得更远）：越过淡出窗口（0.65）之后
			# 手牌已经看不见了 —— 批次 4 Task 2 起「看不见就点不到」，hand_hit 直接给 -1。
			# 这条断言原先写的是"推向 2D 端仍命中"，而**那正是批次 4 要改掉的语义**（2D 端出牌
			# 要回 3D），所以改成钉新的那条；「命中盒跟着相机走」由上面 0.5 那档 + 下面这条几何
			# 断言继续钉住（淡出只改显示与命中，不改几何）。
			t3.snap_view(0.7)
			await process_frame
			_check(tp4.hand_hit(seen4.call(1)) == -1,
				"视角推过淡出窗口（0.7）后手牌看不见 ⇒ 不再命中（-1）")
			_check(tp4.hand_rect(1).get_center().distance_to(seen4.call(1)) < 8.0,
				"越过淡出窗口后命中盒几何照旧跟着相机（淡出不改几何）")
			# 取景回 3D 端：下面的位置断言必须在 game.gd 里真实的那一版取景下做
			t3.snap_view(0.0)
			await process_frame
			# 负路径：离得远的点不算命中（-1 是 hand_hit 自己的约定）
			_check(tp4.hand_hit(Vector2(50.0, 50.0)) == -1, "角落不算命中")
			_check(tp4.hand_hit(t3.board.wheel_screen_pos()) == -1, "转盘中心不算命中（那是掷轮的地盘）")
			_check(tp4.hand_rect(-1).size == Vector2.ZERO and tp4.hand_rect(9).size == Vector2.ZERO,
				"越界下标给空矩形（不是崩掉）")

			# Task 5 的选中反馈：选中的那张**抬起来**（命中盒整体往远端挪），其它张不动；
			# -1 / 越界 = 都不选。反馈必须落在**桌上这张牌自己**身上 —— Task 6 拆掉座位卡牌位后
			# board.set_item_selected 会空转，选中就只剩屏幕上这一点可见反馈了。
			print("== 手中牌：选中反馈（抬起）==")
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			await process_frame
			var plain4: Array = []
			for i in 3:
				plain4.append(tp4.hand_rect(i).get_center())
			tp4.set_hand_selected(1)
			_check(tp4.hand_rect(1).get_center().y < plain4[1].y - 4.0,
				"选中的那张抬起来了（画布 y %.0f → %.0f）" % [plain4[1].y, tp4.hand_rect(1).get_center().y])
			_check(tp4.hand_rect(0).get_center().is_equal_approx(plain4[0])
				and tp4.hand_rect(2).get_center().is_equal_approx(plain4[2]),
				"没选中的两张一动不动（只抬被选的那张）")
			tp4.set_hand_selected(-1)
			_check(tp4.hand_rect(1).get_center().is_equal_approx(plain4[1]), "取消选中后落回原位")
			tp4.set_hand_selected(9)
			_check(tp4.hand_rect(1).get_center().is_equal_approx(plain4[1]),
				"越界下标当作「都不选」（不是崩掉、也不是抬错一张）")
			tp4.set_hand_selected(1)
			# 重摆手牌（每次状态广播都会调）不能把选中态弄丢 —— 位置是重摆的，选中是另外贴上去的
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			_check(tp4.hand_rect(1).get_center().y < plain4[1].y - 4.0,
				"重摆手牌后选中的那张仍抬着（画布 y %.0f）" % tp4.hand_rect(1).get_center().y)
			tp4.set_hand_selected(-1)

			# 位置：整排落在**自己面前那条木纹留白**上（批次 5 Task 3 起）—— 在桌垫**之外**、
			# 木桌之内、桌面的近端半幅；不与自己那排格子错位。
			#（批次 3 时代的"不与筹码堆 / 体力件重叠"那两条随两条子系统退场一并作废，见上。）
			print("== 手中牌：落在桌垫前沿的木纹留白上 ==")
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			await process_frame
			# 批次 5 Task 3 把整排**放大 1.5 倍并下移到桌垫下沿之外**（木桌之内那条木纹留白），
			# 所以"落在桌垫之内"这条老断言反过来成真：牌**在桌垫之外**、还在**木桌之内**。
			# 为什么必须这样：放大后整排的屏幕包围盒高 174 画布像素，而桌垫下沿那两条空档
			# （格子下沿→原阶段按钮上沿、原按钮下沿→桌垫下沿）各只有 72 像素 —— 塞不下（见 HAND_BASE_PX）。
			var mat_px4: Rect2 = t3.board.mat_rect_px()
			var on_mat4 := 0          # 落在桌垫**之内**的张数（今天应当为 0）
			var off_wood4 := 0        # 飞出木桌沿的张数（应当为 0）
			var sunk4 := 0
			var nearest4 := 0.0
			# 「还在木桌之内」一律用**世界坐标**量，**不能**拿画布像素折算：批次 10 把木纹收窄到
			# 0.7（= 176.75 画布像素）之后，木纹边界在画布像素里是 x ∈ [-162.8, 2210.8] /
			# y ∈ [137.0, 1911.0] —— **左右两条边仍落在画布之外**（画布才 0..2048）、上下两条
			# 却已落进画布。也就是说"在画布内"这条尺子在 x 上对木桌**恒真**（画布内的点全都满足），
			# 什么都证明不了（正是本文件反复警告的那类）。世界口径下木桌 = 桌垫半幅 + WOOD_FRAME，
			# 这条**真会失败**（把整排再往下挪一截就越界了）。
			var wood_half: Vector2 = t3.TABLE_SIZE * 0.5 + Vector2(t3.WOOD_FRAME, t3.WOOD_FRAME)
			for i in 3:
				var mi := hr.get_child(i) as MeshInstance3D
				var bp: Vector2 = t3.world_to_canvas_px(mi.global_position)
				if mat_px4.has_point(bp):
					on_mat4 += 1
				if absf(mi.global_position.x) > wood_half.x or absf(mi.global_position.z) > wood_half.y:
					off_wood4 += 1
				if mi.global_position.y <= t3.table_mesh.global_position.y:
					sunk4 += 1
				nearest4 = maxf(nearest4, bp.y)
			_check(on_mat4 == 0, "手牌整排落在**桌垫之外**那条木纹留白上（落在桌垫内的 %d 张）" % on_mat4)
			_check(off_wood4 == 0, "手牌都还在木桌之内（飞出桌沿 %d 张；木桌半宽 %.2f / 半深 %.2f）"
				% [off_wood4, wood_half.x, wood_half.y])
			_check(sunk4 == 0, "手牌都浮在桌面上（陷进去 %d 张）" % sunk4)
			# 看得见的那块（投影盒）同样不许被**画布边缘**裁掉 —— 牌是抬起来 + 倾斜的实物，
			# 它的屏幕包围盒比桌面落点更靠外（近端）。
			# **批次 10 起这条比"在木桌内"松**（别再照抄"木桌比画布大一圈"那句旧话）：木纹现在
			# 上下两条边在画布内（y 到 1911.0）、左右两条在外 ⇒ 投影盒的下沿实际上先撞木桌外沿。
			# 实测（满手 5 张）投影盒并集 y ∈ [1724.6, 1899.4]：下沿离木桌外沿的屏幕位置（1911.0）
			# 还有 11.6px。**这条断言只兜"被画布边缘裁掉"**；"不越木桌外沿"由上面那条世界口径的
			# 牌心判据 + HAND_BASE_PX 的居中取值保证（见 `table_props.HAND_BASE_PX`）。
			var canvas_rect4 := Rect2(Vector2.ZERO, Vector2(t3.VP_SIZE))
			var box_out4 := 0
			for i in 3:
				if not canvas_rect4.encloses(tp4.hand_rect(i)):
					box_out4 += 1
			_check(box_out4 == 0, "连看得见的那块也没被画布边缘裁掉（出界 %d 张；画布 %s）"
				% [box_out4, canvas_rect4])
			_check(nearest4 > mat_px4.get_center().y, "手牌在自己这半张桌子（近端，最靠里一张画布 y=%.0f）" % nearest4)
			# 批次 7：筹码堆 / 体力件已退场 ⇒ 原来这段"手牌不与它们重叠"的比较失去参照物，作废。
			# 手牌落位的硬约束由上面那几条承担（在木纹留白上 / 不压棋盘 / 不被画布边缘裁掉）。

			# ---- 批次 4 Task 2：手牌随视角淡出（看不见就点不到） ----
			# 视角量 view_t 是**纯本地表现**（不进 s_state、不同步）：3D 端看得见也点得到，
			# 2D 端看不见也点不到 —— 出牌要回 3D。核心只有一条规则：`hand_hit` 在淡到看不见时
			# 返回 -1；`game._on_table_click` 判手牌只走 hand_hit，于是 game.gd 一行都不用改
			#（右键丢弃同理：丢弃和出牌一样要回 3D，不为它开特例）。
			# 断言一律走可观察量（hand_alpha 的返回值、材质上的 alpha、Hand 节点的 visible），
			# 不把 _apply_hand_alpha 的推导再写一遍。
			print("== 手牌随视角淡出：看不见就点不到 ==")
			var body5 := (hr.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}])
			tp4.set_view_t(0.0)
			_check(tp4.hand_alpha() > 0.99, "3D 端手牌全不透明（实得 %.2f）" % tp4.hand_alpha())
			_check((hr as Node3D).visible and body5.albedo_color.a > 0.99,
				"3D 端整排可见、牌身材质也是不透明的（实得 %.2f）" % body5.albedo_color.a)
			# E（终审修复）：3D 端（a = 1.0）必须走**不透明模式**，不进透明队列 ——
			# 透明队列会改掉深度写入与投影，而批次 3 重开阴影、批次 6 重做光照都指望实物按不透明走。
			_check(body5.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
				"3D 端牌身材质是不透明模式（不进透明队列，深度写入 / 投影正常）")
			# 牌面单独一档：图标 PNG 带透明边，**不能**跟牌身一样用 DISABLED（透明区会渲染成
			# 一整块不透明方块、把图标糊住 —— 出图核对过）。3D 端用 ALPHA_SCISSOR：透明区照样
			# 裁掉、图标不被糊住，而它仍在**不透明队列**里写深度、能投影。
			var face5 := (hr.get_child(0) as Node3D).get_node_or_null("Face") as MeshInstance3D
			var face_mat5 := face5.material_override as StandardMaterial3D if face5 != null else null
			_check(face_mat5 != null and face_mat5.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"3D 端牌面走 alpha 裁剪（透明区裁掉、仍写深度，不是 alpha 混合）")
			_check(tp4.hand_hit(tp4.hand_rect(0).get_center()) == 0, "3D 端点得到第一张")
			tp4.set_view_t(1.0)
			_check(tp4.hand_alpha() < 0.02, "2D 端手牌基本看不见（实得 %.3f）" % tp4.hand_alpha())
			_check(not (hr as Node3D).visible, "2D 端整排手牌节点已隐藏（不是只把材质调淡）")
			_check(tp4.hand_hit(tp4.hand_rect(0).get_center()) == -1,
				"2D 端点不到（hand_hit 返回 -1）")
			tp4.set_view_t(0.5)
			var mid5: float = tp4.hand_alpha()
			_check(mid5 > 0.02 and mid5 < 0.98, "中段是过渡值（实得 %.2f）" % mid5)
			_check((hr as Node3D).visible, "中段整排仍可见（只是半透明）")
			_check(absf(body5.albedo_color.a - mid5) < 0.01,
				"半透明度真贴到了牌身材质上（材质 %.2f / hand_alpha %.2f）"
					% [body5.albedo_color.a, mid5])
			# 淡出中（0 < a < 1）才切到 ALPHA 混合 —— 否则 albedo.a 不起作用，淡不动。
			# 整排隐藏（a ≤ 0.02）时 _apply_hand_alpha 会早退、材质保持上一档，所以"透明模式"
			# 这一半在**淡出中段**钉（2D 端那半由"整排隐藏 + hand_hit=-1"那几条守着）。
			_check(body5.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
				"淡出中牌身材质切到 alpha 混合（否则 albedo.a 不起作用；3D 端那半见上条不透明模式）")
			if face_mat5 != null:
				_check(face_mat5.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
					"淡出中牌面也切到 alpha 混合（scissor 做不出半透明）")
			# 重摆会把牌身颜色**整份重写**（品质色 / 选中提亮 / 待确认丢弃都是这一笔）——
			# 那一笔若顺带把 alpha 写回 1.0，半透明的牌就会在视角不动时"弹"回不透明
			# （视角不再变化 ⇒ set_view_t 早退 ⇒ 再也没人来修）。选中 / 取消各走一遍这条路径。
			tp4.set_hand_selected(1)
			_check(absf(body5.albedo_color.a - mid5) < 0.01,
				"重摆（选中）之后仍是半透明（实得 %.2f，应为 %.2f）" % [body5.albedo_color.a, mid5])
			tp4.set_hand_selected(-1)
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}])
			_check(absf(body5.albedo_color.a - mid5) < 0.01,
				"重摆手牌之后仍是半透明（实得 %.2f，应为 %.2f）" % [body5.albedo_color.a, mid5])
			tp4.set_view_t(0.0)

			# 接线：淡出必须由 `_apply_camera()` 末尾推一次完成。推进 `_process` 的循环体里
			# 就会**整条摆拍链路漏掉** —— `_process` 在 view_t == view_target 时早退，而
			# snap_view（测试与全部 `--shot` 摆拍都走它）根本不经过 `_process`。
			print("== 视角量由 _apply_camera 推到手牌（摆拍 / 测试走 snap_view）==")
			t3.snap_view(0.0)
			await process_frame
			_check(tp4.hand_alpha() > 0.99, "snap_view(0) 之后手牌回到全不透明（实得 %.2f）" % tp4.hand_alpha())
			t3.snap_view(1.0)
			_check(tp4.hand_alpha() < 0.02, "snap_view(1) 之后手牌淡到看不见（实得 %.3f）" % tp4.hand_alpha())
			# 滚轮那条路（set_view 改目标 → _process 逐帧推移）也要把 view_t 带到手牌上。
			# 按**真实时间**收敛判，不按帧数：无头下一帧跑多快由机器决定（同 Task 1 的写法）。
			t3.snap_view(0.0)
			t3.set_view(1.0)
			var t5 := Time.get_ticks_msec()
			while tp4.hand_alpha() > 0.02 and Time.get_ticks_msec() - t5 < 3000:
				await process_frame
			_check(tp4.hand_alpha() < 0.02,
				"滚轮推到底后手牌跟着淡掉（view_t=%.3f，实得 alpha %.3f）" % [t3.view_t, tp4.hand_alpha()])
			t3.snap_view(0.0)
			await process_frame
			_check(tp4.hand_alpha() > 0.99, "回 3D 端手牌恢复不透明（实得 %.2f）" % tp4.hand_alpha())

			# ---- 批次 4 验收的另一半：2D 端「转盘仍可掷轮、手牌点不到」 ----
			# 此前没有任何地方在 view_t = 1.0 走一遍 screen_to_viewport → wheel_hit（滚轮 / 取景那几段
			# 只到 0.4，21 档扫描只投影四角）。这两条语义成对钉在这里：2D 端能掷轮、出不了牌。
			print("== 2D 端：转盘仍可掷轮、手牌点不到 ==")
			t3.snap_view(1.0)
			await process_frame
			var wheel_px2: Vector2 = t3.board.wheel_screen_pos()
			var wheel_r2: float = t3.board.wheel_screen_radius()
			tp4.build_wheel(wheel_px2, wheel_r2)   # 按当前口径重摆，命中半径回到 1.0×
			var rim2: Node3D = tp4.get_node_or_null("WheelRim") as Node3D
			_check(rim2 != null, "2D 端找得到转盘实体（WheelRim）")
			if rim2 != null:
				# 整条真链：实体世界坐标 → 3D 相机投影 → 屏幕点 → screen_to_viewport → 画布点 → wheel_hit
				var center_px2 = t3.screen_to_viewport(t3.camera.unproject_position(rim2.global_position))
				_check(center_px2 != null, "2D 端转盘中心仍落在桌面上（screen_to_viewport 不是 null）")
				if center_px2 != null:
					_check(tp4.wheel_hit(center_px2),
						"2D 端点转盘中心仍算命中（画布 %s，轮心 %s）" % [center_px2, wheel_px2])
			# 反向：同一档下，手牌在任何点都不命中 —— 「2D 端能掷轮、出不了牌」是一对语义。
			var miss2 := true
			for p2 in [wheel_px2, tp4.hand_rect(0).get_center(), Vector2(1024.0, 1024.0)]:
				if tp4.hand_hit(p2) != -1:
					miss2 = false
			_check(miss2, "2D 端任何点都点不到手牌（hand_hit 全是 -1）")
			t3.snap_view(0.0)
			await process_frame

	# ---- 批次 5 Task 1：视角量是属性（赋值即推送） ----
	# 批次 4 的终审：`view_t` 曾是**公开 var**，唯一更新点是 `_apply_camera()` ⇒ 任何一句
	# `view_t = x` 都会让相机与物件静默脱钩。手牌正要用同一个推送点（淡出按 view_t 算），
	# 所以把不变量变成结构：setter 里 clamp + 早退 + 调 `_apply_camera()`（推送在它末尾）。
	# 断言走可观察量：**直接**写 view_t，手牌的不透明度与相机俯角都必须跟着变。
	print("== 视角量是属性：直接赋值也推相机与物件（不会静默脱钩）==")
	t3.snap_view(0.0)
	await process_frame
	t3.view_t = 0.7                      # 直接赋值（绕过 snap_view / 滚轮这两条常规入口）
	_check(t3.table_props.hand_alpha() < 0.02,
		"直接写 view_t 也把手牌淡掉了（实得 %.3f）" % t3.table_props.hand_alpha())
	var tilt_direct := 90.0 - rad_to_deg(t3.camera.global_position.angle_to(Vector3.UP))
	_check(tilt_direct > t3.CAM_TILT_DEG + 20.0 and tilt_direct < t3.CAM_TILT_2D_DEG + 1.0,
		"相机也跟着摆过去了（俯角 %.1f° 在 3D 端 %.0f° 与 2D 端 %.0f° 之间）"
			% [tilt_direct, t3.CAM_TILT_DEG, t3.CAM_TILT_2D_DEG])
	t3.view_t = 5.0
	_check(is_equal_approx(t3.view_t, 1.0), "直接写越界值也被夹到 [0,1]（实得 %.2f）" % t3.view_t)
	t3.view_t = -3.0
	_check(is_equal_approx(t3.view_t, 0.0), "负值同样夹到 0（实得 %.2f）" % t3.view_t)
	t3.snap_view(0.0)
	await process_frame

	# ---- 批次 6 Task 2：机会 / 命运两摞实体牌堆 ----
	# 桌垫上最后两处"贴片"（画布上印着的那两摞卡背）实体化。钉四件事：
	#   ① 两摞都在、都**有厚度**（叠层 > 1 —— 一块等厚方砖不算"一摞牌"）；
	#   ② 落点与印在桌垫上的那摞卡背**重合**（走 `board.deck_screen_pos()` —— 与轮缘 / 手牌
	#      同一条 chain：`global_position + _view_from_world(...)`；这里也是 layout_test 后面那段
	#      "牌堆在窗口内"用的口径。**别再自己拼 `_view_from_world`** —— 它是私有方法、且容易漏
	#      `global_position` 那一项，批次 6 Task 3 把这条链收进了公开入口）；
	#   ③ 材质是**不透明档**（批次 4 的教训：ALPHA 混合进透明队列、不写深度、投影就废了）；
	#   ④ 幂等（状态广播每次都调，节点池只建一次）。
	# 身份（哪摞是机会、哪摞是命运）走摞顶面平贴的 Label3D：文字 + 配色两重信号。
	print("== 实体牌堆：两摞有厚度的牌，落在画布牌堆中心上 ==")
	var tpD = t3.table_props
	if tpD == null:
		_check(false, "TableProps 未就绪，牌堆断言整段跳过")
	else:
		t3.board.fit_overview(true)
		var deck_names := ["机会", "命运"]
		var deck_px := {}
		for dn in deck_names:
			deck_px[dn] = t3.board.deck_screen_pos(dn)
		# 脚印与中心都从 BoardView 取（修复波 F：尺寸也要跟印刷图案）——
		# **不写死世界尺寸**：写死就等于把"摞该多大"的实现重述一遍，跟没跟取景都看不出来。
		# 红跑（`deck_screen_size` 还没实现）时不硬调：判红后走老的一条路（同本文件
		# `t3.get("lamp_light")` 那条的写法 —— 少一次脚本错误、后面的断言照跑）。
		var f_ok: bool = t3.board.has_method("deck_screen_size")
		var deck_sz := Vector2.ZERO
		if f_ok:
			deck_sz = t3.board.deck_screen_size("机会")
			tpD.build_decks(deck_px, deck_sz)
		else:
			_check(false, "BoardView 没有 deck_screen_size（修复波 F 未实现）")
			tpD.build_decks(deck_px)
		var dr: Node = tpD.get_node_or_null("Decks")
		_check(dr != null, "牌堆父节点在（build_decks 时建）")
		if dr == null:
			_check(false, "牌堆父节点缺了，后半段跳过")
		else:
			_check(dr.get_child_count() == 2, "两摞都在（实得 %d 摞）" % dr.get_child_count())
			var bodies := {}
			for dn in deck_names:
				var droot: Node3D = dr.get_node_or_null("Deck_%s" % dn) as Node3D
				_check(droot != null, "「%s」那一摞在" % dn)
				if droot == null:
					continue
				# ① 有厚度：层数 > 1 + 叠起来的高度
				var layers: Array = []
				for ch in droot.get_children():
					var mi := ch as MeshInstance3D
					if mi != null and mi.mesh is BoxMesh:
						layers.append(mi)
				_check(layers.size() > 1, "「%s」是叠出来的（%d 层）" % [dn, layers.size()])
				var lo := INF
				var hi := -INF
				var opaque := true
				var shadows := true
				for mi in layers:
					var bm: BoxMesh = (mi as MeshInstance3D).mesh as BoxMesh
					lo = minf(lo, (mi as MeshInstance3D).global_position.y - bm.size.y * 0.5)
					hi = maxf(hi, (mi as MeshInstance3D).global_position.y + bm.size.y * 0.5)
					var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
					if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						opaque = false
					if (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						shadows = false
					bodies[dn] = m
				_check(hi - lo > 0.03, "「%s」有厚度（叠起来 %.3f 世界单位高）" % [dn, hi - lo])
				_check(opaque, "「%s」的材质是不透明档（写深度、投得出影子）" % dn)
				_check(shadows, "「%s」的层都投影（实体的影子是台灯那盏灯给的）" % dn)
				# ② 落点 = 画布上那摞卡背的位置（反算回画布像素再比 —— 不把换算公式重述一遍）
				var back: Vector2 = t3.world_to_canvas_px(droot.global_position)
				_check(back.distance_to(deck_px[dn]) < 1.0,
					"「%s」落在画布牌堆中心上（实得 %s，期望 %s）" % [dn, back, deck_px[dn]])
				# ②b **脚印**也 = 印在桌垫上那摞卡背的整体脚印（修复波 F）。量法同轮缘那条：
				# 把共用 mesh 的宽 / 进深折回**画布像素**再比（走真反变换，不拿"世界尺寸 × 常数"
				# 去比 —— 那是把实现的换算重述一遍，常数错成什么值都照样绿）。
				# 尺寸不跟取景时这里就红：全景下它本该是 `board.deck_screen_size`（= 102×147 × _zoom）。
				var bm_f: BoxMesh = (layers[0] as MeshInstance3D).mesh as BoxMesh
				var foot_x: float = t3.world_to_canvas_px(
					droot.global_position + Vector3(bm_f.size.x, 0.0, 0.0)).distance_to(back)
				var foot_z: float = t3.world_to_canvas_px(
					droot.global_position + Vector3(0.0, 0.0, bm_f.size.z)).distance_to(back)
				_check(absf(foot_x - deck_sz.x) < 1.0 and absf(foot_z - deck_sz.y) < 1.0,
					"「%s」的脚印 == 印着那摞卡背的整体脚印（实得 %.1f×%.1f，期望 %.1f×%.1f 画布像素）"
						% [dn, foot_x, foot_z, deck_sz.x, deck_sz.y])
				# 底**就落在桌面上**（批次 6 Task 3 起：不再加 `PROPS_Y` —— 一摞牌是"躺在桌上的"，
				# 抬起来只会让它在屏幕上相对印刷图案往远端漂，见 table_props.DECK_SIZE 那段）。
				# 局部原点 = 这摞在地面的落点，而层 0 抬半层高 ⇒ root.y == 桌面 即"最下层躺在桌上"。
				_check(absf(droot.global_position.y - t3.table_mesh.global_position.y) < 0.001,
					"「%s」的底落在桌面上、不浮空（y=%.3f，桌面 %.3f）"
						% [dn, droot.global_position.y, t3.table_mesh.global_position.y])
				_check(lo >= t3.table_mesh.global_position.y - 0.001,
					"「%s」最下一层的底面不低于桌面（%.3f ≥ %.3f）"
						% [dn, lo, t3.table_mesh.global_position.y])
				# 身份：摞顶面平贴的 Label3D 写着牌名
				var lab := droot.get_node_or_null("Name") as Label3D
				_check(lab != null and String(lab.text) == dn,
					"「%s」摞上写着牌名（实得「%s」）" % [dn, String(lab.text) if lab != null else "无"])
			# 配色分得开 = 比 **albedo_color 真的不同**（批次 6 Task 3 改）：原来比的是**材质实例
			# 身份**，而代码每摞新建一份 `StandardMaterial3D` ⇒ 即便两个 albedo 完全相同也恒不等，
			# 这条断言**不可能因它声称的原因失败**。再进一步：各自等于预期那一份配色条目
			#（改错映射、两摞对调都会红）。
			var got_jh: Color = (bodies.get("机会") as StandardMaterial3D).albedo_color \
				if bodies.get("机会") != null else Color.BLACK
			var got_my: Color = (bodies.get("命运") as StandardMaterial3D).albedo_color \
				if bodies.get("命运") != null else Color.BLACK
			var want_jh: Color = tpD.DECK_BODY_COLORS["机会"]
			var want_my: Color = tpD.DECK_BODY_COLORS["命运"]
			_check(got_jh != got_my, "两摞的配色分得开（机会 %s / 命运 %s）" % [got_jh, got_my])
			_check(got_jh == want_jh and got_my == want_my,
				"两摞各用自己那一份配色（机会 %s / 命运 %s）" % [want_jh, want_my])
			# ④ 幂等：重复调用只重摆、不重建节点树
			var first_root: Node = dr.get_child(0)
			var first_kids: int = (first_root as Node3D).get_child_count()
			tpD.build_decks(deck_px)
			_check(dr.get_child_count() == 2 and dr.get_child(0) == first_root,
				"重复调用不重建节点（实得 %d 摞）" % dr.get_child_count())
			_check((first_root as Node3D).get_child_count() == first_kids,
				"摞里的层数一字未变（%d）" % (first_root as Node3D).get_child_count())

			# ②c 尺寸**跟着取景**（修复波 F 的实质）：把 2D 镜头推近（抽卡那 ≥2× 推近的**同一件事**
			# —— 都是同一个 `_zoom`），重报脚印之后摞必须跟着胀。**只跟位置不跟尺寸时这条会红**
			#（正是"抽卡推近下摞只盖住印刷图案约四分之一"那个病）。量法同轮缘那条
			#「画面半径变大后轮缘跟着放大」：比的是同一个节点 / 同一份 mesh，不重建。
			if not f_ok:
				_check(false, "BoardView 没有 deck_screen_size，②c（尺寸跟取景）整段跳过")
			else:
				t3.board.fit_overview(true)
				await process_frame
				var px0 := {}
				for dn2 in deck_names:
					px0[dn2] = t3.board.deck_screen_pos(dn2)
				tpD.build_decks(px0, deck_sz)
				var zoom0: float = deck_sz.x
				var deck0: Node3D = dr.get_node("Deck_机会") as Node3D
				var w0: float = (deck0.get_child(0) as MeshInstance3D).mesh.size.x
				t3.board.focus_grid(27, 2.0, true)      # 全景的 2 倍 —— 抽卡推近的同一档
				await process_frame
				var sz1: Vector2 = t3.board.deck_screen_size("机会")
				_check(sz1.x > zoom0 * 1.5,
					"推近之后印着的那摞卡背脚印跟着变大（%.1f → %.1f 画布像素）" % [zoom0, sz1.x])
				var px1 := {}
				for dn3 in deck_names:
					px1[dn3] = t3.board.deck_screen_pos(dn3)
				tpD.build_decks(px1, sz1)
				var w1: float = (deck0.get_child(0) as MeshInstance3D).mesh.size.x
				_check(w1 > w0 * 1.5,
					"实体的尺寸跟着胀（%.3f → %.3f 世界单位，须 > 1.5 倍 —— 只跟位置不跟尺寸时它一字不变）"
						% [w0, w1])
				_check(deck0.get_child_count() == (dr.get_child(0) as Node3D).get_child_count(),
					"跟取景重报尺寸也不重建节点（%d 层）" % deck0.get_child_count())
				# 收尾：把取景与实体都放回全景（后面还有断言读这些坐标）
				t3.board.fit_overview(true)
				await process_frame
				tpD.build_decks(px0, t3.board.deck_screen_size("机会"))

	# 坐标系约定：画布下方（y 大）= 近端。相机在 +z（table_3d.CAM_DIST 沿 +z 摆），
	# 而 canvas_px_to_world 走 world_to_uv（uv.y = z/进深 + 0.5）—— 整体 z 翻转的话这条会红。
	# 注意：**单靠这条抓不到「贴图与 UV 约定整体镜像」**，那要对着出图核（见 task-3-report 的镜像核对）。
	_check(t3.canvas_px_to_world(Vector2(1024.0, 2048.0)).z > t3.canvas_px_to_world(Vector2(1024.0, 0.0)).z,
		"画布下方 = 近端（y 大 → z 大）")

	# ---- 批次 11 Task 1：棋子（小人）+ 当前行动者光环搬进 3D ----
	# 桌垫上印着的那枚小人（Kenney 棋子贴图）做成**立在桌上的薄牌**；行动光环从 2D Panel
	# 换成贴桌垫的一条 3D 环。判据一律走**可观察量**：几何取自节点自己的 mesh + 世界变换、
	# 命中走 token_hit 自己、位置走真反变换（world_to_canvas_px）折回画布像素比 ——
	# 不把实现的推导再写一遍（那样写成什么样都过）。
	print("== 棋子：薄牌立着（有高度 / 后倾 / 与印刷图案同链） ==")
	var tpT = t3.table_props
	if tpT == null or not tpT.has_method("set_tokens"):
		_check(false, "TableProps 没有 set_tokens（棋子还没搬进来），本段整段跳过")
	else:
		t3.snap_view(0.0)          # 3D 端取景：命中盒与出图核对都在这一档
		await process_frame
		tpT.set_tokens([
			{"peer": 7, "slot": 0, "idx": 20},
			{"peer": 8, "slot": 2, "idx": 20},
		])
		# 弹入（新棋子出现时 scale 0 → 1，TRANS_BACK）：先抓一帧"还在弹"，再等它落定。
		await process_frame
		var troot0: Node = tpT.get_node_or_null("Tokens")
		var tk_pop: Node3D = _token_node(troot0, 7)
		if tk_pop != null:
			_check(tk_pop.scale.x < 0.99, "新棋子是**弹入**出现的（首帧 scale %.2f < 1）" % tk_pop.scale.x)
		await create_timer(0.5).timeout          # 弹入 0.35s：等它落定再量几何
		var troot: Node = tpT.get_node_or_null("Tokens")
		_check(troot != null, "棋子的父节点在（set_tokens 时建）")
		var tkA: Node3D = null
		var plateA: MeshInstance3D = null
		var bmA: BoxMesh = null
		if troot != null:
			tkA = _token_node(troot, 7)
			if tkA != null:
				plateA = tkA.get_node_or_null("Plate") as MeshInstance3D
				if plateA != null:
					bmA = plateA.mesh as BoxMesh
		_check(tkA != null and plateA != null and bmA != null, "peer 7 的棋子是一块 BoxMesh 薄牌")
		if bmA != null:
			_check(bmA.size.y > 0.1, "薄牌**有高度**（%.3f > 0.1，不是平面贴纸）" % bmA.size.y)
			_check(bmA.size.z < bmA.size.y * 0.5, "薄牌是「薄」的（厚 %.3f 世界单位）" % bmA.size.z)
			# 「后倾」的可执行定义（同已退场立牌那条）：牌面**顶边比板底更靠远端**（z 更小）。
			# 顶边 = 板心沿自己的 +y 半高、板底 = 沿 -y 半高 —— 倾角方向错（或压根没倾）这条就红。
			var top_v: Vector3 = plateA.global_transform * Vector3(0.0, bmA.size.y * 0.5, 0.0)
			var bot_v: Vector3 = plateA.global_transform * Vector3(0.0, -bmA.size.y * 0.5, 0.0)
			_check(top_v.z < bot_v.z, "顶边比板底更靠远端（后倾 ⇒ 2D 端近正俯视也看得见一块面）")
			# 正面贴图：棋子贴图（Kenney CC0）。贴图缺失时退回牌身纯色（与 2D 那套同一条降级），
			# 所以这里只钉"面片在、且它的贴图就是 UIKit 给这个槽位的那张"（拿不到就不钉）。
			var UKt = load("res://scripts/ui_kit.gd")
			var want_tex = UKt.piece_tex(0)
			if want_tex != null:
				var faceA: MeshInstance3D = tkA.get_node_or_null("Face") as MeshInstance3D
				var fmatA: StandardMaterial3D = faceA.material_override as StandardMaterial3D if faceA != null else null
				_check(faceA != null and fmatA != null and fmatA.albedo_texture == want_tex,
					"正面贴的是这个槽位的棋子贴图（UIKit.piece_tex）")
			# 材质**模式**：3D 端必须留在**不透明队列**（写深度、投得出影子）—— 牌身 `DISABLED`、
			# 正面 `ALPHA_SCISSOR`（贴图透明边裁掉但仍在同一队列）。同已退场立牌 / 手牌那两条先例。
			# （只有传送淡出那 0.38s 才切 ALPHA，淡完切回 —— 见 `_set_token_alpha` 与 hud_test 那两条。）
			var pmatA: StandardMaterial3D = plateA.material_override as StandardMaterial3D
			var faceM: MeshInstance3D = tkA.get_node_or_null("Face") as MeshInstance3D
			var fmatM: StandardMaterial3D = faceM.material_override as StandardMaterial3D if faceM != null else null
			_check(pmatA != null and pmatA.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
				"牌身是**不透明档**（实得 %s）" % str(pmatA.transparency if pmatA != null else -1))
			_check(fmatM != null and fmatM.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"正面是 ALPHA_SCISSOR（实得 %s）" % str(fmatM.transparency if fmatM != null else -1))
		# 位置 = 与**印在桌垫上的**那一格同一条链：`tile_screen_pos` / `deck_screen_pos` /
		# `wheel_screen_pos` 的那条（`global_position + _view_from_world(局部点)`）—— 也就是
		# `board.token_screen_pos(idx, slot)`。量法：把棋子的世界落点过真反变换折回画布像素比。
		# **不能拿 `slot_anchor` 的局部坐标比**：那是"镜头在原点、倍率 1"那一档的位置，
		# 全景取景下与印刷位置差约一格（出图逮到过 —— 棋子偏到隔壁格）。
		var want_a: Vector2 = t3.board.token_screen_pos(20, 0)
		var local_a: Vector2 = t3.board.slot_anchor(20, 0)
		_check(want_a.distance_to(local_a) > 8.0,
			"（前提）印刷口径与局部坐标确实不同（差 %.1f 画布像素 —— 少了镜头变换就会偏开）"
				% want_a.distance_to(local_a))
		if tkA != null:
			var back_a: Vector2 = t3.world_to_canvas_px(tkA.global_position)
			_check(back_a.distance_to(want_a) < 1.0,
				"棋子落在该格的「印刷口径」落点上（实得 %s / 期望 %s）" % [back_a, want_a])
			_check(tkA.global_position.y > t3.table_mesh.global_position.y,
				"棋子抬在桌垫之上（y=%.3f）" % tkA.global_position.y)

		# 命中三态：落点上命中 / 别处 -1 / 重叠时取离相机最近。
		# 先只留 peer 7 一枚 —— 两枚都在时它那枚的落点会被**更近**的那枚抢先命中（那是下面要钉的
		# "取最近"），所以"落点上命中"这条必须单枚量。
		print("== 棋子命中：落点上命中 / 别处 -1 / 重叠时取离相机最近 ==")
		tpT.set_tokens([{"peer": 7, "slot": 0, "idx": 20}])
		await process_frame
		_check(tpT.token_hit(want_a) == 7,
			"棋子画布落点上命中 peer 7（实得 %d）" % tpT.token_hit(want_a))
		_check(tpT.token_hit(Vector2(30.0, 30.0)) == -1, "桌垫之外不算命中（-1）")
		var cell30: Vector2 = t3.board.tile_pos(30) + Vector2(t3.board.TILE, t3.board.TILE) * 0.5
		_check(tpT.token_hit(cell30) == -1, "没有棋子的格心不算命中（-1）")
		# 重叠：把两枚都摆在**同一格**（槽 0 与槽 2 —— 偏移只差 y，一远一近，命中盒会交叠）。
		# **前提（真有交叠）不靠猜**：先在"只摆一枚"的两趟里把"同时落在两枚盒内"的点**探出来**
		#（用 token_hit 自己探，不把命中盒的推导再写一遍），再用"两枚都在"的那一次断言取近的那枚。
		# 换人之前要 `await` 一帧：被移走的节点是 queue_free（延迟释放），同帧重建会同名重命名。
		var scan_x := range(-120, 25, 4)
		var scan_y := range(-140, 45, 4)
		var solo_a := {}
		for xi in scan_x:
			for yi in scan_y:
				var qa: Vector2 = want_a + Vector2(float(xi), float(yi))
				if tpT.token_hit(qa) == 7:
					solo_a[qa] = true
		tpT.set_tokens([{"peer": 8, "slot": 2, "idx": 20}])
		await create_timer(0.5).timeout
		var solo_b := {}
		for xi in scan_x:
			for yi in scan_y:
				var qb: Vector2 = want_a + Vector2(float(xi), float(yi))
				if tpT.token_hit(qb) == 8:
					solo_b[qb] = true
		var both: Array = []
		for q in solo_a.keys():
			if solo_b.has(q):
				both.append(q)
		_check(not both.is_empty(),
			"两枚的命中盒**确有交叠**（交叠探针 %d 个；没有交叠这条先红，重叠判据无从谈起）" % both.size())
		if not both.is_empty():
			tpT.set_tokens([{"peer": 7, "slot": 0, "idx": 20}, {"peer": 8, "slot": 2, "idx": 20}])
			await create_timer(0.5).timeout
			var wrong := 0
			for q in both:
				var qc: Vector2 = q
				if tpT.token_hit(qc) != 8:
					wrong += 1
			# 槽 2 的偏移 y 更大 = 画布更靠下 = 离相机更近 ⇒ 交叠处必须一律给 8（近的那枚）。
			_check(wrong == 0, "交叠处一律取**离相机最近**的那枚（%d/%d 个探针给错）" % [wrong, both.size()])
			_check(tpT.token_world_pos(8).z > tpT.token_world_pos(7).z,
				"（前提）peer 8 那枚确实更近（z %.3f > %.3f）"
					% [tpT.token_world_pos(8).z, tpT.token_world_pos(7).z])

		# 光环：贴桌垫的一条 3D 环，套在当前行动者脚下；尺寸**跟印刷图案**（与转盘轮缘同口径）。
		print("== 当前行动者光环：3D 环、跟印刷图案、NO_PEER 时收起 ==")
		tpT.set_tokens([{"peer": 7, "slot": 0, "idx": 20}])
		await create_timer(0.5).timeout
		tpT.set_ring(7)
		await process_frame
		var ring: MeshInstance3D = tpT.get_node_or_null("Ring") as MeshInstance3D
		_check(ring != null, "光环节点在（set_ring 时建）")
		if ring != null:
			_check(ring.visible, "set_ring(peer) 后光环可见")
			var torus: TorusMesh = ring.mesh as TorusMesh
			_check(torus != null, "光环是圆环（TorusMesh —— 中间透空，不盖住格子的图案）")
			var ring_back: Vector2 = t3.world_to_canvas_px(ring.global_position)
			_check(ring_back.distance_to(want_a) < 8.0,
				"环心落在该棋子附近（实得 %s / 棋子 %s）" % [ring_back, want_a])
			if torus != null:
				# 尺寸跟印刷图案：把环的外沿折回**画布像素**，与 board 报的半径比 ——
				# 同轮缘那条（走真反变换，不把"像素 ÷ 常数"的实现重述一遍）。
				var out_px0: float = t3.world_to_canvas_px(
					ring.global_position + ring.global_transform.basis.x * torus.outer_radius) \
					.distance_to(t3.world_to_canvas_px(ring.global_position))
				var want_r: float = t3.board.token_ring_radius_px()
				_check(absf(out_px0 - want_r) < 2.0,
					"环外沿 == 画在桌垫上的那个半径（%.1f vs %.1f 画布像素）" % [out_px0, want_r])
				# 跟取景：2D 镜头推近（取景 / 人数变化都会改 _zoom），重推环要跟着胀 ——
				# 与"轮缘跟着画面半径放大"同一条（只跟位置不跟尺寸时这条会红）。
				t3.board.focus_grid(20, 2.0, true)
				await process_frame
				tpT.set_ring(7)
				var out_px1: float = t3.world_to_canvas_px(
					ring.global_position + ring.global_transform.basis.x * torus.outer_radius) \
					.distance_to(t3.world_to_canvas_px(ring.global_position))
				_check(out_px1 > out_px0 * 1.5,
					"取景推近后环跟着胀（%.1f → %.1f 画布像素）" % [out_px0, out_px1])
				t3.board.fit_overview(true)
				await process_frame
			tpT.set_ring(GameData.NO_PEER)
			await process_frame
			_check(not ring.visible, "set_ring(NO_PEER) 后光环收起")
			# 行动者从名册里消失（掉线 / 出局）：光环也要被收掉（T1 审查 Minor #5）——
			# `_process` 找不到那枚棋子会早退，环若留着就挂在桌上没人收（此后没人再调 set_ring）。
			# 收尾写在 `set_tokens` 的移除分支里。
			tpT.set_ring(7)
			await process_frame
			_check(ring.visible, "（前置）重新点亮光环")
			tpT.set_tokens([])                 # 谁都不要了 ⇒ peer 7 的棋子被移除
			await process_frame
			_check(not ring.visible, "行动者的棋子被移除后光环自动收起")

		# 反向契约：2D 的棋子 / 光环 / 悬停条整套必须**真的没了**（不留空壳）。
		# 谁把它们加回来（或只加个空壳），这几条先红 —— 悬停条由 Task 3 在屏幕层重建。
		print("== 反向契约：2D 棋子 / 光环 / 悬停条整套已从 BoardView 删净 ==")
		var bv = t3.board
		_check(bv.get("_tokens") == null, "BoardView._tokens 已删净")
		_check(bv.get("_token_tip") == null and bv.get("_ring") == null,
			"悬停条与 2D 光环的成员已删净")
		# （`token_screen_pos` 不在这一串里：**名字被新的那条接走了** —— 旧的取 `peer`、
		#   新的取 `(idx, slot)`，是 3D 侧摆棋子用的"印刷口径落点"，上面已经用过、能用。）
		var gone_m := ["play_move", "set_teleport_target", "_teleport_anim", "_kill_token_tw",
			"_set_ring", "_build_ring", "_make_token", "token_world_pos",
			"_token_at_view", "_set_token_hover", "_ensure_token_tip", "_place_token_tip"]
		var still: Array = []
		for m in gone_m:
			if bv.has_method(m):
				still.append(m)
		_check(still.is_empty(), "棋子的 12 个方法都已退场（残留：%s）" % str(still))
		# 保留的接口：3D 侧摆棋子与格详情卡的锚点（`tile_pos` / `slot_offset` 上面已经用过、
		# 能用；这里把"还在"钉住 —— 谁顺手删了，这条先红）
		var kept: Array = []
		for m in ["slot_offset", "slot_anchor", "tile_screen_pos", "token_screen_pos"]:
			if not bv.has_method(m):
				kept.append(m)
		_check(kept.is_empty(), "slot_offset / slot_anchor / tile_screen_pos / token_screen_pos 保留（缺 %s）" % str(kept))

	t3.queue_free()

	# ---- 批次 5 Task 2：座位栏退场，改钉"窗口覆盖了什么"（原第 ③ 条「立牌贴桌沿」随批次 9 删）----
	# T4b/T4c/T-a 那三条（"四条座位栏都在画布内 / 窗口内 / 屏幕内"）随座位栏一起删了：
	# 它们守的是"指向性道具点得到人"，而那个入口随批次 9 挪到**屏幕层的四角身家条**
	#（Task 2 起可点、Task 3 接上选目标高亮；hud_test 里那两条断言守着）。这里只剩两条：
	#   ① 反向契约：座位卡那一套真的没了、也没有留下四条空栏；
	#   ② 窗口必须覆盖**棋盘与两摞牌堆**（可见且可点到）——批次 2 的 T4c 就是踩了这个坑
	#     （窗口裁过头 ⇒ 画布内有、桌面上看不见也点不到）才把窗口恢复成整张画布的。
	print("== 座位卡退场：画布里没有座位栏，棋盘与牌堆仍在窗口内 ==")
	var t4 = load("res://scripts/table_3d.gd").new()
	root.add_child(t4)
	await process_frame
	await process_frame
	t4.board._process(0.0)
	t4.board.fit_overview(true)
	var win4: Rect2 = t4.TEX_WINDOW_PX
	var vp4 := Rect2(Vector2.ZERO, Vector2(t4.viewport.size))
	var b4 = t4.board
	# ① 反向契约
	_check(b4.get_node_or_null("PhaseButtons") == null,
		"牌垫阶段按钮层已随批次 7 退场（谁把它加回来，这条先红）")
	_check(b4.get("_seats") == null and b4.get("_seat_of_peer") == null,
		"座位卡的表（_seats / _seat_of_peer）已从 BoardView 上删净")
	# ② 棋盘 + 两摞牌堆都得在窗口内（画布口径），且窗口在画布内
	var chest4 := Rect2(b4._view_from_world(b4.BOARD_OFFSET),
		b4._view_from_world(b4.BOARD_OFFSET + b4.WORLD) - b4._view_from_world(b4.BOARD_OFFSET))
	_check(vp4.encloses(chest4), "棋盘整块落在画布内（%s）" % chest4)
	_check(win4.encloses(chest4), "棋盘整块落在纹理窗口内（可见且可点）")
	var deck_out := 0
	var deck_zone_out := 0
	for d in ["机会", "命运"]:
		var dc: Vector2 = b4.deck_screen_pos(d)
		# 牌堆底板 280×180（见 board_view._build_deck），要整块在窗口里
		var zone := Rect2(dc - Vector2(140.0, 90.0), Vector2(280.0, 180.0))
		if not win4.has_point(dc):
			deck_out += 1
		if not win4.encloses(zone):
			deck_zone_out += 1
		print("    牌堆 %s：中心（画布）%s 底板 %s" % [d, dc, zone])
	_check(deck_out == 0, "两摞牌堆的中心都在纹理窗口内（窗口外 %d 摞）" % deck_out)
	_check(deck_zone_out == 0, "两摞牌堆的底板整块在纹理窗口内（越界 %d 摞）" % deck_zone_out)
	t4.queue_free()

	if fails == 0:
		print("LAYOUT TEST: ALL PASS")
		quit(0)
	else:
		print("LAYOUT TEST: %d FAILURES" % fails)
		quit(1)
