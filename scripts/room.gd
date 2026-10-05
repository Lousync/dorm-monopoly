class_name GameRoom
extends Node3D
## 3D 房间（一期）：天花板 / 地板 / 四面墙 / 家具 / 四把椅子与名牌 / 地毯 / 补光。
##
## **只摆位与长相，不碰玩法** —— 与 `table_props.gd` 同一条纪律。
## **房间不是对称的**（一期 Task 7 起）：**远半侧**（`z ∈ [-ROOM_D/2, 桌心]`）是玩家看得见的那间屋子，
## 全按 `ROOM_D` 推导；**近半侧**多出一段 `ROOM_NEAR_EXTRA`，只为了给 3D 相机一个站的地方
## （`Ctrl`+滚轮拉远时相机要往后走，而它原本贴在近墙上）—— 那一段**永远不在画面里**。
## 详见 `ROOM_NEAR_EXTRA` 那段。
## **一律不投影**：那盏吊灯是全场唯一投影源（见 `table_3d.LAMP_LIGHT_POS`），
## 房间多一个投影物件就多一张阴影图，性能与氛围两头不讨好。
## **补光也不投影**：它是"只有一处投影源"那条契约的另一半（见 `FILL_LIGHT_POS` 那段）。
##
## 总开关 `ROOM_ENABLED`：置 false 就整层不建，回到"只有桌子"的样子。
## 这是本期的保命开关 —— 房间出任何问题都可以先关掉它，不影响对局。

const ROOM_ENABLED := true

## 房间尺寸。以桌心为原点；桌面在 y = 0。
## 天花板必须高于吊灯的光（`LAMP_LIGHT_POS.y = 10.0`），否则灯吊到了屋顶外。
const ROOM_W := 22.0          # 房间宽（x）
## 房间深（z）—— **远半侧**：**远墙恒在 `z = -ROOM_D * 0.5`**（家具、四把椅子、取景全按它推导）。
const ROOM_D := 18.0
## **近半侧**（相机这一侧）额外多出来的进深。**一期 Task 7 追加**，理由是一期新增的
## `Ctrl`+滚轮推拉：那个轴的"拉远端"要把相机往后挪，而**默认档的相机已经贴在近墙上了** ——
## `CAM_DIST = 8.90`、俯角 50° ⇒ 相机在 `z = +8.90`，而房间近墙原在 `z = +9.00`
## ⇒ 一往后拉就**穿墙到屋外**（实测 `dolly = 1.15` 的摆拍**整张全黑**：
## 近墙与天花板双双挡在相机与桌子之间）。
## 两种补法的取舍（实测）：**把 `ROOM_D` 整体放大不行** —— 远墙跟着往后退，
## 默认档的远墙带会从 18% 掉到 **5%**（远墙脚 y 143 → 40，几乎贴到视口顶端）；
## **只把近半侧加长**则**远半侧一个数都不动**（远墙、家具、椅子、默认档取景全部不变），
## 而多出来的那一截 `z ∈ [+9, +14]` **永远不在画面里**（50° 俯角下面那条视线只到 `z ≈ +4.8`）⇒
## 视觉上零代价。**这不是"把房间偷偷放大"**：可见的那间屋子仍是 `22 × 18`。
## 取 5.0 是照着"拉远端"那一档订的：`dolly = 1.40` 时相机在 `z = +12.46`，离近墙还有 1.54。
const ROOM_NEAR_EXTRA := 5.0
## 天花板高。**一期 Task 7：13.0 → 16.0**（同一件事的另一半：拉远端把相机**顶高**到
## `y = d3d·sin50°`，`dolly = 1.40` 时到 `+14.85` —— 天花板还留在 13 的话相机就窜到屋顶上方，
## 而天花板是**双面**的 ⇒ 又一张全黑的摆拍）。**这一项视觉上也是零代价**：
## 四面墙是**纯色平面**（`_lit_mat(.., "")`、无贴图），加高只把墙往画面上方延长，
## 而画面上方永远是那条近黑背景；天花板本身在 50° 俯角下**从不入画**。
## ⇒ 屋子读起来的进深与层高没变（可见部分仍是 `22 × 18`、墙脚到视口顶边那一截），
## 变的只是"相机有地方站"。
const ROOM_CEIL_Y := 16.0

