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

## 地板高度（**公开常量**：`table_3d` 建桌子底座时读它 —— 方向是 `table_3d` → `GameRoom`，
## 与 `GameRoom.build()` 同向；房间仍然不反向依赖桌子）。
##
## **一期 Task 5 Step 0（2026-10-05 用户拍板，spec §六「地板高度与桌子底座」）**：
## 地板原先在**桌面那一层**（`y = 0`；Task 3 改成 −0.02 只是为了不被木纹外框盖住）——
## 于是桌子读作"平铺在地板上的一块板"，而**按人体比例摆出来的椅子 / 家具"站不对"**
##（椅面会落到桌面之上）。降到这里之后整套比例才立得住：
##   * `-3.70 / 5 = 0.74 m` —— 正是**真实桌高**（同 `FURNITURE_SCALE` 那条"1 米 ≈ 5 世界单位"）；
##   * 房间 `22 × 18 × 16.7` ⇒ `4.4 × 3.6 × 3.34 m`，一间说得通的宿舍；
##   * 吊灯在 `y = 10` ⇒ 离地 `13.7 / 5 = 2.74 m`，一盏正常的吊灯。
## **顺带收益（实测，别夸大）**：地板降下去后 3D 端上缘的视线能打到 `z ≈ −12` ⇒ **远墙进画**，
## 但只占顶上约 **6%** 一条暗带，又细又淡 ⇒ 降地板的主要理由仍是**桌椅能不能站对**，
## 不是"看得见屋子"（那一轴归 Ctrl+滚轮推拉，见 spec §四追加）。
const FLOOR_Y := -3.70

## 家具与椅子的**统一缩放**。**= 10.0**（一期 Task 5 复核后改档，见下）。
##
## **为什么是 10**：这批 Kenney `.glb` 是**半比例**的 —— 把它们的尺寸按米读，书桌只有
## `0.734 × 0.384 × 0.392`（真实书桌 1.5 × 0.75 m）、单人床长 `1.125`（真实 2 m）、
## 椅子高 `0.47`（真实 0.9 m）—— **全都是真实尺寸的一半**。而本项目的世界单位是 1:1 的：
## **1 世界单位 = 0.2 m**（8 宽的桌子 = 1.6 m、`FLOOR_Y` 到桌面 3.70 = 0.74 m 真实桌高、
## 天花板离地 16.7 = 3.34 m）。⇒ 要把半比例的模型摆成真实大小，就得多乘 2：
## **半比例 × 2 = ×10**（相对"按米读"那套换算的 ×5）。
##
## **定档的锚点 = spec §六 那张用户拍过板的比例表**（一期 Task 5 的"书桌顶面与桌面齐平、
## 椅背高出桌面"那条断言就是它的可执行版）：
##   * 书桌 `0.384 × 10 = 3.84` 高 ⇒ 顶面 `FLOOR_Y + 3.84 = +0.14`，**与桌面（y = 0）齐平** ✓；
##   * 椅子（`chair.glb`，`0.47 × 10 = 4.70` 高）⇒ 顶面 `+1.00`，**高出桌面 1.0** ✓
##    （spec 写的是 +0.8，同一档）；
##   * 吊灯 `y = 10` ⇒ 离地 `13.7 / 5 = 2.74 m` ✓（这一条与缩放无关）。
##
## ⚠ **历史（留着，别再踩）**：Task 4 的 `FURNITURE_SCALE = 5.0` 建在一条**错测量**上 ——
## 那份报告写"`chairDesk.glb` 0.479 宽、书桌 0.734 宽 ⇒ 米制 ⇒ ×5"，而 `0.479 × 0.418 × 0.443`
## 是**漏掉嵌套子节点位移**量出来的假值：`chairDesk.glb` 的真值是 **`0.335 × 0.608 × 0.314`**
## （累乘局部变换重测，见 `_model_aabb`；Task 4 的另外两件量得是对的）。
## ×5 的后果是**家具只有真实家具的一半大**：椅背顶只到 `FLOOR_Y + 3.04 = −0.66`，
## **比桌面还低 0.66** ⇒ spec §六 要的"椅背挂名牌"根本摆不出来。一期 Task 5 Fix round 1
## 由控制者裁定改到 10.0，并按新的尺寸重取了家具摆位（见 `FURNITURE` 那段）。
const FURNITURE_SCALE := 10.0

## `lamp_light_pos` = `table_3d.LAMP_LIGHT_POS`（吊灯的光在世界的哪一点）。
## **由调用方传进来**，不让 `room.gd` 去 import `table_3d` 的常量 —— 房间不该反向依赖桌子。
##
## `table_half` = **连木纹外框一起算的半个桌面**（`table_3d` 传
## `Vector2(TABLE_SIZE.x * 0.5 + WOOD_FRAME, TABLE_SIZE.y * 0.5 + WOOD_FRAME)` = **4.7 / 3.4795**）。
## 四把椅子要围着桌子摆（Task 5），房间就得知道"桌子到哪儿为止"；**连木纹一起收下**是为了让
## `room.gd` 不必自己再写一遍木纹那 0.7（房间不认识 `WOOD_FRAME`，那是桌子的实现）——
## 与 `lamp_light_pos` 同一条规矩：**只收数，不反向依赖**。
##（Task 7 Step 0 会把那两项提成 `WOOD_HALF_W` / `WOOD_HALF_D`，届时调用点用那两个常量即可。）
static func build(parent: Node3D, lamp_light_pos: Vector3, table_half: Vector2) -> GameRoom:
	if not ROOM_ENABLED:
		return null
	var r := GameRoom.new()
	r.name = "Room"
	parent.add_child(r)
	r._lamp_light_pos = lamp_light_pos
	r._table_half = table_half
	r._build_shell()
	return r

var _lamp_light_pos := Vector3.ZERO

## **连木纹外框**的半个桌面（宽 / 进深，由 `build()` 收下）。椅子摆位由它推导、**不写死坐标**：
## 桌子尺寸一变（Task 7 会重取取景、可能动 `TABLE_D`），椅子跟着走。
var _table_half := Vector2(4.7, 3.4795)

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
## 站立点 = **地板**（`FLOOR_Y`）。一期 Task 5 Step 0 之前这里写的是 `0.0` —— 那时地板就在
## 桌面那一层；地板一降，家具必须跟着站到新地板上（不跟就是悬在半空，而"看位置对不对"看不出来）。
##
## **一期 Task 5 Fix round 1：整张表按 ×10 重取**（`FURNITURE_SCALE` 5 → 10，每件都大了一倍，
## 原来的坐标全都不成立）。重取时用的尺寸是**实测合并 AABB ×10**（见 `_model_aabb`；
## **不抄 Task 4 报告里的数** —— 那一批的椅子/书桌量短了）：
##   书架 `4.0 × 8.8 × 2.5` / 书桌 `7.34 × 3.84 × 3.92` / 收纳箱 `2.13 × 2.81 × 2.13`（宽 × 高 × 深）。
## 四条约束一条没丢：**位置由 `ROOM_W`/`ROOM_D` 推导**、**两两 AABB 不相交**、**都在木桌远边
## （z ≤ −3.48）之外**、**整体落在房间里**（含 y：站在 `FLOOR_Y` 上、高不过天花板）。
const FURNITURE := [
	# 书架：贴西墙（最靠里的一件）。x = 西墙 + 0.5（墙边留 0.5）；z = 远墙 + 2.65
	#（= 进深 2.5 + 离远墙 0.15）—— 与原来的 +1.4（进深 1.25 + 0.15）同一条式子，只是进深翻倍。
	["bookcaseOpen.glb",       Vector3(-ROOM_W * 0.5 + 0.5, FLOOR_Y, -ROOM_D * 0.5 + 2.65), 0.0],
	# 书桌：贴远墙、在书架右边。z = 远墙 + 3.95（= 进深 3.8 + 离远墙 0.15）；
	# x 让开书架（书架右沿 −6.5，这里从 −6.3 起 ⇒ 净空 0.2）。桌宽 7.34 ⇒ x 一直到 +1.05，
	# 但**站位坐标仍落在左半侧**（−6.2 < 0，光域那条断言量的就是它）。
	["desk.glb",               Vector3(-ROOM_W * 0.5 + 4.8, FLOOR_Y, -ROOM_D * 0.5 + 3.95), 0.0],
	# 收纳箱：在书架**前面**（原本转 20° 是为了"别排成一条直线"，×10 之后它在书架正前方、
	# 已经不成直线了，而转 20° 会让它的 AABB 往书架那边多伸 0.6（2.13 → 2.72）⇒ 净空掉到 0.03，
	# 所以**回到 0 度**，换来 0.18 的净空）。z = 远墙 + 4.95（= 进深 2.13 + 离书架 0.18 + …）。
	["cardboardBoxClosed.glb", Vector3(-ROOM_W * 0.5 + 1.0, FLOOR_Y, -ROOM_D * 0.5 + 4.95), 0.0],
]

## 摆出来的家具落点（世界坐标，与 `FURNITURE` 逐条同序）。
## **由 `_build_furniture()` 落定时填**（不把坐标抄第二遍 —— 单一来源仍是上面那张表）。
## 计划 Interfaces 承诺过这个名字；今天没有下游消费，它记录的是"家具摆在哪"。
static var FURNITURE_ANCHORS: Array[Vector3] = []

# ---------------- 四把椅子 + 椅背名牌（一期 Task 5） ----------------
#
# **这是二期的接口**（spec §十）：每把椅子定死「位置 + 朝向」、并挂一个名牌挂点，
# 二期"把人放上去"只改这一处 —— `seat_anchor(slot)` / `NAMEPLATE_ANCHORS`。

## 椅子用的模型（Task 1 落地的 Kenney Furniture Kit，`assets/models/*.glb`，CC0）。
## **四把同一款**：桌面是张学习桌，四把各一款会读成"随手凑来的四把椅子"。
##
## **一期 Task 5 Fix round 1 从 `chairDesk` 换成 `chair`**：×5 那档选 `chairDesk` 是因为它最高
##（最出镜）；改到 ×10（真实尺寸）之后这条理由没了，该按**真实比例**挑 ——
## `chair` 实测 `0.2 × 0.47 × 0.2` ⇒ ×10 = **`2.0 × 4.7 × 2.0`**，即 **0.4 × 0.94 × 0.4 m**，
## 正是**一把普通椅子**（椅背顶离地 0.94 m）；而 `chairDesk` `0.6076 × 10 = 6.08` ＝ **1.22 m**，
## 那是一把高脚工作椅 / 绘图凳，配上这张 0.74 m 的桌子就太高了。
## spec §六 那张比例表按的就是"椅背高出桌面 0.8"（`chair` 给 1.0，`chairDesk` 会给 2.4）。
##
## **缩放复用 `FURNITURE_SCALE`** —— 不另取一套比例：椅子与家具一旦两套比例，
## 屋里就会出现"椅子比书桌还高"这类说不通的关系。
const CHAIR_MODEL := "chair.glb"

## 椅子前沿离**木桌外沿**（连木纹）的净空（世界单位）= 0.15 ≈ 3 cm：椅子是**贴着桌子**摆的，
## 不是围着桌子散开。
## **Fix round 1：这一项不再需要把木纹那 0.7 算进来** —— `build()` 现在收的 `table_half` 是
## **连木纹一起的**半个桌面，所以这里就是一条**纯净空**（原来 0.85 里那 0.7 是替 `WOOD_FRAME`
## 垫的，见 `build()` 那段）。桌子底下那块裙板一直落到地板 ⇒ 椅子**塞不进桌下**，
## 于是留一条看得见的缝、而不是让椅子与裙子互穿。
const SEAT_INSET := 0.15

## 椅背名牌：一块薄牌（BoxMesh）+ 一行名字（Label3D）。薄牌的**颜色 = 这家的棋子色**
## （`GameData.PLAYER_COLORS`，spec §六/§十）—— **不是**按座位序号取的色。
const NAMEPLATE_SIZE := Vector3(1.10, 0.42, 0.06)
## 名牌文字的量法（同 `table_props.DECK_FONT_PS`）：`pixel_size × font_size` = 一个字的边长（世界）。
## 0.0022 × 64 = 0.141 —— 两个汉字 0.282，占牌宽 1.10 的 **26%**（名字长一点也不会溢出）。
const NAMEPLATE_FONT_PS := 0.0022

## 名牌挂点（世界坐标，与座位序同序）—— spec §十 要的二期接口。
## 与 `FURNITURE_ANCHORS` 同为 `static var`、由 `_build_chairs()` 落定时填（房间在原点、无变换，
## 局部即世界；`build()` 期不许读全局量，见 `_build_furniture` 那段）。
static var NAMEPLATE_ANCHORS: Array[Vector3] = []

