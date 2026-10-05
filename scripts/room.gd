class_name GameRoom
extends Node3D
## 3D 房间（一期）：天花板 / 地板 / 四面墙 / 家具 / 四把椅子与名牌 / 吊灯可见几何 / 补光。
##
## **只摆位与长相，不碰玩法** —— 与 `table_props.gd` 同一条纪律。
## **一律不投影**：那盏吊灯是全场唯一投影源（见 `table_3d.LAMP_LIGHT_POS`），
## 房间多一个投影物件就多一张阴影图，性能与氛围两头不讨好。
##
## 总开关 `ROOM_ENABLED`：置 false 就整层不建，回到"只有桌子"的样子。
## 这是本期的保命开关 —— 房间出任何问题都可以先关掉它，不影响对局。

const ROOM_ENABLED := true

## 房间尺寸。以桌心为原点；桌面在 y = 0。
## 天花板必须高于吊灯的光（`LAMP_LIGHT_POS.y = 10.0`），否则灯吊到了屋顶外。
const ROOM_W := 22.0          # 房间宽（x）
const ROOM_D := 18.0          # 房间深（z）
const ROOM_CEIL_Y := 13.0     # 天花板高

## `lamp_light_pos` = `table_3d.LAMP_LIGHT_POS`（吊灯的光在世界的哪一点）。
## **由调用方传进来**，不让 `room.gd` 去 import `table_3d` 的常量 —— 房间不该反向依赖桌子。
static func build(parent: Node3D, lamp_light_pos: Vector3) -> GameRoom:
	if not ROOM_ENABLED:
		return null
	var r := GameRoom.new()
	r.name = "Room"
	parent.add_child(r)
	r._lamp_light_pos = lamp_light_pos
	r._build_shell()
	return r

var _lamp_light_pos := Vector3.ZERO

## 外壳材质。**受光正确的粗糙材质** —— 房间在暗环境里，材质一滑就会发灰发亮。
## 贴图沿用项目既有来源 ambientCG（与棋盘木纹同源，CC0）；**取不到就退回纯色**
## —— 与项目"素材缺失退回纯色"的既有做法一致。
var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D

func _make_materials() -> void:
	_floor_mat = _lit_mat(Color(0.30, 0.26, 0.22), "res://assets/textures/wood_floor.jpg")
	_wall_mat  = _lit_mat(Color(0.42, 0.40, 0.38), "")   # 白灰墙
	_ceil_mat  = _lit_mat(Color(0.34, 0.33, 0.33), "")

## 受光的粗糙材质。**不许用 UNSHADED** —— 那会让房间对吊灯与环境光毫无反应、
## 变成一块死平的贴图（与 `table_3d._build_table()` 里桌垫那段注释同一个道理）。
func _lit_mat(base: Color, tex_path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = 0.88
	m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# **双面**：PlaneMesh 默认单面，墙绕一圈总有一半背面朝内 —— 不关剔除就会漏出洞。
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex_path != "":
		var t: Texture2D = _ui_kit_tex(tex_path)
		if t != null:
			m.albedo_texture = t
			m.texture_repeat = true
			m.uv1_scale = Vector3(ROOM_W / 3.0, ROOM_D / 3.0, 1.0)   # 每 3 世界单位一轮
	return m

func _build_shell() -> void:
	_make_materials()
	# 地板**略低于桌面**（计划原文写的是 y = 0.0，这里改成 -0.02 —— **一处经实测的修正**）。
	# 桌心那一层（y = 0）同时是桌垫所在、而 `table_3d._build_table()` 的**木桌外框**在
	# y = -0.012 且比桌垫大一圈。地板放 y = 0 会同时踩两个坑：
	#   ① **整片盖掉木桌外框** —— 相机在 y > 0，任何打到外框的视线都先穿过 y = 0 的地板。
	#      实测（出图 + 逐像素比对，见 task-3-report）：外框那条亮木纹带从 (83,41,18) 掉到
	#      (41,28,17)（≈×0.49 = 地板/外框的 albedo 比 0.30/0.62），出图上外框整条不见、
	#      只剩一片糊开的地板。而设计 §二 的 3D 端取景判据正是**木桌四角** —— 外框看不见，
	#      Task 7/8 就是"照着一个看不见的东西取景"。
	#   ② 与桌垫（同为 y = 0）**共面** —— 正是外框当年被压到 -0.012 的那个坑（"共面的两片会闪"）。
	# -0.02 压在两片之下，且不改"以桌心为原点、桌面在 y = 0"这套房间尺寸约定（天花板仍按 0 量）。
	_plane("Floor",   Vector3(0, -0.02, 0),        Vector2(ROOM_W, ROOM_D), Vector3.ZERO,         _floor_mat)
	_plane("Ceiling", Vector3(0, ROOM_CEIL_Y, 0),  Vector2(ROOM_W, ROOM_D), Vector3.ZERO,         _ceil_mat)
	# 四面墙：竖直的 PlaneMesh（默认躺在 XZ 平面，绕 X 转 90° 立起来）
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var h := ROOM_CEIL_Y
	_plane("WallN", Vector3(0, h * 0.5, -ROOM_D * 0.5), Vector2(ROOM_W, h), Vector3(90, 0, 0),    _wall_mat, walls)
	_plane("WallS", Vector3(0, h * 0.5,  ROOM_D * 0.5), Vector2(ROOM_W, h), Vector3(-90, 0, 0),   _wall_mat, walls)
	_plane("WallW", Vector3(-ROOM_W * 0.5, h * 0.5, 0), Vector2(ROOM_D, h), Vector3(90, 90, 0),   _wall_mat, walls)
	_plane("WallE", Vector3( ROOM_W * 0.5, h * 0.5, 0), Vector2(ROOM_D, h), Vector3(90, -90, 0),  _wall_mat, walls)

## `UIKit` **走运行时 `load`**，不静态写类名：`ui_kit.gd` 里的按钮音效引用了 autoload `Fx`，
## 静态引用会把整条依赖链拽进 `--script` 入口的那一次编译（那时 autoload 还没注册）
## ⇒ 整链「Identifier not found: Fx」编译失败，`layout_test.gd` 连文件都跑不起来。
## 本仓库既有约定同此（见 `layout_test.gd` / `table_props.gd` 里对 `item_card.gd` 的那条）。
static func _ui_kit_tex(path: String) -> Texture2D:
	var uk = load("res://scripts/ui_kit.gd")
	if uk == null:
		return null
	return uk.tex(path) as Texture2D

## 一块平面。`rot_deg` 是欧拉角（度）；`parent` 缺省挂在自己身上。
## **一律 `cast_shadow = OFF`** —— 房间不是投影源（全场唯一投影源是那盏吊灯）。
func _plane(nm: String, pos: Vector3, size: Vector2, rot_deg: Vector3,
			mat: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi
