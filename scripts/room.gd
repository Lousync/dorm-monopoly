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

## 椅子的**独立**材质（本轮改版新增，见 `CHAIR_ALBEDO`）。改版前它与 `_furn_mat` 是同一份
## （一期 Task 8 Step 0 的理由是"屋里出现两种木色会读成随手凑的"）—— 那条理由在**家具都是同一种
## 木料**时成立，而用户要的恰恰是"看得出哪件是哪件" ⇒ 拆开。
var _chair_mat: StandardMaterial3D

## 吊灯灯罩那一份材质（三期复核后加）：`PENDANT_SHADE_ALBEDO` + 自发光。理由见
## `_build_pendant` 的"材质"那一段。
var _pendant_shade_mat: StandardMaterial3D

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
## **本轮改版（v0.8.0 判图后，用户 2026-10-06）**：`0.30/0.22/0.15` → **`0.58/0.55/0.50`**。
##
## 上面那两轮（一期 Task 8 / Task 9）调的都还是"**暖色的墙**"——Task 9 那次是把一块**中性灰**
## 往暖里拽（`0.30/0.285/0.27` → `0.30/0.22/0.15`，把绿蓝两维压下去），治的是"灰白斑块"。
## 而用户 2026-10-06 判图时点的是另一件事：「地板、椅子、墙面、家具**颜色太接近**」——
## 四件东西全在暗褐色族里，其中**墙是最不该是木色的那一件**（真实房间里墙是刷漆的，
## 地板 / 家具才是木头）。
##
## **取值口径 = 让墙成为四件里唯一"非木"的面**：往**浅 + 低饱和 + 微暖**走
##（`0.58/0.55/0.50`，比木桌的 `0.62/0.55/0.46` 更灰更亮一点 —— 刷漆墙对木桌）。
## 实测出图：默认档 / 拉远端两档下，墙与木地板 / 木家具 / 灰蓝椅子**四件都分得开**，
## 而**桌面棋盘仍是画面里最亮的对象**（`FURN_LIT_RATIO_MAX` 那条管的是家具，本项不参与；
## 灯照在墙上那一片最亮 0.55 上下，与桌垫那一带的读数同档 —— 主玩法区没有被抢）。
##
## **为什么这一次不违反 Task 9 那条"墙一亮就假"**：那条说的是"**一块中性灰**被暖灯打成
## 死灰白斑"（当时实测那块斑 R/B = 1.5，与木色的 3~4 差得远 ⇒ 一眼出戏）。现在这块墙
## 是**暖灰**（R/B ≈ 1.16 的底、被暖灯照完仍偏暖），而它旁边就挨着更饱和的木地板 ——
## 两条放在一起读作"刷漆墙 + 木地板"，正是要的那件事。判据仍是**出图**，四档两两比对过。
const WALL_ALBEDO := Color(0.58, 0.55, 0.50)

## ---- 本轮改版（v0.8.0 判图后，用户 2026-10-06）：**四件东西各自一个色** ----
##
## **病因（用户原话）**：「地板、椅子、墙面、家具颜色太接近了，缺少真实感」。量一下确实如此：
## 改版前四件全落在一个暗褐色族里 —— 地板 `0.30/0.26/0.22`、墙 `0.30/0.22/0.15`、
## 天花板 `0.34/0.33/0.33`、家具与椅子 `0.34/0.27/0.21`（后两件还共用**同一份材质、同一张木纹**）。
## ⇒ 屋里只能靠**明暗**读体积，读不出一件东西是墙还是柜子，更读不出"这是个什么房间"。
##
## **判据（可执行，`layout_test` 钉着）**：`FURN_LIT_RATIO_MAX`（**家具与椅子**不许是画面里最亮
## 的东西 —— 见下面那条断言）与「房间在暗环境里」的调性。**墙一亮就假**那条（一期 Task 9）说的
## 是**中性灰打上暖光**会变成死灰白斑，不是"墙不许换色" ⇒ 这次让墙往**冷**走
##（刷漆墙的色相），亮度基本不动。
##
## **本文件里这些取值是"变体 A（暗调性 + 色相拉开）"**：亮度大体维持在改版前那一档，
## 靠**色相 + 明度**把四件拉开 —— 地板暖木、墙冷灰、家具深胡桃、椅子冷灰蓝（金属/塑料椅）。
## **变体 B（整体提亮）** 是另一套数（更亮的墙 / 更大的明度差），只用于出图对比，不在代码里留。
const FLOOR_ALBEDO := Color(0.26, 0.18, 0.11)
const CEIL_ALBEDO := Color(0.20, 0.21, 0.23)

