class_name TableView3D
extends Node3D
## 2.5D 桌面容器（见 doc/development/plans/v0.5.0-布局2.5D.md §二 / §6.1）。
##
## 结构：本节点（Node3D）持有 3D 场景 —— 桌面板 + 相机 + 灯 —— 以及一个 SubViewport，
## 现有 BoardView 原样住在那个 SubViewport 里。屏幕层 HUD 在 game 上，叠在 3D 之上。
## 输入由本节点映射：屏幕点 → 相机射线 → 水平桌面 → UV → SubViewport 像素 → push_input。

const TABLE_W := 8.0             # 桌面宽度（世界单位）
const VP_SIZE := Vector2i(2048, 2048)   # SubViewport 分辨率（清晰度靠它，见设计稿 §十 风险）
const CAM_TILT_DEG := 50.0       # 俯角：0 = 平视，90 = 正俯视
const CAM_FOV := 55.0            # 收窄默认 75°：探针实测默认 FOV 下桌面只占屏 1/4
## 相机到注视点的水平距离（3D 端）。
##
## **批次 5 Task 2 重调过（5.8 → 5.2）**：桌面从 8×8 变成 8×6.15（窗口裁到桌垫、进深跟着窗口
## 比例走，见 TEX_WINDOW_PX），加上外圈木纹后整张桌子是 10.4×8.55。5.8 是按"8×8 的方桌"定的，
## 对今天这张浅一些、但要连木框一起入画的桌子就偏远了（桌子只占屏幕约三成）。
## 5.2 是拿三条量夹出来的：
##   * 木桌四角（±5.2 / ±4.28）在**整条视角轨道**上都在画面内，21 档最紧的一档余量 93.4px
##     （layout_test 的取景断言按**木桌**四角量，不再是桌垫四角 —— 木桌才是"看得见的桌子"）；
##   * 四块立牌**牌面**的八个角同样全程在画面内，最紧 21.8px；
##   * 3D 端 ↔ 2D 端桌面投影面积比 0.83（须在 [0.6,1.6]）。
## 再近（4.9 上下）木桌四角会开始贴边；再远则棋盘上的字更小、白占屏幕。
const CAM_DIST := 5.2

# ---- 批次 4：双视角。滚轮沿一条轨道在 3D 第一人称 ↔ 2D 桌面之间连续推移
#（`dolly` 推拉整个删除，见设计稿 §四）。view_t ∈ [0,1] 是这条轨道上的位置。
const CAM_TILT_2D_DEG := 88.0    # 2D 端俯角：接近正俯视（只看桌上地图；手牌在这一端淡出，
                                 # 看不见也就点不到，见批次 4 Task 2）
const VIEW_DIST_2D := 8.6        # 2D 端「相机到注视点的 3D 距离」。**不是随手取的估值**，
                                 # 是拿两条断言、对着出图把值夹出来的：
                                 #   * 为什么这个距离要跟俯角**一起**插值：不是为了"防近边溢出"——
                                 #      那个说法实测是**反的**：把距离固定在 3D 端的 9.02、只插角度，
                                 #      底边余量是 35.1 / 21.9 / 54.2 px（wt=0/0.5/1.0），**比现在这条
                                 #      曲线还宽松**；近边溢出只出现在"距离固定在 2D 端"那种假想曲线上。
                                 #      真正的理由是**让两端的桌面占屏比例接近**（面积比 0.96）：
                                 #      只插角度的话 2D 端桌面会明显缩水。代价是**距离插值收紧了取景**——
                                 #      中段出现一个比两端都紧的取景点（见①）。别把这条当"防溢出推导"读。
                                 #   ① 整张桌面（±4 世界单位的方桌）在整条轨道上**四个角都不许
                                 #      出画面**。俯角越大，桌面在屏幕竖直方向上的投影越长
                                 #（8 格：sin50°≈6.1 → sin88°≈8.0）—— 中段那个最紧的点正是它
                                 #      与上面那笔距离插值两头夹出来的。
                                 #      沿轨道扫 21 档实测：**最紧的一档在 wt≈0.45–0.55**（不在两端），
                                 #      8.2 时那里只剩 0.0~0.3 像素（近边正好贴在屏幕下沿上，
                                 #      浮点一抖就红）；8.6 时同一档余量 10.9px、两端 35px 上下。
                                 #   ② R42：两端桌面投影包围盒的**面积比**要落在 [0.6,1.6]
                                 #（只钉「四角在画面内」是可以骗过去的 —— 把距离调大让桌面整体变小，
                                 #      四角照样在画面内，而 2D 端就成了张缩水的小图）。
                                 #      8.6 实测面积比 0.96：两端大小接近，2D 端仍是"整屏桌面"。
                                 # 取值就是把①的下界（≈8.2，再小就贴边）往上抬到有余量的 8.6；
                                 # 抬得再多（如 9.2）②会单边下滑、2D 端明显缩水，与"2D 桌面"的观感相悖。
const VIEW_STEP := 0.25          # 滚轮每格改多少（4 格从 3D 走到 2D）
const VIEW_SNAP := 6.0           # 平滑逼近速率：每秒把剩余差距衰减 e^-6（帧率无关的指数逼近）

# 纹理窗口 = **桌垫**（棋盘 + 一圈留白），不再铺满整张画布。座位栏已随批次 5 Task 2
# 换成桌上立牌 ⇒ 画布不再需要为它们预留，批次 2 推迟的「棋盘铺满桌面」比例目标在这里兑现：
# 窗口宽 = `BoardView.MAT_WINDOW_W`、与 `BoardView.MAT_RECT`（桌垫的世界矩形）同比例、
# 且水平垂直都在画布正中 —— 取景（`BoardView.fit_overview`）正是按这个关系把桌垫内容
# 铺成这一块。于是桌面上看到的 = 一块居中的桌垫 + 外圈的木桌（见 _build_table 的第二个平面）。
#
# **改窗口必须两边一起改**：`BoardView.MAT_RECT` / `MAT_WINDOW_W` 与之同源，
# layout_test 有一条断言钉住"桌垫比例 == 窗口比例且居中"。
#
# 历史（别丢掉这条教训）：批次 2 的 T4c 曾把窗口裁到 Rect2(0, 348, 2048, 1700) 让「棋盘铺满桌面」，
# 而当时上家的**座位栏**在画布 y∈[16,211]、正落在被裁掉的顶部 —— 在画布内、却在窗口外，
# 桌面上既看不见也点不到，指向性道具（交换生 / 跑腿券 / 强拆令）选不中上家。
# 那时裁定"交互优先于比例"、恢复整张画布。今天座位栏已不在画布上，那条约束随之解除。
const TEX_WINDOW_PX := Rect2(14.0, 247.36, 2020.0, 1553.28)
# 桌面进深：与窗口同比例，否则贴图会被拉伸。
const TABLE_D := TABLE_W * TEX_WINDOW_PX.size.y / TEX_WINDOW_PX.size.x
const TABLE_SIZE := Vector2(TABLE_W, TABLE_D)
## 木纹外框的宽度（世界单位）：桌垫之外铺木纹的那一圈。桌面平面本身**不放**到这么大 ——
## 见 _build_table 里"第二个平面"的做法与理由。
const WOOD_FRAME := 1.2