## 地板高度（**公开常量**：`table_3d` 建桌子底座时读它 —— 方向是 `table_3d` → `GameRoom`，
## 与 `GameRoom.build()` 同向；房间仍然不反向依赖桌子）。
##
## **一期 Task 5 Step 0（2026-10-05 用户拍板，spec §六「地板高度与桌子底座」）**：
## 地板原先在**桌面那一层**（`y = 0`；Task 3 改成 −0.02 只是为了不被木纹外框盖住）——
## 于是桌子读作"平铺在地板上的一块板"，而**按人体比例摆出来的椅子 / 家具"站不对"**
##（椅面会落到桌面之上）。降到这里之后整套比例才立得住：
##   * `-3.70 / 5 = 0.74 m` —— 正是**真实桌高**（同 `FURNITURE_SCALE` 那条"1 米 ≈ 5 世界单位"）；
##   * 房间 `22 × 18 × 19.7` ⇒ `4.4 × 3.6 × 3.94 m`，一间说得通的宿舍；
##     （**终审 F6 改正**：原写 `22 × 18 × 16.7` ⇒ `3.34 m` —— 那是 `ROOM_CEIL_Y` 还在 13 时的数；
##     一期 Task 7 抬到 16.0 ⇒ 层高 `16.0 − (−3.70) = **19.7**`（`layout_test` 印的就是这个值）。）
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
## 天花板离地 19.7 = 3.94 m；终审 F6 改正，原写 16.7 / 3.34 m）。⇒ 要把半比例的模型摆成真实大小，就得多乘 2：
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
## 家具 / 椅子 / 地毯的材质（**一期 Task 8 Step 0**）。`.glb` 自带的纯平色由
## `material_override` 整片换掉（见 `_paint` 与 `FURN_ALBEDO`）。
var _furn_mat: StandardMaterial3D