# ---------------- 程序化表面贴图（v0.8.0 三期「像一间宿舍」） ----------------
#
# **病**：地板 / 墙各是一块**平色板**（地板虽有 `wood_floor.jpg`，但它是一张
# "远看像噪点、近看没有结构"的摄影贴图 —— 木条之间的**缝**在画面上根本读不出来）。
# 参考图（Liar's Bar）里屋子读得出"什么材料"，靠的就是**板缝 / 砖缝**这类**结构线**。
#
# **做法**：用 `Image` **程序化生成**两张"细节图"（detail map）——不是新素材文件（硬约束 6：
# 不许引入外部素材），而是**代码画出来的**，与项目"能用程序化手段画出来的就别加素材"那条一致
#（转盘 / 房子贴图 / 卡面都是这么做的）。
#
# **两张图的共同约定**：它们是**细节图**，颜色**平均接近 1.0**、只把结构线压暗
# ⇒ 与 `albedo_color`（`FLOOR_ALBEDO` / `WALL_ALBEDO`）**相乘**之后，
# 屋子的整体明度基本不变（实测约 −8%），而**四件东西的调性一个都不动** —— 这正是要的。
# 若把颜色整个烘进贴图（`albedo_color = WHITE`），那两个"色相锚点"常量就作废了，
# 下一次调色的人得去改贴图代码 —— 不划算。
##
## 一张图 = **4 × 4 世界单位**（1 世界单位 = 0.2 m ⇒ 一张图 80 cm 见方）。
## 世界侧的重复密度由 `uv1_scale` 定（地板 / 墙各自算，见 `_make_materials`）。
const SURFACE_TILE := 4.0
## 贴图边长（px）。256 落在"板缝看得清"与"生成够快"之间（两张 65536 像素的循环）。
const SURFACE_PX := 256
## 椅子：**独立**于家具的一份材质（改版前共用 `_furn_mat`）。冷灰蓝 = 一把刷漆 / 金属椅，
## 与暖木的书桌、书架摆在一起才分得清"哪件是坐的"。不带木纹贴图，粗糙度也低一档
##（`CHAIR_ROUGH` / `CHAIR_METALLIC`）—— "另一种材料"这件事得**在材质参数上也成立**，
## 只改颜色的话它读起来还是同一块木头。
const CHAIR_ALBEDO := Color(0.19, 0.21, 0.25)
const CHAIR_ROUGH := 0.55
const CHAIR_METALLIC := 0.15

func _make_materials() -> void:
	# 地板：**程序化木条地**（v0.8.0 三期）。原先用的是 `wood_floor.jpg` —— 那张图**没有板缝**，
	# 从取景轨道上看就是一块平色板（用户原话「地板…太粗糙」）。换成程序化的木条之后，
	# "一块块木板"这件事**在画面上读得出来**。
	_floor_mat = _lit_mat(FLOOR_ALBEDO, "")
	_floor_mat.albedo_texture = _plank_texture()
	_floor_mat.texture_repeat = true
	# 地板比"可见房间"多出**近半侧**那一截（见 `ROOM_NEAR_EXTRA`）⇒ 木纹的重复密度按
	# **地板自己的尺寸**算，否则地板一长、木条被拉长 1.28×（`_lit_mat` 里那份是按
	# `ROOM_W`/`ROOM_D` 写的，那里服务的是墙 / 天花板 —— 它们不带贴图，无所谓）。
	_floor_mat.uv1_scale = Vector3(ROOM_W / SURFACE_TILE, (ROOM_D + ROOM_NEAR_EXTRA) / SURFACE_TILE, 1.0)
	# 墙：**程序化砖墙**（v0.8.0 三期）。取色仍是 `WALL_ALBEDO`（上一轮"四件东西各自一个色"
	# 那笔定下来的浅暖灰 = 刷了漆的墙），砖缝只在上面压出**结构**，不改色相。
	_wall_mat  = _lit_mat(WALL_ALBEDO, "")
	_wall_mat.albedo_texture = _brick_texture()
	_wall_mat.texture_repeat = true
	# 墙高 = `ROOM_CEIL_Y − FLOOR_Y`（19.7），**不是** `ROOM_D` —— `_lit_mat` 给的那一份是按
	# 房间平面尺寸写的（那是给地板定的口径），照它贴砖缝会被**竖直拉长 3.3×**。
	var wall_h: float = ROOM_CEIL_Y - FLOOR_Y
	_wall_mat.uv1_scale = Vector3(ROOM_W / SURFACE_TILE, wall_h / SURFACE_TILE, 1.0)
	_ceil_mat  = _lit_mat(CEIL_ALBEDO, "")
	# 家具 / 椅子：同一张木纹贴图，但**不按房间尺寸重复** —— `_lit_mat` 给的是
	# `ROOM_W/3 × ROOM_D/3`（每 3 世界单位一轮），那是给整面墙 / 整块地板定的；
	# 家具是 `_model_aabb` 撑到 8 个单位的小件，按同一个密度贴上去木纹会细成噪点。
	# 这里取 **1.0**（= 模型自己的 UV 铺一张贴图），与"一件家具一层木纹"的观感一致。
	_furn_mat = _lit_mat(FURN_ALBEDO, "res://assets/textures/wood_floor.jpg")
	_furn_mat.uv1_scale = Vector3.ONE
	# 椅子（本版新增的**独立**材质，见 `CHAIR_ALBEDO`）：**不带木纹贴图**（与"金属 / 塑料椅"的
	# 观感一致），粗糙度也比木家具低一档（`CHAIR_ROUGH`）—— 一期那把椅子是共用 `_furn_mat` 的，
	# 用户 2026-10-06 判图后指出"地板 / 椅子 / 墙面 / 家具颜色太接近"，于是把它拆出来。
	_chair_mat = _lit_mat(CHAIR_ALBEDO, "")
	_chair_mat.roughness = CHAIR_ROUGH
	_chair_mat.metallic = CHAIR_METALLIC
	# 吊灯灯罩（三期复核后改，见 `PENDANT_SHADE_ALBEDO` / `_build_pendant`）：**同族的暗暖色**
	# ＋一点自发光。它是屋里**唯一一份带 emission 的材质** —— 那盏 `OmniLight3D` 照不到灯罩自己
	#（N·L ≈ 0），不给自发光它就是一坨深灰。
	_pendant_shade_mat = _lit_mat(PENDANT_SHADE_ALBEDO, "")
	_pendant_shade_mat.emission_enabled = true
	_pendant_shade_mat.emission = PENDANT_GLOW
	_pendant_shade_mat.emission_energy_multiplier = PENDANT_GLOW_ENERGY

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

