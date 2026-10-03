class_name TableProps
extends Node3D
## 桌面上的实体物件（见 doc/development/plans/v0.5.0-桌面实体化-设计.md §五）。
##
## 只负责「摆在哪、长什么样」：坐标一律由桌垫 UV 坐标系换算（TableView3D.canvas_px_to_world），
## 命中判定只回一个布尔 —— 掷轮 / 用道具这些后果由 game.gd 决定，这里不碰任何玩法逻辑。

## 转盘命中半径（棋盘画布像素）。画出来的轮子 `size = 400`、外圈半径 200 世界局部像素，
## 经镜头倍率后落到画布上约 160 画布像素（见下面 WHEEL_MESH_R 的算法）；实体的屏幕投影
## （含抬高的偏移）再宽一点。取 260 是个宽容的落点：比它们都大一圈，手指不容易点空；
## 又不至于误伤 —— 最近的其它可点物是左右两个牌堆，其近边离轮心约 335 画布像素，
## 260 还留着 75 画布像素的余量。
const WHEEL_RADIUS_PX := 260.0
## 转盘实体的半径（世界单位）。桌面 8.0 世界单位 = 2048 画布像素 ⇒ 1 世界单位 = 256 画布像素。
##
## 注意画出来的轮子**不是** 200 画布像素：BoardView 把整块棋盘放进 _world 并按**镜头倍率**
## `_zoom` 缩放（board_view.gd:_apply_cam），于是那个 `size = 400` 的轮子落到画布上只有
## 200 × _zoom ≈ 160 画布像素（默认取景 _zoom ≈ 0.80）。所以「与画出来的轮子同平面 footprint」
## 的那个值是 0.62 —— 但出图核对发现 0.62 时轮子的金色外圈会从圆柱底下露出一大圈：圆柱是
## **立体的**，顶面抬离桌面 0.05~0.08 世界单位，相机 50° 俯角下它的屏幕投影整体上移约 17px
## （实测：顶面椭圆的圆心比画出来的轮心高约 17px），把底面那一圈让了出来。
## 取 0.78（= 200 画布像素的平面 footprint，比画出来的轮子宽 _zoom 分之一）正好把这层投影
## 偏移吸收掉 —— 出图里圆柱把画出来的轮子**盖住**，只在下缘留一线金边。
##
## 遗留：这是**固定**的世界半径，而画出来的轮子随 `_zoom` 变（滚轮推拉 / 窗口尺寸）——
## 只在对局默认取景下对得上。真正的解是让实体跟着镜头倍率缩放，留给后续批次。
const WHEEL_MESH_R := 0.78
## 圆柱厚度（世界单位）：太薄看不出体积、也投不出像样的影子。
const WHEEL_MESH_H := 0.06
## 物件**底面**离桌垫的高度（世界单位）：贴着桌垫但不与它共面，否则两者 z-fighting 拉花。
const PROPS_Y := 0.02

var _t3: TableView3D
var _wheel_px := Vector2.ZERO

func setup(t3: TableView3D) -> void:
	_t3 = t3

## 在画布坐标 center_px 处立起转盘的实体（有厚度、可投影）。
func build_wheel(center_px: Vector2) -> void:
	_wheel_px = center_px
	var body := MeshInstance3D.new()
	body.name = "WheelBody"
	var cyl := CylinderMesh.new()
	# 圆柱轴默认朝 Y（竖直），正是一张平桌上该有的朝向。
	cyl.top_radius = WHEEL_MESH_R
	cyl.bottom_radius = WHEEL_MESH_R
	cyl.height = WHEEL_MESH_H
	body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.34)   # 与 WheelView 的盘面色同系
	mat.roughness = 0.7
	body.material_override = mat
	# 摆位：画布像素 → 桌面世界坐标（与桌垫同一套 UV 坐标系），再抬到桌面上。
	# 圆柱以**中心**定位，所以 y 要再加半个高度，底面才落在「桌垫 + PROPS_Y」处。
	var w: Vector3 = _t3.canvas_px_to_world(center_px)
	w.y = _t3.table_mesh.global_position.y + PROPS_Y + WHEEL_MESH_H * 0.5
	add_child(body)
	body.global_position = w      # canvas_px_to_world 给的是世界坐标，按世界坐标落位

## 命中判定：画布像素是否落在转盘上。
func wheel_hit(canvas_px: Vector2) -> bool:
	return canvas_px.distance_to(_wheel_px) <= WHEEL_RADIUS_PX
