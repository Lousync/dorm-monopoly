class_name TableView3D
extends Node3D
## 2.5D 桌面容器（见 doc/development/plans/v0.5.0-布局2.5D.md §二 / §6.1）。
##
## 结构：本节点（Node3D）持有 3D 场景 —— 桌面板 + 相机 + 灯 —— 以及一个 SubViewport，
## 现有 BoardView 原样住在那个 SubViewport 里。屏幕层 HUD 在 game 上，叠在 3D 之上。
## 输入由本节点映射：屏幕点 → 相机射线 → 水平桌面 → UV → SubViewport 像素 → push_input。

const TABLE_W := 8.0             # 桌面宽度（世界单位）
const VP_SIZE := Vector2i(2048, 2048)   # SubViewport 分辨率（清晰度靠它，见设计稿 §十 风险）
const CAM_TILT_DEG := 50.0       # 俯角：0 = 平视，90 = 正俯视。
                                 # **批次 12 A2b 量过、没动**：抬它换来的格宽远不如收 `CAM_FOV`，
                                 # 且会把 3D 端推向 2D 端、手牌斜切读不出 —— 逐档实测与理由
                                 # 写在下面 `CAM_DIST` 那段的 A2b 一节，别只看这一行就想抬它。
const CAM_FOV := 39.0            # 收窄默认 75°：探针实测默认 FOV 下桌面只占屏 1/4。
                                 # **批次 12 A2b：55 → 39**（用户「棋盘比例放大，现在字还是有点小」
                                 # 的第二遍）。**本批唯一真买到"格子更大"的那一味**，为什么俯角
                                 # 换不到、它换得到，写在下面 `CAM_DIST` 那段的 A2b 一节里。
                                 # 它只改**近大远小的比例**、不改相机的**角度** —— 观感是"给这台
                                 # 相机换了一支长焦"，仍是"坐在桌边看桌子"那一眼；代价是透视变平
                                 # （近端格子不再"扑上来"），换来 3D 端格宽 41.2 → **47.3px**。
                                 # ⚠ **改它必须同步改 `CAM_DIST` / `VIEW_DIST_2D`**（相机要按取景
                                 # 余量往后退，否则桌垫出画）；另外 `hand_rect`（手牌命中盒）是拿
                                 # 3D 相机把牌**投回画布**算的 ⇒ `hud_test` 的「牌底可点条带」
                                 # （69.1 / 58.8 → 61.0 / 45.9）也跟着这一味走，必须重取。
## 相机到注视点的水平距离（3D 端）。
##
## **批次 5 Task 2 重调过（5.8 → 5.2）、批次 10 Task 2 又收到 4.7**：桌面从 8×8 变成
## "窗口比例的浅桌"（进深跟着窗口走，见 TEX_WINDOW_PX；批次 10 收窄木纹后是 8×5.63、
## 连木框共 9.4×7.03）。5.8 是按"8×8 的方桌"定的，对今天这张浅桌就偏远了。
##
## 4.7 是拿**三条量**夹出来的（批次 10 T2 逐档扫描，见下）。**取景判据 = 桌垫四角**
##（设计 §3 定案：要全程入画的是"看得见的棋面" = 桌垫 `TABLE_SIZE`；木纹是"桌子本身"，
## 第一人称下它伸出画面是自然的）：
##   * 桌垫四角在**整条视角轨道**（21 档）上都在画面内：最紧 **81.6px @ wt=0.00**、
##     两端 **81.6 / 112.1px**（layout_test 的取景断言量的就是它；每档余量
##     81.6 90.2 92.9 90.5 88.7 87.3 86.4 86.0 85.9 86.3 87.0 88.2 89.6 91.4 93.6 96.0 98.7 101.7 104.9 108.4 112.1）。
##     ⚠ **这里原写"按木桌四角量（±5.2 / ±4.28）、最紧 93.4px"—— 那句话把 93.4 贴错了角**：
##     93.4px 是**桌垫四角**（±4 / ±3.076）在 CAM_DIST 5.2 下的余量，而**木桌四角**在 3D 端
##     **只有近端两个出画**（本档实测 **-74.6px**）、**远端两个一直在画面内**（**+183.9px**，
##     整条轨道上最紧仍 +50.7px）。原注释还写"四角全出画"—— 那句**不是**被"最紧 -108.1px"
##     证伪的（"最紧"按定义是**最小余量**，最紧为负与"四个角全出画"可以并存）。真正的证伪是
##     **远端两个角一直在画面内**（本档 +183.9px）—— 有一对角在画面内，"四角全出画"就不成立。
##     layout_test 从头到尾量的都是桌垫 —— 取景判据也以它为准
##    （把 93.4 当"木桌的余量"读，会以为木纹还有取景预算）。别再改回去。
##   * 3D 端 ↔ 2D 端桌面投影面积比 **≈0.9**（须在 [0.6,1.6]）。
##   * **批次 10 时最紧的一条是台灯的可见性**（灯罩屏幕包围盒与画面相交占比 ≥ 0.5）——
##     **批次 12 A1 删掉可见几何之后这条前提整个消失**（没有灯罩要留在画内了）⇒ 这条
##     "别再调小"的限制随之作废；**批次 12 A2 才能把 4.7 一路收到 4.15**。
##     ⚠ 但"**别再调小 CAM_DIST 而不重取灯的位置**"那句的另一半仍然成立：光本身的
##     `LAMP_LIGHT_POS` 与整套光照参数是配着取的，动相机**不动光**是对的（这次就是），
##     动光就得重取 `LAMP_ENERGY` / `LAMP_ATTEN`（见那两段）。
## 再远则棋盘上的字更小、白占屏幕（**批次 12 A2 实测**：最远端那格屏幕宽 3D 端
## **40.9px** / 2D 端 **50.0px** —— 批次 10 是 37.6 / 42.8px；见 layout_test 的「格子屏幕宽」断言）。
##
## ⚠ **3D 端到不了设计稿说的 44px，卡在哪一条要写清楚**：设计稿给的是 4.15，但那条**实测会红**
## —— 顶住的不是台灯（那条已随 A1 作废），而是**取景**：`layout_test` 要求**整条轨道 21 档上
## 桌垫四角都在画面内、余量 > 5px**。50° 俯角下**最靠相机那个角**（近左：x=-4、z=+桌垫半深）
## 的水平余量随相机推近掉得最快 —— 实测 4.7 → **83.9px**、4.15 → **-18.2px**（出画）。
## 解析式（本档的几何下）：`余量 = 640 − 3072 / (d − 0.643 × 桌垫半深)`，`d = CAM_DIST / cos50°`
## ⇒ 余量 > 5px 要求 `d ≥ 6.63`、即 `CAM_DIST ≥ 4.26`；把余量留到 **13px** 取 **4.30**
##（= 本档实测 40.9px，就是这条轨道上 3D 端的**上限**）。
## **要真的到 44px，只能动镜头本身**（收窄 `CAM_FOV`：投影面积不变而四角余量变宽 ——
## 45° 下同一份余量能换约 43px；或把 `CAM_TILT_DEG` 调大）。两件都改变 3D 端的整体观感，
## **超出本批次（只调距离）的范围**，所以留在这里如实记档。
##
## ---- **批次 12 A2b：镜头真的动了 —— `CAM_FOV` 55 → 39，本常量 4.30 → 5.77** ----
## 上一段把"抬俯角"与"收镜头"并列成两味等价的药。**实测定档之后发现两者成色差着一大截**：
##
## * **抬俯角（`CAM_TILT_DEG`）几乎换不到东西**。距离不动、φ 一抬，相机就被**顶高**
##   （`dist/cosφ` 随 φ 单调增）⇒ 一切都变小（`depth_far = dist/cosφ + 桌垫半深·cosφ` 单调增）。
##   抬 φ 唯一的好处是**放宽取景**（近端那两个角在屏幕上收窄 ⇒ 允许把 dist 压小），
##   而 dist 的下界**不是取景、是手牌整排要留在屏内**：牌心在 z≈3.164，它到屏幕下沿的余量
##   `≈ z_h·sinφ / ((dist/cosφ − z_h·cosφ)·tan(vfov/2))` 随 φ 变大而**变小**
##   ⇒ **抬俯角挣来的取景余量，正好被手牌那条吃掉**。探针扫过（每一档都取"手牌仍在屏内"
##   允许的最小 dist）：50° → 41.2px、56° → 41.5、60° → 42.0、64° → 42.8、72° → 45.0、
##   **76° → 46.5** —— 要 47px 得把 3D 端推到 **76°**（2D 端才 88°），
##   而手牌（`HAND_TILT_DEG` 20°，几乎平躺）在 76° 下被看成 56° 斜切、卡面读不出来，
##   3D 端"坐在桌边"的身份也整个没了。**⇒ 俯角这一味不划算，本批一点没动它。**
## * **收镜头才管用**。格宽 `w = 400·tile_world / (depth_far·tan(vfov/2))`，而取景把
##   `depth_near·tan(vfov/2) ≥ 2.52` 钉死（近角水平余量 > 5px）⇒ 收窄 FOV 会让
##   `depth_far·tan(vfov/2)` 往 `depth_near·tan(vfov/2)` 靠（**近远两端的大小差被压掉**），
##   格宽随之变大，而相机同步往后退、取景余量守住。逐档实测（每档相机都退到"余量刚够"）：
##   55° → 41.2px、48° → 43.5、44° → 45.2、42° → 46.0、40° → 46.8、**39° → 47.3**、38° → 47.7px。
##   取 39°（47.3px、余量 11.6px）—— 再收下去透视更平、收益只剩 0.4px/档。
## * **它改的是"近大远小"的比例，不是相机的角度** ⇒ 观感是"换了一支长焦"，不是"把相机抬起来"，
##   比抬俯角便宜。代价：近端格子不再"扑上来"（透视变平）—— 如实留痕。
## * 两端同一条镜头 ⇒ 2D 端同步退到 `VIEW_DIST_2D` **9.20**（2D 格宽 50.0 → 53.2px），
##   面积比 **0.97**（A2 是 0.92）。
const CAM_DIST := 5.77

