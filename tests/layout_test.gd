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
	# 尺寸是 Vector2（宽 × 进深）：桌面非正方形 —— 贴图窗口取的是「棋盘 + 一圈木边」，
	# 比例必须跟着窗口走，否则贴图被拉伸（Task 4 的棋盘/桌面比例）。
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

	print("== 棋盘 / 桌面比例：贴图只取画布的一块（棋盘铺满桌面）==")
	# 画布 = 整张方桌（棋盘 + 四条座位栏 + 上下死区），棋盘只占其中一小块。
	# 直接铺满画布就会读成「棋盘摆在桌上」；贴图窗口把棋盘外那一小圈木边之外的都裁掉。
	var win: Rect2 = t3.TEX_WINDOW_PX
	_check(win.position.x >= 0.0 and win.position.y >= 0.0
			and win.position.x + win.size.x <= 2048.0 and win.position.y + win.size.y <= 2048.0,
		"贴图窗口落在画布内（窗口 %s）" % win)
	_check(win.size.y < 2048.0 or win.size.x < 2048.0,
		"贴图窗口比整张画布小（%s < 2048²，即真的裁掉了桌面外的死区）" % win.size)
	_check(absf(t3.TABLE_D / t3.TABLE_W - win.size.y / win.size.x) < 0.002,
		"桌面宽:进深 与 窗口宽:高 同比例（贴图不被拉伸：%.3f vs %.3f）"
			% [t3.TABLE_D / t3.TABLE_W, win.size.y / win.size.x])
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

	print("== 滚轮推拉：factor > 1 拉近，且只改距离、不改方位 ==")
	var d0: float = t3.camera.global_position.length()
	var dir0: Vector3 = t3.camera.global_position.normalized()
	t3.dolly(1.12)
	var d1: float = t3.camera.global_position.length()
	_check(d1 < d0, "滚轮上滚（factor 1.12）把相机拉近（%.2f → %.2f）" % [d0, d1])
	# 只验距离是不够的：把「指向中心的方向」当位置赋回去会把相机绕原点镜像到桌子另一侧，
	# 距离照样变小、两次 dolly 照样抵消（互为逆操作），于是 bug 被完全掩盖。必须钉住方位。
	_check(t3.camera.global_position.normalized().distance_to(dir0) < 0.0001,
		"推拉只改距离、方位不变（实得 %s，期望 %s）" % [t3.camera.global_position.normalized(), dir0])
	_check(t3.camera.global_position.y > 0.0,
		"推拉后相机仍在桌面之上（实得 y=%.2f）" % t3.camera.global_position.y)
	t3.dolly(1.0 / 1.12)
	_check(absf(t3.camera.global_position.length() - d0) < 0.01, "反向推拉回到原距离")
	_check(t3.camera.global_position.normalized().distance_to(dir0) < 0.0001, "反向推拉后方位同样不变")
	t3.dolly(1000.0)
	_check(absf(t3.camera.global_position.length() - 2.0) < 0.01,
		"拉到极限夹在下限 2.0（实得 %.2f）" % t3.camera.global_position.length())
	t3.dolly(0.001)
	_check(absf(t3.camera.global_position.length() - 14.0) < 0.01,
		"推远夹在上限 14.0（实得 %.2f）" % t3.camera.global_position.length())

	print("== 事件注入端到端：屏幕点 → 3D 映射 → SubViewport 内的 2D 控件 ==")
	# 先真的滚一格再点（review 指出的结构缺口：两次 dolly 互为逆操作、且只验距离，
	# 镜像 bug 会被完全掩盖）。相机一旦被镜像到 y<0，射线与桌面交于 t<0 被拒
	# ⇒ screen_to_viewport 对所有屏幕点返回 null ⇒ 下面这几条必红。
	t3.dolly(1.12)
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

	t3.queue_free()

	# ---- Task 4b：座位栏是否落在画布外（先取证） ----
	# 四条座位栏是「指向性道具点人选目标」的区域。座位栏比棋盘占位更宽（左右各 256px、
	# 上下各 286px），若取景只按「棋盘 + 空区」算，栏条就会落到 0..2048 画布之外、点不到。
	# 这里用真身容器（不是裸 BoardView）：座位落位发生在取景之后（客户端等 s_state 才建座），
	# 复现的正是「首次取景时还没有座位」这条路径。
	print("== 装了座位之后，四条座位栏是否都在画布内 ==")
	var t4 = load("res://scripts/table_3d.gd").new()
	root.add_child(t4)
	await process_frame
	await process_frame
	# 装四个座位（peer 1..4；这里只要位置，不联网）
	var pls := []
	for i in 4:
		pls.append({"peer": i + 1, "name": "P%d" % (i + 1), "color": i, "bot": false,
			"money": 20000, "pos": 0, "alive": true, "skip": 0, "sleep": 0,
			"stamina": 3, "items": [], "item_used": false})
	t4.board.build_seats(pls, 1)
	t4.board._process(0.0)        # 触发首帧布局/取景
	t4.board._process(0.0)
	var vp4 := Rect2(Vector2.ZERO, Vector2(t4.viewport.size))
	var out := 0
	for e in 4:
		# _seat_bar 给的是**世界坐标**；要回答「在不在画布内」必须先过镜头变换换成画布（视图）坐标，
		# 否则拿世界矩形直接跟 0..2048 比 —— 两边不同空间，四条永远算越界（假红）。
		var bar: Rect2 = t4.board._seat_bar(e)
		var c0: Vector2 = t4.board._view_from_world(bar.position)
		var c1: Vector2 = t4.board._view_from_world(bar.end)
		var bar_view := Rect2(c0, c1 - c0).abs()
		print("    边 %d：世界 %s → 画布 %s" % [e, bar, bar_view])
		if not vp4.encloses(bar_view):
			out += 1
			print("    [越界] 边 %d 的座位栏 %s 不在画布 %s 内" % [e, bar_view, vp4])
	_check(out == 0, "四条座位栏都在画布内（越界 %d 条）" % out)
	t4.queue_free()

	if fails == 0:
		print("LAYOUT TEST: ALL PASS")
		quit(0)
	else:
		print("LAYOUT TEST: %d FAILURES" % fails)
		quit(1)