## 木条地板（程序化，见 `SURFACE_TILE` / `SURFACE_PX` 那段）。
##
## 画的是**一块 4 × 4 世界单位的木地板**（= 80 cm 见方）：
##   * **板宽 1 个世界单位**（256 px / 4 条 = 64 px）⇒ 20 cm 一块板，与真实的窄条地板同档；
##   * 板与板之间一道**近黑的缝**（3 px）—— 这就是"读得出是地板"的那条结构线；
##   * 每条板的**端缝**（横缝）各自错开（`joint[]`），错缝才是"铺出来"的样子，
##     不错缝会读成**瓷砖**；
##   * 板面加**沿板长方向的细木纹**（正弦叠加，±8%）与**逐板色差**（±10%）。
##
## 返回值是**细节图**：均值≈0.92、最暗是缝（0.22）—— 与 `FLOOR_ALBEDO` 相乘用，
## 不自己带颜色（见那两张图的共同约定）。`Image.FORMAT_RGB8`（不需要 alpha）。
##
## `seed` 固定：同一份地板每次跑出来**逐像素一样** —— 摆拍与"改前 / 改后"逐格比对才有意义
##（随机的话两张图永远不一样，比对就无从谈起）。
func _plank_texture() -> ImageTexture:
	var n := SURFACE_PX
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED_0001
	var planks := 4                       # 4 条板铺满一张图
	var pw: int = n / planks               # 每条板的像素宽（64）
	# 逐板的底色（0.86~1.0）与端缝位置（0..n，逐板错开）
	var tone: PackedFloat32Array = PackedFloat32Array()
	var joint: PackedInt32Array = PackedInt32Array()
	for i in planks:
		tone.append(rng.randf_range(0.86, 1.0))
		joint.append(rng.randi_range(0, n - 1))
	for x in n:
		var pi: int = x / pw
		# "是不是板缝"：每条板的边界上那 3 px
		var d_edge: int = x % pw
		var is_seam: bool = d_edge < 2 or d_edge >= pw - 1
		for y in n:
			# 端缝：每条板在 `joint[pi]` 上下各 2 px 压暗（绕一圈：两头都算，接得上）
			var is_joint: bool = false
			var dy: int = absi(y - joint[pi])
			if dy < 2 or n - dy < 2:
				is_joint = true
			var v: float = tone[pi]
			if is_seam:
				v *= 0.28
			elif is_joint:
				v *= 0.46
			else:
				# 木纹：沿板长（y）方向拉长的细纹 —— 横跨 x 的频率高、沿 y 的频率低
				var g: float = sin(float(x) * 2.7 + sin(float(y) * 0.11 + float(pi)) * 2.4)
				v *= 1.0 - 0.08 * (g * 0.5 + 0.5)
				# 一丝逐像素噪声：纯正弦会读成"塑料"
				v *= 1.0 - 0.03 * absf(sin(float(x * 7 + y * 13) * 0.7))
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