## 3D 端**注视点往近端挪**多少（世界单位，+z = 近端）。
##
## 为什么需要它：手牌那排坐在**桌垫前沿的木纹带**上、比桌垫本身还靠前，而相机一直正对
## **桌心**（`look_at(Vector3.ZERO)`）⇒ 手牌整排的下半截（描述区 + 品质条）落到**屏幕下沿之外**。
## 批次 12 A2b 之前的注释只论证过"手牌要留在屏内"，**判据用的是牌心**、也没有断言，
## 于是这个切边一直没人管（`--shot` 出图里肉眼可见）。现在 `layout_test` 有断言了
##（"整排手牌都在屏内"，量的是 `hand_rect` 四角投影回屏幕的 y）。
##
## 注意它**只挪注视点、不挪相机位置、也不改 FOV** ⇒ 格宽（字号那一半的分母）分文不取，
## 只是把构图整体在屏幕上**上移**：腾出来的上方留白本来就有富余（桌垫上沿离画面上边
## 还有一百多像素），下沿则原本**-42.8px 出画**（实测）。
## 按 `view_t` 插值：2D 端手牌本就淡出、也不需要这一挪 ⇒ `view_t=1` 时回到原点，与从前一致。
const LOOK_NEAR_Z_3D := 0.45

# ---- 批次 4：双视角。滚轮沿一条轨道在 3D 第一人称 ↔ 2D 桌面之间连续推移
#（`dolly` 推拉整个删除，见设计稿 §四）。view_t ∈ [0,1] 是这条轨道上的位置。
const CAM_TILT_2D_DEG := 88.0    # 2D 端俯角：接近正俯视（只看桌上地图；手牌在这一端淡出，
                                 # 看不见也就点不到，见批次 4 Task 2）
