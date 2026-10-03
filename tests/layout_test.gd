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
	# 尺寸是 Vector2（宽 × 进深），函数对任意矩形都成立。当前实现里贴图窗口 = 整张方画布，
	# 所以 TABLE_D == TABLE_W == 8.0（正方形）；下面另用 8×4 钉住「进深按自己的边长折算」，
	# 否则窗口一旦与桌面比例脱钩、贴图就被拉伸（批次 3 若再裁窗口会用到）。
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

	print("== 贴图窗口 = 整张画布（交互优先于比例，见 T4c）==")
	# 画布 = 整张方桌（棋盘 + 四条座位栏 + 上下死区）。T4 曾把窗口裁到 y∈[348,2048] 让
	# 「棋盘铺满桌面」，但上家座位栏在画布 y∈[16,211] —— 它在画布内、却在窗口外，
	# 桌面上既看不见也点不到（指向性道具选不中上家）。裁定：窗口必须覆盖整张画布，
	# 比例目标推迟到批次 3（座位栏将换成桌上立牌）。窗口是否够大由下面 T4c 那段钉住。
	var win: Rect2 = t3.TEX_WINDOW_PX
	_check(win.position.x >= 0.0 and win.position.y >= 0.0
			and win.position.x + win.size.x <= 2048.0 and win.position.y + win.size.y <= 2048.0,
		"贴图窗口落在画布内（窗口 %s）" % win)
	_check(win == Rect2(Vector2.ZERO, Vector2(t3.VP_SIZE)),
		"贴图窗口 = 整张画布（%s，交互优先于比例）" % win)
	# 这条曾写成 `TABLE_D / TABLE_W ≈ win.size.y / win.size.x` —— 而 TABLE_D 就是这么
	# 定义的（`TABLE_W * win.size.y / win.size.x`），同义反复、永远不会红。改成钉具体数值：
	# 桌面为 8×8 正方形（窗口 = 整张方画布 ⇒ 进深 == 宽）。真正的贴图拉伸守卫是下面那条
	# 「材质取样窗口 == 映射窗口」。
	_check(t3.TABLE_W == 8.0 and t3.TABLE_D == 8.0,
		"桌面为 8×8 正方形（宽 %.2f / 进深 %.2f）" % [t3.TABLE_W, t3.TABLE_D])
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

	# ---- 批次 3 Task 1：实体物件先于桌垫内容消费点击 ----
	# 这是本任务唯一的新运行时行为：on_table_click 返回 true = 这次点击落在实体上，2D 棋盘
	# 不该知道它发生过。三条覆盖：消费 / 放行 / 默认态。夹具沿用上面那套（真坐标 push_input
	# 进根视口 → 3D 映射 → SubViewport 内的探针控件）。
	print("== 实体物件先消费点击（on_table_click）==")
	var seen_px: Array = []
	var at_center := func(_px: Vector2) -> bool:
		seen_px.append(_px)
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
	t3.on_table_click = func(_px: Vector2) -> bool: return false
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
	t3.on_table_click = func(_px: Vector2) -> bool: return true
	var pa := InputEventMouseButton.new()
	pa.button_index = MOUSE_BUTTON_LEFT
	pa.pressed = true
	pa.position = click.position
	root.push_input(pa)                       # 被消费 → 旗标 = 左键
	await process_frame
	t3.on_table_click = func(_px: Vector2) -> bool: return false
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
	t3.on_table_click = func(_px: Vector2) -> bool: return true
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
	# props 是实体物件（转盘 / 筹码 / 体力件 / 手牌）的父节点，与桌垫**共用同一套 UV 坐标系**：
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
			# 跟住画面半径：滚轮推拉 / 取景 / 抽卡推近都会改 _zoom，实体必须跟着变。
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
	# 先钉住「这段复现的是客户端路径」：客户端要等 s_state 才建座，那时首次取景早已做完
	# （_fitted=true），build_seats 才会走 fit_overview 硬取景；若容器哪天不再被上面两帧
	# await 布局，_fitted 会是 false，这段就静默退化成房主路径（首帧取景时才建座）、变空洞。
	_check(t4.board._fitted, "建座前已完成首次取景（复现客户端路径）")
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

	# ---- Task 4c：座位栏还得落在**纹理窗口**内 ----
	# 画布内 ≠ 桌面上可见可点：桌面材质只取 TEX_WINDOW_PX 那一块，输入映射由同源的窗口
	# 换算（screen_to_viewport）。T4 为「棋盘铺满桌面」把窗口上边裁到 348，而上家（对家）
	# 那条座位栏正落在画布 y∈[16,211] —— 它在画布内、却在窗口外，于是既看不见也点不到，
	# 指向性道具（交换生 / 跑腿券 / 强拆令）选不中上家。窗口必须覆盖整张画布。
	print("== 四条座位栏都在纹理窗口内（可见且可点到） ==")
	# 同上的空间问题：_seat_bar 给世界坐标，TEX_WINDOW_PX 是画布坐标，先过镜头变换再比。
	var win4: Rect2 = t4.TEX_WINDOW_PX
	var out_win := 0
	for e in 4:
		var bar4: Rect2 = t4.board._seat_bar(e)
		var w0: Vector2 = t4.board._view_from_world(bar4.position)
		var w1: Vector2 = t4.board._view_from_world(bar4.end)
		var cbar := Rect2(w0, w1 - w0).abs()
		if not win4.encloses(cbar):
			out_win += 1
			print("    [窗口外] 边 %d 的座位栏（画布）%s 不在窗口 %s 内" % [e, cbar, win4])
	_check(out_win == 0, "四条座位栏都在纹理窗口内（窗口外 %d 条）" % out_win)

	# ---- T-a：座位栏还得落在**可见屏幕**内（triage #10） ----
	# 「画布内」+「窗口内」都不等于「玩家看得见」：窗口是贴在 3D 桌面上的贴图，还要过相机投影。
	# `CAM_DIST` 从 4.4 提到 5.8 就是因为近端（自己那侧）的座位栏被顶出屏幕底部，
	# 而当时没有任何断言能红 —— 只有出图能抓。这条把整条「画布 → 屏幕」链路钉进测试：
	# 座位栏的四个角经 `_view_from_world → viewport_to_screen` 换算后必须落在窗口可见矩形内。
	print("== 四条座位栏都落在可见屏幕内 ==")
	var screen4: Rect2 = t4.get_viewport().get_visible_rect()
	var out_scr := 0
	for e in 4:
		var bar_e: Rect2 = t4.board._seat_bar(e)
		# 四个角的世界坐标；Rect2.end 是右下角
		var corners: Array = [bar_e.position, Vector2(bar_e.end.x, bar_e.position.y),
			bar_e.end, Vector2(bar_e.position.x, bar_e.end.y)]
		for c in corners:
			var sp = t4.viewport_to_screen(t4.board._view_from_world(c))
			# 用含边界的比较（Rect2.has_point 会排除右/下缘），免得刚好贴边时假红
			var ok: bool = sp != null and (sp as Vector2).x >= 0.0 and (sp as Vector2).y >= 0.0 \
				and (sp as Vector2).x <= screen4.size.x and (sp as Vector2).y <= screen4.size.y
			if not ok:
				out_scr += 1
				print("    [屏外] 边 %d 角 %s → 屏幕 %s（屏幕 %s）" % [e, c, sp, screen4])
	_check(out_scr == 0, "四条座位栏的四个角都在可见屏幕内（屏外角 %d 个）" % out_scr)
	t4.queue_free()

	if fails == 0:
		print("LAYOUT TEST: ALL PASS")
		quit(0)
	else:
		print("LAYOUT TEST: %d FAILURES" % fails)
		quit(1)