## ---- 家具与椅子的材质（一期 Task 8 Step 0）----
##
## **病因（Task 7 出图实证）**：Kenney 那批 `.glb` 是**零贴图的纯平色**（Task 1 已证），
## 椅子 / 书桌 / 书架的 `baseColorFactor` 是 `0.896, 0.602, 0.393`（一层奶白偏橘）——
## 而屋子是**暗木地板 + 灰墙**、桌面那圈木纹还**带贴图**。⇒ 家具成了画面里
## **最亮、最没质感**的东西，读作"没上材质的占位块"，把画面挤满。
##
## **做法**：换成与 `_floor_mat` **同族**的暗木调（同一张 `wood_floor.jpg`），
## `roughness = 0.88` / `metallic = 0`（`_lit_mat` 里那两条，与地板 / 墙同一档）。
##
## **判据（可执行，`layout_test` 钉着）**：**家具的"被照亮的 albedo"必须比桌面暗** ——
## 同一把照度代理式算出来：`albedo 亮度 × 照度(家具形心) ≤ FURN_LIT_RATIO_MAX × albedo 亮度 × 照度(桌面最暗角)`。
## 取值 `0.34, 0.27, 0.21`（亮度 **0.281**，对照：换之前的奶白 `0.896/0.602/0.393` 亮度 **0.649**、
## 木纹外框 `0.62/0.55/0.46` 亮度 **0.558**）⇒ 实测比值 **0.644**；
## **把材质换回奶白那一档，这一条立刻红**（实测 1.49 — 见 task-8-report 的变红验证表）。
##
## **为什么不是更暗**（一度取过 `0.26/0.20/0.16`，实测比值 0.482）：出图比对过两档，
## 更暗那档在**远端**那张图里家具快与地板糊成一片、读不出是件家具。`0.34/0.27/0.21`
## 仍是**暗木调**（亮度只有木桌的一半）、仍稳稳压在家具"不许是最亮的东西"那条线之下，
## 但书桌 / 书架 / 椅背的**形**看得出来了 —— "像样"卡的是这条。
const FURN_ALBEDO := Color(0.34, 0.27, 0.21)
## 墙面（`_wall_mat`）。**一期 Task 8 Step 0：0.42/0.40/0.38 → 0.30/0.285/0.27**。
## 原值在"家具也是奶白"的年代不显眼；家具压暗之后它就是画面里最亮的一面平色板 ——
## 而**房间在暗环境里，墙一亮就假**（设计 §五 那条）。压到与家具同族的中性暗灰就够，
## **不再加贴图**：墙上有补光打出的明暗（见 `FILL_LIGHT_POS`），一块压暗的平色板读得出层高，
## 而加一份"极轻的贴图"在 22 × 19.7 的墙面上只会变成噪点。
##
## **一期 Task 9 Step 0：0.30/0.285/0.27 → 0.30/0.22/0.15（把绿蓝两维拉下去，暖起来）。**
##
## **病因（定位是量出来的）**：默认档那张图上、画面左上（约 `x 75–175 / y 30–165`）有一块
## **偏亮的灰白斑块**，与暗木的调性不符。逐节点隐藏 + 逐像素采样定死它是**墙**：
##   * `(50,100)` 只在**藏西墙**（`Walls/WallW`）时变黑 ⇒ 西墙；`(150,80)` / `(240,40)` 只在
##     **藏远墙**（`Walls/WallN`）时变黑 ⇒ 远墙。**不是家具**（藏家具那几次采样值一字未变）、
##     **不是天花板**（藏它也没变）。
##   * 亮是**吊灯**打的：关吊灯 ⇒ `(60,90)` 从 `#584a3a` 掉到 `#1b1919`；关补光只掉一档
##     （`#4e3f2d`）⇒ 以吊灯为主、补光为辅（吊灯在 `x ≈ −4.13 / y = 10`，离西墙只 6.9）。
##   * 病的**要害不是亮、是"灰"**：实测那块 `#584a3a` 的 R/B = **1.5**，而屋里的木色是
##     地板 `#5b2d15`（R/B 4.3）、书桌 `#392012`（R/B 3.2）—— 一块近中性的灰被打上暖光，
##     就成了唯一的"灰白"。**亮度只比地板高 1.4 倍**（0.30 对 0.21），差的是**色相**。
##
## **取值口径 = 只动绿蓝两维、把红那一维留着**（亮度锚点不动）：`0.30/0.285/0.27` → `0.30/0.22/0.15`。
## 实测（同一次真窗口渲染）那块斑 `#584a3a`（R/B 1.5、亮度 0.30）⇒ `#583920`（**R/B 3.1**、
## 亮度 0.24）—— 落进地板 / 书桌那一族暗木色里了；远墙 / 侧墙一起跟着暖（拉远端那张图的墙面
## `#6a5b4a` ⇒ `#6a482c`），**墙面上的明暗结构一点没少**（补光那半边的明暗仍在）。
## **不选"只压暗不动色相"**（试过 0.26/0.185/0.125）：斑块只是变暗、仍是灰的（R/B 2.9），
## 而墙整体暗下去之后拉远端那张图的墙面会塌掉 —— 这一条卡的是"像一间宿舍"，不是"像一张灰纸"。
## 验收那两张**摆拍图**同向（有 HUD 与暗角在场、绝对值更低）：同一采样点 `#3e3429`
##（R/B 1.5、亮度 0.21）⇒ `#3e2816`（**R/B 2.8**、亮度 0.17）。
const WALL_ALBEDO := Color(0.30, 0.22, 0.15)