# ---------------- 批次 6：房间剪影 + 台灯（见设计稿 §五 / §九 补记 1） ----------------
#
# 观感的主角是**光**：近黑的屋子里只亮着一盏**台灯**，四周落进剪影（设计稿 §五）。
# 屋子**只做剪影** —— 几个 `BoxMesh` 拼出三面墙 / 书架 / 床架，材质**近黑 + 高粗糙**，
# 再补一层**极弱的自发光当底光**（见 `ROOM_EMISSION` 那段：台灯照不到最远那件，
# 光靠它走不进画面）。网格全程序化、**新增素材为零**
#（拿不到外部素材，见设计稿 §九 补记 1）⇒ `LICENSE` 的第三方登记不动。
#
# 所有剪影**共用一份材质**（`room_mat`）：它们本就该是一块黑，每件单建一份是纯浪费
#（本批次点名要避免的那种），同材质还能少几次状态切换 —— **底光也因此是全场一致的**。
const ROOM_FAR_Z := -11.0                      # 后墙（远端）的 z
const ROOM_SIDE_X := 11.5                      # 左右墙的 |x|
const ROOM_SIDE_Z1 := 2.0                      # 左右墙的近端 z（近端不造墙：相机在那一侧）
const ROOM_WALL_H := 11.0                      # 墙高
const ROOM_WALL_T := 0.4                       # 墙厚
const ROOM_COLOR := Color(0.07, 0.066, 0.076)  # 近黑：台灯只擦出一层微光；擦不到的部分**不是黑**（实测约 21/255），见 ROOM_EMISSION 那层底光
const ROOM_ROUGHNESS := 0.95                   # 高粗糙：剪影不该有镜面高光
## 剪影的**自发光底光**（终审修复波 D 补）。
##
## **为什么非有它不可**（实测，1280×800、3D 端围桌全景，取屏幕同一块区域量亮度均值）：
##   书架离灯 ~6.1 ⇒ 出图 **19/255**（清楚可辨）；床架离灯 ~11.0 ⇒ **1/255**，
##   而床架身后的近黑背景是 **4~6/255** ⇒ **床架比它身后的背景还暗**，在画面里就是一坨看不见的黑。
## `_build_room` 原先那句"床架 ~11.0（射程 12.5）⇒ 只被灯擦到一层微光"**断言了一个没发生的效果**：
## 在射程内**必要而不充分** —— 那个距离上灯已经衰减到擦不亮近黑材质（那句已按事实改准）。
## ⇒ 共用材质补一层自发光当底光：它**不过光照、与距离无关**，落在每件剪影上是同一个值，
##   于是最远那件也被抬到背景之上；"台灯是唯一的主光源"这条观感不受影响（底光只是背景量级）。
##
## **取值 0.11 是对着出图夹出来的**（两档实测，床架区域均值）：
##   0.021 ⇒ **1/255**（几乎没变，这条下限证明"给一点点"没用）；
##   0.11  ⇒ 床架 **18/255**、书架 19 → **36/255**、背景不动（4~6/255）⇒ 两件剪影都浮出背景；
##   0.35  ⇒ 床架 **64/255**、书架 **80/255** —— 剪影被洗成灰板，`ROOM_COLOR` 那点近黑白设了（上界）。
## 注意这一项是**加在近黑材质上的常数**：它抬的是"剪影整体"，剪影上那点明暗（台灯擦到的方向感）
## 仍是灯给的（灯照不到的那半件不会因为底光就有方向感）。
##
## **提醒：三面墙共用这份材质 ⇒ 它们也一起被提亮**。已核实**在两个已出图的取景下无害**
##（左沿最大像素一致、剪影之间的缝逐字节相同、背景不变）；但**任何能看到墙的取景**
##（如 30° 俯角的 `--shot=*tilt*`）会把墙显成**一块淡灰板** —— 若将来要出这种图，
## 得重新权衡（把墙拆成独立材质、或单独压掉墙的底光）。
const ROOM_EMISSION := Color(0.92, 0.88, 0.78) # 与台灯同族的暖色：屋子里只有这一盏暖灯
const ROOM_EMISSION_ENERGY := 0.11

## 台灯 = **唯一的主光源**。底座坐在木纹带上（桌垫之外）、灯臂伸到近端桌沿上方，
## 灯罩悬在那里、光池从近端压向桌心，屋子四周落黑（设计稿 §五「单点暖光 + 四周近黑」）。
## **四周的黑是背景色给的**（`_build_environment` 的 `background_color`），不是射程卡出来的：
## 三面墙在这两个摆拍视角里都出画，且墙的包围盒最近面到灯 ~11.8 本来就在射程内 —— 见
## `LAMP_RANGE` 那段。
##
## **为什么底座在木纹带上、不在桌垫上**：灯是"看得见的实物"，压在桌垫上就是**站在棋盘上**
##（遮住格子与字、也压住立牌与手牌）。木纹带是桌垫之外的"桌子本身"，台灯站那里既真实
## 又不挡棋盘 —— layout_test 里那条「灯杆 / 灯罩 / 光源都不在桌垫窗口内」钉的就是它。
## 灯罩的落点（`LAMP_BASE + (LAMP_ARM_LEN, 0, 0)`）同样**必须在窗口之外**：它悬在近端桌沿
## 上方（画布 z 超出窗口下沿），于是光池从近端压向桌心，而灯罩本身落不进棋盘。
## **位置的取值是对着出图夹出来的**（50° 俯角 + 相机在近端 ⇒ 桌边这条"可见、又压不到棋盘"
## 的缝很窄）。三条尺子同时卡住它：
##   ① **在桌垫之外**（|x| > 4.0）—— 否则灯就站在棋盘上（layout_test 那条窗口断言）；
##   ② **在画面之内** —— 台灯是"看见的东西"，掉出画外就等于没有。50° 俯角下，屏幕左侧的
##      点越往近端（z 越大）越贴边：z 一到 2.6 上下，|x|=4.2 就出了左沿；z≈1.0 时同样
##      高度还稳稳在画面里（实测 z=1.0 时左边界的 |x| 上界 ≈4.7）；
##   ③ **不是一团黑影** —— 灯罩的投影不能压在棋盘上（`tests/layout_test.gd` 另有断言钉它）。
## ⇒ 底座落在**左侧木纹带上、偏近端那半张桌子**（x=-4.9 / z=1.0），灯杆立起来、灯罩从杆顶
##   朝桌心探过去一点（`LAMP_ARM_LEN`），整盏灯（连底座）都在画面内。
const LAMP_BASE := Vector3(-4.9, 0.0, 1.0)     # 底座落点（桌心为原点；木纹带上）
## 灯杆高。**固定波 A**：2.3 → 2.8 —— 光池要铺满整张桌面，灯就得再抬一截：
## 灯越低，远端那半张桌子吃到的是越贴地平线的"擦边光"（入射角小 ⇒ 余弦因子把它再压一道），
## 出图实测远端列只有近端的 1/9。抬高之后远端入射角变大，桌面从"左角一盏、右边全黑"
## 变成"整块都在池里"（横切面左 → 右 0.21 → 0.07，**总体下落、中间有起伏** —— 见 `LAMP_ATTEN`）。
## **注意池心仍在桌垫左沿、搬不到桌心**：底座不许站上桌垫 ⇒ 桌面上离灯最近的点永远是左沿。
## 抬杆抹平的是"远端塌陷"，不是池心的位置（这条是几何定的，别指望靠调杆高解决）。
## 上界是**取景**不是玩法：灯越高，屏幕投影越往左外扩（透视），再高灯罩就出画了
##（layout_test 那条「3D 端看得见台灯」钉的就是它）。
const LAMP_POLE_H := 2.8                       # 灯杆高（灯罩挂在杆顶）
const LAMP_ARM_LEN := 0.60                     # 灯臂长：从杆顶朝桌心（+x）探出去一点
const LAMP_SHADE_H := 0.50                     # 灯罩高
const LAMP_SHADE_R_TOP := 0.14                 # 灯罩上口半径
const LAMP_SHADE_R_BOT := 0.40                 # 灯罩下口半径（**上小下大**）
const LAMP_SHADE_TILT := 18.0                  # 灯罩倾角（口朝下、略朝桌心）
const LAMP_COLOR := Color(1.0, 0.86, 0.66)     # 暖光（白炽灯那种偏橙）
## 台灯的能量：**环境光压低之后靠它把桌面重新照亮**（批次 3 那盏顶灯是 energy 2.4 +
## 环境光 0.55）。**固定波 A**：2.6 → 3.5 → **3.9** —— 原值下桌面均值只有批次 5 的一半
##（0.057 对 0.128），观感成了"把原来那张桌子调暗了"，而不是"一盏灯照亮桌面"。
## 上界仍是"别把棋盘左沿烤白"：灯离桌垫左沿只有 2.2 世界单位，能量高了那一列格子的底与字
## 会被一起推到 1.0、白字就看不见了。3.9 是**实测**的上界：出图里桌垫左列均值 0.223、
## 饱和像素 242/16800（1.4%，批次 5 同口径是 0/16800）—— 仍是零星几个高光点、没有连成
## 一片白斑，那一列的格名与价格出图里读得出来。要再加能量，先看这条。
const LAMP_ENERGY := 3.9
## 射程：**够到桌垫四角**（桌垫四角到灯 3.4~9.6；**不是**木桌四角 —— 当前杆高 2.8 下木桌四角是
## 4.4 与 11.2）。
## 收得再小（≤8）远端那半块棋盘就落进死黑、字读不出。
## **注意：房间"近黑"不是这一项管出来的**——屋子四周看到的是**背景色**
##（三面墙在两个摆拍视角里都出画，且墙的最近点本来就在射程内）。所以别拿 `LAMP_RANGE`
## 去调房间明暗（调不动，只会连桌子一起改）；房间的黑见 `_build_environment` 的
## `background_color` 与屏幕层暗角。
## **固定波 A 未改这一项**：桌垫四角（不是木桌四角）到灯 3.4~9.6，12.5 下远端仍落在
## 射程内、只是强度低 —— 远端不够亮由 `LAMP_ENERGY` / `LAMP_ATTEN` / `LAMP_POLE_H` 补，
## 放大射程会把书架床架一起洗白（它们才是"四周的剪影"）。
const LAMP_RANGE := 12.5
## 衰减指数（越大掉得越快）。**固定波 A**：1.15 → 0.85 → **0.72**。衰减是"远端提得比近端多"
## 的那根杠杆，出图实测（能量只 +11%、指数 1.15 → 0.72）远端列 0.017 → 0.074，而近端列只
## 0.167 → 0.223 ⇒ 指数越大掉得越快。1.15 时远端角只剩近端约两成强度，正是"右半张桌子读不出
## 字"那次实测的成因。0.72 下桌面左右比 3.0:1（批次 5 均匀光下是 1.04:1），池子仍有形状
##（横切面从左到右 0.21 → 0.07，**总体下落、中间有起伏**（0.122→0.152、0.087→0.098→0.108、
## 0.044→0.070 三次回升），不是一片平光；"单调"是旧措辞，与量到的剖面不符 —— 批次 6 Task 3 改准）。
const LAMP_ATTEN := 0.72
const LAMP_METAL := Color(0.09, 0.085, 0.08)   # 灯杆 / 底座：暗金属（近黑的屋子里不该亮）
const LAMP_SHADE_COLOR := Color(0.16, 0.13, 0.10)  # 灯罩内壁：比灯杆暖一点，罩住那点光

var board: BoardView
var viewport: SubViewport
var camera: Camera3D
var table_mesh: MeshInstance3D
var wood_mesh: MeshInstance3D       # 木纹外框（桌垫之外那一圈木桌，见 _build_table）
var vignette: ColorRect        # 屏幕层暗角贴片（build_vignette 造，挂在调用方给的屏幕上）

var table_mat: StandardMaterial3D   # 桌面材质（取样窗口与 TEX_WINDOW_PX 同源）

## 房间剪影层（批次 6：三面墙 + 书架 + 床架）与它那份**共用**的近黑材质。
var room: Node3D
var room_mat: StandardMaterial3D
## 台灯（批次 6）：底座 / 灯杆 / 灯臂 / 灯罩挂在 `lamp` 下，`lamp_light` 是**全场唯一**的灯。
var lamp: Node3D
var lamp_light: OmniLight3D

## 实体物件层：与桌垫共用同一套 UV 坐标系，物件都挂这里（见设计稿 §五）。
## 桌垫（table_mesh）只是"印在桌上的画"；转盘 / 两摞牌堆 / 手牌 / 立牌这些有厚度、
## 能投影的实体一律挂 props，摆位走 canvas_px_to_world。
var props: Node3D

## 实体物件的构建与刷新（转盘 / 两摞牌堆 / 手牌 / 立牌，见 scripts/table_props.gd）。
## 挂在 props 下、与桌垫共用同一套坐标；由 game.gd 在收到首个状态后驱动 build_wheel。
var table_props: TableProps

## 桌面上的实体被点中时先问这里；返回 true 表示已消费（不再送进 SubViewport）。
## 签名：`func(canvas_px: Vector2, button: int) -> bool` —— **按键一起带过去**，因为实体对不同
## 键的语义不同（手牌：左键选中 / 右键丢弃；转盘：只吃左键），只给位置的话实体层无从分辨。
## 默认无效（Callable()），即不拦截任何点击 —— 只有 game.gd 接上后才有实体可点。
var on_table_click: Callable = Callable()

## 被实体层吃掉的那次按下的按钮（MOUSE_BUTTON_NONE = 无）。只为了在配对的松开时
## 把这一对事件一起拦掉：2D 侧若只收到「松开」而没收到「按下」，会把上一次按下的拖拽
## 状态当成这次松开在收尾（见 _unhandled_input 里的反例）。按 button_index 认，
## 这样吞掉的必定是同一次点击的松开，不会误伤别的键。
var _consumed_press_btn: int = MOUSE_BUTTON_NONE

