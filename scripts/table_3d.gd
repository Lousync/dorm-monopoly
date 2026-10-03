class_name TableView3D
extends Node3D
## 2.5D 桌面容器（见 doc/development/plans/v0.5.0-布局2.5D.md §二 / §6.1）。
##
## 结构：本节点（Node3D）持有 3D 场景 —— 桌面板 + 相机 + 灯 —— 以及一个 SubViewport，
## 现有 BoardView 原样住在那个 SubViewport 里。屏幕层 HUD 在 game 上，叠在 3D 之上。
## 输入由本节点映射：屏幕点 → 相机射线 → 水平桌面 → UV → SubViewport 像素 → push_input。

const TABLE_SIDE := 8.0          # 桌面边长（世界单位）
const VP_SIZE := Vector2i(2048, 2048)   # SubViewport 分辨率（清晰度靠它，见设计稿 §十 风险）
const CAM_TILT_DEG := 50.0       # 俯角：0 = 平视，90 = 正俯视
const CAM_FOV := 55.0            # 收窄默认 75°：探针实测默认 FOV 下桌面只占屏 1/4

var board: BoardView
var viewport: SubViewport
var camera: Camera3D
var table_mesh: MeshInstance3D

var _table_mat: StandardMaterial3D

func _init() -> void:
	_build_environment()
	_build_table()
	_build_camera()
	_build_viewport()

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.06, 0.085)   # 桌面之外的暗色房间
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.45)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

func _build_table() -> void:
	table_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(TABLE_SIDE, TABLE_SIDE)     # PlaneMesh 躺在 XZ 平面，中心在原点
	table_mesh.mesh = pm
	_table_mat = StandardMaterial3D.new()
	_table_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_table_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	table_mesh.material_override = _table_mat
	add_child(table_mesh)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -28, 0)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.94, 0.85)    # 暖顶光
	add_child(light)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	# 按俯角求相机位置：水平距离 d，高度 d*tan(俯角)，看向桌面中心
	var d := 5.0
	var rad := deg_to_rad(CAM_TILT_DEG)
	# _init 阶段节点尚未入树，look_at 会报错 —— 必须用 look_at_from_position
	camera.look_at_from_position(Vector3(0.0, d * tan(rad), d), Vector3.ZERO, Vector3.UP)
	add_child(camera)
	camera.current = true

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = VP_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	add_child(viewport)
	_table_mat.albedo_texture = viewport.get_texture()

	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.overlay_top = 0.0        # 3D 层不再需要为屏幕 HUD 预留（HUD 浮在 3D 之上）
	board.overlay_bottom = 0.0
	board.overlay_left = 0.0
	board.overlay_right = 0.0
	viewport.add_child(board)

# ---------------- 输入映射（见设计稿 §6.2） ----------------

## 屏幕点 → SubViewport 像素坐标；射线打不到桌面则返回 null。
func screen_to_viewport(screen_pt: Vector2) -> Variant:
	var uv = screen_to_uv(screen_pt)
	if uv == null:
		return null
	return TableGeometry.uv_to_viewport(uv as Vector2, viewport.size)

## 屏幕点 → 桌面 UV；打不到返回 null。
func screen_to_uv(screen_pt: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pt)
	var dir := camera.project_ray_normal(screen_pt)
	var hit = TableGeometry.hit_floor(origin, dir, global_position.y)
	if hit == null:
		return null
	var local: Vector3 = table_mesh.global_transform.affine_inverse() * (hit as Vector3)
	return TableGeometry.world_to_uv(local, TABLE_SIDE)

## 沿视线推拉（滚轮缩放）。factor > 1 拉近。
## 只改「相机到桌面中心的距离」、方向不变 —— 于是俯角恒定，推拉不会把桌子翻成平视。
## 夹取上下限，免得太近钻进桌面、太远让桌子退到屏幕一角。
func dolly(factor: float) -> void:
	# 位置 = 方位 * 距离，方位必须原样保留。若把「相机指向桌面中心的方向」
	# （-camera.global_position）当位置赋回去，相机就绕原点镜像到桌子的另一侧（y<0），
	# 而 basis 不变 ⇒ 射线仍朝下、与桌面交于 t<0，被 Plane.intersects_ray 拒绝
	# ⇒ screen_to_uv 对所有屏幕点返回 null ⇒ 点击与悬停整体失效。
	var dir := camera.global_position.normalized()   # 相机在桌面中心的哪个方位
	var dist := camera.global_position.length()
	var nd := clampf(dist / factor, 2.0, 14.0)
	camera.global_position = dir * nd

## 鼠标事件映射进 SubViewport。键盘等其它事件原样放行。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		# 复刻 SubViewportContainer 的职责：输入映射由本节点自己接管后，就没人告诉
		# SubViewport「鼠标进来了」，而 Godot 会丢掉没进过视口的 MouseMotion —— 悬停
		# 高亮与棋子 tooltip 会全哑（实测：直到该视口里发生过一次按键事件才恢复）。
		# 通知是幂等的，直接随每个鼠标事件补发。
		viewport.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dolly(1.12)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dolly(1.0 / 1.12)
			get_viewport().set_input_as_handled()
			return
		var pos = screen_to_viewport(mb.position)
		if pos == null:
			return
		var fwd := InputEventMouseButton.new()
		fwd.button_index = mb.button_index
		fwd.pressed = mb.pressed
		fwd.position = pos
		fwd.button_mask = mb.button_mask
		viewport.push_input(fwd)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var pos = screen_to_viewport(mm.position)
		if pos == null:
			return
		var fwd := InputEventMouseMotion.new()
		fwd.position = pos
		fwd.relative = Vector2.ZERO      # SubViewport 内不靠相对位移做平移
		fwd.button_mask = mm.button_mask
		viewport.push_input(fwd)