func _make_materials() -> void:
	_floor_mat = _lit_mat(Color(0.30, 0.26, 0.22), "res://assets/textures/wood_floor.jpg")
	# 地板比"可见房间"多出**近半侧**那一截（见 `ROOM_NEAR_EXTRA`）⇒ 木纹的重复密度按
	# **地板自己的尺寸**算，否则地板一长、木条被拉长 1.28×（`_lit_mat` 里那份是按
	# `ROOM_W`/`ROOM_D` 写的，那里服务的是墙 / 天花板 —— 它们不带贴图，无所谓）。
	_floor_mat.uv1_scale = Vector3(ROOM_W / 3.0, (ROOM_D + ROOM_NEAR_EXTRA) / 3.0, 1.0)
	_wall_mat  = _lit_mat(WALL_ALBEDO, "")
	_ceil_mat  = _lit_mat(Color(0.34, 0.33, 0.33), "")
	# 家具 / 椅子：同一张木纹贴图，但**不按房间尺寸重复** —— `_lit_mat` 给的是
	# `ROOM_W/3 × ROOM_D/3`（每 3 世界单位一轮），那是给整面墙 / 整块地板定的；
	# 家具是 `_model_aabb` 撑到 8 个单位的小件，按同一个密度贴上去木纹会细成噪点。
	# 这里取 **1.0**（= 模型自己的 UV 铺一张贴图），与"一件家具一层木纹"的观感一致。
	_furn_mat = _lit_mat(FURN_ALBEDO, "res://assets/textures/wood_floor.jpg")
	_furn_mat.uv1_scale = Vector3.ONE

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

## **名牌嵌进椅背的深度**（一期 Task 9 Step 0 追加）。
##
## **病因（定位是量出来的，不是猜的）**：**侧向那两把椅子的名牌从相机看是侧视** —— 牌面法线
## 朝屋外，于是默认档 / 拉远端两张图上各留一道**游离的亮线**。真窗口渲染后逐像素扫（1280×800）：
##   * 左缘 `x 28–59 / y 287–356` 有 **94 个**亮度 > 0.45 的像素（最亮 **0.67**，棋子色黄）；
##   * 右缘 `x 1220–1251` 同样 **94 个**（最亮 0.55）；
##   * 把 `Seat1` / `Seat3` 的名牌**各藏一次** ⇒ **两道亮线各自消失**（94 → 0）——
##     就是这两块牌，**不是椅子、不是墙**（藏椅子反而更多亮像素：露出的墙面更亮）。
##   * **摆拍图**（`shots/t8_table_plain.png`，有 HUD 与暗角）同一条扫描：左缘 / 右缘各 **94** 个
##     （最亮 0.75 / 0.45）；改后（`shots/room_final_table_plain.png`）**两边都是 0**（最亮 0.21 / 0.20）。
##
## **做法：把牌从"挂在椅背外侧"改成"嵌在椅背外表面上"**（往里 0.06）。
## 椅子自己的背板于是把牌从**背面**挡住 —— 实测同一像素区的最亮值 **0.67 → 0.16**（= 椅背本身），
## 亮线消失；而**朝屋外那一面（贴着名字那一面）照旧露在最外**（标签比牌本身还外 0.01）
## ⇒ 二期"人坐上椅子"之后这块牌仍读得到。
##
## **为什么不压暗**（也试过）：压暗到 0.45 倍只是把亮线换成暗线（同一区域最亮仍有 0.44），
## 且要动"牌色 = 棋子色"那条语义（`layout_test` / `hud_test` 都钉着它）；嵌进椅背是**让椅子
## 自己挡掉**，牌子该亮的地方照旧亮。
const NAMEPLATE_SINK := 0.06

## 名牌挂点（世界坐标，与座位序同序）—— spec §十 要的二期接口。
## 与 `FURNITURE_ANCHORS` 同为 `static var`、由 `_build_chairs()` 落定时填（房间在原点、无变换，
## 局部即世界；`build()` 期不许读全局量，见 `_build_furniture` 那段）。
static var NAMEPLATE_ANCHORS: Array[Vector3] = []

# ---------------- 地毯（一期 Task 8 Step 0 追加） ----------------