const VIEW_DIST_2D := 9.20       # 2D 端「相机到注视点的 3D 距离」。**不是随手取的估值**，
                                 # 是拿两条断言、对着出图把值夹出来的（批次 10 T2 收到 7.6）：
                                 #   * 为什么这个距离要跟俯角**一起**插值：不是为了"防近边溢出"——
                                 #      那个说法实测是**反的**（**当时**量的：桌垫还是 8×8 方桌、
                                 #      CAM_DIST 还是 5.8）：把距离固定在 3D 端的 9.02、只插角度，
                                 #      底边余量是 35.1 / 21.9 / 54.2 px（wt=0/0.5/1.0），**比当时那条
                                 #      曲线还宽松**；近边溢出只出现在"距离固定在 2D 端"那种假想曲线上。
                                 #      真正的理由是**让两端的桌面占屏比例接近**（面积比 0.86）：
                                 #      只插角度的话 2D 端桌面会明显缩水。代价是**距离插值收紧了取景**——
                                 #      中段出现一个比两端都紧的取景点（见①）。别把这条当"防溢出推导"读。
                                 #   ① 整张桌垫（`TABLE_SIZE` 的四角 —— **不是**木桌四角）在整条轨道上
                                 #      **四个角都不许出画面**。俯角越大，桌面在屏幕竖直方向上的
                                 #      投影越长（8 格：sin50°≈6.1 → sin88°≈8.0）—— 中段那个最紧
                                 #      的点正是它与上面那笔距离插值两头夹出来的。
                                 #      沿轨道扫 21 档实测（**本档最终值**：CAM_DIST 4.7 + 本常量 7.6）：
                                 #      **最紧的一档落在 3D 端**（wt=0.00、余量 **81.6px**），两端
                                 #      **81.6 / 112.1px** —— 收相机后 3D 端成了全轨最紧的一处，
                                 #      "中段最紧"是批次 5~9 的旧形态（当时 3D 端离得远、中段被那笔
                                 #      距离插值压得最紧）。别把"中段最紧"当成不变量。
                                 #（**下面这些数全是同一个口径（桌垫四角 = layout_test 量的那组角），
                                 #  只是相机 / 桌垫换过版，别读成"两种口径"**：10.9px @ wt=0.45（两端
                                 #  35px 上下）是 **CAM_DIST 5.8 + 8×8 方桌**（批次 5 Task 2 把距离收到 5.2
                                 #  之前）那一版量的，今天拿 5.2 去量同一个 ±4 方桌是 **-29.5px（出画）**
                                 #  —— 那是相机版本之差，不是角的集合之差；93.4px 是**收到 5.2 之后**
                                 #  那一版（桌垫已裁成 8×6.15）；批次 10 T1（桌垫 8×5.63、相机仍 5.2）
                                 #  是 124.2px @ wt=0.40。取 8.6（**那一版**）就是把当时的下界抬到
                                 #  有余量处 —— **本档是 7.6**，别把 8.6 读成现值。）
                                 #   ② R42：两端桌面投影包围盒的**面积比**要落在 [0.6,1.6]
                                 #（只钉「四角在画面内」是可以骗过去的 —— 把距离调大让桌面整体变小，
                                 #      四角照样在画面内，而 2D 端就成了张缩水的小图）。
                                 #      **7.6 实测面积比 0.86**（两端一起收就守得住这条 —— 与批次 9
                                 #      的 0.86 同值；只收 2D 端会把它顶到 1.0 以上，抬回 8.6 又会
                                 #      掉到约 0.67 ⇒ 2D 端缩水）：两端大小接近，2D 端仍是"整屏桌面"。
                                 # 7.6 是**同时**满足①（余量 81.6px ≫ 5px）与②（0.86 ∈ [0.6,1.6]）
                                 # 再往上抬 2D 端的那一档；真正把 3D 端卡住的是 `CAM_DIST` 那条
                                 #（台灯可见），本常量只管 2D 端与两端比例。
                                 #
                                 # ---- **批次 12 A2b：7.6 → 6.63 → 本常量 9.20**（相机换了镜头）----
                                 # 这两次是**同一条约束下的两个值**，别当成"来回改"：
                                 #   * A2（`CAM_FOV` 仍 55）：3D 端收到 `CAM_DIST` 4.30 ⇒ 为了让两端
                                 #     面积比仍是 ~0.9，2D 端也得跟着收 ⇒ **6.63**（2D 格宽 50.0px）。
                                 #   * A2b（`CAM_FOV` 55 → **39**）：镜头一收、同样的取景要求相机**退**
                                 #     到 3D 端 5.77 ⇒ 2D 端同步退到 **9.20**。
                                 #     实测：2D 余量 **> 11.6px**（整轨最紧那处仍在 3D 端）、
                                 #     面积比 **0.97**（A2 是 0.92）、2D 格宽 **53.2px**。
                                 # ⚠ **本常量与 `CAM_FOV` 是一套的**：改 FOV 就必须按"2D 端余量 + 面积比"
                                 # 两条重取它（`layout_test` 的两条断言 + 格宽下限都会红）。
const VIEW_STEP := 0.25          # 滚轮每格改多少（4 格从 3D 走到 2D）
const VIEW_SNAP := 6.0           # 平滑逼近速率：每秒把剩余差距衰减 e^-6（帧率无关的指数逼近）

# 纹理窗口 = **桌垫**（棋盘 + 一圈留白），不再铺满整张画布。座位栏已随批次 5 Task 2
# 退场（桌上那块 3D 立牌也随批次 9 退场）⇒ 画布不再需要为它们预留，批次 2 推迟的
# 「棋盘铺满桌面」比例目标在这里兑现：
# 窗口宽 = `BoardView.MAT_WINDOW_W`、与 `BoardView.MAT_RECT`（桌垫的世界矩形）同比例、
# 且水平垂直都在画布正中 —— 取景（`BoardView.fit_overview`）正是按这个关系把桌垫内容
# 铺成这一块。于是桌面上看到的 = 一块居中的桌垫 + 外圈的木桌（见 _build_table 的第二个平面）。
#
# **批次 12 A2 按新的 MAT_RECT 重算过**（MAT_MX/MT/MB 40/40/90 → 18/18/64 ⇒ 桌垫
# 2096×1474 → **2052×1426**，宽高比 1.42198 → 1.44039）：
#   ratio    = 1426.0 / 2052.0 = 0.694932…
#   size.y   = MAT_WINDOW_W(2020.0) × ratio = 1403.76
#   position = ((2048 − 2020)/2, (2048 − 1403.76)/2) = (**14.0**, **322.12**)  # 画布 2048²、居中
# ⇒ 连带 `TABLE_D = 8 × 1403.76/2020 = 5.559`（批次 10 是 5.626 ⇒ 桌面更"扁"一档）。
#
# **改窗口必须两边一起改**：`BoardView.MAT_RECT` / `MAT_WINDOW_W` 与之同源，
# layout_test 有一条断言钉住"桌垫比例 == 窗口比例且居中"。
#
# 历史（别丢掉这条教训）：批次 2 的 T4c 曾把窗口裁到 Rect2(0, 348, 2048, 1700) 让「棋盘铺满桌面」，
# 而当时上家的**座位栏**在画布 y∈[16,211]、正落在被裁掉的顶部 —— 在画布内、却在窗口外，
# 桌面上既看不见也点不到，指向性道具（交换生 / 跑腿券 / 强拆令）选不中上家。
# 那时裁定"交互优先于比例"、恢复整张画布。今天座位栏已不在画布上，那条约束随之解除。
const TEX_WINDOW_PX := Rect2(14.0, 322.12, 2020.0, 1403.76)
# 桌面进深：与窗口同比例，否则贴图会被拉伸。
const TABLE_D := TABLE_W * TEX_WINDOW_PX.size.y / TEX_WINDOW_PX.size.x
const TABLE_SIZE := Vector2(TABLE_W, TABLE_D)
## 木纹外框的宽度（世界单位）：桌垫之外铺木纹的那一圈。桌面平面本身**不放**到这么大 ——
## 见 _build_table 里"第二个平面"的做法与理由。
##
## **批次 10：1.2 → 0.7**（设计 §4.2）。它只买"桌子边"的观感，而设计 §3 定案取景判据是
## **桌垫四角**（不是木桌四角）⇒ 木纹本来就不必为取景留预算，收窄它反而让桌垫（=棋盘）在
## 屏幕里更大一圈。0.7 世界 = **176.75 画布像素**（画布 2020 px / 8 世界 = 252.5 px/世界）。
## **两条级联**（改了它就必须跟着改，见设计 §4.5）：① 光节点坐在这一圈木纹带上 ⇒
## 带子一窄，光就会悬到桌外（今天光在 x=-4.127、带子是 [4.0, 4.42]，layout_test 有断言）；
## ② `HAND_BASE_PX` 那排手牌也摆在近端这条木纹带上 ⇒ 带子一窄，整排必须往桌垫那侧挪。
##
## **批次 12 A2 实测定档：这一项不动（设计稿的初值 0.42 被手牌那条级联否掉）**。
## 设计稿给的是 0.42（= 106 画布像素宽的一条带子），**照做会红**：手牌那排的
## **屏幕投影脚印**（`hand_rect`，拿 3D 相机把牌投回画布算的）满手 5 张时高约 **175~200 画布
## 像素**（批次 12 A2 把相机从 4.7 收到 4.15 之后又大了约 15%），而 0.42 的带子只有 106px：
##   * `layout_test` 的「手牌都还在木桌之内」是**世界口径**（`|z| ≤ TABLE_D/2 + WOOD_FRAME`），
##     0.42 下木桌半深只剩 3.20，而牌心在 z≈3.21 ⇒ **立刻红**（把整排往上挪又能过，
##     但那样牌身会越出桌沿约 30px、画面上就是"牌浮在桌子外面"）；
##   * `hud_test` 那条「整排落在近排格子之下」也要它待在近排格子（画布 y≈1663）**之下**。
## ⇒ **这一项的真实下界由手牌那排订出来，不是取景**：0.7（= 176.75px）刚好托得住整排。
## 想真正收到 0.42，得**同时**缩手牌（`HAND_CARD_W/D`）或把整排挪进桌垫下沿那条留白 ——
## 两件都超出批次 A 的范围（手牌归批次 B 的 ⑨）。**别只改这一个数就交差**。
const WOOD_FRAME := 0.7