## 视角量：0 = 3D 第一人称（50°、手里有牌、能出牌），1 = 2D 桌面（88°、只看地图）。
## `view_target` 是滚轮改的**目标**，`view_t` 是每帧向它逼近的**当前值**（见 _process）。
## 纯本地表现：不进 s_state、不同步 —— 每个人自己滚自己的。
##
## **用属性 setter 而不是裸 var（批次 5 Task 1 起）**：摆相机与"把视角量推给桌上物件"是同一次
## 变化的两半，只做一半就会**静默脱钩**（相机动了、手牌与立牌却还按旧视角显示 / 命中）。
## 早先靠"唯一更新点是 `_apply_camera`"这条**约定**；但 `view_t` 是公开 var，谁一句
## `view_t = x` 都能绕过去。立牌正要用同一个推送点（自己的那面按 view_t 显隐），
## 所以把不变量变成**结构**：赋值即推送，绕不过去。
## setter 里 clamp 到 [0,1]、相等则早退（_process 每帧都赋值，值没变不必重摆相机），
## 再调 `_apply_camera()`（推送就在它末尾）。**`_apply_camera` 不许写 view_t**（会递归）。
## setter 的"相等"用**精确** `==` 而不是 is_equal_approx：`_process` 末尾会把当前值**贴到**
## 目标值（`view_t = view_target`），近似相等时早退会让它永远差着百万分之几、再也贴不齐 ——
## 于是 `_process` 的早退条件永远不成立、每帧白跑一次逼近。精确相等只在"确实没变"时早退。
var view_t: float = 0.0:
	set(v):
		var nt := clampf(v, 0.0, 1.0)
		if nt == view_t:
			return
		view_t = nt
		_apply_camera()
var view_target := 0.0

func _init() -> void:
	_build_environment()
	_build_room()           # 房间剪影要在桌子之前落位（桌子是"屋子里的一张桌子"）
	_build_table()
	_build_lamp()           # 台灯坐在木纹带上 ⇒ 要等桌子（木桌平面）就绪
	_build_props()          # 实体物件层要在桌垫坐标系就绪之后建
	_build_table_props()    # 实体物件本身（转盘等）挂在 props 下
	_build_camera()
	_build_viewport()

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# 批次 6：0.055/0.06/0.085 偏亮（四周不是"近黑"）⇒ 压到近黑的一点点冷灰。
	# 屋子里台灯光池之外的地方就是它，加上一层屏幕层暗角（build_vignette）。
	e.background_color = Color(0.012, 0.014, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.42, 0.40)
	# 批次 6：0.55 → 0.10 → **0.20**（固定波 A）。环境光是**棋盘与木桌**的底光：它一高，
	# 桌面被均匀托起来，台灯那点明暗对比就淹没了；它一低，整张桌子一起沉进黑。
	# 0.10 那一档**压过头了**：光池之外的桌面（右半张、木桌右圈）几乎归零，观感是
	# "把桌子调暗"而不是"照亮桌子"。
	# **注意这一项管不到"房间空处"**：那里看到的是背景色（BG_COLOR 直出、不过环境光），
	# 所以 0.10 → 0.20 之后空处仍是 ~0.009，而棋盘与木桌会一起提亮。
	# **它也托不动那两件近黑的剪影**（终审修复波 D 实测）：剪影的底色只有 0.07，环境光给它的
	# 那一层在 0.20 下仍小到看不见 —— 床架出图 **1/255**、比背景（4~6/255）还暗。
	# 剪影的可见性**不归这一项管**，归 `ROOM_EMISSION` 那层自发光底光（见那段）。
	# 0.20 仍远低于批次 3 的 0.55，也仍过 layout_test 那条 < 0.25 的断言。
	e.ambient_light_energy = 0.20
	env.environment = e
	add_child(env)

# ---------------- 批次 6：房间剪影 ----------------

## 房间：三面墙 + 书架 + 床架，全部 `BoxMesh`、**共用一份近黑材质**（见 ROOM_COLOR 那段）。
## 只造**三面**墙 —— 近端那一面在相机之后，造了也看不见，还白占一次绘制。
##
## 落位原则（对着出图调过）：一律在**木桌之外**，且离台灯够远 —— 近处的剪影被灯一擦就亮，
## 那就不是剪影了。后墙最远（z = ROOM_FAR_Z），书架在左后方、床架在右后方。
func _build_room() -> void:
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	room_mat = StandardMaterial3D.new()
	room_mat.albedo_color = ROOM_COLOR
	room_mat.roughness = ROOM_ROUGHNESS
	room_mat.metallic = 0.0
	# 极弱的自发光底光（见 ROOM_EMISSION 那段：台灯够不到最远那件，靠它才看得见）。
	# **不是"让剪影发亮"**：能量只有背景量级，台灯照出来的明暗仍是剪影上唯一的方向性信息。
	room_mat.emission_enabled = true
	room_mat.emission = ROOM_EMISSION
	room_mat.emission_energy_multiplier = ROOM_EMISSION_ENERGY
	# 显式写死不透明档：剪影要写深度、要能彼此遮挡 —— 批次 4 那条教训（ALPHA 会进透明队列、
	# 不写深度、排序也乱）在这里同样成立，别手滑改成透明。
	room_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	# 后墙（远端）
	_room_box("WallBack", Vector3(ROOM_SIDE_X * 2.0, ROOM_WALL_H, ROOM_WALL_T),
		Vector3(0.0, ROOM_WALL_H * 0.5, ROOM_FAR_Z))
	# 左右墙：从后墙一直铺到近端（近端那头不再有墙）
	var side_len: float = ROOM_SIDE_Z1 - ROOM_FAR_Z
	var side_cz: float = (ROOM_FAR_Z + ROOM_SIDE_Z1) * 0.5
	_room_box("WallLeft", Vector3(ROOM_WALL_T, ROOM_WALL_H, side_len),
		Vector3(-ROOM_SIDE_X, ROOM_WALL_H * 0.5, side_cz))
	_room_box("WallRight", Vector3(ROOM_WALL_T, ROOM_WALL_H, side_len),
		Vector3(ROOM_SIDE_X, ROOM_WALL_H * 0.5, side_cz))
	# 书架（左后方）与床架（右后方）。
	# **位置是对着出图夹出来的**：50° 俯角下，桌面之后**看得见的那条带子很薄** ——
	# 画面顶沿那条射线（水平线以下 22.5°）打在地面上是 z ≈ -9.8，也就是"桌子后面"这段里
	# 只有越靠近桌子才越有高度可用：z=-5 处只看得见 0..2 世界单位高，z=-8 处只剩 0.7。
	# 上一版把书架 / 床架摆在 z=-6.6/-5.8 那种"像房间里该有的位置"，结果**整件都在画外**，
	# 台灯也照不到（14 世界单位 > 射程）—— 出图里那一片是纯黑的。
	# ⇒ 两件都收到**紧贴桌子后方**（z ≈ -4.6/-5.6，仍**不与木桌相交**：木桌 z 到 -4.28），
	#   并且压到 2 世界单位高以内（书架 1.8 / 床架 1.25）。这样才既在画面里、离灯也近一截：
	#   书架离灯 ~6.1、床架 ~11.0（射程 12.5）。
	# **别把"在射程内"读成"看得见"**（终审修复波 D 实测）：射程内**必要而不充分** ——
	#   书架 6.1 出图 19/255（可辨），床架 11.0 只有 **1/255**、比身后的近黑背景（4~6/255）还暗，
	#   是屏幕上一坨看不见的黑。**"剪影可辨"靠的是 `ROOM_EMISSION` 那层底光，不是这盏灯**；
	#   这里的位置只负责"在画面里、不与桌子相交"。原先这句写的是"只被灯擦到一层微光"——
	#   那层微光实测没到，已按事实改准。
	_build_bookshelf(Vector3(-4.6, 0.0, -4.85))
	_build_bedframe(Vector3(4.2, 0.0, -5.6))

## 往房间里加一块剪影：`BoxMesh` + 共用材质 + **不投影**。
## 为什么剪影不投影：它们又大又远，影子只会落在屋子外面没人看得见的地方，而每帧要多跑一张
## 阴影图 —— 本批次点名要避免的浪费（性能）。
func _room_box(node_name: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = room_mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(mi)
	return mi

## 书架剪影：两侧立板 + 顶板 / 底板 + 三层隔板 —— 六块板拼出"一层层的书架"那个轮廓。
## 拼轮廓而不是一整块实心盒子：实心的在剪影里只是一坨黑，看不出是书架。
## 尺寸（2.4 × 1.8 × 0.8）是**画面顶沿**给的：桌子后面那条可见带只有 ~2 世界单位高
##（见 _build_room 里那段），再高就顶出画外、只剩半截。
func _build_bookshelf(base: Vector3) -> void:
	var w := 2.4      # 宽
	var h := 1.8      # 高
	var d := 0.8      # 进深
	var t := 0.08     # 板厚
	# 侧板
	_room_box("ShelfSideL", Vector3(t, h, d), base + Vector3(-(w - t) * 0.5, h * 0.5, 0.0))
	_room_box("ShelfSideR", Vector3(t, h, d), base + Vector3((w - t) * 0.5, h * 0.5, 0.0))
	# 顶板 / 底板
	_room_box("ShelfTop", Vector3(w, t, d), base + Vector3(0.0, h - t * 0.5, 0.0))
	_room_box("ShelfBottom", Vector3(w, t, d), base + Vector3(0.0, t * 0.5, 0.0))
	# 三层隔板（把架子分成四格）
	for i in 3:
		_room_box("ShelfBoard%d" % i, Vector3(w, t, d),
			base + Vector3(0.0, h * (float(i) + 1.0) / 4.0, 0.0))

## 床架剪影：床板 + 床头板 + 一只枕头。高度同样**压在画面顶沿**（见 _build_bookshelf）——
## **实测它在那一线上擦着**（1280×800、3D 端全景：床头板屏幕 y ≈ −2..85，上沿越界 2px；
## 书架同口径是 y 5..161）。这 2px 出图里看不出来，**别为它再压高度**：床架的高度是"看得见
## 一整套床"的下限，再矮就只剩一块床板了。
## 床头板摆在**远端（-z）**那头：镜头在近端，这样看到的是"床头挡在床板后方"的侧面轮廓。
func _build_bedframe(base: Vector3) -> void:
	var w := 2.8      # 宽
	var d := 2.2      # 长（沿 z）
	_room_box("BedBase", Vector3(w, 0.5, d), base + Vector3(0.0, 0.25, 0.0))
	_room_box("BedHead", Vector3(w, 1.25, 0.2), base + Vector3(0.0, 0.625, -d * 0.5))
	_room_box("BedPillow", Vector3(w * 0.6, 0.2, 0.5),
		base + Vector3(0.0, 0.6, -d * 0.5 + 0.6))

# ---------------- 批次 6：台灯（唯一主光源） ----------------

## 台灯：底座 + 灯杆 + 灯臂 + 灯罩，以及**全场唯一**的光源 `lamp_light`（挂在灯罩里）。
##
## 为什么光源是灯罩的子节点、而不是挂在容器上：灯罩是**斜的**（`LAMP_SHADE_TILT`），
## 光源要跟着灯罩的口一起斜下去（光池才会从近端压向桌心）。父节点一分家，改倾角就得手动
## 再算一遍光源位置 —— 那是两处会悄悄漂开的数。
##
## 底座 / 灯杆 / 灯臂**共用一份暗金属材质**、四件都**不投影**（理由同 `_room_box`：
## 光源就在灯罩里，灯自己挡不住自己的光；开着只是白跑阴影图）。
func _build_lamp() -> void:
	lamp = Node3D.new()
	lamp.name = "Lamp"
	lamp.position = LAMP_BASE
	add_child(lamp)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = LAMP_METAL
	mmat.roughness = 0.55
	mmat.metallic = 0.6
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	# 底座：矮圆柱（略外扩，坐得稳）。
	# **固定波 C**：半径 0.24/0.30 → 0.20/0.24。原值下底座外缘 = -4.9 - 0.30 = **-5.20**，
	# 正好压在木桌外沿上（`TABLE_W * 0.5 + WOOD_FRAME` = 5.20）—— **零余量**，再大一点底座就
	# 悬出桌外了，而"半径"此前没有任何断言覆盖（只查了各件的中心位置）。收进来 0.06 留余量。
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.20
	base_mesh.bottom_radius = 0.24
	base_mesh.height = 0.06
	_lamp_part("Base", base_mesh, Vector3(0.0, 0.03, 0.0), mmat)
	# 灯杆：细柱
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.032
	pole_mesh.bottom_radius = 0.038
	pole_mesh.height = LAMP_POLE_H
	_lamp_part("Pole", pole_mesh, Vector3(0.0, LAMP_POLE_H * 0.5, 0.0), mmat)
	# 灯臂：一根横杆，从杆顶朝桌心（+x）伸出去（圆柱轴默认沿 Y ⇒ 绕 Z 转 90° 让它躺平）
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.028
	arm_mesh.bottom_radius = 0.028
	arm_mesh.height = LAMP_ARM_LEN
	var arm := _lamp_part("Arm", arm_mesh, Vector3(LAMP_ARM_LEN * 0.5, LAMP_POLE_H, 0.0), mmat)
	arm.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	# 灯罩：上小下大的锥，口朝下、略朝桌心（绕 Z 正角 = 口朝 +x 那侧倾）
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = LAMP_SHADE_R_TOP
	shade_mesh.bottom_radius = LAMP_SHADE_R_BOT
	shade_mesh.height = LAMP_SHADE_H
	shade_mesh.cap_bottom = false     # 下口敞开：光从口里出来（封着的话罩内一片死黑）
	# 灯罩单独一份材质：内壁比灯杆暖、也比灯杆糙一点（罩住那点光，不至于黑成一个洞）。
	# **两面都画（cull_disabled）+ 自发光**：出图核出来的两条 ——
	#   ① 相机从斜上方看这盏灯，看到的是灯罩的外壁；罩壁是"背光面"，不给自发光的话
	#      灯罩就是黑屋子里的**一团黑**（第一版出图实测：连灯在哪都看不出来）。
	#   ② 罩口朝下、相机俯角 50° 正好能看进去一点 ⇒ 双面画之后能看见**内壁被自己那盏灯照亮的
	#      那一圈暖色**，这才是"一盏亮着的台灯"该有的样子（gl_compatibility 有 emission）。
	var smat := StandardMaterial3D.new()
	smat.albedo_color = LAMP_SHADE_COLOR
	smat.roughness = 0.7
	smat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.62, 0.28)
	# 自发光能量：**固定波 A** 0.45 → 0.25。自发光只是"让灯罩在暗屋子里看得见轮廓"，
	# 0.45 时灯罩自己成了画面最亮的東西（出图实测灯罩 0.237 > 光池峰值 0.167 —— 比它照出的
	# 池还亮），读起来像"一块发光的牌子"而不是"一盏灯"。压到 0.25 之后最亮的是**池**。
	smat.emission_energy_multiplier = 0.25
	var shade := _lamp_part("Shade", shade_mesh,
		Vector3(LAMP_ARM_LEN, LAMP_POLE_H, 0.0), smat)
	shade.rotation = Vector3(0.0, 0.0, deg_to_rad(LAMP_SHADE_TILT))
	# 光源：挂在灯罩里、口沿之上一点点（露在口外的话灯光会"漏"到罩子上方）
	lamp_light = OmniLight3D.new()
	lamp_light.name = "LampLight"
	lamp_light.position = Vector3(0.0, -LAMP_SHADE_H * 0.15, 0.0)
	lamp_light.light_color = LAMP_COLOR
	lamp_light.light_energy = LAMP_ENERGY
	lamp_light.omni_range = LAMP_RANGE
	lamp_light.omni_attenuation = LAMP_ATTEN
	# 批次 3 为"桌上实物能投影"重开的阴影，本批跟着换成这一盏：**全场唯一投影的光源**。
	# 影子方向从此由台灯决定（从近端一侧斜着拉出来），不再是顶灯那种正下方的短影。
	lamp_light.shadow_enabled = true
	shade.add_child(lamp_light)