## 地毯模型（Task 1 落地的 25 件之一，CC0）。
## **它不挂在 `Room/Furniture` 下**（见 `_build_rug`）：那张表是"靠墙摆的家具"，
## 而 `layout_test` 有三条断言按它逐件量 —— 家具必须在**左半侧**、必须在**木桌远边之外**、
## 三件两两不相交。一块**居中的地毯**三条全违（它就在桌子正下方、x 从 −4.8 到 +4.8）。
## ⇒ 单开一个 `Room/Rug` 节点，谁也不挡。
const RUG_MODEL := "rugRectangle.glb"

## 地毯比**木桌外沿**（连木纹，= `_table_half`）多出来的那一点（世界单位）。
## **上界由椅子订出来，不是审美**：椅子前沿离木桌外沿 `SEAT_INSET`(0.15) ⇒ 地毯再往外
## 就伸到椅子脚底下、"坐到地毯上"了（brief 明令不要）。取 **0.10**（= `SEAT_INSET` 的三分之二），
## 四周各留 0.05 的净空。
## 注意它**只能是一条窄边**：桌子底座（`table_3d.TableBase`）本身就填满了木桌那两维，
## 地毯在桌子底下那部分是看不见的，真正露出来的是这一圈 0.10 —— 这正是"把桌子锚在地上"要的。
const RUG_MARGIN := 0.10

## 地毯压暗系数（乘在模型自带的 `albedo_color` 上，见 `_dim_subtree`）。
## 模型自带的 `carpet` 是 `0.943, 0.367, 0.343`（一块饱和的砖红）—— 那是 Kenney 展示用的
## 配色，直接铺进来会是屋子里**最跳的一块色**，与"暗木 + 灰墙"的调性打架。
## 乘 0.45 ⇒ 面色 `0.42, 0.17, 0.15`、边色 `0.27, 0.13, 0.13`：仍看得出是块**暖色**的地毯
##（与木色同族、不是灰的），但比地板暗，不抢家具 / 桌面。
const RUG_DIM := 0.45

# ---------------- 补光（一期 Task 8 Step 3） ----------------

## 一盏**不投影**的弱补光：屋子（墙 / 家具）要有方向感与明暗，而**桌面照度基本不变**。
##
## **为什么是 `OmniLight3D` 而不是 `DirectionalLight3D`**：本项目的照度验收尺子是
## `layout_test._mat_sample_irradiance`，它的公式是**按 omni 衰减写的**（射程形状 +
## 距离衰减 + 桌面法线朝上的 N·L）。换平行光，那把尺子量不了它 —— "补光不碰桌面"
## 就只能靠肉眼，正是设计 §五「尺子只能用一把」要避免的事。
##
## **位置**（由 `ROOM_W` / `ROOM_D` 推导，不写死）：房间**近侧偏右**。
## 吊灯在远侧偏左（`table_3d.LAMP_LIGHT_POS` 的 x ≈ −4.13）、家具也全在左半侧
## ⇒ 补光从**对角**补过来，墙面上才有第二道方向（同侧补 = 只是把吊灯调亮一点）。
##
## **高度 0.5 是这里唯一的巧劲**（桌面在 y = 0）：桌面法线朝上，灯只比它高**一点点**
## ⇒ 桌面吃到的 `N·L = (y灯 − 0) / d` 小到几乎为零，而**竖直的墙**吃到的 N·L 由水平那一维
## 撑着、几乎不受高度影响 ⇒ 光主要落在墙上、桌面上只剩一点点。
## **实测（照度代理式）**：桌面采样点最大贡献 **0.0494**，只有吊灯直射那一份（0.79~1.12）的 **6%**
##（见 `layout_test.FILL_ON_TABLE_MAX` 的注释）。
## ⚠ **那把尺子量不到墙**：它的 N·L 是按**桌面法线 +Y** 写的，而墙是竖直面 —— 墙那一半只能
## 靠出图核对（`shots/t8b_dollyfar_table_plain.png` 对 `shots/t7b_dollyfar_table_plain.png`：
## 远墙从"顶上一条暗带"变成看得见的墙面、且左右有明暗）。
## **抬高它才是错的那一手**（1.5 → 桌面贡献立刻翻三倍）：补光一高就变成"第二盏吊灯"，
## 桌面被两盏灯一起打 —— 而桌面那亮度是用户签过字的（批次 13 ⑧）。
const FILL_LIGHT_POS := Vector3(ROOM_W * 0.36, 0.5, ROOM_D * 0.28)
## 补光的能量与射程。**衰减指数取 0**（与吊灯同一档）：补光要的是"整间屋子均匀抬一层"，
## 不是又一个光池。能量 0.45 = 逐次出图调到"墙看得出明暗、但不抢桌面"的那一档。
const FILL_ENERGY := 0.45
const FILL_RANGE := 30.0
## 补光的颜色：**偏冷的一档白**（吊灯是暖橙）。同色补光只是把吊灯调亮一点，
## 冷暖一对才有"两处光源"的方向感 —— 也就是"窗外透进来的一点天光"。
## 只偏一点点：偏狠了会与桌面那层暖色叠成灰（设计 §六 对"窗是冷色"那条警告）。
const FILL_COLOR := Color(0.80, 0.84, 0.92)