## 砖墙（程序化，见 `SURFACE_TILE` / `SURFACE_PX` 那段）。
##
## 画的是**一块 4 × 4 世界单位的砖墙**（= 80 cm 见方）：砖 **1 × 0.5 世界单位**
##（64 × 32 px = 20 × 10 cm，与实心砖的"两皮一顺"比例同档），**错缝砌**（每隔一皮错半砖）。
##   * 砖面亮度逐块抖动（0.80~1.0，`tone[]`）—— 一块块砖才读得出来；
##   * 灰缝比砖**暗**（0.45）：砖墙在**暗屋子里**就是靠这几条缝读出来的，
##     缝一亮（砂浆本色比砖亮）就变成"贴了砖纹的纸"；
##   * 砖面再加一点噪声，免得整块砖是死平的。
##
## 同样是**细节图**（与 `WALL_ALBEDO` 相乘）。上界锁在 1.0 之内，所以墙会**略暗一点**
##（实测墙均值 ≈ 0.90 ⇒ 有效 albedo 0.58 → 0.52）—— 这一点是**有意的**：
## 砖缝吃掉的亮度正好把上一轮"墙比别的都亮"那口气收回来，而墙仍是四件里最浅的那一件。
func _brick_texture() -> ImageTexture:
	var n := SURFACE_PX
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED_0002
	var bw := 64                          # 砖宽（px）= 1 世界单位
	var bh := 32                          # 砖高（px）= 0.5 世界单位
	var rows: int = n / bh
	var cols: int = n / bw
	# 逐块砖的亮度（按 [皮][列] 存，错缝时按同一块砖查得到同一个值）
	var tone: Array = []
	for r in rows:
		var line: PackedFloat32Array = PackedFloat32Array()
		for c in cols:
			line.append(rng.randf_range(0.80, 1.0))
		tone.append(line)
	for y in n:
		var r: int = y / bh
		var in_row: int = y % bh
		# 灰缝：每一皮的上下各 2 px
		var is_bed: bool = in_row < 2 or in_row >= bh - 2
		# 错缝：奇数皮整体右移半砖
		var shift: int = (bw / 2) if (r % 2 == 1) else 0
		for x in n:
			var xs: int = (x - shift + n) % n
			var in_col: int = xs % bw
			var is_head: bool = in_col < 2 or in_col >= bw - 2
			var v := 0.45                                  # 灰缝色（比砖暗）
			if not is_bed and not is_head:
				v = tone[r][xs / bw]
				v *= 1.0 - 0.04 * absf(sin(float(x * 11 + y * 5) * 0.5))
			elif is_bed and is_head:
				v = 0.40                                   # 缝的交点再压一点，砖格读得更清
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

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
	# ---- 远墙一排（rot 0 = 正面朝 +z / 朝屋里；`az` 一律 = 远墙 + 进深 + 0.15）----
	# 敞口书架：最靠左的一件。它左边那条 `x ∈ [西墙, −6.93]` 归西墙的书桌（那张桌沿 z 轴铺
	# 满整个远半侧），所以这里从 −6.5 起 ⇒ 与书桌净空 0.43。
	["bookcaseOpen.glb",       Vector3(-ROOM_W * 0.5 + 4.5, FLOOR_Y, -ROOM_D * 0.5 + 2.65), 0.0],
	# 双门大书柜：远墙正中（桌子正后方）。8.0 宽 ⇒ 从 −2.0 到 +6.0，与左边那件净空 0.5。
	# 它是**唯一一件会从桌子远边之上露出来的大家伙**（高 7.9），远墙那一条带子全靠它撑。
	["bookcaseClosedWide.glb", Vector3(-ROOM_W * 0.5 + 9.0, FLOOR_Y, -ROOM_D * 0.5 + 2.65), 0.0],
	# 矮柜（床边抽屉柜）：远墙右段，与书柜净空 0.3。矮（2.63）⇒ 补"远墙一排全是高柜"的单调。
	["cabinetBedDrawer.glb",   Vector3(-ROOM_W * 0.5 + 17.4, FLOOR_Y, -ROOM_D * 0.5 + 2.20), 0.0],

	# ---- 西墙：那张长书桌（rot 90 = 正面朝 +x / 朝屋里）----
	# 7.34 长的书桌**只能沿侧墙摆**：正向摆在远墙上时，它 3.92 的进深 + 一把椅子的 3.14
	# 已经吃掉 7.1，而远半侧的可用进深只有 5.37 ⇒ 桌椅摆不开（见报告"放不下"那节）。
	# 转 90° 后它沿 z 从 −9 铺到 −1.66（离远墙 0.15），x 只占 3.92 ⇒ 与游戏桌净空 2.08。
	["desk.glb",               Vector3(-ROOM_W * 0.5 + 3.95, FLOOR_Y, -ROOM_D * 0.5 + 7.39), 90.0],

	# ---- 西侧带（书桌以南）：一路摆到近角，人从桌子左后侧绕过去 ----
	# 垃圾桶：紧挨游戏桌左后的椅子（slot3，x ∈ [−7, −5]）外沿，净空 0.16。
	["trashcan.glb",           Vector3(-ROOM_W * 0.5 + 2.8, FLOOR_Y, -ROOM_D * 0.5 + 8.80), 0.0],
	# 摊在地上的笔记本电脑（地板上，不是桌上 —— 见"不许叠放"那节）。
	["laptop.glb",             Vector3(-ROOM_W * 0.5 + 2.0, FLOOR_Y, -ROOM_D * 0.5 + 12.80), 0.0],
	# 台灯（圆）落在地上当"备用灯"：贴着西墙，与垃圾桶净空 0.10。
	["lampRoundTable.glb",     Vector3(-ROOM_W * 0.5 + 0.3, FLOOR_Y, -ROOM_D * 0.5 + 10.60), 0.0],
	# 台灯（方）+ 盆栽：西近角一组，给左下方一点东西可看。
	["lampSquareTable.glb",    Vector3(-ROOM_W * 0.5 + 0.6, FLOOR_Y, -ROOM_D * 0.5 + 13.20), 0.0],
	["plantSmall1.glb",        Vector3(-ROOM_W * 0.5 + 1.0, FLOOR_Y, -ROOM_D * 0.5 + 14.00), 0.0],

	# ---- 东墙：矮边柜（rot 270 = 正面朝 −x）+ 落地灯 ----
	# 边柜 5.34 长，沿 z 铺在远侧段（−4.0 ~ +1.34），与桌右椅子（z ∈ [−1, 1]，x ≤ 7）净空 1.7。
	["sideTable.glb",          Vector3(ROOM_W * 0.5 - 2.2, FLOOR_Y, -ROOM_D * 0.5 + 5.10), 270.0],
	# 落地灯：东北角，与矮柜净空 0.28。它是画面右上角唯一的竖向元素（高 8.6）。
	["lampRoundFloor.glb",     Vector3(ROOM_W * 0.5 - 1.6, FLOOR_Y, -ROOM_D * 0.5 + 1.58), 0.0],
	# 盆栽：东侧中部，给"矮柜—箱子"之间补一件。
	["plantSmall1.glb",        Vector3(ROOM_W * 0.5 - 3.8, FLOOR_Y, -ROOM_D * 0.5 + 7.00), 0.0],

	# ---- 近半侧（只在 `Ctrl`+滚轮拉远端那一档入画）：箱子 / 备用椅子 ----
	# 敞口收纳箱：东侧中部，与边柜净空 0.43。
	["cardboardBoxOpen.glb",   Vector3(ROOM_W * 0.5 - 3.8, FLOOR_Y, -ROOM_D * 0.5 + 12.90), 0.0],
	# 圆背椅（rot 270 = 朝 −x）：桌右椅子外侧的一把备用椅。
	["chairRounded.glb",       Vector3(-ROOM_W * 0.5 + 15.0, FLOOR_Y, -ROOM_D * 0.5 + 13.00), 270.0],
	# 软垫椅（rot 180 = 朝 −z / 面朝桌子）：桌左椅子外侧的备用椅。
	["chairModernCushion.glb", Vector3(-ROOM_W * 0.5 + 7.0, FLOOR_Y, -ROOM_D * 0.5 + 13.20), 180.0],

	# ---- 中段散件（远半侧的空隙：桌子背后那一条）----
	# 书堆：大书柜正前方地上（与柜净空 0.21），补远墙一排的"生活感"。
	["books.glb",              Vector3(-ROOM_W * 0.5 + 14.0, FLOOR_Y, -ROOM_D * 0.5 + 3.80), 0.0],
	# 封口纸箱：近左角（桌左椅子外侧），与近侧那把椅子净空 0.27。
	["cardboardBoxClosed.glb", Vector3(-ROOM_W * 0.5 + 7.6, FLOOR_Y, -ROOM_D * 0.5 + 15.20), 0.0],
]

## 摆出来的家具落点（世界坐标，与 `FURNITURE` 逐条同序）。
## **由 `_build_furniture()` 落定时填**（不把坐标抄第二遍 —— 单一来源仍是上面那张表）。
## 计划 Interfaces 承诺过这个名字；今天没有下游消费，它记录的是"家具摆在哪"。
static var FURNITURE_ANCHORS: Array[Vector3] = []

# ---------------- 四把椅子 + 椅背名牌（一期 Task 5） ----------------
#
# **这是二期的接口**（spec §十）：每把椅子定死「位置 + 朝向」、并挂一个名牌挂点，
# 二期"把人放上去"只读这一处 —— `seat_anchor(slot)`（名牌挂点 `NAMEPLATE_ANCHORS` 已删）。

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

## **椅背名牌整段已删（v0.8.0 判图后，用户 2026-10-06）** —— 用户原话：「去掉椅子上的铭牌」。
##
## **为什么删得掉**：它的职责（认出这把椅子上坐的是谁）**整段搬到了 `chars.gd` 的头顶名牌**
## （`Tags/Tag{i}`：棋子色 + 昵称 + billboard + 行动者金边，见 `scripts/chars.gd`）。
## 两块牌子同时存在只会互相干扰 —— 而且椅背那块**本来就看不见**：它挂在椅背**朝外**那一面
##（一期 Task 9 把它嵌进椅背外表面，为的是消掉侧向那两把椅子在画面边缘留下的亮线），
## 也就是说除了"对面那一家"之外，其余两家的牌一律背对相机 ⇒ 二期"靠角色认人"读不出来，
## 有一半原因就在这儿。
##
## **连带删掉的东西**：`NAMEPLATE_SIZE` / `NAMEPLATE_FONT_PS` / `NAMEPLATE_SINK`、
## `NAMEPLATE_ANCHORS`（原 spec §十 的"二期接口"，实际从未被消费 —— 二期取座位坐标一直走
## `seat_anchor(slot)`）、`_make_nameplate()`、`_refresh_nameplates()`。
## `set_seats()` 仍在（它维护 `_seat_peers` / `seat_peers()`，那是**角色层与 HUD 都要的那份顺序**）。

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
	_build_trim()
	_build_pendant()
	_build_furniture()
	_build_chairs()
	_build_chars()
	_build_rug()
	_build_fill_light()

# ---------------- 踢脚线 / 顶角线（v0.8.0 三期） ----------------
#
# **为什么要有**：一块平墙 + 一块平地直接相交，交线在画面上**读不出来**（两片暗色糊在一起），
# 屋子就"没有角"。参考图里墙脚那一圈深色线条是**屋子立得住**的关键之一 —— 它同时给出
# "墙从哪儿开始"与"地板到哪儿为止"。
#
# **做法**：四面墙各一条 `BoxMesh` 压在墙脚，**厚度 0.30、高 1.1 世界单位**（= 6 cm × 22 cm 的
# 踢脚板，真实尺寸）。`WALL_*` 那一套照旧；踢脚线用**比墙暗得多的木色**
#（`TRIM_ALBEDO`）—— 与地板同族、但比地板更暗，于是"墙 / 踢脚 / 地板"三段分得开。
#
# **顶角线**同尺寸、贴着天花板（`ROOM_CEIL_Y`）。⚠ **它今天一个像素都入不了画**
#（50° 俯角下天花板从不入画，见 `ROOM_CEIL_Y` 那段）—— 留着是为了"四面墙是完整的"
# 这件事在数据上成立，将来镜头一动不必回来补。它**不参与任何断言**，也不投影。
const TRIM_ALBEDO := Color(0.16, 0.115, 0.075)
const TRIM_H := 1.1           # 踢脚板高（世界单位）= 22 cm
const TRIM_T := 0.30          # 踢脚板厚（世界单位）= 6 cm（比家具离墙的 0.15 略厚，压在家具脚后）

