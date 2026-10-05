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

## 家具模型的**统一缩放**。Kenney 那批 `.glb` 是**米制**的（实测 `desk.glb` 0.734 宽、
## `chairDesk.glb` 0.479 宽），而本项目的世界单位是"桌宽 8"那一档 —— 1:1 摆进去的话
## 家具只有桌子的 1/11 宽，像桌上的火柴盒（一期 Task 4 实测过）。
##
## **1 米 ≈ 5 世界单位**：8 宽的桌子 ≈ 1.6 m、13 高的天花板 ≈ 2.6 m，是一间说得通的屋子；
## 椅子 0.479 × 5 = **2.4 宽**，对着 8 宽的桌子，四把围一圈还宽裕 —— **这一条才是定档的
## 锚点**（桌子与椅子的大小关系就是按它定的）。
## ⚠ **Task 5 的四把椅子必须用同一个常量** —— 它和桌子的大小关系是这一条定下来的。
const FURNITURE_SCALE := 5.0

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

## 家具清单：`[模型文件名, 世界位置（**站立点的世界坐标**）, 绕 Y 的朝向角]`。
## **位置全在左半侧（x < 0）** —— 落在吊灯的光域里（见下面那条断言的理由）。
## 模型文件名出自 Task 1 落地的 Kenney Furniture Kit（`assets/models/*.glb`，CC0）。
##
## **世界位置一律由 `ROOM_W` / `ROOM_D` 推导、不写死**：Task 7 要重取 3D 端取景、可能改
## `ROOM_D` —— 写死的坐标要么把家具埋进墙里、要么把它摞到桌子上。做法是**每件都贴着墙角摆**：
## x 从西墙量、z 从远墙量（`-ROOM_D * 0.5 + 进深`），墙一挪家具跟着挪。
##
## **模型是朝 -z 长的**（站立点在它的**前沿**、背板朝远墙缩进去），所以"离墙多远"那一项
## 用的是各件**实测**的进深（`.glb` 的 AABB：书架 1.25 / 书桌 1.9 / 收纳箱 1.06，均已 ×5）。
## 三件的 AABB 两两不相交（实测），且都在木桌远边（z = -3.4797）之外。
const FURNITURE := [
	# 书架：贴西墙（最靠里的一件）
	["bookcaseOpen.glb",       Vector3(-ROOM_W * 0.5 + 0.3, 0.0, -ROOM_D * 0.5 + 1.4),  0.0],
	# 书桌：贴远墙、在书架右边（背板与书架齐平，都离远墙 0.15）
	["desk.glb",               Vector3(-ROOM_W * 0.5 + 2.6, 0.0, -ROOM_D * 0.5 + 2.05), 0.0],
	# 收纳箱：挪到书架**前面**、转 20°（别排成一条直线 —— 转过的 AABB 仍与那两件不相交）
	["cardboardBoxClosed.glb", Vector3(-ROOM_W * 0.5 + 0.6, 0.0, -ROOM_D * 0.5 + 3.0), 20.0],
]

## 摆出来的家具落点（世界坐标，与 `FURNITURE` 逐条同序）。
## **由 `_build_furniture()` 落定时填**（不把坐标抄第二遍 —— 单一来源仍是上面那张表）。
## 计划 Interfaces 承诺过这个名字；今天没有下游消费，它记录的是"家具摆在哪"。
static var FURNITURE_ANCHORS: Array[Vector3] = []

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
	_build_furniture()

## 家具摆位。**外壳的一部分**（`build()` 只认外壳那一层，这里不再往外挂别的入口）。
## 缺模型时 `load()` 给 null ⇒ `push_warning` 跳过，而测试里"至少三件家具"那条会红
## —— **这是有意的**（缺模型本来就该拦住，见 progress.md 的 Ruling D）。
func _build_furniture() -> void:
	var fur := Node3D.new()
	fur.name = "Furniture"
	add_child(fur)
	FURNITURE_ANCHORS.clear()
	for row in FURNITURE:
		var path: String = "res://assets/models/%s" % row[0]
		var packed: PackedScene = load(path)
		if packed == null:
			push_warning("房间家具缺模型：%s（跳过）" % path)
			continue
		var mi := packed.instantiate() as Node3D
		fur.add_child(mi)
		# **缩放只改变外形，不改"站哪儿"**：节点的 `position` 活在**父节点**那一系里，与它自己的
		# `scale` 无关 ⇒ 上面那张表里的坐标仍是**世界站立点**（`layout_test` 量的也是 global_position）。
		# 模型的基点本来就在脚底（实测 AABB 的 min.y = 0），绕着原点放大不会陷进地板。
		mi.scale = Vector3.ONE * FURNITURE_SCALE
		mi.position = row[1]
		mi.rotation_degrees = Vector3(0.0, row[2], 0.0)
		# **记局部 `position`，不读 `global_position`**：`build()` 是 `table_3d._init()` 里调的，
		# 那时 `TableView3D` 自己还没进树 ⇒ 整棵子树 `is_inside_tree() == false`，读全局变换会
		# 打一串 `Condition "!is_inside_tree()" is true` 的 ERROR。房间自己恒在原点、无旋转，
		# 局部 == 世界，`FURNITURE_ANCHORS` 记的就是世界落点（`layout_test` 那条断言量的也是它）。
		FURNITURE_ANCHORS.append(mi.position)
		# **模型自带的几何实例要逐个关投影** —— instantiate 出来的节点不继承父级的 shadow 设置，
		# 这是本项目最容易漏关阴影的地方（`layout_test` 那条"房间物件一律不投影"就是为了兜住它）。
		for n in mi.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