func _build_shell() -> void:
	_make_materials()
	# 地板在 **`FLOOR_Y`**（真实桌高）。
	# 历史（别按它改回去）：Task 3 曾把地板放在 −0.02 —— 那是"地板就在桌面那一层"的年代，
	# 压 0.02 只为不被木纹外框整片盖掉（桌心那一层 y = 0 同时是桌垫所在，而木桌外框在
	# y = -0.012 且比桌垫大一圈：地板放 y = 0 会先被相机打到、外框那条亮木纹带整条不见，
	# 而取景判据正是按木桌四角量的；另外与桌垫共面还会闪）。
	# 地板降到 `FLOOR_Y` 之后这两条都不再成立（外框在 3.7 之上，离地板远得很），
	# 见 `FLOOR_Y` 那段。
	# 地板 / 天花板 / 东西两面墙、连近墙一起：**都按"远半侧 + 近半侧"那两段摆**（见 `ROOM_NEAR_EXTRA`）。
	# 远墙（WallN）**不动** —— 它与家具、椅子、取景是同一份基准。
	var span_z: float = ROOM_D + ROOM_NEAR_EXTRA           # 地板的总进深（远墙 → 近墙）
	var mid_z: float = ROOM_NEAR_EXTRA * 0.5               # 地板中心（远半侧对称 ⇒ 中心朝近端挪半段）
	_plane("Floor",   Vector3(0, FLOOR_Y, mid_z),     Vector2(ROOM_W, span_z), Vector3.ZERO, _floor_mat)
	_plane("Ceiling", Vector3(0, ROOM_CEIL_Y, mid_z), Vector2(ROOM_W, span_z), Vector3.ZERO, _ceil_mat)
	# 四面墙：竖直的 PlaneMesh（默认躺在 XZ 平面，绕 X 转 90° 立起来）
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	# **墙高与墙心都跟着地板走**：`h = 天花板 − 地板`、中心取两者中点 ⇒ 墙脚正好落在地板上。
	# 少了这一条（还按 `ROOM_CEIL_Y` 量），四面墙一圈的墙脚会悬在地板上方 3.7 个单位。
	var h := ROOM_CEIL_Y - FLOOR_Y
	var wy := (ROOM_CEIL_Y + FLOOR_Y) * 0.5
	_plane("WallN", Vector3(0, wy, -ROOM_D * 0.5), Vector2(ROOM_W, h), Vector3(90, 0, 0),    _wall_mat, walls)
	_plane("WallS", Vector3(0, wy,  ROOM_D * 0.5 + ROOM_NEAR_EXTRA),
		Vector2(ROOM_W, h), Vector3(-90, 0, 0), _wall_mat, walls)
	_plane("WallW", Vector3(-ROOM_W * 0.5, wy, mid_z), Vector2(span_z, h), Vector3(90, 90, 0),  _wall_mat, walls)
	_plane("WallE", Vector3( ROOM_W * 0.5, wy, mid_z), Vector2(span_z, h), Vector3(90, -90, 0), _wall_mat, walls)
	_build_furniture()
	_build_chairs()
	_build_chars()
	_build_rug()
	_build_fill_light()

