extends SceneTree
## 2.5D 桌面几何单测：平面求交 + 世界↔UV↔SubViewport 往返一致性
## godot --headless --path . --script tests/layout_test.gd

var fails := 0

# ---------------- 阈值常量（一期 Task 8 新增；与光照 / 材质那几条断言同源） ----------------
#
# **写法照批次 13 ⑦⑧ 那条**（"1.4 是设计给的界；本档实测 1.27"）：先实测、再定档，
# 实测过程与实测值写在这里 —— 光写一个数、不写它是怎么来的，下一个人只能猜。

## 补光对**桌面采样点**的照度贡献上限（照度代理式口径，`_mat_sample_irradiance`）。
##
## 这是 Task 8 的**新增断言**用到的阈值，设计稿 §十二 待核 #4 只写了"照度代理式实测后定"，
## 没写数 —— 所以这里是**实测定的档**：
##   * 补光 = `room.gd.FILL_LIGHT_POS`（`22×0.36, 0.5, 18×0.28`）、能量 0.45、射程 30、指数 0；
##   * 桌面采样点 = 桌垫四角 + 中心（与上面"桌面均匀"那条**同一组点**、**同一把尺子**）；
##   * **本档实测 fill_max = 0.0494**（最亮那一点是近右侧那个桌角 —— 补光在近侧偏右）。
## 取 **0.08**（≈ 实测的 1.6 倍，留一点余量给"补光颜色 / 色温微调"这类不改变落点的改动）。
##
## **它防的是什么**：补光一旦被调强 / 调高，桌面会被**第二盏灯**一起打 ——
## 而桌面那亮度是用户签过字的（批次 13 ⑧「桌面各位置亮度一致」）。
## 对照：把 `FILL_ENERGY` 从 0.45 提到 1.0 ⇒ 实测 0.110 > 0.08 **立刻红**（见 task-8-report 的
## 变红验证表）。**别拿它当"补光总能量上限"读**：它量的是**落在桌面上**的那一份，
## 补光挪远 / 压低都能在"总能量更大"的同时把这一份压小（这正是 `FILL_LIGHT_POS.y = 0.5` 干的事）。
const FILL_ON_TABLE_MAX := 0.08

## 补光对**桌面采样点**的照度贡献**下界**（同一把尺子、同一组采样点）。
##
## 一期审查残留（2026-10-06 补上）：`FILL_ON_TABLE_MAX` 只有上限 —— **灯在但没效果**
## （`FILL_ENERGY` 归零 / 补光挪出射程）时 `fill_max = 0.0 ≤ 0.08` 照样全绿，
## "补光存在"那三条（恰好一盏 / 是 omni / 不碰桌面）管不住"它还有没有用"。
## 取 **0.02**（本档实测 0.0494 的四成）：能量减半（→ 0.0247）仍绿；
## 归零 / 挪出射程（→ ≈0）必红。补光对桌面的贡献只许在这个带子里动。
const FILL_ON_TABLE_MIN := 0.02

## 家具的"被照亮的 albedo"相对**桌面最暗那个采样点**的比值上限。
##
## 判据的由来（Task 8 Step 0）：家具必须是屋里**不再是画面里最亮的东西**。
## **同一把照度代理式**（设计 §五）：`albedo 亮度 × 照度(家具形心)` 对
## `木桌 albedo 亮度 × 照度(桌面最暗那个角)` —— 拿桌面的**最暗**处去比，是**故意从严**。
##   * 换材质**之前**（Kenney 自带的纯平奶白 `0.896, 0.602, 0.393`，albedo 亮度 **0.649**）：
##     实测比值 **1.49** ⇒ 家具确实比被照亮的桌面更亮（这就是出图上那些"发亮的积木"）；
##   * 换成暗木调（`room.gd.FURN_ALBEDO`，albedo 亮度 **0.281**；木桌 albedo 亮度 0.558）之后：
##     实测 **0.644**（最亮那一件是左近那把椅子，0.372 —— 它离灯最近）。
## 取 **0.85**（比实测松 1.3 倍，比"换回奶白"那一档紧 1.8 倍 —— 两头都留了余量，
## 而它**真会红**：把 `FURN_ALBEDO` 改回 `Color(0.896, 0.602, 0.393)`，这条立刻红）。
## **别再把它收紧回 0.70**：一度取过 0.70（当时家具更暗、实测 0.482），但更暗那档在出图上
## 家具与地板糊成一片 —— 放宽到这里是为了给"看得清是件家具"留位置（见 `FURN_ALBEDO` 那段）。
const FURN_LIT_RATIO_MAX := 0.85

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

## 房子薄牌在**画布像素**下的宽度：把薄牌的左右两沿（局部 ±w/2）过真反变换折回画布像素量距离。
## 薄牌只绕 X 后倾 ⇒ 局部 x 仍是世界 x，两点只差一个 x ⇒ 这个距离就是它在画布上的宽。
func _house_w_px(t3, h: Node3D, bm: BoxMesh) -> float:
	if h == null or bm == null:
		return 0.0
	var plate: MeshInstance3D = h.get_node("Plate")
	var l: Vector2 = t3.world_to_canvas_px(plate.global_transform * Vector3(-bm.size.x * 0.5, 0.0, 0.0))
	var r: Vector2 = t3.world_to_canvas_px(plate.global_transform * Vector3(bm.size.x * 0.5, 0.0, 0.0))
	return l.distance_to(r)

## 桌面上一点吃到的**相对照度**（"桌面各位置亮度一致"那条断言的**代理式**，见光照段那段注释）。
##
## 与**渲染器同口径**地估：Compatibility 后端（本项目用的 `gl_compatibility`）就是 GLES3，
## 它的 omni 衰减在 `drivers/gles3/shaders/scene.glsl` 的 `get_omni_spot_attenuation`：
##     `atten = max(1 − (d/range)^4, 0)^2 × d^(−衰减指数)`
## 直射那一份 = `能量 × atten × N·L`（桌面法线朝上 ⇒ `N·L = 灯高 / d`，夹到 0），
## 再加上**与位置无关**的环境光那一份 = `环境能量 × 环境色亮度`。
##
## **为什么不能只写 `pow(clamp(1 − d/range, 0, 1), atten)`**（那条更"像衰减"的写法）：
## 它把 `(1 − (d/range)^4)^2` 那一项整个丢掉了，而在**衰减指数被压到 0**（本批就是这么取的）
## 时，那一项正是**唯一**还会随距离变化的因子 —— 用它估的话，射程被改小到 12.5（远端角
## 直接被乘到 0、画面上就是一条黑边）也照样"均匀"。**断言会变成永真**，正是要避免的那种。
##
## **环境光那一份必须算进去**：它是渲染器实际会加上去的一层（`frag_color.rgb += emission + ambient_light`），
## 与位置无关 ⇒ 它让"桌面均匀"这条更容易满足，也让"环境光被压回 0.1"那种回归漏不出去。
func _mat_sample_irradiance(light: OmniLight3D, p: Vector3, ambient: float) -> float:
	var d: float = light.global_position.distance_to(p)
	if d < 0.0001:
		d = 0.0001
	var nd: float = d / light.omni_range
	nd = nd * nd
	nd = nd * nd                                     # (d/range)^4
	var shape: float = maxf(1.0 - nd, 0.0)
	shape = shape * shape                            # (1 − (d/range)^4)^2
	var decay: float = pow(maxf(d, 0.0001), -light.omni_attenuation)
	var cos_i: float = clampf((light.global_position.y - p.y) / d, 0.0, 1.0)  # N·L（N = 桌面法线 +Y）
	return light.light_energy * shape * decay * cos_i + ambient

## 一棵子树里**所有几何实例的材质 albedo 亮度中最亮的那个**（一件材质都找不到给 -1）。
##
## 为什么从材质上读、不读 `GameRoom.FURN_ALBEDO`：读常量等于把实现重述一遍 ——
## 材质改成什么颜色都照样过，那正是本文件反复警告的"永真断言"。
## **`material_override` 优先**（`room.gd._paint()` 就是往那儿刷的）；没有就退回面 0 的实际材质。
func _subtree_albedo_lum(root: Node) -> float:
	var mx := -1.0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null:
			continue
		var m := g.material_override as StandardMaterial3D
		if m == null and g.mesh != null and g.mesh.get_surface_count() > 0:
			m = g.get_active_material(0) as StandardMaterial3D
		if m == null:
			continue
		mx = maxf(mx, m.albedo_color.get_luminance())
	return mx

## 一棵子树里所有几何实例的世界 AABB 的并集（一件都量不到给**空 AABB** —— `size == (0,0,0)`）。
## 口径与"家具整体落在房间里 / 家具与椅子都站在地板上"那几条**同一条**（逐个
## `GeometryInstance3D` 的 AABB 过自己的世界变换再并起来），不另立一套。
##
## 【终审 F4】这三处（家具的"整体落在房间里"、"站在地板上"、地毯）此前各写一份内联循环，
## 口径一改就会**只改一处**（助手改了、内联那两处静默留在旧口径上）⇒ 现在全部走这里。
## **"量不到几何"按 `size == Vector3.ZERO` 判**（旧内联版那个 `got_mesh` 旗标的等价写法：
## 一件几何都没量到时返回的正是空盒）—— 房间里的物件都是 `PlaneMesh` / `.glb`，没有退化 AABB。
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

## **单个**几何节点（连同它自己）的世界 AABB —— `_subtree_world_aabb` 只扫**子孙**，
## 量不到"传进来那一个节点自己"。桌子的三块（`TableBase` / 桌垫 `table_mesh` / 木纹外框
## `wood_mesh`）都是**叶子** `MeshInstance3D` ⇒ 用 `_subtree_world_aabb` 量它们会拿到空盒
##（与"量不到"分不开），于是桌子那一条会**恒真**。传 `null` 给空盒（调用方按空盒判）。
func _self_world_aabb(n: Node) -> AABB:
	var g := n as MeshInstance3D
	if g == null or g.mesh == null:
		return AABB()
	return g.global_transform * g.mesh.get_aabb()

## 【批次 12 A1 删除】原先这里有个 `_shade_screen_bbox(t3, shade)`：把灯罩当成"底口半径 × 罩高"
## 的盒子投影到屏幕，用来判"台灯还看得见吗"。灯罩已随 A1 整体删除（`Lamp` 节点不存在了），
## 这个助手也跟着删掉 —— 留着只会在下一个读它的人那里暗示"还有灯罩可量"。

## 木桌**远边**（`z = -WOOD_HALF_D` 那条边、两角取屏幕上**更高**的那条）的屏幕 y。
##
## 【终审 F4】"默认档房间带"与"拉远端把远墙拉进画"两处量的是**同一条线**（此前各写一遍）——
## 抽成一处，改口径时不会只改一处。
func _wood_far_edge_y(t3) -> float:
	var y := INF
	for sx in [-t3.WOOD_HALF_W, t3.WOOD_HALF_W]:
		y = minf(y, (t3.camera.unproject_position(
			Vector3(sx, 0.0, -t3.WOOD_HALF_D)) as Vector2).y)
	return y

## 远墙**墙脚**三点（`y = FLOOR_Y`、`z = -ROOM_D/2`、x = −半宽 / 0 / +半宽）投影到屏幕。
##
## 【终审 F4】这三点的投影此前写了**三遍**（入画计数 / 拉远端的墙脚线 / 默认档的墙脚线）——
## 抽成一处。返回 `Array[Vector2]`，调用方各取所需（计数或取 `.y` 的最高那条）。
func _far_wall_base_screen(t3) -> Array:
	var out: Array = []
	var fz: float = -GameRoom.ROOM_D * 0.5
	for sx in [-GameRoom.ROOM_W * 0.5, 0.0, GameRoom.ROOM_W * 0.5]:
		out.append(t3.camera.unproject_position(Vector3(sx, GameRoom.FLOOR_Y, fz)))
	return out

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