func _build_trim() -> void:
	var root := Node3D.new()
	root.name = "Trim"
	add_child(root)
	var mat := _lit_mat(TRIM_ALBEDO, "")
	# 四面墙：`[名字, 中心, 尺寸]`。踢脚线**贴在墙内侧**（墙在 `±ROOM_W/2` / `−ROOM_D/2`），
	# 中心从墙面往里让半个厚度 ⇒ 它的外表面与墙共面、内表面朝屋里凸出 `TRIM_T`。
	# 与墙**共面**（而不是埋进墙里）是有意的：埋进去之后"凸出来那一点"就只剩一半，
	# 在 22 单位的墙上看不见。
	var half_t: float = TRIM_T * 0.5
	var span_z: float = ROOM_D + ROOM_NEAR_EXTRA
	var mid_z: float = ROOM_NEAR_EXTRA * 0.5
	# 踢脚线的**纵向**落点：底面 == 地板，顶面 = 地板 + TRIM_H（同 `FLOOR_Y` 那条纪律）
	var trim_y: float = FLOOR_Y + TRIM_H * 0.5
	var crown_y: float = ROOM_CEIL_Y - TRIM_H * 0.5
	for row in [
		# 远墙 / 近墙：沿 x 铺满 ROOM_W，贴在自己的 z 上
		["TrimN", Vector3(0.0, 0.0, -ROOM_D * 0.5 + half_t), Vector3(ROOM_W, TRIM_H, TRIM_T)],
		["TrimS", Vector3(0.0, 0.0, ROOM_D * 0.5 + ROOM_NEAR_EXTRA - half_t),
			Vector3(ROOM_W, TRIM_H, TRIM_T)],
		# 东西墙：沿 z 铺满整段（含近半侧那一截），贴在自己的 x 上
		["TrimW", Vector3(-ROOM_W * 0.5 + half_t, 0.0, mid_z), Vector3(TRIM_T, TRIM_H, span_z)],
		["TrimE", Vector3(ROOM_W * 0.5 - half_t, 0.0, mid_z), Vector3(TRIM_T, TRIM_H, span_z)],
	]:
		for yv in [trim_y, crown_y]:
			var mi := MeshInstance3D.new()
			mi.name = String(row[0]) + ("Crown" if yv == crown_y else "")
			var bm := BoxMesh.new()
			bm.size = row[2]
			mi.mesh = bm
			mi.material_override = mat
			mi.position = (row[1] as Vector3) + Vector3(0.0, yv, 0.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)

# ---------------- 吊灯的**可见几何**（v0.8.0 三期） ----------------
#
# **病**：批次 12 A1 把台灯那四件实物删掉之后，屋子里**没有任何可见光源** ——
# 光从空气里来（`table_3d` 那段写着"观感上变成窗外透进来的一束暖光"）。用户这轮要的是
# 参考图里那盏**看得见的吊灯**（它是整个氛围的来源）。
#
# **⚠ 只加几何、不动光**：`LAMP_ENERGY` / `LAMP_RANGE` / `LAMP_ATTEN` / `LAMP_LIGHT_POS`
# 一个都不碰（它们被 `layout_test` 的照度与"唯一投影源"那几条钉着）。这里挂的是一盏
# `OmniLight3D` **都没有**的纯摆设。
#
# **灯挂在哪儿**：
#   * 平面位置 = `LAMP_LIGHT_POS` 的 (x, z) —— "挂在光的位置上"；
#   * 高度**不能**用光的 y（10.0）：50° 俯角下画面顶端那条视线在 z = 0 处只到 y ≈ 5.06
#     （默认档）—— 灯罩放在 y = 10 就是**永远不在画面里**（等于没做）。所以灯罩落到
#     **y ∈ [2.6, 4.0]**（罩口到罩顶）：两档都整只入画，而罩口中心的画布落点是
#     **(245, 211)** —— 在**左上方那条空带**里，**压不到棋盘**（棋盘上沿在画布 y≈230）。
#
# **几何用"程序化"而不是那批 `.glb`** —— 这是**量出来**的结论，不是偏好：
#
# 拿三个 Kenney 灯逐面量了"罩的口 / 顶哪边宽"（`surface_get_arrays` 的顶点，取上下各 10%
# 那一圈的最大半径）：
#   * `lampRoundFloor` 罩 `lamp` 面：底圈 1.71 / 顶圈 1.46 ⇒ **口朝下**（落地灯本来就该朝下）；
#   * `lampRoundTable` 罩：底 1.71 / 顶 1.46 ⇒ 同上；
#   * `lampSquareCeiling` 罩：底 1.70 / 顶 1.70 ⇒ 方盒，口朝上。
#
# 而**吊灯的形状要求两个条件同时成立**：罩在最下面 **且** 口朝下。落地灯的罩在**杆顶**
# ⇒ 不翻过来就吊不了；**绕 X 翻 180° 又会把口翻成朝上**（出图实证：`shots/room3_g_…`
# 里那口"朝上的六边形盆"、能看见罩腔）。
# ⇒ 那两款模型的罩**两条件不可兼得**（罩与杆的上下关系是模型定死的，靠摆位换不来）。
# 所以这一件走**程序化**：一个 `CylinderMesh` 圆台（口朝下、顶封住）+ 一根细杆 + 一块天花板底座
# —— 与项目既有的那条纪律一致（"能用程序化手段画出来的就别加素材"，转盘 / 房子贴图 / 卡面
# 都是这么做的），而且**零新增素材**。
#
# **尺寸**（协调者给的目标：罩宽 2.5~3.5 世界）：
const PENDANT_SHADE_R := 1.25        # 罩**口**半径 ⇒ 宽 2.50 世界 = 0.50 m（一盏普通吊灯罩）
const PENDANT_SHADE_TOP_R := 0.60    # 罩**顶**半径（收口；顶封住，从相机这一侧看过去是个盖）
const PENDANT_SHADE_H := 1.40        # 罩高 —— **比宽小得多**（宽:高 = 1.79:1），
                                     # 这一条是改版的要害：上一版罩高 2.77（比它还宽），读成一根柱子