func _build_shell() -> void:
	_make_materials()
	# 地板在 **`FLOOR_Y`**（真实桌高）。
	# 历史（别按它改回去）：Task 3 曾把地板放在 −0.02 —— 那是"地板就在桌面那一层"的年代，
	# 压 0.02 只为不被木纹外框整片盖掉（桌心那一层 y = 0 同时是桌垫所在，而木桌外框在
	# y = -0.012 且比桌垫大一圈：地板放 y = 0 会先被相机打到、外框那条亮木纹带整条不见，
	# 而取景判据正是按木桌四角量的；另外与桌垫共面还会闪）。
	# 地板降到 `FLOOR_Y` 之后这两条都不再成立（外框在 3.7 之上，离地板远得很），
	# 见 `FLOOR_Y` 那段。
	_plane("Floor",   Vector3(0, FLOOR_Y, 0),      Vector2(ROOM_W, ROOM_D), Vector3.ZERO,         _floor_mat)
	_plane("Ceiling", Vector3(0, ROOM_CEIL_Y, 0),  Vector2(ROOM_W, ROOM_D), Vector3.ZERO,         _ceil_mat)
	# 四面墙：竖直的 PlaneMesh（默认躺在 XZ 平面，绕 X 转 90° 立起来）
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	# **墙高与墙心都跟着地板走**：`h = 天花板 − 地板`、中心取两者中点 ⇒ 墙脚正好落在地板上。
	# 少了这一条（还按 `ROOM_CEIL_Y` 量），四面墙一圈的墙脚会悬在地板上方 3.7 个单位。
	var h := ROOM_CEIL_Y - FLOOR_Y
	var wy := (ROOM_CEIL_Y + FLOOR_Y) * 0.5
	_plane("WallN", Vector3(0, wy, -ROOM_D * 0.5), Vector2(ROOM_W, h), Vector3(90, 0, 0),    _wall_mat, walls)
	_plane("WallS", Vector3(0, wy,  ROOM_D * 0.5), Vector2(ROOM_W, h), Vector3(-90, 0, 0),   _wall_mat, walls)
	_plane("WallW", Vector3(-ROOM_W * 0.5, wy, 0), Vector2(ROOM_D, h), Vector3(90, 90, 0),   _wall_mat, walls)
	_plane("WallE", Vector3( ROOM_W * 0.5, wy, 0), Vector2(ROOM_D, h), Vector3(90, -90, 0),  _wall_mat, walls)
	_build_furniture()
	_build_chairs()

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
		_no_shadow(mi)