# ---------------- 批次 6：台灯（唯一主光源） ----------------
#
# **批次 13 ⑨（用户原话「删除桌面旁的其他 3D 物体」）：房间剪影整段删除。**
#
# 删的是**桌子之外的全部可见物件**：三面墙 / 书架 / 床架（原先各是一组 `BoxMesh`，
# 共用一份近黑材质），连同 `ROOM_*` 九个常量、`room` / `room_mat` 两个成员、
# `_build_room` / `_room_box` / `_build_bookshelf` / `_build_bedframe` 四个方法与它们那段
# "剪影可辨靠一层极弱自发光底光（`ROOM_EMISSION`）"的推导。
#
# **为什么删得掉**（判据，不是"用户说了就删"）：
#   * 剪影当年（批次 6）是为了"近黑屋子里的一盏台灯"那套观感服务的 —— 屋子**只做剪影**
#     是因为拿不到外部素材（设计稿 §九 补记 1）。用户 ⑨ 要的正是"桌旁不要别的物件"
#     ⇒ **意图反转**：那套氛围本批也一并反掉了（⑧ 要的是"桌面完全均匀"，见 LAMP_ATTEN 那段），
#     剪影与均匀照明是同一套观感的两半，留着一半反而更怪。
#   * 它们**不参与任何玩法 / 命中 / 取景**：不投影、不吃点击（`_room_box` 一律
#     `SHADOW_CASTING_SETTING_OFF`），`layout_test` 当年量它们的也只有"近黑 / 高粗糙 / 不透明 /
#     共用材质 / 不压桌子 / 不投影"这几条 —— 随载体一起删。
#
# **留下来的两件**（都不是"物件"，别顺手也删了）：
#   * `WorldEnvironment`（背景近黑 + 环境光）—— 那是**暗底**，不是物体；
#   * `lamp_light`（那盏 `OmniLight3D`）—— 全场**唯一光源 + 唯一投影源**，删了桌面全黑、影子全丢
#     （它的**可见几何**批次 12 A1 就已删净，本批只动它的参数，见 LAMP_* 那几段）。