const PENDANT_ROD_R := 0.085         # 吊杆半径（细杆；它要一路顶到天花板 = 12 个单位长）
const PENDANT_SEG := 8               # 段数：与 Kenney 那批的低模调子同一档（8 段 = 八棱圆台）
## 天花板底座（贴着 `ROOM_CEIL_Y` 的那块小圆盘）的半径 / 厚。
const PENDANT_PLATE_R := 0.42
const PENDANT_PLATE_H := 0.30
## 灯罩**口**（最下面那一圈）挂的世界高度。这是唯一的自由量：罩顶 = 它 + `PENDANT_SHADE_H`、
## 吊杆从罩顶拉到天花板。取 **3.0** 是**画布判据**定的：`layout_test` 有一条
## 「吊灯罩在屏幕上不遮住桌垫」（把罩子上下两圈口沿投影成凸包，与桌垫四边形求交）。
## 2.6 那一档实测**刚好擦到桌垫左缘 ~2px**（罩子有一角伸到 x = −2.83，落在桌垫的 x 范围内，
## 而它挂得越低、屏幕上就越往右下走）—— 抬到 3.0 之后实测余量 ≈18px。
## 再往上抬会**削弱"这是吊着的"那件事**（默认档画面上沿只到 y ≈ 5.06，罩顶 4.4 已经是
## 露出来的那截吊杆的下限了），所以 3.0 是这条画布判据与构图之间的平衡点。
const PENDANT_SHADE_BOTTOM := 3.0

func _build_pendant() -> void:
	var root := Node3D.new()
	root.name = "Pendant"
	add_child(root)
	# **不叫 `Lamp`**：`layout_test` 有一条反向契约查 `t3.get_node_or_null("Lamp") == null`
	#（批次 12 A1 删台灯实物时留下的：树里不许再有那盏**台灯**）。那一条查的是**容器的直接
	# 子节点**、挂在这里本来也不会撞；改叫 `Pendant` 是为了**读代码的人一眼分得清**
	# ——"台灯的实物已删"与"这轮新加的吊灯"是两件事。
	#
	# 三块都按 `LAMP_LIGHT_POS` 的 **(x, z)** 摆（"挂在光的位置上"），y 由 `PENDANT_*` 那几个定。
	var axis := Vector3(_lamp_light_pos.x, 0.0, _lamp_light_pos.z)
	var shade_top: float = PENDANT_SHADE_BOTTOM + PENDANT_SHADE_H
	# ① 灯罩：圆台，**口朝下**（`bottom_radius` > `top_radius`）、**顶封住**（`cap_top`）。
	#    相机在 50° 俯角上、灯罩又在桌上方的近处 ⇒ 看过去只会看到**顶盖 + 外壁**，
	#    "能看见罩腔"那件事（上一版 .glb 的病灶）从根上没了。
	var shade := MeshInstance3D.new()
	shade.name = "Shade"
	var scm := CylinderMesh.new()
	scm.top_radius = PENDANT_SHADE_TOP_R
	scm.bottom_radius = PENDANT_SHADE_R
	scm.height = PENDANT_SHADE_H
	scm.radial_segments = PENDANT_SEG
	scm.cap_top = true
	scm.cap_bottom = true
	shade.mesh = scm
	shade.material_override = _pendant_shade_mat
	shade.position = axis + Vector3(0.0, PENDANT_SHADE_BOTTOM + PENDANT_SHADE_H * 0.5, 0.0)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shade)
	# ② 吊杆：从罩顶一路拉到天花板（12 个单位长）。**它大半在画面之外**（默认档画面上沿在
	#    z = 0 处只到 y ≈ 5.06）—— 露出来的那一小截正好是"这盏灯是吊着的"那句话。
	var rod_h: float = ROOM_CEIL_Y - shade_top
	var rod := MeshInstance3D.new()
	rod.name = "Rod"
	var rcm := CylinderMesh.new()
	rcm.top_radius = PENDANT_ROD_R
	rcm.bottom_radius = PENDANT_ROD_R
	rcm.height = rod_h
	rcm.radial_segments = PENDANT_SEG
	rod.mesh = rcm
	rod.material_override = _furn_mat          # **与其余 17 件家具同一份材质**（见下面"材质"那段）
	rod.position = axis + Vector3(0.0, shade_top + rod_h * 0.5, 0.0)
	rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rod)
	# ③ 天花板底座（`ROOM_CEIL_Y` 之上那一小块圆盘）。**它永远不在画面里** —— 留着与
	#    "吊杆要顶到天花板上"这件事对上，将来镜头一动不必回来补。
	var plate := MeshInstance3D.new()
	plate.name = "CeilingPlate"
	var pcm := CylinderMesh.new()
	pcm.top_radius = PENDANT_PLATE_R
	pcm.bottom_radius = PENDANT_PLATE_R
	pcm.height = PENDANT_PLATE_H
	pcm.radial_segments = PENDANT_SEG
	plate.mesh = pcm
	plate.material_override = _furn_mat
	plate.position = axis + Vector3(0.0, ROOM_CEIL_Y - PENDANT_PLATE_H * 0.5, 0.0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plate)
	# ---- 材质（三期复核后改，协调者判图 + 探针实测）----
	#
	# **病灶**：屋里每一件家具都走 `_paint()` 压成暗木调，**吊灯是唯一一件没压的** ——
	# 探针量到它自带的 `metal (0.48, 0.50, 0.51)`（一块**冷灰**）与 `lamp (0.55, 0.53, 0.43)`
	# （奶白），**两块都亮过家具（0.281）与墙（有效 0.52）** ⇒ 它是画面里唯一的亮色块。
	# ⇒ 照家具那条口径走：
	#   * **吊杆 / 底座** → `_furn_mat`（**与其余 17 件家具逐字同一份材质**，"同一族"就是这么落实的）；
	#   * **灯罩** → `_pendant_shade_mat`：**同族的暗暖色**打底（`PENDANT_SHADE_ALBEDO`）
	#     ＋**一点自发光**（`PENDANT_GLOW`）。
	#
	# **自发光不是装饰、是必须的**：那盏 `OmniLight3D` 就吊在灯罩正上方 4.6 处，罩壁几乎竖直
	# ⇒ `N·L ≈ 0` ⇒ 光**照不到灯罩自己**（试过不给自发光：出图是一坨深灰，
	# `shots/room3_b_table_plain.png` 左上角）。灯罩本来就该是**里头的灯泡照亮的** ——
	# **底色先压到家具那一档、再靠它读出来**，才是对的次序。
	# ⚠ 它**不是第二盏灯**：`emission` 只加在材质上、不产生任何光照，`layout_test` 那两条
	#（"唯一投影源" / "补光恰好一盏"）数的是 `Light3D`，与它无关。