## 一棵子树里的几何实例**逐个关投影**（房间的纪律：全场唯一投影源是那盏吊灯）。
## 为什么要走一遍而不是继承：`instantiate()` 出来的节点不继承父级的 shadow 设置。
static func _no_shadow(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------- 四把椅子（一期 Task 5） ----------------

## 围桌四把椅子：**一条边一把**（桌子 8 宽 × 5.56 深，一边一把最平衡）。
##
## **座位序（slot）与 `game._seat_peers()` 是同一份顺序** —— 那份顺序由 `game.gd` 的
## `_refresh_players()` 每次状态广播经 `set_seats()` 喂进来（**不在 `_ready`**：那一刻
## 状态还是空的）。slot 0 = **近端 = 相机这一侧 = "我"**（`_seat_peers()` 以"我"打头；
## spec §六：近侧看到的是**我自己那把椅子的椅背**），之后按**俯视逆时针**排：
## 近 → 右 → 远 → 左。为什么是这个旋向：棋盘上棋子的行进是"近边从右往左 → 左边向上 →
## 远边从左往右"，也就是俯视的逆时针 ⇒ 座位跟着走，二期把人放上去时"下家在我右手边"。
##
## 位置与朝向**一律由 `_table_size`（+ 实测的椅子尺寸）推导、不写死坐标**：
## Task 7 会重取取景、可能改桌子进深，写死就会让椅子穿进桌子或飘到屋外。
func _build_chairs() -> void:
	var seats := Node3D.new()
	seats.name = "Seats"
	add_child(seats)
	NAMEPLATE_ANCHORS.clear()
	var packed: PackedScene = load("res://assets/models/%s" % CHAIR_MODEL)
	if packed == null:
		push_warning("房间缺椅子模型：%s（跳过）" % CHAIR_MODEL)
		return
	# 量一次模型的 AABB。两个用途：① 把椅子**按包围盒居中**（模型的原点不在中间：
	# `chairDesk` 的 x 只往 +x 长、z 只往 −z 长，不居中摆的话四把会朝同一侧偏出去）；
	# ② 算出它占多大，据此把四条边上的座位摆到桌子之外。
	var ab := _model_aabb(packed)
	var c := ab.get_center()
	var half_x := ab.size.x * 0.5 * FURNITURE_SCALE
	var half_z := ab.size.z * 0.5 * FURNITURE_SCALE
	# `_table_half` 已经是**连木纹外框**的半宽 / 半深 ⇒ 再加净空与椅子自己的半身，就是座位框落点。
	var off_x: float = _table_half.x + SEAT_INSET + half_x
	var off_z: float = _table_half.y + SEAT_INSET + half_z
	# 位置 + 朝向角。**朝向 = 面朝桌心**：模型自己朝 +z 长、背在 −z（实测顶点：最高那一撮
	# 全落在 z 的负半边），所以"面朝桌心"就是把座位框绕 Y 转到"它自己的 +z 指向桌心"，
	# 也就是方位角 `atan2(dx, dz)`。
	var slots := [
		[Vector3(0.0, FLOOR_Y, off_z), 180.0],    # 0 近（+z，镜头这一侧）＝"我"
		[Vector3(off_x, FLOOR_Y, 0.0), -90.0],    # 1 右（+x）
		[Vector3(0.0, FLOOR_Y, -off_z), 0.0],     # 2 远（−z）
		[Vector3(-off_x, FLOOR_Y, 0.0), 90.0],    # 3 左（−x）
	]
	for i in slots.size():
		var row: Array = slots[i]
		var seat := Node3D.new()
		seat.name = "Seat%d" % i
		seats.add_child(seat)
		seat.position = row[0]
		seat.rotation_degrees = Vector3(0.0, row[1], 0.0)
		var mi := packed.instantiate() as Node3D
		seat.add_child(mi)
		# **缩放只改变外形，不改"站哪儿"**（同 `_build_furniture` 那条）。
		mi.scale = Vector3.ONE * FURNITURE_SCALE
		# 包围盒居中；**底面留在座位框的 y = 0**（座位框摆在 `FLOOR_Y` ⇒ 椅子站在地板上，
		# 这正是 `layout_test` 那条"站在地板上"量的东西）。
		mi.position = Vector3(-c.x * FURNITURE_SCALE, 0.0, -c.z * FURNITURE_SCALE)
		_no_shadow(mi)
		_make_nameplate(seat, ab, half_z)

## 椅背名牌：一块薄牌 + 一行名字，挂在**椅背**上（座位框的 −z 侧 —— 模型自己的背在 −z）。
## 薄牌的颜色**先留白**，等 `set_seats()` 喂进各家颜色再上色（没有状态时整块不露）。
func _make_nameplate(seat: Node3D, ab: AABB, half_z: float) -> void:
	var root := Node3D.new()
	root.name = "Nameplate"
	seat.add_child(root)
	# 挂在椅背顶上：比椅子矮 0.30（不顶到椅子最高那一线），贴在背板外侧
	root.position = Vector3(0.0, ab.size.y * FURNITURE_SCALE - 0.30,
		-half_z - NAMEPLATE_SIZE.z * 0.5 - 0.02)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var bm := BoxMesh.new()
	bm.size = NAMEPLATE_SIZE
	plate.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.55)     # 没人坐时的底色（`set_seats` 会刷成棋子色）
	mat.roughness = 0.72
	plate.material_override = mat
	root.add_child(plate)
	var lab := Label3D.new()
	lab.name = "Label"
	lab.font_size = 64
	lab.pixel_size = NAMEPLATE_FONT_PS
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.outline_size = 10
	lab.outline_modulate = Color(0.02, 0.02, 0.03, 0.95)
	# 名字贴在牌的**外侧**那一面：Label3D 默认面朝 +z，而名牌挂在椅背的 −z 侧
	#（读它的人站在椅子背后）⇒ 绕 Y 转 180°。
	# 不 billboard：它是钉在椅背上的铭牌，不该随镜头转（同牌堆顶上那两块牌名）。
	lab.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	lab.position = Vector3(0.0, 0.0, -NAMEPLATE_SIZE.z * 0.5 - 0.01)
	root.add_child(lab)
	_no_shadow(root)
	# 二期接口：名牌挂点（房间自己无变换 ⇒ 局部 == 世界）
	NAMEPLATE_ANCHORS.append(seat.transform * root.position)