## 那盏灯 = **唯一的主光源**（**批次 12 A1：台灯的可见几何已整体删除，光原地保留**）。
##
## **删的是什么、为什么**（用户 ①「台灯先去掉」）：删的是**看得见的灯罩那套**（底座 / 灯杆 /
## 灯臂 / 灯罩四个 `MeshInstance3D`），**不是光** —— 这盏 `OmniLight3D` 是全场**唯一**的光源、
## 也是**唯一**的投影光源（批次 6 定案）：直接删光会让屋子变全黑、实体影子全丢。
## 代价（如实留痕，设计 §一①）：**光的来源不再有可视载体**，观感上变成"窗外透进来的一束暖光"。
## ⇒ 今天树里**没有**名为 `Lamp` 的节点（layout_test 有一条反向契约钉它），只有 `LampLight`。
##
## **光的位置 = 旧灯罩里那一点**（`LAMP_LIGHT_POS`）：杆高 / 臂长 / 灯罩倾角 / 罩内偏移四项
## 合成出来的**同一个世界点**，光照参数（色 / 能量 / 射程 / 衰减 / 阴影）一个都没改 ——
## 所以这次删除对画面的唯一影响就是"少了那件实物"，光池的形状与亮度逐位不变。
## （**"一个都没改"是 A1 当时的事实**；**批次 13 ⑦⑧**把能量 / 射程 / 衰减与光的 y 整套重取过
## —— 见那三个常量各自的段落，别再拿这一句当今天的现状。）
## 下面这些"底座 / 灯杆 / 灯罩"的字样一律按**历史**读（位置怎么夹出来的仍然有效，
## 实物已经不在了）。
##
## 位置的四条尺子（50° 俯角 + 相机在近端 ⇒ 桌边这条"可见、又压不到棋盘"的缝很窄。
## **批次 10 收窄木纹框（1.2 → 0.7）之后这四条一起收紧**，括号里是重取的实测值）：
##   ① **在桌垫之外**（平面落点 |x| > 4.0）—— 否则光就压在棋盘上（layout_test 那条窗口断言）。
##      **真正的约束节点是灯里的光，不是灯罩**（灯罩绕 Z 倾了 18°，光是它的子节点、
##      局部坐标 (0, -0.075, 0)，一倾就被带到 +x 侧 0.0232）⇒ 光的 x = 底座 + 臂长 + 0.0232；
##   ② **在画面之内** —— 50° 俯角下屏幕左侧的点越往近端（z 越大）越贴边 ⇒ **z 要小**。
##      批次 10 T2 把 z 从 1.0 挪到 **0.0**（木纹带正中）—— 那一档正是被"灯罩可见性"顶出来的；
##      **批次 12 A1 删掉可见几何之后这条尺子作废**（没有实物要留在画内了），但光本身
##      **不动**：位置是照着旧灯罩那个点取的，动了就得重取整套光照参数；
##   ③ **不是一团黑影** —— 灯罩的屏幕位置不落在桌垫的屏幕四边形内（**该断言随 A1 一并删除**）；
##   ④ **底座外缘不越木桌外沿** —— `|x| + 底座半径(0.24) ≤ 木桌半宽`。取 -4.35（底座中心
##      落在左侧木纹带正中）；**该断言随 A1 一并删除**。
const LAMP_BASE := Vector3(-4.35, 0.0, 0.0)    # 历史上底座落点（桌心为原点；木纹带上）；今天只用于推导光源位置
## 灯杆高（历史）。**固定波 A**：2.3 → 2.8 —— 光池要铺满整张桌面，灯就得再抬一截：
## 灯越低，远端那半张桌子吃到的是越贴地平线的"擦边光"（入射角小 ⇒ 余弦因子把它再压一道），
## **当时（杆 2.3）出图实测远端列只有近端的 1/9**。抬高之后远端入射角变大，桌面从
## "左角一盏、右边全黑"变成"整块都在池里"（批次 10 T2 重取：棋盘逐列均值
## 0.250 0.149 … 0.057 0.083 0.184，**总体下落、中间有起伏** —— 见 `LAMP_ATTEN`）。
## **注意池心仍在桌垫左沿、搬不到桌心**：光节点不许压上桌垫 ⇒ 桌面上离它最近的点永远是左沿。
## 抬杆抹平的是"远端塌陷"，不是池心的位置（这条是几何定的，别指望靠调杆高解决）。
##
## **批次 13 ⑦⑧：2.8 → 10.071329**（用户 ⑧「取消桌面亮度的渐变」；光的水平位置不动 ⇒
## 这是**唯一**能改的几何量）。理由：桌面上的照度里有一项是**余弦因子 N·L**（入射角），
## 灯偏在 x=-4.13、只吊 2.8 高时，近灯那一列的 N·L ≈ 0.70、最远那一列只有 0.30 —— 这一项
## **与阴影 / 衰减都无关**，所以批次 6~12 那种"调衰减 / 调能量"的手法永远抹不平它（实测左右 4.4:1）。
## 抬到 10.0 之后 N·L 收到 0.96 ~ 0.76（全表极差 1.33:1，含环境光后 1.28:1，见 `LAMP_ATTEN` 那段的新表）。
## 抬杆的**顺带好处**：影子变短（灯越高、桌面实物的影子越短，原先 2.8 高时转盘 / 牌堆的影子拖得长）。
## 代价（如实留痕）：**"坐在桌边被一盏侧灯照着"的侧向感淡了**，光更像从上方罩下来 ——
## 这正是 ⑧ 要的"完全均匀"的另一面，别再往回调 y。
const LAMP_POLE_H := 10.071329                # 历史上灯杆高（光的 y 由它 + 罩内偏移合成）
## 灯臂长（历史）：从杆顶朝桌心（+x）探出去一点。**批次 10：0.60 → 0.20** —— 这一项是被上面那把
## 尺子①**夹出来的**：木纹框收到 0.7 之后，灯罩的平面落点（= 底座 + 臂长）必须仍在桌垫之外
## （|x| > 4.0），而底座又必须留在木桌里（|x| + 0.24 ≤ 木桌半宽）。
## **臂长上界 = 4.35 − 4.0 − 0.0232 = 0.3268**（再长光就落进窗口）。取 0.20 让光落 **-4.127**，
## 离桌垫左沿还有 **0.127** —— 灯罩的可见几何已删，这一项今天只参与推导光的 x。
const LAMP_ARM_LEN := 0.20
## 灯罩的罩内偏移（历史）：光挂在灯罩里、口沿之上一点点（露在口外的话灯光会"漏"到罩子上方）。
## 0.075 = 罩高 0.50 × 0.15。罩子已删，这一项今天只参与推导光的 y（`LAMP_LIGHT_POS`）。
const LAMP_IN_SHADE := 0.075
const LAMP_SHADE_TILT := 18.0                  # 灯罩倾角（历史：它把光带向 +x 侧 0.0232）
## **光源的世界位置**（**批次 12 A1 定案**）：= 旧台灯"灯罩里那一点"的世界坐标。
## 逐项合成（照着当年的层级抄下来，一个数都没重取）：
##   * 底座 `LAMP_BASE` = (-4.35, 0, 0)；
##   * 灯罩挂在 `(LAMP_ARM_LEN, LAMP_POLE_H, 0)`，绕 Z 倾 `LAMP_SHADE_TILT`；
##   * 光是灯罩的子节点、局部 `(0, -LAMP_IN_SHADE, 0)` —— 一倾就被带到
##     `(+LAMP_IN_SHADE·sin18°, -LAMP_IN_SHADE·cos18°, 0)` = **(+0.023177, -0.071329, 0)**。
## ⇒ x = -4.35 + 0.20 + 0.023177 = **-4.126823**、y = `LAMP_POLE_H` − 0.071329。
##
## **批次 13 ⑦⑧**：**只有 y 变了**（2.728671 → **10.0**，见 `LAMP_POLE_H` 那段），
## **水平位置 (x, z) 一个数都没动** —— 这是 controller 的裁定，理由是可执行的：
## 有一类断言钉着"**光源的平面落点必须在桌垫窗口之外**"（= 光不许压在棋盘上，`layout_test` 里
## 那条 `TEX_WINDOW_PX` 断言）。把灯挪到桌子正上方（x → 0）会让那条**立刻红**，而它背后的
## 意图（灯不许压在棋盘上）本批**并没有反转**。抬 y 不动 (x, z) 正好绕开这个冲突：
## 平面落点还是 x = -4.126823（画布 x ≈ -18px，仍在窗口外），而桌面上的余弦因子被抬杆抹平。
##
## **别"顺手挪一点"水平**：整套光照参数（`LAMP_ENERGY` / `LAMP_RANGE` / `LAMP_ATTEN`）都是
## 对着这个点取的，挪了就得全部重取（本批就是这么重取的 —— 但那是因为 **y** 变了）。
const LAMP_LIGHT_POS := Vector3(-4.126823, 10.0, 0.0)
const LAMP_COLOR := Color(1.0, 0.86, 0.66)     # 暖光（白炽灯那种偏橙）
## 台灯的能量。**批次 13 ⑦⑧：3.9 → 1.2。**
##
## **为什么必须跟着降**（这一项是"改了衰减就必须重取能量"那条约定的实例，见 `LAMP_ATTEN`）：
## 本批把衰减压到 0 ⇒ 照度 ≈ `能量 × 形状(N·L)`，**与到灯的距离基本无关**（见 `LAMP_ATTEN` 的
## 新表）。原来那 3.9 是配着 0.72 的衰减取的 —— 衰减那 0.72 次幂在近端只有 0.376、
## 在远端的距离上只剩 0.205，能量里有一大半是用来"把远端补回来"的。衰减一压平，
## 那部分就成了**纯过曝**：近灯那一列（桌垫左角）的直射照度会是改动前的 **~3.6 倍**
##（同一代理式的口径：旧参数 **1.006** → 能量仍取 3.9 时 **3.65**），字与格底一起推到 1.0。
##
## **取 1.2 的判据**（`layout_test` 的新断言 + 出图，两条一起）：
##   * 桌面各采样点的直射照度落在 **0.84 ~ 1.12**（近灯角最高、远端角最低）—— 与改动前
##     **"整块棋盘均值 0.1266"** 是同一量级（新的更亮一点点、但**极差从 4.4:1 收到 1.33:1**）；
##   * 出图复核：`shots/b13_level_table_plain.png` / `b13_table_plain.png` 里棋盘四角与中心的
##     **格内文字都读得出、没有一片白斑**（口径：同 `LAMP_ENERGY` 历史那套 —— 3D 端出图、
##     按格坐标取区域、`Color.get_luminance()`、饱和 = 亮度 ≥ 0.95）。
##
## **历史（改这一项之前那套取值，别按它调）**：批次 3 那盏顶灯是 energy 2.4 + 环境光 0.55；
## 批次 6 **固定波 A**：2.6 → 3.5 → **3.9**（原值下桌面均值只有批次 5 的一半：0.057 对 0.128，
## 观感是"把原来那张桌子调暗了"）。当时的上界是"别把棋盘左沿烤白"，实测口径：**棋盘左列**
## （col 0 × rows 0..11）均值 **0.250**、饱和 **300/20067（1.49%）**、最大连通块 **42px**、
## 峰值 0.995（没有连成一片白斑）；**棋盘整块**均值 **0.1266**。那套数是**衰减 0.72 下**量的，
## 衰减一改就不适用了 —— 留着只为说明"3.9 不是一个可以照搬的绝对值"。
## **要再动能量，先看 `layout_test` 那两条新断言**（均匀度 max/min ≤ 1.4、直射照度 0.5~1.8）。
const LAMP_ENERGY := 1.2
## 射程：**够到桌垫四角**。**批次 13 ⑦⑧重取**：灯抬到 y = 10 之后，桌垫四角到灯是
## **9.42 ~ 12.44**（远端角 = 右前/右后那两个；**不是**木桌四角 —— 木桌四角更远）。
##
## **为什么从 12.5 放到 30.0**：射程在本批**不只是"够不够得到"**，它就是**亮度渐变的第二个来源**。
## Godot 的 omni 衰减（`drivers/gles3/shaders/scene.glsl` 的 `get_omni_spot_attenuation`，
## Compatibility 用的就是这个后端）是
##   `atten = max(1 − (d/range)^4, 0)^2 × d^(−attenuation)`
## —— **`attenuation`（指数）压到 0 只干掉了后一项**，前一项 `(1 − (d/range)^4)^2` 还在：
## 12.5 的射程下远端角 (d/range = 0.995) 会被它**乘到 0**、而近端角还剩 0.98 —— 一条比原来更陡的
## 边缘渐变。放到 30 之后（远端角 d/range = 0.41）前一项只从 0.98 落到 0.94，**几乎平**。
## ⇒ 判据写成 `远端角 ≤ 0.9 × 射程`（layout_test 那条），今天实测 12.44 ≤ 27 有厚余量。
##
## **注意：背景"近黑"不是这一项管出来的** —— 桌子之外看到的是**背景色**
##（`Environment.background_color` 直出、不过光照）。所以别拿 `LAMP_RANGE` 去调背景明暗
##（调不动，只会连桌子一起改）；见 `_build_environment`。
## **批次 13 ⑨删掉房间剪影之后，这一项也不再会"把书架床架洗白"**（它们不存在了）。
const LAMP_RANGE := 30.0
## 衰减指数（越大掉得越快）。**批次 13 ⑦⑧：0.72 → 0.0**（用户 ⑧「取消桌面亮度的渐变」）——
## **这是本批的核心一笔**，也是**对批次 6 / 10 那套"近黑房间 + 一盏台灯 + 中心亮四周暗"的有意反转**。
##
## **0.0 的含义**：上面那条公式里的 `d^(−attenuation)` 变成 `d^0 = 1` ⇒ **照度与距离无关**，
## 桌面上的明暗只剩两件事决定：**余弦因子 N·L**（灯偏在一侧 ⇒ 近端列亮、远端列暗）与
## **射程那一项**（放到 30 后几乎平，见 `LAMP_RANGE`）。前者由 `LAMP_POLE_H` 抬杆抹平。
##
## **改动前的实测（历史，别拿去当今天的余量）**：批次 6 **固定波 A**：1.15 → 0.85 → **0.72**；
## 批次 10 T2 出图逐列均值（3D 端，col0 → col17）：
##   0.250 0.149 0.142 0.156 0.148 0.129 0.124 0.140 0.153 0.138 0.112 0.087 0.080 0.076 0.071 **0.057** 0.083 0.184
## ⇒ 池心（col0，灯正下方）0.250、最暗 **col15 的 0.057** ⇒ **左/右比 4.4:1**（批次 5 均匀光下是 1.04:1）。
##
## **批次 13 ⑦⑧的新口径**（`layout_test` 的 `_mat_sample_irradiance`：桌垫四角 + 中心 5 点，
## 按渲染器那条公式估直射照度 = `能量 × (1−(d/range)^4)^2 × N·L`）：
##   | 采样点 | d | N·L | 直射照度（能量 1.2） |
##   |---|---|---|---|
##   | 近左角（±2.78 各一个） | 10.39 | 0.963 | **1.12** |
##   | 桌心 | 10.82 | 0.924 | 1.07 |
##   | 远右角（±2.78 各一个） | 13.18 | 0.759 | **0.85** |
## ⇒ **极差 1.12 : 0.85 = 1.33:1**（再叠加**与位置无关**的环境光 0.45 × 0.425 ≈ 0.19 ⇒ **1.27:1**；
## layout_test 实测打印 1.314 / 1.035 = 1.27）。
## 断言钉的是**含环境光的那一条 ≤ 1.4**（含环境光更贴近渲染器与"人眼看到的桌面"，见 layout_test）。
##
## **回归会红在哪（同一代理式、同一组采样点，改动前那套参数）**：能量 3.9 / 射程 12.5 / 指数 0.72 /
## 光高 2.73 ⇒ 5 点估出 **1.091 / 0.214 = 5.1:1**（近左角 1.09、远右角 0.21）——
## 比出图逐列实测的 **4.4:1** 还狠（那是另一个口径：屏幕上逐列取像素均值），
## 两种口径都远在 1.4 之外 ⇒ layout_test 那条"桌面各位置亮度一致"必红。
## **注意两条断言各守一半**（实跑验证）：把 0.72 **单独**调回来时，射程 30 下只有 `d^-0.72`
## 那一项在动 ⇒ **均匀度那条仍绿**（实测 1.24），红的是"直射照度"那条（远端角掉到 0.13）；
## 把**光挪回 2.73 高**（其余不动）⇒ 均匀度 **1.88 红**、"直射照度"也红（远端角 0.357）；
## **射程收回 12.5**（远端角被 `(1−(d/range)^4)^2` 乘到 0）⇒ 按同一公式均匀度 **2.66**，
## 且"远端角 ≤ 0.9 × 射程"那条同时红（13.18 > 11.25）。⇒ 想退回旧观感，得跨过好几条。
const LAMP_ATTEN := 0.0