## 灯罩的面色：**与家具同族的暗暖色**（比 `FURN_ALBEDO (0.34, 0.27, 0.21)` 稍暗、更偏琥珀）。
const PENDANT_SHADE_ALBEDO := Color(0.38, 0.26, 0.15)
## 灯罩的自发光色 / 强度。**暖白**（不是纯橙）—— 纯橙的自发光会把罩子染成一块**饱和橙**
## （上一版 `(1.0, 0.56, 0.26) @ 0.45` 出图就是一只橙色塑料筒，见 `shots/room3_g_*` 那两轮）。
## 现在这组：`albedo×受光 + emission×energy ≈ (0.49, 0.39, 0.27)`（亮度 0.39、R/B ≈ 1.8）——
## **亮过家具（0.281）、仍暗于桌垫（0.56）**，"灯在亮着"读得出来，但抢不走棋盘。
## 强度 0.38 是出图调的第三档（0.85 白成一块板 → 0.45 饱和橙 → 0.38 暖白）。
const PENDANT_GLOW := Color(1.0, 0.82, 0.58)
const PENDANT_GLOW_ENERGY := 0.38

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
		# **同名模型（两盆盆栽）要给后一件一个稳定名字**：Godot 的自动改名给的是
		# `@Node3D@21` 这类**随节点序号漂移**的名字，日志里读不出是哪一件（三期铺满之后
		# 表里就有两件 `plantSmall1`）。**第一件保持原名** —— `layout_test` 有一条断言
		# 按 `stand_boxes["desk"]` 取书桌（"书桌顶面与桌面齐平"），改名字会把它打空。
		# ⚠ 要在 `add_child` **之前**查重：加进去之后 `has_node` 连**它自己**都能查到，
		# 于是每一件都会被改成 `xxx_2`（书桌那条断言就是这么红过一次的）。
		var nm: String = String(row[0]).get_basename()
		if fur.has_node(NodePath(nm)):
			var k := 2
			while fur.has_node(NodePath("%s_%d" % [nm, k])):
				k += 1
			nm = "%s_%d" % [nm, k]
		mi.name = nm
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
		# 椅子用**自己那份**材质（本轮改版起，见 `CHAIR_ALBEDO`）—— 一期那句"与家具同一份材质"
		# 是为了"别读成随手凑的"，而用户要的正是"椅子看得出是椅子"。
		_paint(mi, _chair_mat)

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
## （同一期 `_build_furniture` 那段）。⇒ **摆人一律由 `set_chars()` 驱动**
##（`game.gd:_refresh_players()` 同一处喂；`chars.gd` **没有 `_ready()`**，也不许在 `_ready` 里摆人 ——
## 那刻还没有任何状态，"谁坐哪"无从谈起，而入树前读座位锚点的 `global_transform` 会静默写错值）。
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
## **顺序 / 颜色 / 名字一字未变时直接返回**（每次广播都调本函数）。
##
## **改版后本函数只干一件事**：维护 `_seat_peers` —— 那是**角色层与 HUD 都要的那份顺序**
##（`game._refresh_players()` 从它推出喂给 `chars.set_chars()` 的座位序，`hud_test` 钉着两边同序）。
## 原先它还负责把棋子色 / 昵称刷到椅背名牌上；**椅背名牌已整段删除**（见文件上方那段），
## 那件事现在归 `chars.gd` 的头顶名牌。
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