## 台灯的一件（底座 / 灯杆 / 灯臂 / 灯罩）：建节点、挂进 `lamp`、**不投影**。
func _lamp_part(node_name: String, mesh: Mesh, pos: Vector3,
		part_mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = part_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(mi)
	return mi

func _build_table() -> void:
	table_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = TABLE_SIZE       # PlaneMesh 躺在 XZ 平面，中心在原点；宽 × 进深
	table_mesh.mesh = pm
	table_mat = StandardMaterial3D.new()
	# 不能用 UNSHADED：那样顶光与环境光对棋盘一点作用都没有，桌面只是一块死平的贴图。
	# 走默认的逐像素着色，桌面才吃得到「中心亮、四周暗」；顺带开 alpha 混合 ——
	# 画布（SubViewport.transparent_bg）的透明像素由此交给环境背景，
	# 不再被渲染成黑（review 留给 T4 的遗留项）。
	table_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	table_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 取样窗口必须和输入映射（TEX_WINDOW_PX）用同一块：材质默认采整张画布，
	# 只改几何不改材质的话，看到的是整张桌子、点到的却是窗口那一块 —— 画面与命中不一致。
	# uv1 采样是 UV * uv1_scale + uv1_offset（偏移在缩放之后）；uv1_* 是 Vector3，只用 xy。
	# **两个分量都得给**：窗口曾是"整张画布"，x 那一路 scale 恒为 1 也碰巧对；
	# 批次 5 Task 2 把窗口裁窄之后，再写死 1.0 就会沿 x 拉出 2020/2048 倍的错位
	#（layout_test 的「取样窗口 == 映射窗口」那条立刻红 —— 它正是为这个坑留的）。
	table_mat.uv1_scale = Vector3(TEX_WINDOW_PX.size.x / float(VP_SIZE.x),
		TEX_WINDOW_PX.size.y / float(VP_SIZE.y), 1.0)
	table_mat.uv1_offset = Vector3(TEX_WINDOW_PX.position.x / float(VP_SIZE.x),
		TEX_WINDOW_PX.position.y / float(VP_SIZE.y), 0.0)
	table_mesh.material_override = table_mat
	add_child(table_mesh)

	# ---- 木纹外框（批次 5 Task 2）：**第二个平面**，比桌垫大一圈、略低一点 ----
	# 为什么用第二个平面而不是给桌垫加第二材质：桌垫那一面必须保持**单一材质**把
	# `TEX_WINDOW_PX` 那一块精确采样上去（uv1_scale/offset 与输入映射同源，见上面那条注释），
	# 再塞一层"框"进同一材质就得另写 shader 或加第二个 surface —— 前者是多一份要维护的
	# 采样数学，后者在 gl_compatibility 下走多 pass。独立一个平面最简单，也最不容易把
	# "看到的那块"与"点到的那块"拆开。它同时兜住了桌垫画布的透明像素
	#（SubViewport 是 transparent_bg，桌垫外沿那些 alpha=0 的像素会直接露出这层木纹）。
	wood_mesh = MeshInstance3D.new()
	var wpm := PlaneMesh.new()
	wpm.size = TABLE_SIZE + Vector2(WOOD_FRAME, WOOD_FRAME) * 2.0
	wood_mesh.mesh = wpm
	wood_mesh.position = Vector3(0.0, -0.012, 0.0)   # 略低于桌垫：共面的两片会闪
	var wmat := StandardMaterial3D.new()
	wmat.albedo_texture = UIKit.tex("res://assets/textures/wood_floor.jpg")
	wmat.albedo_color = Color(0.62, 0.55, 0.46)      # 比桌垫亮一档：木桌是桌面，桌垫是印上去的那块
	wmat.roughness = 0.88
	wmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wmat.texture_repeat = true
	# 木纹按世界尺度重复（每 3 个世界单位一轮），不然一张贴图拉满整块桌子就成了糊色块。
	wmat.uv1_scale = Vector3(wpm.size.x / 3.0, wpm.size.y / 3.0, 1.0)
	wood_mesh.material_override = wmat
	add_child(wood_mesh)

	# 批次 6：**原来那盏吊在桌心正上方的暖色顶灯整个搬走了** —— 位置 / 颜色 / 能量 / 射程 /
	# 阴影开关一并挪进 `_build_lamp()`，成为台灯的光源（`lamp_light`）。
	# 为什么不留在这里"改成台灯"：灯的位置现在由**台灯这件实物**决定（光源在灯罩里、跟着灯罩
	# 走），留在这里就成了无主的第二盏灯 —— 两盏灯 = 氛围被拆成两半，还多一张每帧要渲染的
	# 阴影图（双抛物面 2 个 pass）。它的参数也整套重定过（旧那套是按"桌心正上方、
	# 屋子里没有别的东西"调的）：见 LAMP_ENERGY / LAMP_RANGE / LAMP_ATTEN 那几段。

## 实体物件层：一个空的 Node3D 容器，本身不占地、只提供"物件都挂这儿"的父节点
## 与统一的世界原点（= 桌面中心）。坐标换算见 canvas_px_to_world。
func _build_props() -> void:
	props = Node3D.new()
	# 叫 PropLayer 而不是 TableProps：那个名字被**类类型子节点**占着（TableProps.new()
	# 自动取脚本的 class_name），两者同名的话调试时的路径是 `TableProps/TableProps`。
	props.name = "PropLayer"
	add_child(props)

## 实体物件的家（TableProps）。这里只**建**不摆：转盘要等 BoardView 落座、镜头取景之后
## 才知道自己该在画布哪个位置（game.gd 在首个状态后调 build_wheel）。
func _build_table_props() -> void:
	table_props = TableProps.new()
	table_props.setup(self)
	props.add_child(table_props)

## 棋盘画布像素 → 桌面世界坐标（桌垫坐标系，物件摆位一律走这里）。
## 链：画布像素 →（贴图窗口）→ UV →（桌面尺寸）→ 桌垫局部坐标 → 世界坐标。
## 桌垫有旋转/缩放时这里也跟着走 —— 与 screen_to_uv 用的是同一条逆变换。
func canvas_px_to_world(px: Vector2) -> Vector3:
	var uv := TableGeometry.viewport_to_uv(px, TEX_WINDOW_PX)
	return table_mesh.global_transform * TableGeometry.uv_to_world(uv, TABLE_SIZE)

## 反向：桌面世界坐标 → 棋盘画布像素（测试与命中反算用）。
func world_to_canvas_px(w: Vector3) -> Vector2:
	var local: Vector3 = table_mesh.global_transform.affine_inverse() * w
	return TableGeometry.uv_to_viewport(TableGeometry.world_to_uv(local, TABLE_SIZE), TEX_WINDOW_PX)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	add_child(camera)
	camera.current = true
	# 摆位统一走 _apply_camera（全文件唯一摆相机的地方）：这里只负责把相机造出来并挂进本子树。
	# 此时本节点还在 `_init` 里、尚未入树，`_apply_camera` 自己会分辨那条路径（见那里的注释）。
	_apply_camera()

## 设视角目标（滚轮走这里）。夹到 [0,1]。
func set_view(t: float) -> void:
	view_target = clampf(t, 0.0, 1.0)

## 设目标**并立即到位**：摆拍与测试用。玩法里别用 —— 那会丢掉平滑（滚轮要的是推移感）。
##
## `view_t = view_target` 走 setter（赋值即摆相机 + 推送）；**末尾这一笔显式 `_apply_camera()`
## 仍然要留**：值没变时 setter 会早退（`snap_view(0.0)` 在已经 0 的时候是常态，测试与摆拍都这么调），
## 而"摆到这一档"这件事本身必须发生。
func snap_view(t: float) -> void:
	view_target = clampf(t, 0.0, 1.0)
	view_t = view_target
	_apply_camera()

## 按 view_t 摆相机 —— 全文件唯一摆相机的地方（相机的位置与朝向只有这一个来源）。
##
## 俯角与「到注视点的 3D 距离」**一起**插值 —— 理由是让**两端的桌面占屏比例接近**（面积比
## 0.96），代价是**中段会出现一个比两端都紧的取景点**（wt≈0.45，余量 10.9px）。
## 别把这条读成"距离不插值就会溢出"：实测反了 —— 把距离固定在 3D 端的 9.02、只插角度，
## 底边余量是 35.1 / 21.9 / 54.2 px（wt=0/0.5/1.0），**比现在这条曲线更宽松**；
## 近边溢出只出现在"距离固定在 2D 端"那种假想曲线上。
##
## 位置 = 方位 × 距离。**方位是"相机在桌心的哪个方位"，不是"相机指向桌心的方向"** ——
## 两者差一个负号，把后者当位置赋回去，相机就绕原点镜像到桌子的另一侧（y<0），而 basis
## 不变 ⇒ 射线仍朝下、与桌面交于 t<0，被 Plane.intersects_ray 拒绝 ⇒ screen_to_uv 对所有
## 屏幕点返回 null ⇒ 点击与悬停整体失效（批次 2 的 `dolly` 踩过这个坑，那个函数已删，
## 教训留在这里：**方向 ≠ 位置**）。
##
## 相机在树内用 `global_position` + `look_at`（本节点恒挂在原点，两条路等价，但这是"真·全局"
## 那条）；`_build_camera` 里刚 `add_child` 完就调这里时本节点还在 `_init` 里**没入树**，
## 相机自然也还没入树 —— 那时 `look_at` 会 ERR_FAIL（"Node not inside tree"）、
## `global_position` 的 setter 也会因父节点取不到全局变换而报错，于是退回批次 2 验证过的
## `look_at_from_position`（它按局部变换算，树外安全）。入树之后的每一次调用（滚轮 / snap_view /
## _process）都走真·全局那条。
func _apply_camera() -> void:
	# 本函数现在由 `view_t` 的 setter 调用，**不许**在里面写 view_t（会递归）。
	# 相机还没造出来时直接返回：正常路径不会走到（view_t 的唯一初值来自字段初始化，
	# 不触发 setter；`_build_camera` 在 _init 里建完相机才轮到别人赋值），
	# 但留着这一条，将来谁把赋值挪到 _init 前面也不会炸。
	if camera == null:
		return
	var rad := deg_to_rad(lerpf(CAM_TILT_DEG, CAM_TILT_2D_DEG, view_t))
	var d3d := lerpf(CAM_DIST / cos(deg_to_rad(CAM_TILT_DEG)), VIEW_DIST_2D, view_t)
	var pos := Vector3(0.0, d3d * sin(rad), d3d * cos(rad))
	if camera.is_inside_tree():
		camera.global_position = pos
		camera.look_at(Vector3.ZERO, Vector3.UP)
	else:
		camera.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	# 视角量顺带推给桌上实体（批次 4 Task 2：手牌跟着淡出，看不见就点不到）。推在**这里**、
	# 不推在 `_process` 的循环体里 —— `_process` 在 view_t == view_target 时早退，而 snap_view
	#（`--shot` 全部摆拍与测试都走它）**根本不经过 `_process`**：推在循环体里的话，摆拍与测试
	# 那条路上的手牌永远不会淡，淡出等于没做。本函数是"相机 / 视角量变了"的唯一出口
	#（snap_view 与 _process 都调它），所以这是唯一不会漏的推送点。
	if table_props != null:
		table_props.set_view_t(view_t)

## 逐帧把 view_t 平滑逼近 view_target。指数逼近：每帧把剩余差距乘 e^(-VIEW_SNAP*delta)，
## 与帧率无关（60fps 与 144fps 走同样的时间曲线），且**永不过冲**（单调逼近）。
##
## 相等时直接早退：省掉每帧的 look_at（相机不动就没必要重摆）。
## 注意：这里早退掉的只是"摆相机"这一件事 —— 批次 4 Task 2 的「把手牌视角量推给桌上实体」
## 挂在 `_apply_camera` 上（那条路覆盖 snap_view，见那里的注释），不跟着一起早退；
## 而 snap_view 那条路走完之后也不需要 `_process` 再推：`set_hand` 重建节点后会自己补贴
## 当前透明度（table_props._apply_hand_layout 末尾）。
##
## 批次 5 Task 1 起**本函数里不再显式调 `_apply_camera()`**：`view_t` 是属性，
## 下面两次赋值（逼近值、最后贴到目标值）都走 setter，而 setter 里就是"赋值即摆相机 + 推送"。
## 少一处显式调用不是省事，是要让"只有改 view_t 这一条路能改相机"成为结构上的事实。
func _process(delta: float) -> void:
	if is_equal_approx(view_t, view_target):
		return
	view_t = lerpf(view_target, view_t, exp(-VIEW_SNAP * delta))
	if absf(view_t - view_target) < 0.001:
		view_t = view_target

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = VP_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	add_child(viewport)
	table_mat.albedo_texture = viewport.get_texture()

	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.overlay_top = 0.0        # 3D 层不再需要为屏幕 HUD 预留（HUD 浮在 3D 之上）
	board.overlay_bottom = 0.0
	board.overlay_left = 0.0
	board.overlay_right = 0.0
	viewport.add_child(board)
	# （原先这里往 BoardView 注入抽卡「抽出」的起点供给 `deck_top_provider`。批次 8 把抽卡演出
	#  搬到屏幕层的 `DeckReveal`、不再"从实体摞顶面抽出"，那条注入连同 `TableProps.deck_top_px`
	#  一起删掉了。BoardView 与 TableProps 之间不再有这条依赖。）

# ---------------- 屏幕层暗角（设计稿 §三 / §6.4） ----------------

## 屏幕层暗角：四周压暗，补 Compatibility 渲染器没有的 SSAO / 景深。
## 只造出来挂到调用方给的屏幕层上（挂哪儿、压在哪一层由 table_hud 决定）。
func build_vignette(parent: Control) -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只做外观，绝不吃点击
	vignette.color = Color(0.0, 0.0, 0.0, 0.35)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// 四周压暗：到中心的归一化半径越大越暗（暗角）
void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) / 0.7071;
	float v = smoothstep(0.35, 1.0, r);
	COLOR = vec4(0.0, 0.0, 0.0, v * COLOR.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vignette.material = mat
	parent.add_child(vignette)

# ---------------- 输入映射（见设计稿 §6.2） ----------------

## 屏幕点 → 桌面 UV；打不到返回 null。
func screen_to_uv(screen_pt: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pt)
	var dir := camera.project_ray_normal(screen_pt)
	var hit = TableGeometry.hit_floor(origin, dir, global_position.y)
	if hit == null:
		return null
	var local: Vector3 = table_mesh.global_transform.affine_inverse() * (hit as Vector3)
	return TableGeometry.world_to_uv(local, TABLE_SIZE)

## 屏幕点 → SubViewport 像素坐标；射线打不到桌面则返回 null。
func screen_to_viewport(screen_pt: Vector2) -> Variant:
	var uv = screen_to_uv(screen_pt)
	if uv == null:
		return null
	return TableGeometry.uv_to_viewport(uv as Vector2, TEX_WINDOW_PX)

## SubViewport 像素坐标 → 屏幕像素坐标；该点不在桌面上时返回 null。
## （Task 3 的正变换 screen_to_viewport 的逆；见设计稿 §6.2 与批次 2 的 Task 3b）
## 用途：BoardView 的 tile/token/wheel_screen_pos 返回的是画布（SubViewport）坐标，
## 而消费它们的屏幕层 HUD 活在窗口空间 —— 少了这步换算，格详情卡会被 clamp 到屏幕边缘。
func viewport_to_screen(pos: Vector2) -> Variant:
	var uv := TableGeometry.viewport_to_uv(pos, TEX_WINDOW_PX)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return null                       # 超出桌面范围
	var world: Vector3 = table_mesh.global_transform * TableGeometry.uv_to_world(uv, TABLE_SIZE)
	return camera.unproject_position(world)

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
		# 滚轮分支不吃旗标：旗标认的是某个具体按键的"按下还没被松开"，而滚轮既不是那个按键、
		# 也不代表它松开了（滚轮事件照旧改视角，与左/右键的配对互不相干）。这里若顺手清掉，
		# 一个被消费的按下在"滚一格再松开"之后就又漏进 2D 了。
		# 滚轮改的是**目标值**，不是当前值：相机由 _process 平滑推移过去（推移感，不是硬切）。
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_view(view_target + VIEW_STEP)     # 向前滚 = 推向 2D 桌面
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_view(view_target - VIEW_STEP)     # 向后滚 = 拉回 3D 第一人称
			get_viewport().set_input_as_handled()
			return
		# 旗标的生命期恰好是「被消费的按下 → 它的松开」。所以同一个键**又按下**时先清掉：
		# 那意味着上一次配对早就断了（松开的那个事件根本没送到，比如按住时窗口失焦后松手），
		# 而新按下的按下是照常转发进 2D 的 —— 旗标若还挂着，新按下的松开就会被误吞，
		# 2D 侧于是收到一个没有按下的松开（正是这个旗标要防的那类事故）。
		if mb.pressed and mb.button_index == _consumed_press_btn:
			_consumed_press_btn = MOUSE_BUTTON_NONE
		# 实体层吃掉的那次按下，它的**松开**也必须一并吞掉（配对，按 button_index 认）。
		# 放进去会出事：BoardView 的点击语义其实在**松开**分支（seat_clicked :894 / tile_clicked
		# :899 / cancel_clicked :901），而按下分支（:885）只设 `_dragging`。反例：桌垫上左键按下
		# （转发，`_dragging = true`）→ 转盘上右键按下（被实体消费，不转发）→ 右键松开：左键还
		# 按着，`:902` 不会清 `_dragging`，松开就命中 `:900-901` 发出 cancel_clicked ——
		# 一次明明被实体吃掉的点击，却给 2D 板子送了个取消。
		if not mb.pressed and mb.button_index == _consumed_press_btn:
			_consumed_press_btn = MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()
			return
		var pos = screen_to_viewport(mb.position)
		if pos == null:
			# 打不到桌面 = 这次事件谁也收不到，旗标留着没意义（兜底；配对的按下/松开其实已被上面
			# 两条拦掉）。只清**同一个键**的：旗标按键记，只可能被同一个键的松开消费，
			# 别的键打不到桌面时顺手清掉反而有害 —— 旗标一没，那个还没到的配对松开就会照常
			# 转发进 2D，正是下面反例里的事故。
			if mb.button_index == _consumed_press_btn:
				_consumed_press_btn = MOUSE_BUTTON_NONE
			return
		# 实体物件优先：命中转盘 / 手牌等实体则消费掉，不再送进 SubViewport。
		# 只判按下：一次点击消费一次即可，松开的收尾由上面的旗标分支负责。
		# 按键原样传进实体层（左/右键语义不同，见 on_table_click 的签名说明）。
		if mb.pressed and on_table_click.is_valid() \
				and bool(on_table_click.call(pos as Vector2, mb.button_index)):
			_consumed_press_btn = mb.button_index
			get_viewport().set_input_as_handled()
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