var board: BoardView
var viewport: SubViewport
var camera: Camera3D
var table_mesh: MeshInstance3D
var wood_mesh: MeshInstance3D       # 木纹外框（桌垫之外那一圈木桌，见 _build_table）
var vignette: ColorRect        # 屏幕层暗角贴片（build_vignette 造，挂在调用方给的屏幕上）

var table_mat: StandardMaterial3D   # 桌面材质（取样窗口与 TEX_WINDOW_PX 同源）

## `lamp_light` 是**全场唯一**的灯（批次 6；**批次 12 A1 起台灯的可见几何已删**，
## 树里没有 `Lamp` 节点，只有这个名字叫 `LampLight` 的光 —— 见 `_build_lamp`）。
var lamp_light: OmniLight3D

## 实体物件层：与桌垫共用同一套 UV 坐标系，物件都挂这里（见设计稿 §五）。
## 桌垫（table_mesh）只是"印在桌上的画"；转盘 / 两摞牌堆 / 手牌这些有厚度、
## 能投影的实体一律挂 props，摆位走 canvas_px_to_world。
var props: Node3D

## 实体物件的构建与刷新（转盘 / 两摞牌堆 / 手牌，见 scripts/table_props.gd）。
## 挂在 props 下、与桌垫共用同一套坐标；由 game.gd 在收到首个状态后驱动 build_wheel。
var table_props: TableProps

