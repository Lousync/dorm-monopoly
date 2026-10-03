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

## 沿视线推拉相机（Task 3 的滚轮缩放用）。factor > 1 拉远、< 1 拉近。
## 只改「相机到桌面中心的距离」，方向不变 —— 于是俯角恒定，缩放不会把桌子翻成平视。
## 上下限留出余量：太近会钻进桌面，太远则桌子退到屏幕一隅。
func dolly(factor: float) -> void:
	var dir := camera.global_position.normalized()
	var dist := clampf(camera.global_position.length() * factor, 2.5, 22.0)
	camera.global_position = dir * dist