## 桌下那块地毯（一期 Task 8 Step 0）。**"把桌子锚在地上"最省的一手，且不挡棋盘**
##（它整个躺在 `FLOOR_Y` 上、比桌面低 3.7，从取景轨道上任何位置都看不进桌垫）。
##
## 摆位一律由 `_table_half`（连木纹外框的半个桌面）与 `RUG_MARGIN` 推导，**不写死尺寸**：
## 桌子一改（Task 7 那类改动），地毯跟着走。
## **挂在自己的 `Room/Rug` 下**，理由见 `RUG_MODEL` 那段（`Furniture` 那三条断言会红）。
func _build_rug() -> void:
	var packed: PackedScene = load("res://assets/models/%s" % RUG_MODEL)
	if packed == null:
		push_warning("房间缺地毯模型：%s（跳过）" % RUG_MODEL)
		return
	var root := Node3D.new()
	root.name = "Rug"
	add_child(root)
	var mi := packed.instantiate() as Node3D
	root.add_child(mi)
	# 量一次模型的 AABB：① 它的原点在**角上**（实测 `pos (0, 0, -0.92)`）不是中心，
	# 不居中摆就会整块偏到桌子外面去；② 尺寸要**按目标大小反算缩放**，不能照抄
	# `FURNITURE_SCALE` —— 这块模型 ×10 之后是 `15.7 × 9.2`，**比整间屋子还大**。
	var ab := _model_aabb(packed)
	var c := ab.get_center()
	var want := (_table_half + Vector2(RUG_MARGIN, RUG_MARGIN)) * 2.0
	# y 仍按 `FURNITURE_SCALE`（厚度 0.10 —— 一块薄地毯，不是一张纸片）
	var sy: float = FURNITURE_SCALE
	var sx: float = want.x / ab.size.x
	var sz: float = want.y / ab.size.z
	mi.scale = Vector3(sx, sy, sz)
	# 底面留在 `FLOOR_Y`（模型的基点本来就在脚底，实测 AABB 的 min.y = 0）
	mi.position = Vector3(-c.x * sx, FLOOR_Y, -c.z * sz)
	_no_shadow(mi)
	_dim_subtree(mi, RUG_DIM)

## 那盏不投影的补光（一期 Task 8 Step 3，见 `FILL_LIGHT_POS`）。
## **`shadow_enabled = false` 是硬要求**：全场只许有一处投影源（吊灯），
## 第二张阴影图 = 性能与氛围两头不讨好（`layout_test` 那条"只有一处投影源"钉着它）。
func _build_fill_light() -> void:
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = FILL_LIGHT_POS
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.omni_range = FILL_RANGE
	fill.omni_attenuation = 0.0
	fill.shadow_enabled = false
	add_child(fill)

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
		# **换掉 `.glb` 自带的纯平奶白**（一期 Task 8 Step 0，见 `FURN_ALBEDO`）。
		_paint(mi, _furn_mat)

## 一棵子树里的几何实例**逐个关投影**（房间的纪律：全场唯一投影源是那盏吊灯）。
## 为什么要走一遍而不是继承：`instantiate()` 出来的节点不继承父级的 shadow 设置。
static func _no_shadow(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 一棵子树里的几何实例**逐个换材质**（一期 Task 8 Step 0）。
## 与 `_no_shadow` 同一条理由：`material_override` **不过继** —— 挂在父 `Node3D` 上不会往
## 子节点传，`.glb` 的几何挂在各自的 `MeshInstance3D` 上（还常常是嵌套的）⇒ 必须逐个走一遍。
## 这不是"改不动原材质"的权宜：Kenney 的模型本来就是**用 `material_override` 换色**的用法
##（它自带的那份纯平色只是默认值）。
static func _paint(root: Node, mat: Material) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).material_override = mat