## 桌面上的实体被点中时先问这里；返回 true 表示已消费（不再送进 SubViewport）。
## 签名：`func(canvas_px: Vector2, button: int) -> bool` —— **按键一起带过去**，因为实体对不同
## 键的语义不同（手牌：左键选中 / 右键丢弃；转盘：只吃左键），只给位置的话实体层无从分辨。
## 默认无效（Callable()），即不拦截任何点击 —— 只有 game.gd 接上后才有实体可点。
var on_table_click: Callable = Callable()

## 鼠标在桌面上移动时先问这里；签名 `func(canvas_px: Vector2) -> int`，返回被悬停的 peer
## 或 `GameData.NO_PEER`。**默认无效（Callable()），即谁都不悬停** —— 与 `on_table_click`
## 同一种注入方式（只有 game.gd 接上后才有反馈）。
##
## 与点击那条的区别：**悬停不消费输入** —— 问完之后这次 motion 照旧转发进 SubViewport
##（2D 那边的悬停高亮还要），所以这里只是"顺路问一句"，没有返回值的使用者（返回 peer 是给
## 调用方 / 测试读的）。
## 拿不到画布点（射线打不到桌面）时**仍会调一次**，传 `Vector2.INF`：悬停是"每一动都重算"的
## 语义，漏掉这一动会让信息条留在上一枚棋子上不掉（旧 2D 那条链每个 motion 都会重算）。
var on_table_hover: Callable = Callable()

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
## 变化的两半，只做一半就会**静默脱钩**（相机动了、手牌却还按旧视角显示 / 命中）。
## 早先靠"唯一更新点是 `_apply_camera`"这条**约定**；但 `view_t` 是公开 var，谁一句
## `view_t = x` 都能绕过去。手牌正要用同一个推送点（淡出按 view_t 算），
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
	_build_table()
	_build_lamp()           # 唯一光源（批次 12 A1 起只有光，没有实物 —— 见 _build_lamp）
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
	# **批次 13 ⑦⑧：0.20 → 0.45**（用户 ⑧）。环境光**与位置无关**（它不过那盏灯的几何），
	# 所以它是"桌面均匀"这件事上的**第二根、也是唯一不会偏心的一根**杠杆：
	# 直射光那一份再平也还有 N·L 的残余（1.33:1），环境光按 albedo × 能量 × 色 均匀铺一层，
	# 把极差压到 **1.27:1**（见 `LAMP_ATTEN` 那张表）。抬它的第二个理由是**暗部读字**：
	# 抬 y 之后灯对桌面的入射角虽然更"正"了，但**灯偏在一侧**这件事没法消除 ⇒ 远端那两列
	# 的暗部只有靠环境光托。**它管不到"桌子之外"**：那里看到的是背景色（BG_COLOR 直出、
	# 不过环境光），所以抬它不会把四周点亮（背景仍是近黑 —— layout_test 那条断言钉着）。
	#
	# **上界（别再加）**：环境光一高，"一盏灯照亮桌面"这件事就没了形状（桌面变成一块死平的光），
	# 而且它与灯的暖色是**叠加**的 ⇒ 太高会把整张桌子洗成灰白。layout_test 钉区间 [0.30, 0.75]
	# （下界防"又压回去、远端读不出字"，上界防"死平 + 洗白"）。
	#
	# 历史（别按它调）：批次 6：0.55 → 0.10 → **0.20**（固定波 A）。0.10 那一档**压过头了**：
	# 光池之外的桌面（右半张、木桌右圈）几乎归零，观感是"把桌子调暗"而不是"照亮桌子"。
	e.ambient_light_energy = 0.45
	env.environment = e
	add_child(env)

# ---------------- 批次 6：唯一主光源（批次 12 A1：可见几何已删，光保留） ----------------

## 建**唯一**的光源（`lamp_light`，节点名 `LampLight`）。
##
## **批次 12 A1**：原先这里还建台灯那四件实物（底座 / 灯杆 / 灯臂 / 灯罩），用户 ① 要求
## "台灯先去掉"⇒ 四件连同只服务于它们的材质 / 常量一起删掉，**只留光**。
## 光的世界坐标写死成 `LAMP_LIGHT_POS`（= 旧灯罩里那一点，见那段推导）——
## 于是光照表现与删之前**逐位相同**，唯一的变化是"那件碍事的灯罩没了"。
##
## 光今天**直接挂在本容器下**（不再挂在灯罩的子节点上）：当年"光源是灯罩的子节点"是为了
## 让光跟着斜的灯罩走（父节点一分家就得手动重算位置）—— 灯罩没了，那条理由随之消失，
## 直接挂本节点反而少一层要维护的层级（位置就是世界坐标，一眼对得上 `LAMP_LIGHT_POS`）。
##
## **批次 13 ⑦⑧**：光照参数整套重取过（`LAMP_ENERGY` 3.9 → 1.2、`LAMP_RANGE` 12.5 → 30、
## `LAMP_ATTEN` 0.72 → 0.0、光源 y 2.73 → 10），**但"只有一盏灯、它开着阴影"这两条没变**：
## 它是全场唯一的投影源（手牌 / 牌堆 / 转盘 / 棋子 / 房子的影子全来自它）。
func _build_lamp() -> void:
	lamp_light = OmniLight3D.new()
	lamp_light.name = "LampLight"
	lamp_light.position = LAMP_LIGHT_POS
	lamp_light.light_color = LAMP_COLOR
	lamp_light.light_energy = LAMP_ENERGY
	lamp_light.omni_range = LAMP_RANGE
	lamp_light.omni_attenuation = LAMP_ATTEN
	# 批次 3 为"桌上实物能投影"重开的阴影，本批跟着换成这一盏：**全场唯一投影的光源**。
	# 影子方向从此由它决定：光在**左侧**木纹带上（x≈-4.13）⇒ 影子整体朝右拉；
	# z 那一维按物件自己在光的哪一侧分（位置在 z=0）。
	# **批次 13 ⑦⑧**：光抬到 10 高之后影子**短了一截**（灯越高、投影越接近正下方）。
	# 影子只投影在**桌面 / 其它实物**上 —— 房间剪影已随 ⑨ 删除，不再有"落在墙上"的影子。
	lamp_light.shadow_enabled = true
	add_child(lamp_light)