## 一格在**画布像素**下的脚印（`tile_pos` 过 BoardView 的取景变换，尺寸 = `TILE × _zoom`）——
## 与 `hud_test` 里的 `cell_of` 同一条（那边量"手牌有没有压住近排格子"，这边量"薄牌躺平后
## 还在不在自己那格里"）。
func _cell_px(t3, idx: int) -> Rect2:
	var p: Vector2 = t3.board._view_from_world(t3.board.tile_pos(idx))
	var s: float = t3.board.TILE * t3.board._zoom
	return Rect2(p, Vector2(s, s))

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

	# ---- 3D 房间（一期）：总开关 + 房间一律不投影 ----
	# 契约：ROOM_ENABLED 为 true 时房间里必须有墙/地/天花板/家具；为 false 时
	# 房间里一个节点都不许留（退回到"只有桌子"的样子）—— 这是本期唯一的保命开关。
	# 写明 `: Node` 而不是 `:=`：`t3` 是 `load(...).new()`（Variant），动态调用的返回值推不出类型，
	# `:=` 会直接 Parse Error（本文件里取 t3 的东西一律不靠推断，见 `var lamp_l = t3.get(...)`）。
	var room: Node = t3.get_node_or_null("Room")
	_check((room != null) == GameRoom.ROOM_ENABLED,
		"ROOM_ENABLED=%s 时房间节点%s存在" % [GameRoom.ROOM_ENABLED, "" if room != null else "不"])
	if room != null:
		# 房间物件**一律不投影**：吊灯是唯一投影源，多一个投影物件 = 多一张阴影图。
		var shadow_casters: Array = []
		for n in room.find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_casters.append(n)
		_check(shadow_casters.is_empty(),
			"房间物件一律不投影（违规 %d 个）" % shadow_casters.size())
		# 外壳必须齐：四面墙 + 一地板 + 一天花板。
		_check(room.get_node_or_null("Ceiling") != null, "房间有天花板（吊灯要挂得住）")
		_check(room.get_node_or_null("Floor") != null, "房间有地板")
		var walls: Node = room.get_node_or_null("Walls")
		_check(walls != null and walls.get_child_count() == 4, "房间有四面墙")

		# ---- 一期 Task 4 起：家具摆位（**v0.8.0 三期按"铺满整间屋"重写**）----
		#
		# 【三期改版：删掉的两条 + 换成的是什么】用户 2026-10-06：「整个屋子的建模还是太粗糙了…
		# 把能塞的都塞进去」。摆位从"远墙左半侧三件"变成"三面墙 + 两侧带铺满的 17 件"，于是
		# 当年那两条**挡的就是新设计本身**，必须换掉：
		#
		#   ① 删「家具落在**左半侧**（x < 0，光域内）」。
		#      **它当年守的是**："家具别掉出吊灯的光域、退化成一块暗剪影"。屋子铺满之后
		#      左右两侧**都必须**有东西（用户原话），这条直接判设计违规。
		#      ⇒ **换成**「**每件家具都落在吊灯的射程之内**」（`距离(灯, 家具形心) ≤ 射程`）：
		#      同一条意图、同一个对象，只是把"左半侧"这个**当年的充分条件**换成了真正要守的
		#      **充要条件**。它拦得住同一类错：把家具搬到射程外的角落（或把 `LAMP_RANGE` 收小
		#      到够不着）—— 那时家具就是一块暗剪影，这条先红。
		#
		#   ② 删「家具都在**木桌远边之外**（z ≤ −3.6）」。
		#      **它当年守的是**："家具别叠到桌子上"，附带一句"z 是从 `ROOM_D` 推导的，
		#      `ROOM_D` 一收小家具会跟着往近端跑"。
		#      ⇒ **换成**「**家具与桌子（底座 + 桌面 + 木纹外框的合并 AABB）不相交**」，并**新增**
		#      一条「**家具与四把椅子不相交**」。新口径**更严也更对**：老那条只量**站位点**的 z、
		#      而"叠没叠上"是**体**的事（一件 5.34 长的边柜站在 z = −3.9 上照样能把桌子压住）；
		#      而且它只认桌子、不认椅子 —— 铺满之后家具最先撞上的其实是**四把椅子**。
		#      它拦得住同一类错，还多拦一类：桌子 / 椅子跟着 `WOOD_FRAME` / `TABLE_D` 长大、
		#      或家具跟着 `ROOM_D` 往近端跑，都会在这里现形。
		#
		# **保留**：两两不相交（17 件之后它比从前更值钱）、整体落在房间里、站在地板上、
		# `FURNITURE_ANCHORS` 与摆出来的逐条对得上、一律不投影（在上一节）。
		# **计数下限（v0.8.0 三期减负后：17 → 10 件，下限跟着 12 → 9）**：
		# 它**拦的是"摆位表被清空 / 被误删一大片"**，不是"删到 N 件" —— 用户 2026-10-06 第二条
		# 明确要求**去掉一批**（"桌子旁太挤"），下限若还钉在 12 就把那条设计变更判成违规。
		# 取"实际件数 − 1"（今天 10 件 ⇒ 9）：**再多删一件就红**，逼下一个人回来重议一次，
		# 而不是悄悄把屋子删空。**别把它读成"至少要摆 9 件"那种许愿值。**
		var furn: Node = room.get_node_or_null("Furniture")
		_check(furn != null and furn.get_child_count() >= 9,
			"房间里至少摆了 9 件家具（下限 = 实际件数 − 1；拦「摆位表被清空」，不是拦「删到 N 件」）")
		if furn == null:
			_check(false, "Furniture 节点缺了，家具那几条断言整段跳过")
		else:
			# 家具整体落在房间里 与 光域 两条共用的两个量：房间半宽 / 半深、吊灯的射程。
			var hw: float = GameRoom.ROOM_W * 0.5
			var hd: float = GameRoom.ROOM_D * 0.5
			# 计划 Interfaces 承诺过的 `FURNITURE_ANCHORS`：今天没有下游消费，但它是"摆在哪"的唯一
			# 记录（摆位表在 `room.gd` 里是常量，读它就等于把坐标再抄一遍）。钉它与摆出来的家具同源。
			_check(GameRoom.FURNITURE_ANCHORS.size() == furn.get_child_count(),
				"FURNITURE_ANCHORS 与摆出来的家具逐条对得上（%d / %d 件）"
					% [GameRoom.FURNITURE_ANCHORS.size(), furn.get_child_count()])
			# **每件家具的世界 AABB 必须整个落在房间里** —— 这条才拦得住"整体缩放定错档"：
			# 定小了（1:1 的米制模型）与定大了（50×）在"位置对不对"上**完全看不出来**，
			# 只有量尺寸才现形。尺寸取自**节点自己的 mesh**（逐个 GeometryInstance3D 的 AABB
			# 过自己的世界变换再并起来）—— **不读 `GameRoom.FURNITURE_SCALE`**：读常量等于把
			# 实现重述一遍，缩放改成什么值都照样过，正是本文件反复警告的那类永真断言。
			var boxes := {}
			for n in furn.get_children():
				# 走公共助手（终审 F4；"量到没量到"按空盒判，见 `_subtree_world_aabb` 的注释）
				var wb := _subtree_world_aabb(n)
				var got_mesh := wb.size != Vector3.ZERO
				boxes[n.name] = wb
				# 前提：真量到了几何。空盒（一个几何实例都没有）会让下面那条**恒真**。
				_check(got_mesh, "%s 有可量的几何实例（否则它的 AABB 是空盒、下面那条恒真）" % n.name)
				if not got_mesh:
					continue
				# **竖直下界是地板**（一期 Task 5 Step 0：地板从"桌面那一层"降到 `FLOOR_Y`）。
				# 这里原写 −0.02 —— 那是地板在桌面那一层的年代；不跟着改的话，家具悬在地板上方
				# 或陷进地板都照样绿。
				_check(wb.position.x >= -hw and wb.end.x <= hw
						and wb.position.z >= -hd and wb.end.z <= hd
						and wb.position.y >= GameRoom.FLOOR_Y - 0.05 and wb.end.y <= GameRoom.ROOM_CEIL_Y,
					"%s 整体落在房间里（世界 AABB %s..%s，尺寸 %s；房间 |x| ≤ %.1f / |z| ≤ %.1f / y ∈ [%.2f, %.1f]）"
						% [n.name, wb.position, wb.end, wb.size, hw, hd, GameRoom.FLOOR_Y, GameRoom.ROOM_CEIL_Y])
				# **每件家具都落在吊灯的射程之内**（= 删掉的那条"左半侧（光域内）"的替身，
				# 理由见上面那一段）。量的是**射程**（`omni_range`）而不是"x < 0"：
				# 射程之外 `(1 − (d/range)^4)^2` 归零 ⇒ 那件家具**一点灯都吃不到**，
				# 在暗屋子里就是一块纯黑剪影 —— 正是当年那条要防的东西。
				var lamp_l2 = t3.get("lamp_light")
				if lamp_l2 != null:
					var d_lamp: float = (lamp_l2 as OmniLight3D).global_position.distance_to(wb.get_center())
					_check(d_lamp <= (lamp_l2 as OmniLight3D).omni_range,
						"%s 落在吊灯射程内（形心离灯 %.2f ≤ 射程 %.1f —— 射程外一点灯都吃不到、是块黑剪影）"
							% [n.name, d_lamp, (lamp_l2 as OmniLight3D).omni_range])
			# **17 件两两不相交**（AABB 口径 —— 比几何口径严）。家具一铺满，最先撞上的就是彼此；
			# 摆位表动一个数就可能让两件叠在一起，而"在房间里 / 站在地板上"两条都拦不住它。
			var fnames: Array = boxes.keys()
			for i_f in fnames.size():
				for j_f in range(i_f + 1, fnames.size()):
					var a_f: AABB = boxes[fnames[i_f]]
					var b_f: AABB = boxes[fnames[j_f]]
					_check(not a_f.intersects(b_f),
						"%s 与 %s 不相交（%s..%s / %s..%s）"
							% [fnames[i_f], fnames[j_f], a_f.position, a_f.end, b_f.position, b_f.end])
			# **家具不许压在桌子 / 椅子上**（= 删掉的那条"都在木桌远边之外"的替身 + 一条新增的
			# 椅子版，理由见上面那段）。**对象全部量出来、不写死尺寸**：
			#   * 桌子 = `TableBase`（裙板）+ 桌垫（`table_mesh`）+ 木纹外框（`wood_mesh`）三块的
			#     合并世界 AABB —— 这才是"那张桌子"占的地方（老那条只量"木桌远边那一刀"的 z）；
			#   * 椅子 = 四把各自的世界 AABB（`_subtree_world_aabb` 与上面"站在地板上"同一条口径）。
			# ⚠ **`_subtree_world_aabb` 量不到"传进来那个节点自己"**（它扫的是子孙）——
			# 这三块都是 `MeshInstance3D` 叶子，所以要走 `_self_world_aabb`（带上自己那一块）。
			var table_box := _self_world_aabb(t3.table_mesh)
			table_box = table_box.merge(_self_world_aabb(t3.wood_mesh))
			table_box = table_box.merge(_self_world_aabb(t3.get_node_or_null("TableBase")))
			var solid: Array = [["桌子", table_box]]
			var seats_f: Node = room.get_node_or_null("Seats")
			if seats_f != null:
				for ch in seats_f.get_children():
					solid.append([ch.name, _subtree_world_aabb(ch)])
			var on_top := 0
			var on_top_log := ""
			for nm in fnames:
				for sl in solid:
					if (boxes[nm] as AABB).intersects(sl[1] as AABB):
						on_top += 1
						on_top_log += "%s×%s " % [nm, sl[0]]
			_check(on_top == 0,
				"家具不压在桌子 / 椅子上（压上的 %d 处：%s —— 三期「铺满三面墙 + 两侧带」之后"
					% [on_top, on_top_log]
					+ "**又减负删过一批**，这条比当年那条「远边之外」更严：它量的是**体**，不是站位点）")

		# ---- 一期 Task 5 Step 0：地板落到真实桌高（2026-10-05 用户拍板）----
		# 地板原先在**桌面那一层**（y = −0.02）⇒ 桌子读作"平铺在地板上的一块板"，按人体比例
		# 摆出来的椅子 / 家具"站不对"。降到 `FLOOR_Y`（= 3.70 / 5 = 0.74 m，真实桌高）之后整套
		# 比例才立得住。三条一起钉：① 地板就在 `FLOOR_Y`；② 四面墙跟着一起长（墙脚不许悬空）；
		# ③ 家具与椅子**站在地板上**（这一条才是"地板改了、站立点没跟着改"的守卫）。
		var floor_node: Node3D = room.get_node_or_null("Floor")
		_check(GameRoom.FLOOR_Y < 0.0 and floor_node != null \
				and absf(floor_node.position.y - GameRoom.FLOOR_Y) < 0.001,
			"地板落在 FLOOR_Y=%.2f（实得 %.3f —— 桌面仍在 y=0，地板在它下面 0.74 m）"
				% [GameRoom.FLOOR_Y, floor_node.position.y if floor_node != null else 999.0])
		var walls_node: Node = room.get_node_or_null("Walls")
		var wall_ok := walls_node != null and walls_node.get_child_count() == 4
		var wall_log := ""
		if walls_node != null:
			var want_h: float = GameRoom.ROOM_CEIL_Y - GameRoom.FLOOR_Y
			for ch in walls_node.get_children():
				var wm := ch as MeshInstance3D
				var wpm := wm.mesh as PlaneMesh if wm != null else null
				if wpm == null:
					wall_ok = false
					continue
				# 墙是绕 X 转 90° 立起来的 PlaneMesh ⇒ 它的 `size.y` 就是**世界高度**，
				# 墙心 `position.y ± 半高` 即墙顶 / 墙脚。
				var foot: float = wm.position.y - wpm.size.y * 0.5
				var head: float = wm.position.y + wpm.size.y * 0.5
				wall_log += "%s:[%.2f,%.2f] " % [ch.name, foot, head]
				if absf(foot - GameRoom.FLOOR_Y) > 0.05 or absf(head - GameRoom.ROOM_CEIL_Y) > 0.05 \
						or absf(wpm.size.y - want_h) > 0.05:
					wall_ok = false
		_check(wall_ok,
			"四面墙跟着地板一起长（墙脚落在地板上、墙顶够到天花板，高 %.1f；实得 %s）"
				% [GameRoom.ROOM_CEIL_Y - GameRoom.FLOOR_Y, wall_log])
		# 桌子底座（`table_3d` 侧的新几何）：地板一降，只有"桌垫 + 一圈木纹"的桌子就是悬在屋里
		# 的一块板 ⇒ 补一块从地板顶到木纹外框**底面**的裙板。三条：位置（不许与木纹共面、
		# 也不许悬空）、尺寸（= 木纹外框那两维）、不投影（房间的纪律）。
		var tbase: MeshInstance3D = t3.get_node_or_null("TableBase")
		_check(tbase != null and tbase.mesh is BoxMesh, "桌子有底座（TableBase 是 BoxMesh）")
		if tbase != null and tbase.mesh is BoxMesh:
			var tbm := tbase.mesh as BoxMesh
			var bb_bottom: float = tbase.position.y - tbm.size.y * 0.5
			var bb_top: float = tbase.position.y + tbm.size.y * 0.5
			_check(absf(bb_bottom - GameRoom.FLOOR_Y) < 0.001 and absf(bb_top + 0.012) < 0.001,
				"底座从地板顶到木纹外框底面（y ∈ [%.3f, %.3f]；地板 %.2f / 木纹底面 -0.012）"
					% [bb_bottom, bb_top, GameRoom.FLOOR_Y])
			_check(absf(tbm.size.x - (t3.TABLE_SIZE.x + t3.WOOD_FRAME * 2.0)) < 0.001 \
					and absf(tbm.size.z - (t3.TABLE_SIZE.y + t3.WOOD_FRAME * 2.0)) < 0.001,
				"底座尺寸 = 木纹外框那两维（实得 %.2f × %.2f，期望 %.2f × %.2f）"
					% [tbm.size.x, tbm.size.z, t3.TABLE_SIZE.x + t3.WOOD_FRAME * 2.0,
						t3.TABLE_SIZE.y + t3.WOOD_FRAME * 2.0])
			_check(tbase.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"底座不投影（全场唯一投影源仍是那盏吊灯）")

		# ---- 一期 Task 5 Step 0：家具与椅子**站在地板上** ----
		# 判据 = 各件**世界 AABB 的底面**贴合 `FLOOR_Y`（容差 0.05）。这条挡的是"地板降了、
		# 站立点没跟着改"（家具 / 椅子悬在半空或陷进地板）—— 那是"看位置对不对"永远看不出来的错。
		# 椅子也一并量：Task 5 的四把椅子必须自己站到新地板上（座位框摆在 `FLOOR_Y`）。
		# 变红验证：把某一件的 y 抬 1.0 ⇒ 这一条必须红（见 task-5-report）。
		var seat_root: Node = room.get_node_or_null("Seats")
		var stand: Array = []
		if furn != null:
			stand.append_array(furn.get_children())
		if seat_root != null:
			stand.append_array(seat_root.get_children())
		var lifted := 0
		var sunk := 0
		var unmeasured := 0
		var stand_log := ""
		var stand_boxes := {}
		for n in stand:
			# 走公共助手（终审 F4；"量到没量到"按空盒判，见 `_subtree_world_aabb` 的注释）
			var wb := _subtree_world_aabb(n as Node)
			var got_mesh := wb.size != Vector3.ZERO
			if not got_mesh:
				unmeasured += 1
				continue
			stand_boxes[n.name] = wb
			var off: float = wb.position.y - GameRoom.FLOOR_Y
			stand_log += "%s:%.3f " % [n.name, off]
			if off > 0.05:
				lifted += 1
			elif off < -0.05:
				sunk += 1
		_check(stand.size() > 0 and unmeasured == 0,
			"（前提）家具与椅子都量得到几何（%d 件、量不到 %d 件）" % [stand.size(), unmeasured])
		_check(lifted == 0 and sunk == 0,
			"家具与椅子都站在地板上（底面 == FLOOR_Y=%.2f 容差 0.05；悬空 %d / 陷入 %d；逐件偏差 %s）"
				% [GameRoom.FLOOR_Y, lifted, sunk, stand_log])

		# ---- 一期 Task 5 Fix round 1：spec §六 的比例（**能自动逮住"缩放定错档"的那条**）----
		# §六 那张用户拍过板的比例表有两个可执行判据，两个都从**实测 AABB**（= 节点的世界 AABB，
		# 也就是 `FURNITURE_SCALE` 已经乘进去之后的尺寸）算 —— **不写死任何米数**，缩放改档它跟着变：
		#   ① **书桌顶面与桌面齐平**（桌面在 y = 0）。实得 `FLOOR_Y + 3.84 = +0.14`，容差 ±0.35。
		#   ② **椅背顶高出桌面**，正余量。实得 `+1.00`，下界 +0.2。
		# **变红验证**（Fix round 1 做过）：把 `FURNITURE_SCALE` 临时改回 5.0 ⇒ 两条同时红
		#（书桌顶面 −1.78、椅背顶 −0.66），其余断言不受影响 —— 这正是 ×5 那档的病：
		# 家具只有真实家具的一半大，§六 要的"椅背挂名牌"摆不出来。
		var desk_top := INF
		if stand_boxes.has("desk"):
			desk_top = (stand_boxes["desk"] as AABB).end.y
		_check(absf(desk_top) <= 0.35,
			"书桌顶面与桌面齐平（顶面 y=%.2f，|y| ≤ 0.35；桌面在 y=0 —— spec §六）" % desk_top)
		# 椅背顶 = 座位框里那部分几何的 AABB 顶。
		# （v0.8.0 改版：原先这里要**剔掉 `Nameplate`** —— 椅背名牌挂在椅背顶上、会把它再抬 0.2。
		#  那块牌子已整段删除（用户 2026-10-06：「去掉椅子上的铭牌」），这道剔除也就跟着没了。）
		var back_top := -INF
		if seat_root != null:
			var s0: Node3D = seat_root.get_child(0)
			for ch in s0.get_children():
				for m in (ch as Node).find_children("*", "GeometryInstance3D", true, false):
					var g2 := m as MeshInstance3D
					if g2 == null or g2.mesh == null:
						continue
					back_top = maxf(back_top, (g2.global_transform * g2.mesh.get_aabb()).end.y)
		_check(back_top >= 0.2,
			"椅背顶高出桌面（顶面 y=%.2f ≥ 0.2；桌面在 y=0 —— spec §六「椅背挂名牌」那条）" % back_top)

		# ---- 一期 Task 5：四把椅子 + 椅背名牌 + 座位锚点 ↔ peer 映射 ----
		# **这一节是二期的接口**（spec §十：每把椅子定死「位置 + 朝向」、并挂一个名牌挂点，
		# 二期"把人放上去"只改这一处）。这里量两件：
		#   ① 四把椅子在，且座位序**收得下、原样保留**（"椅子顺序 == `game._seat_peers()`"那条
		#      在 `hud_test` —— 本文件没有 game 实例、没有 `g`，喂进去的就只能是测试自己编的）；
		#   ② 名牌按**各家的棋子色**上色（喂 `color` 0..3，就要看到 `PLAYER_COLORS[0..3]`）。
		_check(seat_root != null and seat_root.get_child_count() == 4,
			"围桌四把椅子（实得 %d）" % (0 if seat_root == null else seat_root.get_child_count()))
		if seat_root != null and seat_root.get_child_count() == 4:
			room.set_seats([
				{"peer": 10, "color": 0, "name": "甲"},
				{"peer": 11, "color": 1, "name": "乙"},
				{"peer": 12, "color": 2, "name": "丙"},
				{"peer": 13, "color": 3, "name": "丁"},
			])
			var mapped: Array = room.seat_peers()
			_check(mapped.size() == 4, "四把椅子都映射到了 peer（实得 %d）" % mapped.size())
			_check(mapped == [10, 11, 12, 13],
				"`seat_peers()` 原样保留喂进来的顺序（实得 %s —— 顺序就是 peer 的映射，不许在这里重排）"
					% str(mapped))
			# **v0.8.0 改版：椅背名牌整段删除**（用户 2026-10-06：「去掉椅子上的铭牌」）。
			# 本节原先在这里查四件事 —— `NAMEPLATE_ANCHORS` 四份、牌色 = 各家棋子色、
			# 四块牌各有一份材质、牌挂在椅背顶上。**那四件事现在都不存在了**：
			#   * 认人的职责整体搬到 `chars.gd` 的**头顶名牌**（`Chars/Tags/Tag{i}`），
			#     牌色 / 昵称 / billboard / 行动者金边由 `chars_test` ⑰ 逐条钉；
			#   * "色随 `p.color` 走、不随座位序号走"那一条由 `hud_test` 改指头顶名牌后继续守着；
			#   * `NAMEPLATE_ANCHORS` 那个"二期接口"**从未被消费**（二期取座位坐标一直走 `seat_anchor`）。
			# ⇒ 这里只留座位锚点那一段（二期真正的入口）。
			# 座位锚点（**二期唯一入口**）：位置 + 朝向。四条边各一把，四把**都面朝桌心**。
			# 朝向 = 座位框自己的 +z（模型朝 +z 长、背在 −z，实测顶点）⇒ 它应当指向桌心。
			var anchor_ok := true
			var anchor_log := ""
			var pos := []
			for i in 4:
				var an: Transform3D = room.seat_anchor(i)
				pos.append(an.origin)
				anchor_log += "%d:(%.2f,%.2f,%.2f) " % [i, an.origin.x, an.origin.y, an.origin.z]
				if absf(an.origin.y - GameRoom.FLOOR_Y) > 0.001:
					anchor_ok = false
				# 朝向 = 座位框自己的 +z（模型朝 +z 长、背在 −z，实测顶点）⇒ 它应当指向桌心
				var to_center := Vector3(-an.origin.x, 0.0, -an.origin.z).normalized()
				if (an.basis * Vector3(0.0, 0.0, 1.0)).normalized().dot(to_center) < 0.95:
					anchor_ok = false
			_check(anchor_ok,
				"四个座位锚点都立在地板上、且**四把椅子都面朝桌心**（%s）" % anchor_log)
			_check((pos[0] as Vector3).z > 0.0 and (pos[2] as Vector3).z < 0.0 \
					and (pos[1] as Vector3).x > 0.0 and (pos[3] as Vector3).x < 0.0,
				"一辺一把：slot0 近（+z，镜头这一侧＝「我」）/ slot1 右（+x）/ slot2 远（−z）/ slot3 左（−x）")
			_check(absf((pos[0] as Vector3).x) < 0.001 and absf((pos[2] as Vector3).x) < 0.001 \
					and absf((pos[1] as Vector3).z) < 0.001 and absf((pos[3] as Vector3).z) < 0.001,
				"四把椅子都摆在各自那条边的中线上（不在角上）")
			_check(absf((pos[0] as Vector3).z + (pos[2] as Vector3).z) < 0.001 \
					and absf((pos[1] as Vector3).x + (pos[3] as Vector3).x) < 0.001,
				"近/远、左/右两两对称（桌子摆正 ⇒ 椅子也摆正）")
			# **椅子不许埋进桌子**：木桌（桌垫 + 一圈木纹）那两维之内不许有椅子的脚印。
			# 摆位全由 `_table_size` 推导，Task 7 一改桌子进深，这条就是"椅子压到桌上"的守卫。
			var wood_hw: float = t3.WOOD_FRAME + t3.TABLE_SIZE.x * 0.5
			var wood_hd: float = t3.WOOD_FRAME + t3.TABLE_SIZE.y * 0.5
			var inside := 0
			for i in 4:
				var bn: Node3D = seat_root.get_child(i)
				var cb: AABB = stand_boxes.get(bn.name, AABB())
				if cb.position.x < wood_hw and cb.end.x > -wood_hw \
						and cb.position.z < wood_hd and cb.end.z > -wood_hd:
					inside += 1
			_check(inside == 0, "四把椅子都在木桌之外（埋进桌子里的是 %d 把；木桌半宽 %.2f / 半深 %.2f）"
				% [inside, wood_hw, wood_hd])

			# ---- 一期 Task 8 Step 0：桌下那块地毯 ----
			# 四条一起钉（brief Step 0 第 3 条要求"铺在桌子底下、盖住桌子足迹、**不压到椅子的座位区**"）：
			#   ① 它**不挂在 `Room/Furniture` 下** —— 那是"靠墙家具"那张表，三条断言按它逐件量
			#      （左半侧 / 木桌远边之外 / 两两不相交），居中的地毯三条全违。谁把它挪回去，这几条先红；
			#   ② 躺在 `FLOOR_Y` 上、且是**一块薄片**（不是一堵墙）；
			#   ③ **盖住木桌那两维**（`WOOD_HALF_W/D`）—— 少了它，地毯缩到桌子底下就"看不见"了
			#      （而"把桌子锚在地上"正是要它露出来那一圈）；
			#   ④ **一寸都不许压到椅子** —— 用**量的**椅子 AABB（`stand_boxes`，同上一段那四块），
			#      不读 `SEAT_INSET`：读常量等于把摆位实现重述一遍（摆位一改就静默失效）。
			# **变红验证**：把 `room.RUG_MARGIN` 从 0.10 提到 0.30 ⇒ ④ 立刻红（地毯伸进椅子脚印）。
			var rug: Node3D = room.get_node_or_null("Rug") as Node3D
			var rb: AABB = _subtree_world_aabb(rug) if rug != null else AABB()
			_check(rug != null and rug.get_parent() == room,
				"地毯挂在 `Room/Rug` 下（不在 `Furniture` 里 —— 那张表是「靠墙家具」，居中的地毯会违三条断言）")
			_check(rug != null and absf(rb.position.y - GameRoom.FLOOR_Y) < 0.01 and rb.size.y < 0.5,
				"地毯铺在 FLOOR_Y=%.2f 上、且是一块薄片（底面 y=%.3f / 厚 %.3f）"
					% [GameRoom.FLOOR_Y, rb.position.y, rb.size.y])
			_check(rb.position.x <= -t3.WOOD_HALF_W and rb.end.x >= t3.WOOD_HALF_W \
					and rb.position.z <= -t3.WOOD_HALF_D and rb.end.z >= t3.WOOD_HALF_D,
				"地毯盖住木桌那两维（地毯 x ∈ [%.2f, %.2f] / z ∈ [%.2f, %.2f] ⊇ 木桌半宽 %.2f / 半深 %.2f）"
					% [rb.position.x, rb.end.x, rb.position.z, rb.end.z,
						t3.WOOD_HALF_W, t3.WOOD_HALF_D])
			var rug_hit := 0
			var rug_log := ""
			if seat_root != null:
				for i_r in 4:
					var bn_r: Node3D = seat_root.get_child(i_r)
					var cb_r: AABB = stand_boxes.get(bn_r.name, AABB())
					if cb_r.size != Vector3.ZERO and rb.intersects(cb_r):
						rug_hit += 1
						rug_log += "%s " % bn_r.name
			_check(rug_hit == 0,
				"地毯不压到任何一把椅子（压到 %d 把：%s —— 地毯大一圈就「坐到地毯上」了）" % [rug_hit, rug_log])

			# ---- 三期：吊灯的**可见几何**（`Room/Pendant`）----
			# 三条一起钉。它对应的是简报里那三条要求（"一盏看得见的吊灯 / 挂在光的位置附近 /
			# **别改光本身**"），而**光**那一边由上面「唯一主光源 + 桌面照度均匀」那一整段守着
			#（`LAMP_*` 一个数都不许动 ⇒ 这一段只量**新加的几何**，两者互不重叠）。
			#
			#   ① **吊杆顶到天花板**（`ROOM_CEIL_Y`）—— 少了它，灯就是"浮在桌上方的半截"。
			#   ② **灯罩在桌上方的光位附近**：平面落点 = `LAMP_LIGHT_POS` 的 (x, z)（容差 0.05）。
			#      这条挡的是"把灯挪到桌子正中 / 挪到墙角"——那种改法一眼看过去"也挺好看"，
			#      而它已经不是"挂在光的位置上"了。
			#   ③ **灯罩的屏幕脚印不压在桌垫窗口上**（协调者给的判据："默认档下它不许压到棋盘"）。
			#      量法：把灯罩世界 AABB 的八个角过 `world_to_canvas_px` 投影成画布矩形，
			#      与 `TEX_WINDOW_PX`（= 桌垫在画布上的那一块）比相交。**同一把尺子**：
			#      下面"光源不在桌垫窗口内"那条量的是**光点**，这条量的是**罩子的体**。
			#      **变红验证**：把 `room.gd.PENDANT_SHADE_BOTTOM` 从 2.6 降到 1.6 ⇒ 罩子沉下来、
			#      立刻压到左边那一列格子 ⇒ 这条先红（出图 `shots/room_c_bad_*` 那种）。
			var pend: Node = room.get_node_or_null("Pendant")
			_check(pend != null, "房间挂着吊灯（`Room/Pendant` —— 光有可见载体了）")
			if pend != null:
				var pend_box := _subtree_world_aabb(pend)
				_check(absf(pend_box.end.y - GameRoom.ROOM_CEIL_Y) < 0.05,
					"吊灯一路够到天花板（整盏顶面 y=%.2f == ROOM_CEIL_Y=%.2f —— 杆不够长就是浮着的一截）"
						% [pend_box.end.y, GameRoom.ROOM_CEIL_Y])
				var sh: Node = pend.get_node_or_null("Shade")
				var sb := _self_world_aabb(sh)
				_check(sb.size != Vector3.ZERO, "吊灯有灯罩（`Pendant/Shade` 量得到几何）")
				if sb.size != Vector3.ZERO:
					var sc: Vector3 = sb.get_center()
					_check(absf(sc.x - t3.LAMP_LIGHT_POS.x) < 0.05 and absf(sc.z - t3.LAMP_LIGHT_POS.z) < 0.05,
						"灯罩挂在吊灯光位附近（罩心 (%.2f, %.2f) vs LAMP_LIGHT_POS (%.2f, %.2f)）"
							% [sc.x, sc.z, t3.LAMP_LIGHT_POS.x, t3.LAMP_LIGHT_POS.z])
					# ③-a **平面落点**（协调者给的判据原话）：罩心的平面落点要在桌垫窗口之外。
					#     **与"光源不在桌垫窗口内"那条同一把尺子**（`world_to_canvas_px`
					#     + `TEX_WINDOW_PX`）—— 灯罩挂的就是光那一点，所以这两条本来就该同结论。
					var cpx: Vector2 = t3.world_to_canvas_px(sc)
					_check(not t3.TEX_WINDOW_PX.has_point(cpx),
						"灯罩的平面落点在桌垫窗口之外（罩心画布 %s —— 与那条「光源不在桌垫窗口内」同一把尺子）" % cpx)
					# ③-b **屏幕上不遮住桌垫** —— ③-a 只是**平面落点**这一点，而"压没压到棋盘"
					#     说的是**遮挡**，两者在"灯吊在桌面上方"时并不等价（罩子在 2.6~4.0 高处，
					#     它挡住的是**更远**那一块桌面，不是它正下方那一块）。
					#     ⇒ 真正要钉的是**相机投影下**的遮挡，量法：
					#       ① 罩子上下两圈口沿各取 16 点，投影到屏幕，取**凸包**（罩子是圆台、
					#          它的轮廓就是这两圈的凸包 ⇒ 这是**精确**轮廓，不是包络）；
					#       ② 桌垫四角走 `table_mesh.global_transform * uv_to_world` 投影成四边形；
					#       ③ `Geometry2D.intersect_polygons`——**空 = 不遮住**。
					#     **为什么不是"两个包围盒比相交"**：那是拿**矩形**替**圆台 / 斜四边形**，
					#     虚大的那一圈会把"其实一格没盖"报成盖住（这一条第一次跑就是这么假红的，
					#     实测两个包围盒交 103×85px，而轮廓多边形不相交）。
					#     两个半径**从 mesh 上读**（`CylinderMesh.bottom_radius` / `top_radius`），
					#     不抄 `room.gd` 的常量 —— 与全文件"不把实现重述一遍"同一条纪律。
					var scm := (sh as MeshInstance3D).mesh as CylinderMesh
					var rim: Array = []
					if scm != null:
						rim = [[scm.bottom_radius, sb.position.y], [scm.top_radius, sb.end.y]]
					_check(rim.size() == 2,
						"（前提）灯罩是圆台、量得到上下两个半径（否则下面那条恒真）")
					var sh_pts := PackedVector2Array()
					for ring in rim:
						for i_k in 16:
							var ang: float = TAU * float(i_k) / 16.0
							var r_k: float = float(ring[0])
							sh_pts.append(t3.camera.unproject_position(Vector3(
								sc.x + cos(ang) * r_k, float(ring[1]), sc.z + sin(ang) * r_k)))
					var mat_quad := PackedVector2Array()
					for uv in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]:
						mat_quad.append(t3.camera.unproject_position(
							t3.table_mesh.global_transform * TableGeometry.uv_to_world(uv, t3.TABLE_SIZE)))
					var hull := Geometry2D.convex_hull(sh_pts)
					var inter := Geometry2D.intersect_polygons(hull, mat_quad)
					_check(inter.is_empty(),
						"吊灯罩在屏幕上不遮住桌垫（罩轮廓 %d 点 ⊗ 桌垫四边形 = %d 块交 —— 默认档）"
							% [hull.size(), inter.size()])

	# ---- 批次 6 Task 1 → 批次 13 ⑦⑧：台灯（唯一主光源）+ 桌面照度均匀 ----
	# 观感的主角仍是**光**：全场只有一盏 `OmniLight3D`（`lamp_light`），它同时是**唯一**的
	# 投影源（手牌 / 转盘 / 棋子 / 房子的影子全来自它）。可执行的判据：
	#   ① 全场只有这一盏、开着阴影；② 暖色；③ 吊在桌面上方；
	#   ④ 它的**平面落点**在桌垫窗口之外（光不许压在棋盘上 —— 批次 13 ⑦⑧"只抬 y、不动水平"
	#      那条裁定就是为它让的路）；⑤ **远端角落在射程的 0.9 以内**（射程之外照度归零 ⇒ 桌角
	#      直接黑掉，而本批把衰减压平之后射程那一项**重新有了话事权**，见 `_mat_sample_irradiance`）；
	#   ⑥ **桌面各位置的照度一致**（批次 13 ⑧ 反转出来的那一条，见下面那段）。
	#
	# **批次 6 那整段「房间剪影」已随批次 13 ⑨ 删除** —— 三面墙 / 书架 / 床架
	# 连同"块数 ≥ 8 / 三面墙点名 / 近黑 / 高粗糙 / 不透明 / 共用材质 / 不压桌子 / 不投影"
	# 那**八条**断言（与"容器带 Room"那道门）一起没了。
	# **这不是放宽，是载体没了**：那八条量的全是**剪影物体自己的材质与摆放**，物件被用户 ⑨
	# 要求删掉之后，它们既无从量起、背后那套"剪影可辨"（`ROOM_EMISSION` 底光）也随 `room_mat`
	# 一起删了。谁把剪影加回来，得**连这套判据一起加回来**（只把物体加回去 = 无人守）。

	# 环境光要参与"桌面均匀"那条代理式（它那一份**与位置无关**，是渲染器真会加上去的一层）⇒ 先取。
	var wenv: WorldEnvironment = null
	for c in t3.get_children():
		if c is WorldEnvironment:
			wenv = c
	var amb_irr := 0.0
	if wenv != null:
		amb_irr = wenv.environment.ambient_light_energy \
			* wenv.environment.ambient_light_color.get_luminance()

	print("== 批次 6 / 批次 12 A1 / 批次 13 ⑦⑧：唯一主光源 + 桌面照度均匀 ==")
	# 用 get("lamp_light") 而不是 t3.lamp_light：**红跑**（还没实现）时前者给 null、
	# 后者是 "Invalid access to property" 的脚本错误，会把 _run() 打断在半路、
	# 后面的断言一条都跑不到（红跑还会挂住不退）。
	var lamp_l = t3.get("lamp_light")
	_check(t3.get_node_or_null("Lamp") == null,
		"台灯的可见几何已删净（树里没有名为 Lamp 的节点）")
	_check(lamp_l != null, "唯一主光源仍在（`lamp_light` / 节点名 LampLight）")
	if lamp_l == null:
		_check(false, "光源缺了，下面那组断言整段跳过")
	else:
		# 全场唯一的光源：**别留下第二盏会投影的灯**（第二盏 = 多一张阴影图 + 氛围被拆开）
		var lights: Array = []
		for n in t3.find_children("*", "Light3D", true, false):
			lights.append(n)
		# 【一期 Task 8】从"只有一盏灯"改成"**只有一处投影源**" —— 房间需要补光（`Room/FillLight`，
		# 见 `room.gd.FILL_LIGHT_POS`），但**投影必须仍然唯一**：第二张阴影图 = 性能与氛围
		# 两头不讨好（那盏吊灯仍是手牌 / 转盘 / 棋子 / 房子所有影子的唯一来源）。
		# ⚠ **这不是放宽**：原来那条"只有一盏灯"守的有一半是这件事，另一半（**灯共几盏**）
		# 由下面「补光恰好一盏」那组断言守着 —— 原注释在这里写"它被下面那条『补光不碰桌面』
		# 接住了"，**那句是错的**（终审 F2 改正）：补光**缺席**时"不碰桌面"恰恰是最松的一条
		#（`0.0 <= 0.08` 恒真），两条一起才拦得住。见下面那段。
		var casters: Array = []
		for n in lights:
			if (n as Light3D).shadow_enabled:
				casters.append(n)
		_check(casters.size() == 1 and casters[0] == lamp_l,
			"全场只有一处投影源（实得 %d 处；灯共 %d 盏）" % [casters.size(), lights.size()])
		_check(lamp_l.shadow_enabled, "台灯开着阴影（桌上的实物才投得出影子）")
		_check(lamp_l.light_color.r > lamp_l.light_color.b + 0.1, "台灯是暖色（r 明显大于 b）")
		var lp: Vector3 = lamp_l.global_position
		_check(lp.y > t3.table_mesh.global_position.y + 1.0,
			"主光源吊在桌面上方（实得 y=%.2f —— 批次 13 ⑦⑧抬到 10 高，桌面上的 N·L 才收得平）" % lp.y)
		# 【批次 13 ⑦⑧删掉的那条】原来这里断言「光源位置逐位 == `LAMP_LIGHT_POS`」。
		# **意图反转，不是放宽**：那条钉的是**批次 12 A1 那次"删可见几何时不许顺手挪光"**
		#（当时整套光照参数都是照着那个世界点取的）。本批**有意**把光抬高了（y 2.73 → 10）
		# 并整套重取了参数 ⇒ "位置不许动"这条契约的对象在本批不存在了。
		# **仍然不许动的是它的水平位置**（`x` / `z`）—— 那一条由下面「光源不在桌垫窗口内」继续守着
		#（把灯挪到桌子正上方就会压在棋盘上 ⇒ 立刻红）。
		#
		# 光池要够到棋盘：**远端角落在射程的 0.9 以内**。本批把衰减指数压到 0 之后，
		# 射程那一项 `(1 − (d/range)^4)^2` **重新成了唯一还会随距离变化的因子**（见下面那段）：
		# 射程一收，桌角就直接被乘到 0 —— 这条比改动前更该留着。
		var corners: Array = []
		for sx in [-t3.TABLE_SIZE.x * 0.5, t3.TABLE_SIZE.x * 0.5]:
			for sz in [-t3.TABLE_SIZE.y * 0.5, t3.TABLE_SIZE.y * 0.5]:
				corners.append(Vector3(sx, t3.table_mesh.global_position.y, sz))
		var d_far := 0.0
		for cw in corners:
			d_far = maxf(d_far, lp.distance_to(cw))
		_check(d_far <= lamp_l.omni_range * 0.9,
			"远端角落在射程的 0.9 以内（远端 %.2f ≤ %.2f，射程 %.1f —— 射程之外照度归零、桌角会黑掉）"
				% [d_far, lamp_l.omni_range * 0.9, lamp_l.omni_range])
		# 【批次 13 ⑦⑧换掉的那一组】原来是「远端角照度 ≥ 1.1 / ≥ 近端 × 0.25 / 衰减 ≤ 1.0 /
		# 光池不拉成长条」。它们钉的是**批次 6/10 那套「中心亮、四周暗」的分布**（远端要够亮、
		# 但又不许亮过近端太多，衰减不许比线性更陡）—— 本批用户 ⑧ 要的正是**取消渐变**
		# ⇒ **意图反转**：换成下面两条"均匀"断言（含 N·L 与射程形状的同一口径代理式）。
		#
		# ---- 批次 13 ⑧：**桌面各位置的亮度一致** ----
		# 采样点 = 桌垫**四角 + 中心**。四角正是改动前落差最大的两处：近灯那对角 N·L ≈ 0.70、
		# 远端那对角只有 0.30，再乘 0.72 的衰减 ⇒ 批次 10 实测**左/右 4.4:1**。
		# 代理式见 `_mat_sample_irradiance`：**与渲染器同口径**（GLES3 的
		# `max(1 − (d/range)^4, 0)^2 × d^(−指数)` × 能量 × N·L），再加上环境光那一份。
		var samples: Array = corners.duplicate()
		samples.append(Vector3(0.0, t3.table_mesh.global_position.y, 0.0))
		var i_min := INF
		var i_max := 0.0
		var i_light_min := INF      # 只算灯的直射那一份（环境光单列 —— 见两条各守什么）
		var i_light_max := 0.0
		for p in samples:
			var lit: float = _mat_sample_irradiance(lamp_l, p, 0.0)
			i_light_min = minf(i_light_min, lit)
			i_light_max = maxf(i_light_max, lit)
			var total: float = lit + amb_irr
			i_min = minf(i_min, total)
			i_max = maxf(i_max, total)
		# ① **均匀**（本批的核心判据 = "桌面完全均匀"的可执行定义）。**含环境光**：它也是渲染器
		#    真会加上去的一层、且与位置无关 ⇒ 含它才与画面一致。
		#    1.4 是设计给的界；本档实测 **1.27**（1.314 / 1.035）。
		#    **同一口径、同一组采样点下改动前那套参数是 5.1:1**（能量 3.9 / 射程 12.5 / 指数 0.72 /
		#    光高 2.73 ⇒ 近左角 1.09、远右角 0.21 —— 出图逐列实测的 4.4:1 是另一个口径）⇒ 必红。
		#    **本条会红在哪**（实跑验证：光挪回 2.73 高、其余不动 ⇒ 实测 **1.88** 红；
		#    射程收回 12.5 ⇒ 按同一公式 **2.66**，且上面那条"远端角 ≤ 0.9×射程"同时红：
		#    13.18 > 11.25 是算术）。
		#    ⚠ **把 `LAMP_ATTEN` 单独调回 0.72 本条仍绿**（射程 30 下只有 `d^-0.72` 那一项在动，
		#    实测 1.24）—— 那一档红的是下面 ②（远端角的直射照度掉到 0.13）。两条各守一半，
		#    **别以为一条能顶两条**。
		_check(i_max / i_min <= 1.4,
			"桌面各位置亮度一致（最高 %.3f / 最低 %.3f = %.2f ≤ 1.4，含环境光 %.3f —— 用户 ⑧）"
				% [i_max, i_min, i_max / i_min, amb_irr])
		# 【一期 Task 8 注】本条的求和**只有吊灯 + 环境光两项**（`lamp_l` 的直射 + 与位置无关的
		# 环境光那一份）——**没有把房间那盏补光算进来**。补光是本批新加的，本条是用户签过字的
		# 契约、语义不动；**补光落在桌面上的那一小份由下面那条"补光对桌面的照度贡献 ≤
		# `FILL_ON_TABLE_MAX`"单独封顶**（实测 0.0494，只有吊灯直射那份 0.79~1.12 的 6%）。
		# 两条合起来才等于"桌面亮度不许被偷改"：**改补光时别只看这一条**
		#（把 `FILL_ENERGY` 提到 1.0 ⇒ 本条仍绿 1.27、下面那条红 —— 实跑验证过）。
		# ② **灯仍是主角、且够亮**（把 ① 里与位置无关的环境光那一份摘掉，单看直射）。
		#    少了这条，"环境光抬到 0.75 + 灯只给一点点"也能把 ① 糊过去（而那不是"一盏灯照亮桌面"）。
		#    本档实测 **0.85 ~ 1.12**：下界 0.5 挡"能量塌掉 / 射程被收小 / 光被挪远"，
		#    上界 1.8 挡"能量退回批次 6 的 3.9"（衰减已压到 0 ⇒ 那会把近灯那一列推到 ~3.6、烤白）。
		_check(i_light_min >= 0.5 and i_light_max <= 1.8,
			"灯的直射照度在采用档位附近（最低 %.3f ≥ 0.5、最高 %.3f ≤ 1.8 —— 能量 %.2f / 射程 %.1f / 指数 %.2f）"
				% [i_light_min, i_light_max, lamp_l.light_energy, lamp_l.omni_range,
					lamp_l.omni_attenuation])

		# ---- 一期 Task 8 新增 ①：**补光存在、且不许改掉桌面** ----
		# 房间那一盏补光（`Room/FillLight`，不投影）是为了给墙 / 家具方向感与明暗；它**不许**
		# 顺手把批次 13 ⑧ 那条"桌面各位置亮度一致"改掉（那是用户签过字的）。用**同一把照度代理式**
		# 量它落在桌面采样点上的那一点贡献（设计 §五「尺子只能用一把」—— 这里**不许**改成
		# "屏幕取像素"，那会变成第二把尺子）。
		# 阈值 `FILL_ON_TABLE_MAX` 的取值口径见它的声明处（先实测、再定档）。
		#
		# 【终审 F2 修：这三条**必须都要求补光真存在**】改前这里是 `fill_max := 0.0` 与
		# `fill_non_omni := ""` 两条 —— 它们**只在"存在非吊灯的灯"时才被写**：一盏非吊灯都没有时
		# 循环体一次都不跑 ⇒ `"" == ""` 与 `0.0 <= 0.08` **双双恒真**（把 `Room/FillLight` 删掉 /
		# 改名 / 挪出 `FILL_RANGE`，十五套件全绿而无人在守这盏灯 —— 正是 Task 8 的整件事）。
		# 消息那头也退化回 Task 9 Step 0 ③ 点名要修的 `实得「」` 空插值（"消息修好了"只修在
		# "补光存在"那条路上）。⇒ 现在每条都带 `fill_lights.size() == 1`、消息一律印**真值**
		#（灯共几盏 / 非吊灯几盏 / 每一盏的类名）。
		var fill_lights: Array = []
		var fill_kinds := ""
		var fill_max := 0.0
		for n in lights:
			if n == lamp_l:
				continue
			fill_lights.append(n)
			# 照度代理式是按 **omni** 写的（射程形状 + 距离衰减 + 桌面法线朝上的 N·L）——
			# 补光换成平行光，这把尺子就量不了它，"不碰桌面"只剩肉眼（那正是要避免的）。
			# 「实得」那一栏报的是**每一盏非吊灯的类名**（非 omni 的另外点名）—— 通过时印
			# `OmniLight3D`、不通过时印 `DirectionalLight3D（非 omni）`，两头都读得懂。
			var nl := n as OmniLight3D
			if nl == null:
				fill_kinds += "%s（非 omni） " % (n as Node).get_class()
				continue
			fill_kinds += "%s " % (n as Node).get_class()
			for p in samples:
				fill_max = maxf(fill_max, _mat_sample_irradiance(nl, p, 0.0))
		# ①-a **补光恰好一盏**（存在性 —— 这条是终审 F2 补回来的；原 `lights.size() == 1` 的那一半
		#     被降级成了读数，见上面 :621 那段改正的注释）。
		#     变红验证（实跑过）：把 `room.gd._build_shell` 里那一句 `_build_fill_light()` 注掉
		#     （补光整盏不存在）⇒ 本条与下面两条一起红（layout_test 3 FAILURES）。
		#     **改名不算**：这条数的是"非吊灯的灯有几盏"，与节点名无关（改名不动运行时、也不该红）。
		#     下面三条的"实得"都印**真值**：一盏非吊灯都没有时印 `（没有非吊灯的灯）`，
		#     不再退回 Task 9 Step 0 ③ 那个 `实得「」` 空插值。
		var fill_kinds_s: String = fill_kinds.strip_edges()
		if fill_kinds_s == "":
			fill_kinds_s = "（没有非吊灯的灯）"
		_check(fill_lights.size() == 1,
			"补光恰好一盏（灯共 %d 盏 ⇒ 非吊灯 %d 盏；实得「%s」—— 一盏都没有时下面两条恒真）"
				% [lights.size(), fill_lights.size(), fill_kinds_s])
		# ①-b **是 omni**（照度代理式只认 omni）。
		_check(fill_lights.size() == 1 and fill_lights[0] is OmniLight3D,
			"补光是 OmniLight3D（照度代理式只认 omni；实得 %d 盏非吊灯「%s」—— 换平行光就没人量得动它了）"
				% [fill_lights.size(), fill_kinds_s])
		# ①-c **不碰桌面**（`FILL_ON_TABLE_MAX` 封顶）。`fill_lights.size() == 1` 这一半不能省：
		#     少了它，补光缺席时 `fill_max` 是 0.0 ⇒ 这条断言恒真。
		_check(fill_lights.size() == 1 and fill_max <= FILL_ON_TABLE_MAX,
			"补光对桌面的照度贡献 ≤ %.2f（实得 %.4f，量到 %d 盏非吊灯 —— 超了就是把批次 13 ⑧ 的"
				% [FILL_ON_TABLE_MAX, fill_max, fill_lights.size()]
				+ "「桌面均匀」偷偷改掉了）")
		# ①-d **下界**（一期审查残留，2026-10-06 补）：F2 修的是"补光缺席时上面三条恒真"，
		#     管不住另一半 —— **灯在但没效果**（能量归零 / 挪出射程 ⇒ fill_max ≈ 0 依旧全绿）。
		#     用同一把尺子的 fill_max 量"它还在干活"；阈值口径见 `FILL_ON_TABLE_MIN` 声明处。
		_check(fill_lights.size() == 1 and fill_max >= FILL_ON_TABLE_MIN,
			"补光对桌面的照度贡献 ≥ %.2f（实得 %.4f —— 掉到 0 就是灯在而不亮，屋子明暗没了出处）"
				% [FILL_ON_TABLE_MIN, fill_max])

		# ---- 一期 Task 8 新增 ②：**家具不再是画面里最亮的东西** ----
		# 病（Task 7 出图实证）：Kenney 那批 `.glb` 是**零贴图的纯平奶白**，而屋子是暗木 + 灰墙、
		# 桌面那圈木纹还**带贴图** ⇒ 家具成了画面里最亮、最没质感的东西，读作"没上材质的占位块"。
		# 判据 = **"被照亮的 albedo"**：每件家具的 albedo 亮度 × 它自己那点照度，必须比
		# **桌面最暗那个采样点**的同一笔更暗 —— 也就是"家具连桌面最暗的那一角都比不过"，
		# 这正是"不再是画面里最亮的东西"的保守写法（拿桌面的**最暗**处去比，是故意从严）。
		# albedo **从材质上读**（不读 `GameRoom.FURN_ALBEDO`：读常量等于把实现重述一遍，
		# 材质改成什么色都照样过 —— 本文件反复警告的那类永真断言）。
		var fur_lit := 0.0
		var fur_lum := -1.0
		var fur_n := 0
		var fur_log := ""
		var fur_roots: Array = []
		if room != null:
			var furn8: Node = room.get_node_or_null("Furniture")
			if furn8 != null:
				fur_roots.append_array(furn8.get_children())
			var seats8: Node = room.get_node_or_null("Seats")
			if seats8 != null:
				for s in seats8.get_children():
					for ch in (s as Node).get_children():
						# （v0.8.0 改版：原先这里要跳过 `Nameplate` —— 它是棋子色、故意的亮。
						#  椅背名牌已整段删除，椅子那一支现在只剩椅子自己。）
							fur_roots.append(ch)
		var wood_lum := 0.0
		var wm8 := t3.wood_mesh.material_override as StandardMaterial3D
		if wm8 != null:
			wood_lum = wm8.albedo_color.get_luminance()
		for n in fur_roots:
			var lum := _subtree_albedo_lum(n)
			if lum < 0.0:
				continue
			fur_n += 1
			fur_lum = maxf(fur_lum, lum)
			# 采样点 = 这一件**世界 AABB 的形心**（形心随家具怎么摆怎么变，不另立一套坐标）
			var wb8 := _subtree_world_aabb(n)
			if wb8.size == Vector3.ZERO:
				continue
			var lit8: float = lum * _mat_sample_irradiance(lamp_l, wb8.get_center(), amb_irr)
			fur_log += "%s:%.3f " % [n.name, lit8]
			fur_lit = maxf(fur_lit, lit8)
		# 桌面那一笔 = **最暗的那个采样点**（同一把代理式、同一组采样点）
		var tab_lit := INF
		for p in samples:
			tab_lit = minf(tab_lit, wood_lum * _mat_sample_irradiance(lamp_l, p, amb_irr))
		_check(fur_n >= 7 and wood_lum > 0.0,
			"（前提）家具与椅子都量得到材质与尺寸（%d 件；木桌 albedo 亮度 %.3f）" % [fur_n, wood_lum])
		var lit_ratio: float = fur_lit / maxf(tab_lit, 0.0001)
		_check(lit_ratio <= FURN_LIT_RATIO_MAX,
			"家具不再是画面里最亮的东西：最亮的家具 albedo × 照度 %.4f ≤ %.2f × 桌面最暗那个角 %.4f"
				% [fur_lit, FURN_LIT_RATIO_MAX, tab_lit]
				+ "（实得比值 %.3f，家具 albedo 亮度 %.3f ≤ 木桌 %.3f；逐件 %s）"
				% [lit_ratio, fur_lum, wood_lum, fur_log])
		# 光**不许压在棋盘上**：它的平面落点要在**桌垫窗口之外**
		#（窗口 = 棋盘 + 一圈留白；压在窗口里就成了"棋盘上方的灯"）。
		# **批次 12 A1**：原先这里查的是"灯杆 / 灯罩 / 光源三个都不在窗口内"（实物已删），
		# 今天只剩光这一个 —— 判据本身没变，只是对象少了两件。
		# **批次 13 ⑦⑧**：这条就是那条"水平位置不动"裁定的**唯一执行者** —— 抬 y 不改平面落点，
		# 所以它在；把灯挪到桌心（x → 0）会让它立刻红。
		_check(not t3.TEX_WINDOW_PX.has_point(t3.world_to_canvas_px(lamp_l.global_position)),
			"光源不在桌垫窗口内（画布 %s）" % t3.world_to_canvas_px(lamp_l.global_position))
		# 【批次 12 A1 删掉的那两条】
		#   ① 「3D 端看得见台灯」（灯罩屏幕包围盒与画面相交占比 ≥ 0.5）—— 灯罩已删，无从量起；
		#      它当年是 `CAM_DIST` **最紧**的一条约束（4.60 时就红），删掉它之后相机才能收到 4.15
		#     （批次 12 A2）；
		#   ② 「灯罩的屏幕位置不落在桌垫上」—— 同上，随灯罩一起去。
		# 两条都不是"放宽"，是**判据的载体没了**。

	print("== 批次 13 ⑦⑧：环境光托底 + 背景仍近黑 ==")
	_check(wenv != null, "容器带 WorldEnvironment")
	if wenv != null:
		var en := wenv.environment
		# 环境光是**与位置无关**的那一层，本批把它从"压到很低"**反转成"托底"**：
		# 原先那条断言是 `< 0.25`（那时候环境光一高，"一盏台灯 + 中心亮四周暗"就被淹没了）；
		# 本批用户 ⑧ 要的是"桌面各位置亮度一致、暗部的字也读得出" ⇒ 它得**抬**（见 `LAMP_ATTEN`
		# 那张表：环境光那一份把极差从 1.33:1 压到 1.26:1）。
		# **钉区间而不是单边**：下界 0.30 防"又压回去"（远端那两列重新读不出字），
		# 上界 0.75 防"抬过头"（桌面被均匀洗成一块死平的光、与灯的暖色叠加后发灰）。
		_check(en.ambient_light_energy >= 0.30 and en.ambient_light_energy <= 0.75,
			"环境光落在新档位区间 [0.30, 0.75]（energy %.2f —— 与位置无关的那一层，托住暗部）"
				% en.ambient_light_energy)
		_check(en.background_color.get_luminance() < 0.03,
			"背景色近黑（亮度 %.3f —— 桌子之外仍是暗底：⑨ 删的是物件，不是背景）"
				% en.background_color.get_luminance())
		# 【批次 13 ⑨删掉的那三条】剪影底光那一组（`room_mat.emission` 与
		# `albedo × 环境能量 × 环境色` 要和背景亮度比大小）—— **载体没了**：`room_mat` 与三件剪影
		# 随用户 ⑨ 一并删除。它们当年守的是"剪影不许比它身后的背景更暗"（床架出图 1/255 < 背景
		# 4~6/255），而**今天画面里已经没有剪影**，这个比较没有对象了。
		# **"背景近黑"那条仍留在上面** —— 它守的是"暗底"，与剪影有没有无关。


	print("== 贴图窗口 = 桌垫（棋盘 + 一圈留白），不再铺满整张画布 ==")
	# 批次 5 Task 2：座位栏退场，画布不再需要为它们预留 —— 窗口从"整张画布"
	# 收到"桌垫"（`BoardView.MAT_RECT`）。批次 2 的 T4c 之所以把窗口恢复成整张画布，
	# 是因为当时上家座位栏会落到窗口之外、既看不见也点不到；座位栏一走，这条约束随之解除。
	# 窗口是否覆盖了该覆盖的东西，由下面「棋盘整块在窗口内」那段钉住。
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
	# 【一期 Task 7】判据按 `view_t` 插值：3D 端（wt=0）= **木桌四角**、2D 端（wt=1）= **桌垫四角**。
	# 方向容易搞反：**木桌比桌垫大** ⇒ 3D 端是**收紧**、不是放宽（设计 §四）。
	# 为什么 3D 端要收紧回木桌：房间里要有"上缘那条带子"，**木桌远边必须进画** ——
	# 只认桌垫的话木纹可以整条出画，上缘就永远只剩桌垫自己的边缘（批次 10 松掉的那条，
	# 现在按用户 2026-10-05 的拍板收回来）。
	# 四角一律从**两个现成的常量**取，不写死数字：桌面不是正方形（进深由窗口比例定）。
	var hw_mat: float = t3.TABLE_SIZE.x * 0.5
	var hd_mat: float = t3.TABLE_SIZE.y * 0.5
	var hw_wood: float = t3.WOOD_HALF_W        # Step 0 刚加的（= TABLE_W/2 + WOOD_FRAME）
	var hd_wood: float = t3.WOOD_HALF_D
	# **推拉只扫默认档**（`dolly == 1.0`）：这条契约是"默认取景"的契约，推拉值漏进来
	# 就不是同一条合同了（那条轴由下面那组推拉断言管）。
	t3.snap_dolly(1.0)
	for i in 21:
		var wt := i * 0.05
		t3.snap_view(wt)
		var hw: float = lerpf(hw_wood, hw_mat, wt)
		var hd: float = lerpf(hd_wood, hd_mat, wt)
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

	# 【一期 Task 7 新增】上缘必须留出房间带 —— 木桌远边不得贴到视口顶端，否则"房间"根本没露头。
	# ⚠ **这里不再钉死 32%**（2026-10-05 改）：32% 与"格子 ≥32px"数学上互斥（spec §四 追加一节），
	# 解结的办法是加推拉轴、把二选一交给玩家现场掌控 ⇒ 默认档的**硬门是格子 ≥32px**（下面那条），
	# 房间带取"32px 还能撑住的**最外**取景"、实测值打印出来（**不许静默取值**）。
	t3.snap_view(0.0)
	var top_edge_y := _wood_far_edge_y(t3)      # 【终审 F4】与 ④ 那条共用同一处投影
	print("  [实测] 默认档房间带 = 视口高 %.1f%%（木桌远边 y=%.1f / 视口 %.0f）"
		% [100.0 * top_edge_y / vr.size.y, top_edge_y, vr.size.y])
	_check(top_edge_y >= vr.size.y * 0.03,
		"3D 端上缘留出房间带（木桌远边 y=%.1f ≥ 视口高 3%% = %.1f）"
			% [top_edge_y, vr.size.y * 0.03])
	# 【R42】只钉「四个角都在画面内」是能被骗过去的：把 VIEW_DIST_2D 调大让桌面整体变小，
	# 四角照样落在画面内，而 2D 端就成了一张小图 —— 验收要求是「始终在画面内**且大小接近**」。
	# 所以再钉一条：两端桌面投影**包围盒的面积比**必须落在 [0.6, 1.6]（用 unproject_position
	# 把四角投影出来算包围盒）。少了这条，"把桌面缩小"这种退化会全绿通过。
	var boxes: Array = []
	# 【一期 Task 7 改】"两端大小接近"这一对**换了对象**：原来比的是「3D 默认档 ↔ 2D 端」，
	# 那时两端都是"读棋盘"的档。用户拍板"默认看屋子"之后，3D 默认档**有意**缩到 32px 硬底线
	# （面积只有 2D 端的 ~2.6 分之一）—— 这时再拿它对 2D 端比"大小接近"就**前提不成立**了。
	# **不是放宽、是换对比对象**：仍然比"两张**读棋盘**的视图"，即 **2D 端 ↔ 3D 推近端**
	# （`DOLLY_MIN`，实测 44.5px 对 53.2px —— 正是这条断言要的"大小接近"）；
	# 默认档与 2D 端的面积比仍按实测打印出来（读数、不当门槛）。**区间 [0.6,1.6] 一个字没动。**
	for spec in [[0.0, t3.DOLLY_MIN], [0.0, 1.0], [1.0, 1.0]]:
		t3.snap_dolly(spec[1])
		t3.snap_view(spec[0])
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for sx in [-hw_mat, hw_mat]:
			for sz in [-hd_mat, hd_mat]:
				var sp: Vector2 = t3.camera.unproject_position(Vector3(sx, 0.0, sz))
				mn = mn.min(sp)
				mx = mx.max(sp)
		boxes.append(Rect2(mn, mx - mn))
	var area_near: float = (boxes[2] as Rect2).get_area() / (boxes[0] as Rect2).get_area()
	var area_def: float = (boxes[2] as Rect2).get_area() / (boxes[1] as Rect2).get_area()
	print("  [实测] 桌面投影面积比：2D端/3D推近端 = %.2f（门槛 [0.6,1.6]）；2D端/3D默认档 = %.2f"
		% [area_near, area_def]
		+ "（**读数**：默认档是「看屋子」那一档，有意比 2D 端小，不当门槛）")
	_check(area_near > 0.6 and area_near < 1.6,
		"两端**读棋盘**的视图投影大小接近（2D端 / 3D推近端 面积比 %.2f，须在 [0.6,1.6]；3D 推近端 %s / 2D 端 %s）"
			% [area_near, boxes[0], boxes[2]])
	t3.snap_dolly(1.0)
	# ---- 批次 10 T2：钉住"字更大"的可执行判据 = 一格的**屏幕宽度** ----
	# 前面两条（余量 / 面积比）只保证「整块桌垫在画面里、两端大小接近」——**只把相机往后退**
	# 就照样全绿，而桌子在屏幕里整体缩小、"字更大"这个本批目标恰恰落空。
	#（**别拿"桌垫与相机等比一起往外挪"来推这条**：那是自相似变换，两条守卫与格子屏幕宽
	#  都不会变 —— 那种挪法说明不了任何事。这条拦的是**只动相机**那一档。）
	# 补一条**绝对尺寸**：
	# 取**最不利**的一格（远端正中：50° 俯角下它被透视压得最扁），量它四角投影的包围盒宽。
	t3.snap_dolly(1.0)
	t3.snap_view(0.0)
	await process_frame
	t3.board.fit_overview(true)      # 量格宽要 BoardView 的取景变换（_view_from_world）是当前态
	await process_frame
	var probe_idx: int = t3.board.grid_to_index(GameData.BOARD_COLS / 2, 0)   # 远端正中那格
	var probe_w3: float = _tile_screen_w(t3, probe_idx)
	t3.snap_dolly(t3.DOLLY_MIN)
	await process_frame
	var probe_w_near: float = _tile_screen_w(t3, probe_idx)
	t3.snap_dolly(t3.DOLLY_MAX)
	await process_frame
	var probe_w_far: float = _tile_screen_w(t3, probe_idx)
	t3.snap_dolly(1.0)
	t3.snap_view(1.0)
	await process_frame
	var probe_w2: float = _tile_screen_w(t3, probe_idx)
	t3.snap_view(0.0)
	print("    格子屏幕宽（一期 Task 7）：3D 默认档 %.1fpx / 推近端(%.1f) %.1fpx / 拉远端(%.1f) %.1fpx / 2D 端 %.1fpx"
		% [probe_w3, t3.DOLLY_MIN, probe_w_near, t3.DOLLY_MAX, probe_w_far, probe_w2])
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
	#
	# ---- 批次 12 A2：**两条都按新基线重取**（台灯那条闸已随 A1 删除、相机一路收到 4.30）----
	#   * **2D 端 42.8 → 50.0px**（`VIEW_DIST_2D` 7.6 → 6.63）：**到得了设计稿的目标 50**
	#     ⇒ 门槛钉 **49.5**（实测量到 50.0，留 0.5px 只为浮点噪声，不是为了放宽）。
	#   * **3D 端 37.6 → 41.2px**（`CAM_DIST` 4.7 → 4.30）：**到不了设计稿说的 44px**。
	#     ⚠ **A2 把"到不了"归给"只准动距离"是对的，但那句"要 44px 得改 CAM_FOV / CAM_TILT_DEG"
	#     里，两味药的成色差着一大截 —— 见下面 A2b 那段：俯角几乎换不到东西、镜头换得很实在。**
	#
	# ---- 批次 12 A2b：**换镜头**（`CAM_FOV` 55 → **39**、`CAM_DIST` 4.30 → **5.77**、
	#      `VIEW_DIST_2D` 6.63 → **9.20**）。两条都到得了本批目标：----
	#   * **2D 端 50.0 → 53.2px**（目标 53）⇒ 门槛钉 **52.6**（实测 53.2，留 0.6px 只为浮点噪声）。
	#   * **3D 端 41.2 → 47.3px**（目标 47）⇒ 门槛钉 **47.0**。
	#   **为什么是镜头而不是俯角 —— 这一段是本批量出来的，别丢**：
	#   * 格宽的解析式（`tile_world` 是一格的世界宽 0.4546，两端同一条）：
	#     `w = 400·tile_world / (depth_far · tan(vfov/2))`；而**取景把近端那一头钉死**：
	#     近角水平余量 > 5px ⇔ `depth_near · tan(vfov/2) ≥ 2.52`
	#     （`depth_near = dist/cosφ − hd·cosφ`、`depth_far = dist/cosφ + hd·cosφ`）。
	#   * **抬俯角 φ、距离不动 ⇒ 相机被顶高**（`dist/cosφ` 随 φ 单调增）⇒ `depth_far` 变大、
	#     格宽**变小**。抬 φ 唯一的好处是放宽**取景余量**（近端角在屏幕上收窄、允许把 dist 压小），
	#     而 dist 的下界**不是取景、是手牌整排要留在屏内**：牌心在 z≈3.164，
	#     它到屏幕下沿的余量随 φ 变大而变小（`≈ z_h·sinφ / ((dist/cosφ − z_h·cosφ)·tan(vfov/2))`）
	#     ⇒ **抬俯角挣来的取景余量，正好被手牌那条吃掉**。探针扫过（保持"手牌仍在屏内"）：
	#     50° → 41.2、56° → 41.5、60° → 42.0、64° → 42.8、**76° → 46.5** —— 即要 47px
	#     得把 3D 端推到 **76°**（几乎就是 2D 端 88°），且手牌（`HAND_TILT_DEG` 20°、几乎平躺）
	#     在那里被看成 56° 斜切、卡面读不出来。**俯角这一味不划算**（到 64° 只换 1.6px，
	#     代价是整个"坐在桌边"的身份）。
	#   * **收镜头（`CAM_FOV`）才管用**：它不改相机的**角度**，只改"近大远小"的**比例**——
	#     收窄 FOV 时近远两端在屏幕上的大小差被压掉（`depth_far·tan(vfov/2)` 往
	#     `depth_near·tan(vfov/2)` 靠），格宽随之**变大**，而相机同步往后退、取景余量守住。
	#     实测每一档（相机都退到"余量刚够"）：55° → 41.2px、48° → 43.5、44° → 45.2、
	#     42° → 46.0、40° → 46.8、**39° → 47.3**、38° → 47.7px。
	#     代价是透视变平（近端格子不再"扑上来"）—— 比抬俯角便宜得多。
	#   * 两端一起收 ⇒ 面积比 **0.97**（A2 是 0.92）；整轨最小余量 **11.6px @ wt=0.00**。
	# **两条前提写在这里，免得后人把这条当"字的大小"本身读**：
	#   ① 这是**代理量**：`_tile_screen_w` 量的是**格子的屏幕包围盒宽**，它只在 **`TILE` 与格内
	#      字号都不变**时才与"屏幕上那格字"成比例。**批次 12 A2b 格内字号动了**（棋盘名
	#      18 → 22、价格行 14 → 16，见 `board_view._build_tiles`）⇒ **格宽这条不再是"字"的
	#      全部**：屏幕上的字大小 = 格宽 × 格内字号（同一帧里两者相乘）。这条仍按**格宽**
	#      钉（本批的相机改动直接作用在它上面），**字号那一半由 `--shot` 出图核对"不换行、
	#      不溢出"**（22px 下 4 字名 ≈ 88px < 盒宽 92）；`TILE` 仍是 112.0 未动；
	#   ② 探针只守**远端正中**那一格（`probe_idx = grid_to_index(BOARD_COLS/2, 0)`）—— **远端
	#      【角】格没被覆盖**（角格通常投影更宽 ⇒ 这条偏保守，宁可漏也不误红）。
	#
	# ---- **一期 Task 7：3D 端那条下限换了判据（47.0 → 32.0）** ----
	# 批次 12 A2b 那条 47.0 钉的是"3D 端格子变大"（用户当时要"棋盘比例放大"）。
	# 用户 2026-10-05 拍板"**默认看屋子**"之后，3D 默认档**有意**后退到**格子 32px 的硬底线**
	#（spec §九 的回退触发器）：默认那档归"看屋子"，"读棋盘"改由 **Ctrl+滚轮推近端**（44.5px）
	# 与 **2D 端**（53.2px）承担 ⇒ 47.0 这条**前提反转**，不是放宽。
	# 三条一起钉住那个取舍（缺一条就能靠"悄悄改一个端点"骗过去）：
	#   ① 默认档 ≥ 32px（硬底线，**再往外推一点点就红** —— 这条与"房间带尽量大"共同定档）；
	#   ② 推近端 ≥ 默认档（"读棋盘"的退路不许丢，spec §九 后半句）；
	#   ③ 2D 端下限 52.6 **一个字没动**（那条契约本期不许碰）。
	_check(probe_w3 >= 32.0,
		"**默认档**格子屏幕宽 ≥ 32.0px（spec §九 硬底线；实得 %.1f —— 批次 12 A2b 是 47.3，" \
			% probe_w3 + "本档为「看屋子」有意后退到 32px 上沿）")
	_check(probe_w_near >= probe_w3,
		"**推近端**格子屏幕宽 ≥ 默认档（实得 %.1f ≥ %.1f —— 「读棋盘」那条退路不许丢）"
			% [probe_w_near, probe_w3])
	_check(probe_w_far > 0.0,
		"拉远端格子屏幕宽 > 0（实得 %.1f —— 那一端是「看屋子」用的，**不设下限**，只钉" \
			% probe_w_far + "它还看得见棋盘）")
	_check(probe_w2 >= 52.6,
		"2D 端格子屏幕宽 ≥ 52.6px（实得 %.1f；那条契约本期一字未动）" % probe_w2)

	# ---- 一期 Task 7：推拉轴的两条专属断言（③ 不改 2D 端 / ④ 拉远端把远墙拉进画）----
	print("== 一期 Task 7：Ctrl+滚轮推拉（第二条轴）==")
	# ③ **推拉不改 2D 端**：`view_t = 1` 时推拉的权重为 0 ⇒ 推拉前后 2D 端的取景与格宽
	# **逐字节相同**。这条是本期唯一不许碰的契约（2D 端"桌垫四角入画"），
	# 而推拉是一个**新加的自由度** —— 它最容易的翻车方式就是"顺手把 2D 端也乘了一下"。
	# 量法：三个推拉档各摆一次 2D 端，比 `camera.global_transform`（精确 `==`，不是近似）
	# 与格子屏幕宽。基准取推拉默认档。
	var ref_xf := Transform3D()
	var ref_tw := 0.0
	var dolly_2d_ok := true
	var dolly_2d_log := ""
	for dv in [1.0, t3.DOLLY_MIN, t3.DOLLY_MAX]:
		t3.snap_dolly(dv)
		t3.snap_view(1.0)
		await process_frame
		var xf: Transform3D = t3.camera.global_transform
		var tw := _tile_screen_w(t3, probe_idx)
		dolly_2d_log += "dolly%.1f:pos%s/w%.3f " % [dv, xf.origin, tw]
		if dv == 1.0:
			ref_xf = xf
			ref_tw = tw
		elif xf != ref_xf or tw != ref_tw:
			dolly_2d_ok = false
	_check(dolly_2d_ok,
		"推拉不改 2D 端（`view_t = 1` 时推拉权重为 0：相机变换与格宽逐字节相同；%s）" % dolly_2d_log)

	# ④ **拉远端把远墙拉进画** —— 否则"看屋子"那一端形同虚设。
	# 远墙在 `z = -ROOM_D * 0.5`；判据三条一起（缺一条就能骗过去）：
	#   * 墙脚线（`y = FLOOR_Y` 那一圈）**落在视口内** —— 墙脚在画内 ⇒ 墙脚之上那一片就是远墙；
	#   * 它比**木桌远边**更靠上（屏幕 y 更小）—— 否则那条线可能是被桌子挡住的/看错成地板缝；
	#   * ⚠ **并且必须比默认档看得更多**（墙脚线在屏幕上更靠下 = 露出更多墙）。
	#     这第三条是**实测补上的**：地板降到 `FLOOR_Y` 之后，**默认档的上缘本来就能打到远墙**
	#     （实测墙脚 y=143 就在画内，spec §六 记着这件事）⇒ 只钉"入画"那两条**恒真**，
	#     等于一条什么都没断言的断言。加一条"远墙带必须比默认档大出一档"（实测 **+54px**），
	#     "看屋子"那一端才真的被钉住（**不许静默留一条恒真的断言**）。
	#   * ⚠ **还有一件投影量不出来的事**（Task 7 实施时踩的坑）：远端**必须在屋里** ——
	#     相机一过近墙 / 天花板就窜到屋外，而它们是**双面**的 ⇒ **整张摆拍全黑**，
	#     上面这三条**全是绿的**。`DOLLY_MAX` 的上限因此由 `room.gd` 的
	#     `ROOM_NEAR_EXTRA` / `ROOM_CEIL_Y` 订（见那两段与 `table_3d.DOLLY_MAX` 段）；
	#     这条投影断言拦不住它 —— 【终审 F3 起不再"只能靠出图核"】：下面新增了一条
	#     "相机全程在屋里"的断言（扫 `DOLLY_MIN/中点/DOLLY_MAX` × `view_t 0/0.5/1`，留 0.5 余量），
	#     它是这件事的可执行合同（出图核仍照旧做：`shots/t7b_dollyfar_table_plain.png`）。
	t3.snap_dolly(t3.DOLLY_MAX)
	t3.snap_view(0.0)
	await process_frame
	# 墙脚三点与木桌远边都走公共投影（终审 F4：这三点此前写了三遍、木桌远边写了两遍）
	var wall_pts: Array = _far_wall_base_screen(t3)
	var wall_in := 0
	var wall_log := ""
	for sp in wall_pts:
		wall_log += "(%.0f,%.0f) " % [sp.x, sp.y]
		if sp.x >= vr.position.x and sp.x <= vr.position.x + vr.size.x \
				and sp.y >= vr.position.y and sp.y <= vr.position.y + vr.size.y:
			wall_in += 1
	var wood_edge_y := _wood_far_edge_y(t3)
	var wall_y := INF
	for sp in wall_pts:
		wall_y = minf(wall_y, sp.y)
	# 默认档的墙脚线（同样三点取最高那条）—— "拉远端比默认档多看多少"
	t3.snap_dolly(1.0)
	t3.snap_view(0.0)
	await process_frame
	var wall_y_def := INF
	for sp in _far_wall_base_screen(t3):
		wall_y_def = minf(wall_y_def, sp.y)
	print("  [实测] 拉远端（dolly %.1f）：远墙墙脚 %s/ 木桌远边 y=%.0f（视口 %.0f 高）"
		% [t3.DOLLY_MAX, wall_log, wood_edge_y, vr.size.y])
	print("  [实测] 远墙带：默认档墙脚 y=%.0f → 拉远端 y=%.0f（露出多 %.0fpx = 视口高 %.1f%%）"
		% [wall_y_def, wall_y, wall_y - wall_y_def, 100.0 * (wall_y - wall_y_def) / vr.size.y])
	_check(wall_in == 3 and wall_y < wood_edge_y,
		"拉远端把远墙拉进画（墙脚三点入画 %d/3、且都在木桌远边之上：墙脚 y=%.0f < 木桌远边 y=%.0f）"
			% [wall_in, wall_y, wood_edge_y])
	_check(wall_y - wall_y_def >= vr.size.y * 0.05,
		"拉远端比默认档**多看一截屋子**（远墙带 %.0fpx ≥ 视口高 5%% = %.0fpx：默认档 y=%.0f → 拉远端 y=%.0f）"
			% [wall_y - wall_y_def, vr.size.y * 0.05, wall_y_def, wall_y])

	# ---- 【终审 F3 新增】相机**全程在屋里** ----
	# 这是"全黑摆拍而断言全绿"的那条盲区（Task 7 真踩过：`dolly = 1.15` 时相机穿到近墙外，
	# 而近墙与天花板都是**双面**的 ⇒ 整张出图全黑，见 `shots/t7_dollyfar_table_plain.png` 那张
	# 77 KB 全黑图）。上面 ④ 那三条**只量投影**、量不出遮挡（原注释就写着"这条投影断言拦不住它，
	# **靠出图核**"）—— 相机位置是 `dolly` 与 `view_t` 的**确定函数**
	#（`table_3d._apply_camera`：`pos = (0, d3d·sin, d3d·cos)`）⇒ 可以直接扫成可执行的合同，
	# 把"天花板 / 近墙还剩多少余量"从注释里的两个数变成断言。
	# 房间盒取 `room.gd` 的**公开常量**（不写死）：`|x| ≤ ROOM_W/2`、`y ∈ [FLOOR_Y, ROOM_CEIL_Y]`、
	# `z ∈ [−ROOM_D/2, +ROOM_D/2 + ROOM_NEAR_EXTRA]`。**留 0.5 的余量**：余量 > 0 只说明"还没出屋"，
	# 相机**贴着**天花板 / 近墙时画面已经全黑（透视被挡在面外）⇒ 要它**在贴面之前**先红。
	# 实测最小余量 **1.15**（天花板，`dolly = DOLLY_MAX`、`view_t = 0`）。
	# 变红验证：把 `table_3d.DOLLY_MAX` 临时改成 1.5（相机 `y = 15.91`、离天花板只剩 0.09）⇒ 本条红。
	# 三档 × 三段视角都扫：3D 端那一段（`view_t = 0`）是推拉的权重所在，中段与 2D 端一并钉住
	#（`view_t` 越大相机越收回桌心，两端都不是最险的档，但多扫两行换"整条轨道"这句话）。
	var cam_bad := 0
	var cam_worst := INF
	var cam_log := ""
	for dv in [t3.DOLLY_MIN, (t3.DOLLY_MIN + t3.DOLLY_MAX) * 0.5, t3.DOLLY_MAX]:
		for wt in [0.0, 0.5, 1.0]:
			t3.snap_dolly(dv)
			t3.snap_view(wt)
			await process_frame
			var cp: Vector3 = t3.camera.global_position
			# 五个面各自到相机的余量（x 对称，取一次绝对值）
			var m_cam: float = minf(minf(GameRoom.ROOM_W * 0.5 - absf(cp.x), cp.y - GameRoom.FLOOR_Y),
				minf(minf(GameRoom.ROOM_CEIL_Y - cp.y,
					GameRoom.ROOM_D * 0.5 + GameRoom.ROOM_NEAR_EXTRA - cp.z),
					cp.z + GameRoom.ROOM_D * 0.5))
			cam_worst = minf(cam_worst, m_cam)
			cam_log += "d%.2f/w%.1f:%s(余%.2f) " % [dv, wt, cp, m_cam]
			if m_cam < 0.5:
				cam_bad += 1
	_check(cam_bad == 0,
		"相机全程在屋里、且离每个面都留有余量（越界 %d 档，最小余量须 ≥ 0.5；实得最小 %.2f；%s）"
			% [cam_bad, cam_worst, cam_log])

	t3.snap_dolly(1.0)
	t3.snap_view(0.0)
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

	# ---- 一期 Task 7：`Ctrl` + 滚轮 = 推拉（**同一条件，两种语义**）----
	# 这条必须走**真输入链路**：`Ctrl` 那条判断若接反（或干脆漏了），功能静默变成"切视角"，
	# 而**看代码很难发现**。三条一起钉：
	#   ① 带 Ctrl 的一滚只改 `dolly_target`、`view_target` 一动不动（不抢滚轮原来的活）；
	#   ② 不带 Ctrl 的一滚仍走视角推移、且**推拉目标一动不动**（两维互不串）；
	#   ③ 两端夹在 [`DOLLY_MIN`, `DOLLY_MAX`]（同 `view_target` 那条 clamp 的道理）。
	t3.snap_view(0.0)
	t3.snap_dolly(1.0)
	var ctrl_up := InputEventMouseButton.new()
	ctrl_up.button_index = MOUSE_BUTTON_WHEEL_UP
	ctrl_up.pressed = true
	ctrl_up.ctrl_pressed = true
	root.push_input(ctrl_up)
	_check(is_equal_approx(t3.dolly_target, 1.0 + t3.DOLLY_STEP) and is_equal_approx(t3.view_target, 0.0),
		"Ctrl+滚轮向前一格 ⇒ 只改推拉目标（实得 %.2f），视角目标仍 0（实得 %.2f）"
			% [t3.dolly_target, t3.view_target])
	await process_frame
	_check(t3.dolly > 1.0 and t3.dolly <= 1.0 + t3.DOLLY_STEP + 0.0001,
		"注入后推拉当前值朝目标走且不过冲（实得 %.3f，目标 %.2f）" % [t3.dolly, t3.dolly_target])
	var ctrl_down := InputEventMouseButton.new()
	ctrl_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ctrl_down.pressed = true
	ctrl_down.ctrl_pressed = true
	root.push_input(ctrl_down)
	_check(is_equal_approx(t3.dolly_target, 1.0),
		"Ctrl+滚轮向后一格 ⇒ 推拉目标减回默认档（实得 %.2f）" % t3.dolly_target)
	await process_frame
	t3.snap_dolly(1.0)
	for i in 20:
		root.push_input(ctrl_up)
		await process_frame
	_check(is_equal_approx(t3.dolly_target, t3.DOLLY_MAX),
		"连拉 20 格 ⇒ 推拉目标夹在 DOLLY_MAX（实得 %.2f / 上限 %.2f）"
			% [t3.dolly_target, t3.DOLLY_MAX])
	for i in 20:
		root.push_input(ctrl_down)
		await process_frame
	_check(is_equal_approx(t3.dolly_target, t3.DOLLY_MIN),
		"连推 20 格 ⇒ 推拉目标夹在 DOLLY_MIN（实得 %.2f / 下限 %.2f）"
			% [t3.dolly_target, t3.DOLLY_MIN])
	# 不带 Ctrl：回到视角推移，且推拉目标**一动不动**（留在刚夹到的下限）
	root.push_input(wheel_up)
	_check(is_equal_approx(t3.view_target, t3.VIEW_STEP) and is_equal_approx(t3.dolly_target, t3.DOLLY_MIN),
		"不按 Ctrl 的一滚 ⇒ 仍走视角推移（实得 %.2f），推拉目标纹丝不动（实得 %.2f）"
			% [t3.view_target, t3.dolly_target])
	t3.snap_dolly(1.0)
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
	# props 是实体物件（转盘 / 手牌 / 棋子 / 房子等）的父节点，与桌垫**共用同一套 UV 坐标系**：
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

		# ---- 批次 12 ④：指针 3D 化（金箭头平贴桌面，立在轮盘正上方、指向轮心） ----
		# 先按 1.0× 半径重摆一次（上面那段把它放大到 1.5× 了），量出来的才是"当前口径"。
		print("== 批次 12 ④：指针 = 平贴桌面的 3D 金箭头（2D 三角形已删） ==")
		t3.table_props.build_wheel(wheel_px, wheel_r)
		var ptr: MeshInstance3D = t3.table_props.get_node_or_null("WheelRim/WheelPointer") as MeshInstance3D
		_check(ptr != null, "3D 指针在（WheelRim/WheelPointer —— 挂在轮缘下，不打断「转盘只有一个子节点」那条契约）")
		if ptr != null:
			# ① **平贴桌面**：法线（局部 +Y）在世界里仍朝上 —— 立着的指针在 2D 俯视下只剩一条棱，
			#    那正是本条要治的病（与 ②⑥ 的薄牌同一个道理）。
			var pn: Vector3 = (ptr.global_transform.basis * Vector3(0.0, 1.0, 0.0)).normalized()
			_check(pn.dot(Vector3.UP) > 0.99, "箭头平贴桌面（法线 %s ≈ +Y，不是立着的针）" % pn)
			# ② **在轮盘正上方**：尖端那一点（网格局部 -z 端的顶点，缩放含在 global_transform 里）
			#    折回画布像素，应当落在"轮心正上方一个半径"那一带（画布 y 向下 ⇒ 上方是 -y）。
			var tip_w: Vector3 = ptr.global_transform * Vector3(0.0, 0.0, -0.5)
			var tip_px: Vector2 = t3.world_to_canvas_px(tip_w)
			var want_tip: Vector2 = wheel_px + Vector2(0.0, -wheel_r)
			_check(tip_px.y < wheel_px.y and absf(tip_px.x - wheel_px.x) < 12.0
					and absf(tip_px.distance_to(wheel_px) - wheel_r) < wheel_r * 0.25,
				"箭头尖端落在轮盘正上方（实得 %s / 期望 ≈%s，轮心 %s）" % [tip_px, want_tip, wheel_px])
			# ③ **指向轮心**：尖端比箭身中心更靠近轮心（局部 -z 那一端是尖的那头）。
			var mid_px: Vector2 = t3.world_to_canvas_px(ptr.global_position)
			_check(tip_px.distance_to(wheel_px) < mid_px.distance_to(wheel_px),
				"箭头指向轮心（尖端 %.1f < 箭身中心 %.1f，到轮心的画布距离）"
					% [tip_px.distance_to(wheel_px), mid_px.distance_to(wheel_px)])
			# ④ **金 + 金属**：与轮缘同一份取色的金属材质（不是一块哑光色块）。
			var pm: StandardMaterial3D = ptr.material_override as StandardMaterial3D
			_check(pm != null and pm.metallic > 0.4 and pm.albedo_color.r > 0.5
					and pm.albedo_color.r > pm.albedo_color.b + 0.2,
				"箭头是金色金属材质（metallic %.2f / 色 %s）"
					% [pm.metallic if pm != null else -1.0, pm.albedo_color if pm != null else Color.BLACK])
			var rim_mat: StandardMaterial3D = (t3.table_props.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
			_check(pm != null and rim_mat != null and pm.albedo_color.is_equal_approx(rim_mat.albedo_color),
				"箭头与轮缘**同一份金色**（箭头 %s / 轮缘 %s）"
					% [pm.albedo_color if pm != null else Color.BLACK,
						rim_mat.albedo_color if rim_mat != null else Color.BLACK])
			# ⑤ 箭头**有厚度**（是薄挤出的实物，不是一张零厚的贴片）。
			var pm2: ArrayMesh = ptr.mesh as ArrayMesh
			var aabb: AABB = pm2.get_aabb() if pm2 != null else AABB()
			_check(pm2 != null and aabb.size.y > 0.0 and aabb.size.z > aabb.size.y,
				"箭头是「薄挤出」的三角（归一化 AABB %s —— 厚度 y 小、长度 z 大）" % aabb.size)
		# ⑥ **反向契约：2D 三角形真的没了**（画布上那个指针画在 `_draw()` 里，没有可观察的节点或
		#    接口 ⇒ 只能查源码里那几行独有的画法还在不在。谁把它加回来，这条先红）。
		var wsrc := FileAccess.get_file_as_string("res://scripts/wheel_view.gd")
		_check(not wsrc.contains("-(r - 14.0)") and not wsrc.contains("var tip := c +"),
			"WheelView 不再画那个 2D 三角形指针（源码里已无那几行画法）")
		# `_seg_under_pointer` 的语义**一字未改**：中奖格仍按"盘面顶格"算，3D 箭头只是把它画出来。
		_check(t3.table_props.wheel_hit(wheel_px), "（对照）转盘命中判定不受指针改动影响")

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
			# **整排手牌必须完整在屏内**（批次 12 A2b 补）。此前这条只在 `_apply_camera` 那段
			# 注释里论证过、**没有任何断言**，而那段论证用的判据是**牌心**（"牌心在 z≈3.164"）
			# ⇒ 牌的下半截（描述区 + 品质条）掉到屏幕下沿外也照样绿 —— 实测正是如此
			#（`--shot` 出图里手牌被屏幕下沿切掉）。这里摆满 5 张（最宽那种），把每张
			# `hand_rect` 的四个角**投影回屏幕坐标系**逐个量。
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"},
				{"id": "共享单车"}, {"id": "饭卡"}])
			var vr4: Rect2 = t3.get_viewport().get_visible_rect()
			var off4 := 0
			var lo4 := INF
			var hi4 := -INF
			for k4 in tp4.hand_count():
				var r4: Rect2 = tp4.hand_rect(k4)
				for c4 in [r4.position, r4.position + Vector2(r4.size.x, 0.0),
						r4.position + Vector2(0.0, r4.size.y), r4.position + r4.size]:
					var sp4: Vector2 = t3.camera.unproject_position(t3.canvas_px_to_world(c4))
					lo4 = minf(lo4, sp4.y)
					hi4 = maxf(hi4, sp4.y)
					if sp4.y < vr4.position.y - 0.5 or sp4.y > vr4.position.y + vr4.size.y + 0.5:
						off4 += 1
			_check(off4 == 0, "整排手牌都在屏内（越界角 %d 个；屏幕 y %.1f..%.1f，视口高 %.1f）"
				% [off4, lo4, hi4, vr4.size.y])
			tp4.set_hand([])
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
			print("== 手中牌：正面贴的就是商店那张卡（批次 12 B1）==")
			# 手牌正面从"品质色块 + 一个图标 PNG"改成**一张完整的 `ItemCard`**（与商店货架 / 黑市
			# 同一份画法）。做法 = 每槽一个 `SubViewport`，里面挂一张 `ItemCard.make(id, 150×210)`，
			# 正面那个 `PlaneMesh` 贴它的 `ViewportTexture`（与批次 11 烘房子纹理同源）。
			# 断言一律走**可观察量**：牌的网格 → 材质 → 贴图 → 视口 → 视口里的那棵控件树。
			# **别把实现里的推导再写一遍**（那样写成什么样都过）。
			var FACE4 = load("res://scripts/table_props.gd")
			var face_consts: Dictionary = FACE4.get_script_constant_map()
			var want_face: Vector2 = face_consts["HAND_FACE_CARD"]
			var want_vp: Vector2i = face_consts["HAND_FACE_VP"]
			# **`ItemCard` 一律走运行时 `load`**：静态写类名会把 item_card.gd（→ ui_kit.gd，里面引用了
			# autoload `Fx`）拽进本脚本的静态依赖链，而 `--script` 入口下此时 autoload 还没注册 ⇒
			# 整链「Identifier not found: Fx」编译失败（同本文件顶部与 hud_test 里那条既有约定）。
			var ICARD4 = load("res://scripts/item_card.gd")
			tp4.set_hand([{"id": "招财猫"}, {"id": "黑卡"}])
			await process_frame
			var face_ok := true
			var live_ok := true
			var one_ok := true
			var id_ok := true
			var aspect_ok := true
			var slot_tex: Array = []
			var want_ids := ["招财猫", "黑卡"]
			for i in 2:
				var mi_f := hr.get_child(i) as MeshInstance3D
				var fc_f := mi_f.get_node_or_null("Face") as MeshInstance3D
				var fm_f := fc_f.material_override as StandardMaterial3D if fc_f != null else null
				var vp_f = tp4.hand_face_viewport(i)
				if fm_f == null or vp_f == null:
					face_ok = false
					continue
				# ① 正面贴的**就是这一槽的视口**（活引用：换牌不会换掉它，见 `_make_card`）
				if fm_f.albedo_texture != vp_f.get_texture():
					live_ok = false
				slot_tex.append(fm_f.albedo_texture)
				# ② 视口里只有一张 `ItemCard`，id 就是这件道具，尺寸就是手牌卡面尺寸
				var cards: Array = []
				for ch in vp_f.get_children():
					if ch.get_script() == ICARD4:      # 同一份画法（不是"手牌专用卡"）
						cards.append(ch)
				if cards.size() != 1:
					one_ok = false
					continue
				var ic_f = cards[0]
				if String(ic_f.id) != String(want_ids[i]):
					id_ok = false
				if not Vector2(ic_f.size).is_equal_approx(want_face):
					face_ok = false
				# ③ 卡面没被拉扁：正面贴片的宽高比 == 视口（含留白）的宽高比
				var pm_f := fc_f.mesh as PlaneMesh
				if pm_f != null:
					var pa_f: float = pm_f.size.x / pm_f.size.y
					var va_f: float = float(vp_f.size.x) / float(vp_f.size.y)
					if absf(pa_f - va_f) > 0.01:
						aspect_ok = false
			_check(face_ok, "两张牌正面都是**该槽视口里那张 `ItemCard`**（尺寸 %s，实得 %s）"
				% [want_face, "?" if tp4.hand_face_card(0) == null else tp4.hand_face_card(0).size])
			_check(live_ok, "正面材质贴的是**该槽视口的 `ViewportTexture`**（活引用，不是烘出来的图）")
			_check(one_ok, "每槽视口里恰好一张 `ItemCard`（5 张牌 = 5 个视口，各烘一张）")
			_check(id_ok, "视口里那张卡的 id 就是该槽的道具 id（招财猫 / 黑卡）")
			_check(aspect_ok, "卡面没被拉扁：正面贴片宽高比 == 视口宽高比（%s 对 0.748）" % str(want_vp))
			_check(slot_tex.size() == 2 and slot_tex[0] != slot_tex[1],
				"两张牌贴的是**两张不同的纹理**（同一个视口的话会共用一张 —— 房子那 4 级同款坑）")
			# 同一份画法：卡面节点的脚本就是商店那份 `item_card.gd`（不是另写一个"手牌专用卡"）
			var ic0 = tp4.hand_face_card(0)
			_check(ic0 != null and ic0.get_script() == ICARD4,
				"手牌卡面与商店货架**同一份画法**（item_card.gd）")
			# 换牌：视口里的卡跟着换（id 变了就重画 + 重置更新模式，否则永远停在上一次的画面）
			var vp0 = tp4.hand_face_viewport(0)
			tp4.set_hand([{"id": "包租婆"}, {"id": "黑卡"}])
			_check(tp4.hand_face_card(0) != null and String(tp4.hand_face_card(0).id) == "包租婆",
				"换牌后卡面跟着换（实得 %s）"
					% ("?" if tp4.hand_face_card(0) == null else tp4.hand_face_card(0).id))
			_check(vp0 != null and vp0.render_target_update_mode == SubViewport.UPDATE_ONCE,
				"换牌后把该槽视口的更新模式重置成 UPDATE_ONCE（不然换完还停在旧画面）")
			_check(vp0 != null and tp4.hand_face_viewport(0) == vp0,
				"换牌**复用同一个视口**（每槽一个，不是每次新建）")
			var fresh_n := 0
			var same_id_ok := true
			for ch in vp0.get_children():
				if ch.get_script() == ICARD4:
					fresh_n += 1
					if String(ch.id) != "包租婆":
						same_id_ok = false
			_check(same_id_ok and fresh_n == 1,
				"旧卡没有留在视口里（同一槽只留一张，实得 %d 张）" % fresh_n)
			tp4.set_hand([{"id": "招财猫"}, {"id": "作弊器"}, {"id": "黑卡"}])
			await process_frame
			print("== 手中牌：落在桌垫前沿的木纹留白上 ==")
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

	# ---- 反向契约：机会 / 命运两摞牌堆（印在桌垫上的图案 + 桌面上的实体）已整体退场 ----
	# 2026-10-09「机会格统一」：两副事件牌堆合成一副机会牌堆，桌面上那两摞随之没了 ——
	# 印在桌垫上的两摞卡背图案（`board_view._build_deck`）与桌面上的两摞实体摞
	#（`TableProps.build_decks`）一起退场，只服务于「实体摞贴合印刷图案」的那三个查询
	#（`deck_center` / `deck_screen_pos` / `deck_screen_size`）随之删净。
	# **写成反向契约、不直接删掉旧的正面断言**：删了就是"没人守"—— 谁把牌堆加回来都不会红；
	# 这三条钉的是「入口已不存在」，加回来（哪怕只加个空壳）先红。
	print("== 反向契约：桌面两摞牌堆（印刷图案 + 3D 实体）已整体退场 ==")
	_check(not t3.board.has_method("deck_screen_pos"), "BoardView 不再有 deck_screen_pos")
	_check(not t3.board.has_method("deck_screen_size"), "BoardView 不再有 deck_screen_size")
	_check(not t3.table_props.has_method("build_decks"), "TableProps 不再有 build_decks")

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
	# ---- 批次 11 Task 3：悬停转发（on_table_hover）----
	# 放在**这一节之前**：悬停链要有一枚棋子才问得出来，而下面那一节断言"peer 7 是新棋子（弹入）"
	#（`set_tokens` 对已存在的池子不重建、也就没有弹入）⇒ 本段用完必须把池子清空还回去。
	# 悬停（MouseMotion）此前**从不**问实体层：棋子搬进 3D 之后命中判定只在 `TableProps.token_hit`
	# 里，而那条链的入口就是本注入点。三条覆盖：命中一枚棋子 / 打不到桌面 / 默认态。
	# 关键区别：**悬停不消费输入** —— 问完之后这一动照旧转发进 SubViewport（2D 悬停高亮还要）。
	print("== 悬停转发（on_table_hover）：先问实体层、但不消费这一动 ==")
	t3.snap_view(0.0)
	var hover_px: Array = []
	t3.on_table_hover = func(px: Vector2) -> int:
		hover_px.append(px)
		return GameData.NO_PEER
	t3.table_props.set_tokens([{"peer": 7, "slot": 0, "idx": 20}])
	await create_timer(0.5).timeout                  # 等棋子弹入落定
	var tok_screen: Vector2 = t3.camera.unproject_position(t3.table_props.token_world_pos(7))
	got_events.clear()
	var hv := InputEventMouseMotion.new()
	hv.position = tok_screen                          # 鼠标指着那枚棋子
	root.push_input(hv)
	await process_frame
	_check(hover_px.size() == 1, "悬停回调被调用一次（实得 %d）" % hover_px.size())
	var hv_px: Vector2 = hover_px[0] if not hover_px.is_empty() else Vector2(-9999.0, -9999.0)
	# 回调收到的必须是**画布像素**（实体层的命中判定全在画布坐标系里做）——用 token_hit 自己复核
	# 这一点真落在 peer 7 的命中盒里（给错坐标系这条会红）。
	_check(t3.table_props.token_hit(hv_px) == 7,
		"回调收到的是棋子上那一点（画布 %s → 命中 %d）" % [hv_px, t3.table_props.token_hit(hv_px)])
	_check(got_events.size() == 1,
		"悬停**不消费**输入：这一动仍转发进 SubViewport（实得 %d）" % got_events.size())
	# 打不到桌面（射线翻过水平线）：**仍要通知一次**，传 `Vector2.INF` —— 悬停是"每一动都重算"的
	# 语义，漏掉这一动会让信息条留在上一枚棋子上不掉（旧 2D 那条链每个 motion 都会重算）。
	hover_px.clear()
	var hv_miss := InputEventMouseMotion.new()
	hv_miss.position = Vector2(vr.size.x * 0.5, -vr.size.y * 2.0)
	root.push_input(hv_miss)
	await process_frame
	_check(hover_px.size() == 1 and not is_finite((hover_px[0] as Vector2).x),
		"打不到桌面时仍通知一次、且传 Vector2.INF（实得 %s）" % str(hover_px))
	# 默认态：没接回调（批次 3 以来的常态）时一行都不做 —— 悬停零回归。
	t3.on_table_hover = Callable()
	hover_px.clear()
	root.push_input(hv)
	await process_frame
	_check(hover_px.is_empty(), "回调为空（Callable()）：默认谁都不悬停")
	t3.table_props.set_tokens([])                    # 归还：下面那节要"全新"的池子（弹入那条）
	await process_frame
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
			_check(top_v.z < bot_v.z, "3D 端顶边比板底更靠远端（后倾 ⇒ 正脸朝镜头）")
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
			# **批次 12 A3 新增：牌身 / 正面都带自发光**（用户 ②「小人偏暗」）——
			# 近黑屋子里只有一盏偏在一侧的灯，只靠光照照不出对比，自发光是"小人跳得出来"的另一半。
			# 读的是**材质上的值**（不是常量）：漏开 `emission_enabled` / 能量是 0，这条就红。
			var emit_ok := true
			for m in [pmatA, fmatM]:
				if m == null or not m.emission_enabled or m.emission_energy_multiplier <= 0.0:
					emit_ok = false
			_check(emit_ok, "棋子牌身 / 正面都开着自发光（牌身 %.2f / 正面 %.2f）"
				% [pmatA.emission_energy_multiplier if pmatA != null else -1.0,
					fmatM.emission_energy_multiplier if fmatM != null else -1.0])
		# 位置 = 与**印在桌垫上的**那一格同一条链：`tile_screen_pos` /
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
			# ---- 批次 12 A3：2D 端薄牌**躺平**（`view_t` 驱动 + 中心锚定） ----
			# ① 法线（薄牌局部 +Z）转到世界 **+Y** ⇒ 正俯视下看到的是**正脸**（老写法固定后倾
			#    25°，2D 端只剩一条棱 —— 用户 ② 报的正是它）；
			# ② **四角仍在**本格脚印里 —— 中心锚定保住的那条（躺平时不许从格子里甩出去）。
			# 量完立刻回到 3D 档：下面的命中三态全在 3D 端量。
			t3.snap_view(1.0)
			await process_frame
			var tn: Vector3 = (plateA.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
			_check(tn.dot(Vector3.UP) > 0.99, "2D 端棋子薄牌**平贴桌面**（面法线 %s ≈ +Y）" % tn)
			var t_cell: Rect2 = _cell_px(t3, 20)
			var t_out: int = 0
			for sx_v in [-0.5, 0.5]:
				for sy_v in [-0.5, 0.5]:
					var cnr: Vector3 = plateA.global_transform * Vector3(
						bmA.size.x * float(sx_v), bmA.size.y * float(sy_v), 0.0)
					if not t_cell.has_point(t3.world_to_canvas_px(cnr)):
						t_out += 1
			_check(t_out == 0,
				"2D 端棋子的四角仍落在本格脚印里（出格 %d 个角；格 %s）" % [t_out, t_cell])
			t3.snap_view(0.0)
			await process_frame

		# 命中三态：落点上命中 / 别处 -1 / 重叠时取离相机最近。
		# 先只留 peer 7 一枚 —— 两枚都在时它那枚的落点会被**更近**的那枚抢先命中（那是下面要钉的
		# "取最近"），所以"落点上命中"这条必须单枚量。
		print("== 棋子命中：落点上命中 / 别处 -1 / 重叠时取离相机最近 ==")
		tpT.set_tokens([{"peer": 7, "slot": 0, "idx": 20}])
		await process_frame
		_check(tpT.token_hit(want_a) == 7,
			"棋子画布落点上命中 peer 7（实得 %d）" % tpT.token_hit(want_a))
		# **没命中用 `GameData.NO_PEER`、不是 -1**（批次 11 T3 从 T1 的 -1 改过来）：机器人 peer
		# **从 -1 起编号**（`net._free_bot_id`；AGENTS.md 硬性约定「哨兵值…不要用 -1」），
		# -1 作哨兵会与"命中 -1 号机器人"撞成同一个数 —— 而悬停链正是分不开两者的那个消费者。
		# 下面（重叠段之后）有一条「-1 号机器人也能被命中」把它钉死。
		_check(tpT.token_hit(Vector2(30.0, 30.0)) == GameData.NO_PEER,
			"桌垫之外不算命中（NO_PEER = %d）" % GameData.NO_PEER)
		var cell30: Vector2 = t3.board.tile_pos(30) + Vector2(t3.board.TILE, t3.board.TILE) * 0.5
		_check(tpT.token_hit(cell30) == GameData.NO_PEER, "没有棋子的格心不算命中")
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

		# 哨兵改 `GameData.NO_PEER` 的**意义**就在这里：-1 号机器人必须能被命中。
		# 机器人 peer 从 -1 起编号（`net._free_bot_id` 第一个就给 -1）—— 若哨兵还是 -1，
		# "命中机器人 A"与"没命中"就再也分不开，悬停链会静默地对单人局里的 -1 号机器人失效。
		print("== 命中哨兵：-1 号机器人也命中，且与「没命中」分得开 ==")
		var want_bot: Vector2 = t3.board.token_screen_pos(21, 0)
		tpT.set_tokens([{"peer": -1, "slot": 0, "idx": 21}])
		await create_timer(0.5).timeout      # 等被换掉的那枚释放 + 新棋子弹入落定
		_check(tpT.token_hit(want_bot) == -1,
			"**-1 号机器人**的落点上命中、回 -1（实得 %d —— 与「没命中」同值但语义相反）"
				% tpT.token_hit(want_bot))
		_check(tpT.token_hit(Vector2(30.0, 30.0)) == GameData.NO_PEER,
			"同一时刻「没命中」仍是 NO_PEER（两者不再撞车）")

		# **看不见就点不到**（批次 11 T1 审查 M3 裁定）：与手牌那条既有闸（`HAND_HIT_MIN_ALPHA`）
		# **同一条规则** —— 正在传送淡出的棋子不该还能被悬停出信息条。
		# 闸是**读 alpha 的**（`token_hit` 逐枚比 `TOKEN_HIT_MIN_ALPHA`），所以这里把棋子按在
		# 「淡出中」那一档：`_set_token_alpha(池子条目, true, 0.10)` 正是**传送补间每帧驱动的
		# 那个 setter**（两条路写的是同一份材质），只是不跑补间、直接把值放上去。
		# **故意不跑真补间再逐帧采样**：那版在本任务里真写过 —— 无头下闸下那一档只有一两帧
		# （0.16s 的淡出里 a<0.15 只占 0.024s），采到与否**取决于机器每帧多长**，正是项目里
		# 一再避免的那类靠帧率的脆弱断言。补间的 alpha 曲线本身由 hud_test 的
		# 「传送期间淡到看不见（最小 alpha < 0.05）」钉住，这里只钉**闸**。
		print("== 看不见就点不到：淡到闸下的棋子不参与命中（M3 闸） ==")
		var tcm: Dictionary = tpT.get_script().get_script_constant_map()
		var v_tok := float(tcm.get("TOKEN_HIT_MIN_ALPHA", -1.0))
		var v_hand := float(tcm.get("HAND_HIT_MIN_ALPHA", -2.0))
		_check(v_tok > 0.0 and is_equal_approx(v_tok, v_hand),
			"棋子的命中闸与手牌那条**同值**（同一条规则，实得 %.2f / 手牌 %.2f）" % [v_tok, v_hand])
		tpT.set_tokens([{"peer": 7, "slot": 0, "idx": 20}])
		await create_timer(0.5).timeout
		var tk7: Dictionary = tpT._tokens.get(7, {})
		_check(not tk7.is_empty(), "（前提）拿到 peer 7 的池子条目")
		if not tk7.is_empty():
			tpT._set_token_alpha(tk7, true, 0.10)      # 半路淡出中（闸下）
			await process_frame
			_check(tpT.token_alpha(7) < v_tok,
				"（前提）棋子已淡到闸下（alpha %.3f < %.2f）" % [tpT.token_alpha(7), v_tok])
			_check(tpT.token_hit(want_a) == GameData.NO_PEER,
				"淡到闸下的棋子**命中不到**（看不见就点不到，实得 %d）" % tpT.token_hit(want_a))
			# 闸是双向的：淡完回到不透明后必须又能命中（否则"临时淡出"就成了"永久点不到"）。
			tpT._set_token_alpha(tk7, false, 1.0)
			await process_frame
			_check(tpT.token_hit(want_a) == 7,
				"恢复不透明后又命中得到（实得 %d）" % tpT.token_hit(want_a))

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

	# ---- 批次 11 Task 2：装修房子（56 格各一块薄牌，压在印着的那座房子上） ----
	# 桌垫上每格右下那条带里**印着**的房子图案，做成**立在格上的薄牌**（原先是 2D `HouseIcon`）。
	# 判据一律走可观察量：几何读节点自己的 BoxMesh、等级读**贴上去的材质/纹理**（不读内部标志）、
	# 位置与尺寸走真反变换（`world_to_canvas_px`）折回画布像素与 `board.house_*` 比 ——
	# 不把实现的推导再写一遍（那样写成什么样都过）。
	print("== 房子：56 格各一块薄牌（池子只建一次 / level 0 不露 / 跟印刷图案） ==")
	var tpH = t3.table_props
	if tpH == null or not tpH.has_method("set_houses"):
		_check(false, "TableProps 没有 set_houses（房子还没搬进来），本段整段跳过")
	else:
		t3.board.fit_overview(true)     # 全景取景：印刷口径与局部坐标差得最开（下面那条前提要用）
		t3.snap_view(0.0)
		await process_frame
		var zero_lv: Array = []
		for i in GameData.TILES.size():
			zero_lv.append(0)
		tpH.set_houses(zero_lv)
		await process_frame
		var hroot: Node = tpH.get_node_or_null("Houses")
		_check(hroot != null, "房子的父节点在（set_houses 时建）")
		var hcount: int = 0 if hroot == null else hroot.get_child_count()
		_check(hcount == GameData.TILES.size(), "56 格各一块薄牌（实得 %d）" % hcount)
		# 池子只建一次：再刷一遍，节点数不变、且**还是那个节点**（不是重建 —— 56 块，禁节点 churn）
		var h_node0: Node3D = _house_node(hroot, 0)
		tpH.set_houses(zero_lv)
		await process_frame
		_check(hroot != null and hroot.get_child_count() == hcount,
			"重刷不会多建节点（实得 %d）" % (0 if hroot == null else hroot.get_child_count()))
		_check(h_node0 != null and is_same(h_node0, _house_node(hroot, 0)),
			"重刷时用的是**同一批节点**（池子只建一次）")
		# level == 0 ⇒ 整块不露（全 0 等级时一块都不该露）
		var shown0: int = 0
		if hroot != null:
			for ch in hroot.get_children():
				if (ch as Node3D).visible:
					shown0 += 1
		_check(shown0 == 0, "全 0 等级时一块都不露（实得 %d 块露着）" % shown0)
		# 等级 → 贴图 / 材质：读**贴上去的那份材质**（0 与 5 同级、9 另一级）
		var lv_pick := {0: 3, 5: 3, 9: 1}
		var lvs: Array = []
		for i in GameData.TILES.size():
			lvs.append(int(lv_pick.get(i, 0)))
		tpH.set_houses(lvs)
		await create_timer(0.5).timeout          # 等弹入（0.32s）落定再量几何
		var h0: Node3D = _house_node(hroot, 0)
		var h5: Node3D = _house_node(hroot, 5)
		var h9: Node3D = _house_node(hroot, 9)
		_check(h0 != null and h0.visible and h5 != null and h5.visible,
			"有等级的格子立起了房子薄牌（0 号 %s / 5 号 %s）"
				% [str(h0 != null and h0.visible), str(h5 != null and h5.visible)])
		var h_hidden := 0
		if hroot != null:
			for i in GameData.TILES.size():
				var ch2: Node3D = _house_node(hroot, i)
				if ch2 != null and ch2.visible and not lv_pick.has(i):
					h_hidden += 1
		_check(h_hidden == 0, "没写等级的格子一块都不露（实得 %d 块）" % h_hidden)
		var tex1 = tpH.house_tex(1)
		var tex3 = tpH.house_tex(3)
		_check(tex1 != null and tex3 != null, "（前提）4 张等级纹理烘出来了（1 级 %s / 3 级 %s）" % [tex1, tex3])
		_check(tex1 != tex3, "（前提）不同等级的纹理**不是同一张**（等级信号才立得住）")
		var f0: MeshInstance3D = _house_face(hroot, 0)
		var f5: MeshInstance3D = _house_face(hroot, 5)
		var f9: MeshInstance3D = _house_face(hroot, 9)
		var m0: StandardMaterial3D = f0.material_override as StandardMaterial3D if f0 != null else null
		var m5: StandardMaterial3D = f5.material_override as StandardMaterial3D if f5 != null else null
		var m9: StandardMaterial3D = f9.material_override as StandardMaterial3D if f9 != null else null
		_check(m0 != null and m0.albedo_texture == tex3,
			"3 级的房子正面贴的是 3 级那张纹理（读贴上去的，实得 %s）" % (m0.albedo_texture if m0 != null else null))
		_check(m9 != null and m9.albedo_texture == tex1, "1 级的房子贴的是 1 级那张纹理")
		_check(m0 != null and m9 != null and m0 != m9, "不同等级用的是**不同的材质**")
		_check(m0 != null and is_same(m0, m5),
			"同等级共用**同一份材质**（不是一格格新建 —— 4 份材质摊到 56 格上）")
		# ---- 批次 13 ⑦：正面**以自发光为主** ⇒ 牌面颜色与灯的位置 / 这一牌摆在
		# 哪一排**无关**。用户报的是"最底那一栏的房子在 3D 视角下立牌没有颜色"：薄牌后倾 25°、
		# 最底那两排背对着那盏偏在一侧的灯 ⇒ 只吃得到环境光 + 原先那层**白色**弱自发光 ⇒ 冲成近灰。
		# 这一组是**无头下唯一能钉住它**的东西（观感本身要靠出图），钉三件：
		#   ① 自发光**开着**且**照着同一张等级纹理**（`emission_texture == albedo_texture`）；
		#   ② 算子是 `MULTIPLY` —— **默认是 `ADD`**，而 `ADD` + 白色 = "白 + 贴图"⇒ 牌面冲成白板
		#     （这是最容易手滑改回去的一处）；
		#   ③ 自发光那一份**压过**受光那一份（`albedo_color` 已压到 0.30）：比值取的是**两个材质
		#     常数**（自发光能量 0.75 / albedo 亮度 0.30 = **2.5**）—— 桌面上那份照度（≈1.2）不在
		#     材质里，把它算进去真值是 ≈2.1，所以 2.0 这个界两边都够得着；
		#     自发光不到受光的两倍时，「哪一排骨面朝哪边」就又开始说话（正是用户 ⑦ 报的那件事）。
		var face_emit_ok: bool = m0 != null and m9 != null \
			and m0.emission_enabled and m9.emission_enabled \
			and m0.emission_texture == tex3 and m9.emission_texture == tex1 \
			and m0.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY \
			and m9.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY
		_check(face_emit_ok,
			"房子正面以自发光为主（emission_texture == 等级纹理 且 算子 = MULTIPLY —— 各排同色，用户 ⑦）")
		# `m0` 是 3 级那份、`m9` 是 1 级那份（两份都查，免得"只给一级改了"漏过）。
		var face_emit_min := INF
		for fm in [m0, m9]:
			if fm == null:
				continue
			face_emit_min = minf(face_emit_min,
				fm.emission_energy_multiplier / maxf(fm.albedo_color.get_luminance(), 0.001))
		_check(face_emit_min >= 2.0,
			"自发光那一份 ≥ 受光那一份 × 2（比值 %.2f ≥ 2.0 —— 不到两倍就又变成「看灯的脸色」）"
				% face_emit_min)
		if h0 != null and h5 != null and h9 != null:
			var bm0 := (h0.get_node("Plate") as MeshInstance3D).mesh as BoxMesh
			var bm5 := (h5.get_node("Plate") as MeshInstance3D).mesh as BoxMesh
			_check(bm0 != null and bm5 != null, "房子薄牌是 BoxMesh")
			if bm0 != null:
				_check(bm0.size.y > 0.02, "薄牌**有高度**（%.3f > 0.02，不是平面贴纸）" % bm0.size.y)
				_check(bm0.size.z < bm0.size.y * 0.5, "薄牌是「薄」的（厚 %.3f 世界单位）" % bm0.size.z)
				# 「后倾」的可执行定义（同棋子那条）：牌面**顶边比板底更靠远端**（z 更小）
				var hb_top: Vector3 = h0.get_node("Plate").global_transform * Vector3(0.0, bm0.size.y * 0.5, 0.0)
				var hb_bot: Vector3 = h0.get_node("Plate").global_transform * Vector3(0.0, -bm0.size.y * 0.5, 0.0)
				_check(hb_top.z < hb_bot.z, "顶边比板底更靠远端（后倾 ⇒ 2D 端近正俯视也看得见一块面）")
				_check(is_same(bm0, bm5), "56 格共用**一份 BoxMesh**（不是一格格新建 mesh）")
			# 位置 = 与**印在桌垫上的**那座房子同一条链（`tile_screen_pos` /
			# `wheel_screen_pos` 那条：`global_position + _view_from_world(局部点)`）。
			# **不能拿格内局部坐标比**：那是"镜头在原点、倍率 1"那一档的位置（T1 的棋子照字面
			# 实现就偏了整整一格）—— 下面第一条前提就是钉这个。
			var h_want: Vector2 = t3.board.house_screen_pos(0)
			var h_local: Vector2 = t3.board.house_anchor(0)
			_check(h_want.distance_to(h_local) > 8.0,
				"（前提）房子的印刷口径与格内局部坐标确实不同（差 %.1f 画布像素 —— 少了镜头变换就会偏开）"
					% h_want.distance_to(h_local))
			var h_back: Vector2 = t3.world_to_canvas_px(h0.global_position)
			_check(h_back.distance_to(h_want) < 1.0,
				"房子落在该格那条带的「印刷口径」落点上（实得 %s / 期望 %s）" % [h_back, h_want])
			_check(h0.global_position.y > t3.table_mesh.global_position.y,
				"房子抬在桌垫之上（y=%.3f —— 站在桌上而不是陷进桌垫）" % h0.global_position.y)
			# 尺寸**也跟印刷图案**（R4：房子压在格子上），**且放大 `HOUSE_SCALE` 倍**
			#（批次 12 ⑥：用户「房子太小」）。把薄牌的左右两沿（局部 ±w/2）过真反变换折回
			# 画布像素，与 `board.house_screen_size().x × 1.3` 比 ——
			# ① 只跟位置不跟尺寸（老 bug）会红；② **漏乘放大倍数**也会红（下面那条就是它）。
			var sz_px: float = _house_w_px(t3, h0, bm0)
			var printed_px: float = t3.board.house_screen_size().x
			_check(absf(sz_px - printed_px * 1.3) < 2.0,
				"薄牌宽 == 印刷口径宽度 × 1.3（%.1f vs %.1f × 1.3 = %.1f 画布像素）"
					% [sz_px, printed_px, printed_px * 1.3])
			_check(sz_px > printed_px * 1.2,
				"房子确实比印在桌垫上那座**大了一档**（%.1f > 印刷 %.1f × 1.2 —— 用户 ⑥ 要的正是它）"
					% [sz_px, printed_px])
			# ---- 批次 12 ⑥/② ：2D 端薄牌**躺平**（与棋子同一套 `view_t` 驱动 + 中心锚定） ----
			# ① 牌面的法线（薄牌局部 +Z）转到世界 **+Y**（朝上）—— 这就是"平贴桌面、正脸朝上"的
			#    可执行定义（老写法固定后倾 25°，2D 端只剩一条棱）；
			# ② 四个角**仍在**本格的脚印里（中心锚定要保住的那条：躺平时不许从格子里甩出去）。
			t3.snap_view(1.0)
			await process_frame
			var h_plate0: MeshInstance3D = h0.get_node("Plate") as MeshInstance3D
			var h_n: Vector3 = (h_plate0.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
			_check(h_n.dot(Vector3.UP) > 0.99,
				"2D 端房子薄牌**平贴桌面**（面法线 %s ≈ +Y）" % h_n)
			var h_cell: Rect2 = _cell_px(t3, 0)
			var h_out: int = 0
			for sx_v in [-0.5, 0.5]:
				for sz_v in [-0.5, 0.5]:
					var cnr: Vector3 = h_plate0.global_transform * Vector3(
						bm0.size.x * float(sx_v), bm0.size.y * float(sz_v), 0.0)
					if not h_cell.has_point(t3.world_to_canvas_px(cnr)):
						h_out += 1
			_check(h_out == 0,
				"2D 端房子的四角仍落在本格脚印里（出格 %d 个角；格 %s）" % [h_out, h_cell])
			t3.snap_view(0.0)
			await process_frame
			# 跟取景：2D 镜头推近（取景 / 人数变化都会改 _zoom）⇒ 重推后房子要跟着胀
			#（与"轮缘跟着画面半径放大"/"环外沿跟着胀"同一条）。
			t3.board.focus_grid(9, 2.0, true)
			await process_frame
			tpH.set_houses(lvs)
			await process_frame
			var sz_px1: float = _house_w_px(t3, h9, (h9.get_node("Plate") as MeshInstance3D).mesh as BoxMesh)
			_check(sz_px1 > sz_px * 1.5, "取景推近后房子跟着胀（%.1f → %.1f 画布像素）" % [sz_px, sz_px1])
			t3.board.fit_overview(true)
			await process_frame

			# **visible → visible 的材质切换**（R8-e）：3 级 → 1 级时牌子**留在原地**（不收起）
			# 但正面必须换成 1 级那份材质。上面那几条只覆盖了"可见 → 可见的**不同格**"，
			# 同一格换档这条路径（`_set_house_plate` 的 `lv != _house_levels[i]` 那一支）此前没测过。
			var lv2: Array = lvs.duplicate()
			lv2[0] = 1
			tpH.set_houses(lv2)
			await process_frame
			var f0b: MeshInstance3D = _house_face(hroot, 0)
			var m0b: StandardMaterial3D = f0b.material_override as StandardMaterial3D if f0b != null else null
			_check(h0 != null and h0.visible, "换档后房子仍在（3 级 → 1 级不收起）")
			_check(m0b != null and m0b.albedo_texture == tex1,
				"3 级 → 1 级：正面换成 1 级那张纹理（实得 %s）"
					% (m0b.albedo_texture if m0b != null else null))
			# `clampi(lv, 0, MAX_LEVEL)`：越界等级要**夹**到合法档 —— 99 ⇒ MAX_LEVEL 那份材质、
			# -3 ⇒ 0（收起）。少了夹取，越界值会去索引一个不存在的材质 / 把 -3 当"有等级的"摆出来。
			var lv3: Array = lvs.duplicate()
			lv3[0] = 99
			lv3[5] = -3
			tpH.set_houses(lv3)
			await process_frame
			var f0c: MeshInstance3D = _house_face(hroot, 0)
			var m0c: StandardMaterial3D = f0c.material_override as StandardMaterial3D if f0c != null else null
			var tex_max = tpH.house_tex(GameData.MAX_LEVEL)
			_check(m0c != null and m0c.albedo_texture == tex_max,
				"越界等级 99 夹到 MAX_LEVEL=%d 那份纹理" % GameData.MAX_LEVEL)
			var h5c: Node3D = _house_node(hroot, 5)
			_check(h5c != null and not h5c.visible, "负等级 -3 夹到 0 ⇒ 那一格收起")
			tpH.set_houses(lvs)          # 还原（反向契约那段与本段无依赖，但别把状态留在半截）
			await process_frame

	# 反向契约：2D 的房子图标整套必须**真的没了**（不留空壳）。谁把它们加回来（或只加个空壳），
	# 这几条先红。画法只留一份 —— 留在 `TableProps` 里（烘纹理要用它）。
	# **提一层**（R8-d）：这段原先落在上面那个 `else:`（`set_houses` 存在）分支里 ⇒ RED 时被跳过
	# （`TableProps` 还没有 `set_houses`，正是它要抓的那个状态），`set_houses` 真被删时同样被跳过
	# —— 反向契约在最需要它的两个时刻都不跑。它只读 `t3.board`，与 `tpH` 无关 ⇒ 提到 `if/else` 之外。
	print("== 反向契约：2D 房子图标整套已从 BoardView 删净 ==")
	var bvh = t3.board
	_check(bvh.get("_house_icons") == null, "BoardView._house_icons 已删净")
	_check(bvh.get("_levels") == null, "BoardView._levels（房子弹跳的等级缓存）已删净")
	_check(not bvh.has_method("_set_house"), "BoardView._set_house 已删净")
	_check(not bvh.has_method("_make_house"), "BoardView 没有留下建房壳子")
	var hcm: Dictionary = bvh.get_script().get_script_constant_map()
	_check(hcm.get("HouseIcon") == null, "BoardView 不再带 HouseIcon 类（画法只留在 TableProps）")
	# 保留的查询（3D 侧摆房子要用；谁顺手删了这条先红）
	var hkept: Array = []
	for m in ["house_anchor", "house_screen_pos", "house_screen_size"]:
		if not bvh.has_method(m):
			hkept.append(m)
	_check(hkept.is_empty(), "house_anchor / house_screen_pos / house_screen_size 保留（缺 %s）" % str(hkept))

	t3.queue_free()

	# ---- 批次 5 Task 2：座位栏退场，改钉"窗口覆盖了什么"（原第 ③ 条「立牌贴桌沿」随批次 9 删）----
	# T4b/T4c/T-a 那三条（"四条座位栏都在画布内 / 窗口内 / 屏幕内"）随座位栏一起删了：
	# 它们守的是"指向性道具点得到人"，而那个入口随批次 9 挪到**屏幕层的四角身家条**
	#（Task 2 起可点、Task 3 接上选目标高亮；hud_test 里那两条断言守着）。这里只剩两条：
	#   ① 反向契约：座位卡那一套真的没了、也没有留下四条空栏；
	#   ② 窗口必须覆盖**棋盘**（可见且可点到）——批次 2 的 T4c 就是踩了这个坑
	#     （窗口裁过头 ⇒ 画布内有、桌面上看不见也点不到）才把窗口恢复成整张画布的。
	print("== 座位卡退场：画布里没有座位栏，棋盘仍在窗口内 ==")
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
	# ② 棋盘必须整块在窗口内（画布口径），且窗口在画布内
	#（原先此处还遍历 `deck_screen_pos` 量两摞牌堆的中心 / 底板在不在窗口内 —— 牌堆已整体退场
	#  （见上面那条反向契约），那段遍历随之一并删掉。）
	var chest4 := Rect2(b4._view_from_world(b4.BOARD_OFFSET),
		b4._view_from_world(b4.BOARD_OFFSET + b4.WORLD) - b4._view_from_world(b4.BOARD_OFFSET))
	_check(vp4.encloses(chest4), "棋盘整块落在画布内（%s）" % chest4)
	_check(win4.encloses(chest4), "棋盘整块落在纹理窗口内（可见且可点）")
	t4.queue_free()

	if fails == 0:
		print("LAYOUT TEST: ALL PASS")
		quit(0)
	else:
		print("LAYOUT TEST: %d FAILURES" % fails)
		quit(1)