## 一棵子树里的几何实例**按系数压暗自己的材质**（地毯用，见 `RUG_DIM`）。
##
## 为什么不照家具那样一刀 `_paint()` 成单色：**地毯有两份材质**（`carpet` 面色 + `carpetDarker`
## 边色，模型自带），一刀切成单色就把"面 / 边"的分工抹平了 —— 而那条深色边正是让它读作
## "一块地毯"而不是"地上一个色块"的东西。
##
## ⚠ **必须用 `set_surface_override_material(面号, …)` 而不是 `material_override`**：
## `material_override` 是**一个材质盖住所有面**（实测：地毯两个面被盖成同一个色），
## 按面覆盖才保得住模型自带的分工。
## 复制一份再改：`instantiate()` 出来的材质与 `PackedScene` **共用同一份资源**，
## 直接改会污染缓存里的那份（同一场景第二次实例化就带着上一次的改动）。
static func _dim_subtree(root: Node, factor: float) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi is not MeshInstance3D:
			continue
		var mesh := (gi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := gi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color(m.albedo_color.r * factor, m.albedo_color.g * factor,
				m.albedo_color.b * factor, m.albedo_color.a)
			gi.set_surface_override_material(s, m)

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
		# 椅子与家具**同一份材质**（一期 Task 8 Step 0）：屋里出现两种木色会读成"随手凑的"。
		_paint(mi, _furn_mat)
		_make_nameplate(seat, ab, half_z)

## 椅背名牌：一块薄牌 + 一行名字，挂在**椅背**上（座位框的 −z 侧 —— 模型自己的背在 −z）。
## 薄牌的颜色**先留白**，等 `set_seats()` 喂进各家颜色再上色（没有状态时整块不露）。
func _make_nameplate(seat: Node3D, ab: AABB, half_z: float) -> void:
	var root := Node3D.new()
	root.name = "Nameplate"
	seat.add_child(root)
	# 挂在椅背顶上：比椅子矮 0.30（不顶到椅子最高那一线），**嵌在背板外表面上**（见 `NAMEPLATE_SINK`）。
	# 原式把牌**整个**挑在椅背之外（牌心离椅背外表面 0.05）；减去 0.06 之后牌心落到外表面
	# **之内** 0.01 ⇒ 只剩外沿那 0.02 露在椅子外面，背面被椅子自己的背板挡住。
	root.position = Vector3(0.0, ab.size.y * FURNITURE_SCALE - 0.30,
		-half_z - NAMEPLATE_SIZE.z * 0.5 - 0.02 + NAMEPLATE_SINK)
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

# ---------------- 角色层（二期 Task 1） ----------------

## 坐在椅子上的角色（`Room/Chars`，`scripts/chars.gd`）。**二期只读表现层，房间只负责建它 +
## 把四把椅子的锚点交出去**；人摆得对不对全归 `GameChars`（`chars_test` 管）。
## 生命周期同 `_furn_mat` 那一类成员：`_build_chars()` 落定。
var _chars: GameChars

## 建角色层（二期 Task 1）。**只建节点，不摆人** —— 摆人要读座位锚点的 `global_transform`，
## 那要求整棵子树**已经入树**；而 `build()` 是 `table_3d._init()` 里调的，那时还没进树
## （同一期 `_build_furniture` 那段）。⇒ 角色在 `GameChars._ready()` 里自己摆。
##
## 与 `ROOM_ENABLED` 同理：`CHARS_ENABLED = false` 时 `GameChars.build()` 返回 null
## ⇒ **这里不能当成必然拿到节点用**（本期的保命开关，退回到"只有椅子"的样子）。
func _build_chars() -> void:
	var seats := get_node_or_null("Seats") as Node3D
	if seats == null:
		return
	_chars = GameChars.build(self, seats)

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