func _build_table() -> void:
	table_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = TABLE_SIZE       # PlaneMesh 躺在 XZ 平面，中心在原点；宽 × 进深
	table_mesh.mesh = pm
	table_mat = StandardMaterial3D.new()
	# 不能用 UNSHADED：那样灯与环境光对棋盘一点作用都没有，桌面只是一块死平的贴图
	# ——**桌上物件的影子也会落在桌面上**（唯一投影源就是那盏灯），UNSHADED 收不到影子。
	# 走默认的逐像素着色。（批次 13 ⑧ 反转的只是"中心亮四周暗"的**分布**：均匀照明下桌面
	# 仍吃灯与环境光，只是各位置一样亮 —— 别把这条读成"当年那套渐变还要"。）
	# 顺带开 alpha 混合 —— 画布（SubViewport.transparent_bg）的透明像素由此交给环境背景，
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

	# ---- 桌子底座（一期 Task 5 Step 0，2026-10-05 用户拍板；spec §六「地板高度与桌子底座」）----
	# 地板降到 `GameRoom.FLOOR_Y`（真实桌高）之后，一叠"桌垫 + 一圈木纹"在画面上就是**悬在屋里
	# 的一块板**。补一块从地板顶到木纹外框底面的裙板，桌子才读作"摆在屋里的一张桌子"。
	#
	# 三条约束：
	#   * **别动木纹外框本身的位置**（`wood_mesh.position.y = -0.012`）—— Task 7 的取景判据量的
	#     就是它；底座顶面顶到它的**底面**（-0.012），两层不共面。
	#   * **尺寸 = 木纹外框那两维**（`TABLE_W * 0.5 + WOOD_FRAME` / `TABLE_D * 0.5 + WOOD_FRAME`）。
	#     Task 7 Step 0 会把它们提成 `WOOD_HALF_W` / `WOOD_HALF_D`，届时这两行改成那两个常量。
	#   * **一律 `cast_shadow = OFF`** —— 房间的纪律，全场唯一投影源仍是那盏吊灯。
	var base_mesh := MeshInstance3D.new()
	base_mesh.name = "TableBase"
	var bm := BoxMesh.new()
	bm.size = Vector3((TABLE_W * 0.5 + WOOD_FRAME) * 2.0, -0.012 - GameRoom.FLOOR_Y,
		(TABLE_D * 0.5 + WOOD_FRAME) * 2.0)
	base_mesh.mesh = bm
	base_mesh.position = Vector3(0.0, (GameRoom.FLOOR_Y - 0.012) * 0.5, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = UIKit.tex("res://assets/textures/wood_floor.jpg")
	bmat.albedo_color = wmat.albedo_color            # 与外框同一份木色（底座是"桌子本身"那一圈）
	bmat.roughness = 0.88
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bmat.texture_repeat = true
	bmat.uv1_scale = Vector3(bm.size.x / 3.0, bm.size.z / 3.0, 1.0)   # 每 3 世界单位一轮，同外框那条
	base_mesh.material_override = bmat
	base_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base_mesh)

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
## 0.86），批次 5~9 的代价是**中段会出现一个比两端都紧的取景点** —— 但**批次 10 T2 之后
## 最紧的一档挪到了 3D 端**（wt=0.00、余量 81.6px；两端 81.6 / 112.1px）：相机一近，3D 端
## 自己成了全轨最紧处，中段那笔距离插值的"夹"反而松了。别把"中段最紧"当不变量。
## 别把这条读成"距离不插值就会溢出"：实测反了（批次 5 的几何下量的）—— 把距离固定在 3D 端的
## 9.02、只插角度，底边余量是 35.1 / 21.9 / 54.2 px（wt=0/0.5/1.0），**比当时那条曲线更宽松**；
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
	# 注视点：3D 端往近端挪一点（把整排手牌带回屏内），2D 端回原点（见 LOOK_NEAR_Z_3D）。
	var look := Vector3(0.0, 0.0, lerpf(LOOK_NEAR_Z_3D, 0.0, view_t))
	if camera.is_inside_tree():
		camera.global_position = pos
		camera.look_at(look, Vector3.UP)
	else:
		camera.look_at_from_position(pos, look, Vector3.UP)
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

	# ---- 3D 房间（一期）：挂在容器自己名下（节点名 `Room`）----
	# 挂在这里（3D 场景与桌垫都已就绪之后）而不是 `_init` 的最前面：房间不参与任何玩法，
	# 只需"桌子已经在那儿"。它**只摆位与长相**，一行玩法都不碰。
	# `ROOM_ENABLED=false` 时 `build()` 返回 null（本期的保命开关，退回到"只有桌子"的样子）
	# ⇒ 这里**不能**当成必然拿到节点用（下一行没有别的话要接它，是故意的）。
	# `TABLE_SIZE` 一起传进去：四把椅子要围着桌子摆，房间得知道桌子多大（**只收这个数**，
	# 房间仍然不反向依赖桌子 —— 与 `LAMP_LIGHT_POS` 同一条规矩）。
	var room := GameRoom.build(self, LAMP_LIGHT_POS, TABLE_SIZE)

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
			# 打不到桌面：这一动谁都不悬停 —— 也要通知一次（传 `Vector2.INF`），
			# 否则悬停信息条会留在上一枚棋子上不掉（见 `on_table_hover` 的说明）。
			if on_table_hover.is_valid():
				on_table_hover.call(Vector2.INF)
			return
		# 实体层先问一句（与点击同一条注入点）：鼠标压在一枚棋子/实体上时由 game 决定悬停到谁
		#（屏幕层信息条的显隐）。**不消费** —— 下面照旧把这一动转发进 SubViewport。
		if on_table_hover.is_valid():
			on_table_hover.call(pos as Vector2)
		var fwd := InputEventMouseMotion.new()
		fwd.position = pos
		fwd.relative = Vector2.ZERO      # SubViewport 内不靠相对位移做平移
		fwd.button_mask = mm.button_mask
		viewport.push_input(fwd)