## 一个模型（`PackedScene`）自己的 AABB。**用累乘的局部变换算，不读任何全局量**。
## 为什么不照 `_build_furniture` 那样直接摆：那些模型的几何挂在**嵌套**的子节点上
##（`chairDesk` 的椅身就是它的子节点、还带自己的位移），只看第一层的 `transform` 会量错 ——
## 实测漏掉那一层位移时得到 `0.479 × 0.418 × 0.443`，真值是 `0.335 × 0.608 × 0.314`
##（Task 4 报告里那个"椅子宽 0.48"就是这么量出来的，`FURNITURE_SCALE` 的推导挂在它上面）。
static func _model_aabb(packed: PackedScene) -> AABB:
	var mi := packed.instantiate() as Node3D
	var boxes: Array[AABB] = []
	_collect_aabb(mi, Transform3D(), boxes)     # 根节点的自己在 `_collect_aabb` 里乘进去
	var out := AABB()
	for i in boxes.size():
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	mi.free()
	return out

static func _collect_aabb(n: Node, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(xf * (n as MeshInstance3D).mesh.get_aabb())
	for ch in n.get_children():
		_collect_aabb(ch, xf, out)

# ---- 座位 ↔ peer（二期"往椅子上放人"的唯一入口） ----

## 椅子 ↔ peer 的映射。**与 `game._seat_peers()` 同一份顺序** —— 不许各写一份。
var _seat_peers: Array = []
## 每个座位一条 `{peer, color, name}`（颜色 = 各家的棋子色，名牌用它上色）。
var _seats: Array = []
## 上一次喂进来的那份的指纹（**早退用**）：`_refresh_players()` 每次状态广播都会调 `set_seats`，
## 少了这条早退，每次广播都会把四块名牌重刷一遍。
var _seat_key := ""

## 喂座位序：`[{peer, color, name}, …]`，下标 = 第几把椅子（slot）。
## `color` 是 `st` 里那个**棋子色下标**（`p.color`）⇒ 名牌取 `GameData.PLAYER_COLORS[color]`；
## `name` 可缺（缺就是空名牌）。**顺序 / 颜色 / 名字一字未变时直接返回**（每次广播都调本函数）。
func set_seats(seats: Array) -> void:
	var key := ""
	for s in seats:
		var d: Dictionary = s
		key += "%d/%d/%s|" % [int(d.get("peer", GameData.NO_PEER)),
			int(d.get("color", 0)), String(d.get("name", ""))]
	if key == _seat_key:
		return
	_seat_key = key
	_seats = seats.duplicate(true)
	_seat_peers.clear()
	for s in _seats:
		_seat_peers.append(int((s as Dictionary).get("peer", GameData.NO_PEER)))
	_refresh_nameplates()

## 当前座位序（与喂进来的那份逐项相同）。
func seat_peers() -> Array:
	return _seat_peers

## 第 `slot` 把椅子的锚点（**位置 + 朝向**）。**二期往椅子上放人只读这一个接口。**
## ⚠ 返回 `global_transform` ⇒ **只在入树之后调**：`build()` 期整棵子树还没入树，那时读全局量
## 会打 ERROR 并**静默写错值**（同 `_build_furniture` 那段）。
func seat_anchor(slot: int) -> Transform3D:
	var seats := get_node_or_null("Seats")
	if seats == null or slot < 0 or slot >= seats.get_child_count():
		return Transform3D()
	return (seats.get_child(slot) as Node3D).global_transform

## 把各家的棋子色与名字刷到椅背名牌上。座位比人多时（单人局）多出来的那几块收起。
func _refresh_nameplates() -> void:
	var seats := get_node_or_null("Seats")
	if seats == null:
		return
	for i in seats.get_child_count():
		var seat := seats.get_child(i) as Node3D
		var root := seat.get_node_or_null("Nameplate") as Node3D
		if root == null:
			continue
		var occupied := i < _seats.size()
		root.visible = occupied
		if not occupied:
			continue
		var s: Dictionary = _seats[i]
		var plate := root.get_node_or_null("Plate") as MeshInstance3D
		if plate != null:
			var mat := plate.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = GameData.PLAYER_COLORS[
					clampi(int(s.get("color", 0)), 0, GameData.PLAYER_COLORS.size() - 1)]
		var lab := root.get_node_or_null("Label") as Label3D
		if lab != null:
			lab.text = String(s.get("name", ""))

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
