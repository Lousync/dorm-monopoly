class_name TableProps
extends Node3D
## 桌面上的实体物件（见 doc/development/plans/v0.5.0-桌面实体化-设计.md §五）。
##
## 只负责「摆在哪、长什么样」：坐标一律由桌垫 UV 坐标系换算（TableView3D.canvas_px_to_world），
## 命中判定只回一个布尔 —— 掷轮 / 用道具这些后果由 game.gd 决定，这里不碰任何玩法逻辑。

## 转盘轮缘的内 / 外沿，相对「画出来的轮子半径」的比例。对着出图定的：
## WheelView 由内到外是 扇区 0~0.93R、金属外圈 0.91~1.0R（R = 200 `_world` 局部像素）。
## 取 0.82~1.02 —— 内沿压住那圈金属外圈并略微进到扇区里，外沿比轮子外径宽 2%。
## 为什么是这个宽度：再细（比如 0.92~1.02）圆环就细成一根线，看不出体积、也投不出影子；
## 再粗就开始吃掉扇区颜色。**关键是它必须是环**：中间的盘面、13 个数字、转动动画
## 全部透空可见 —— 那些是玩法反馈（board_view.gd:_build_wheel「点数来源，掷点时镜头对准它」），
## 不是装饰。实心圆盘 / 圆柱会把它整个盖住，玩家就看不到转到几点了。
const RIM_INNER_R := 0.82
const RIM_OUTER_R := 1.02
## 命中半径 = 画面半径 × 它：轮缘外沿再放宽一圈，手指不容易点空。
## 放宽 20% 仍然离最近的其它可点物很远（左右两个牌堆的近边在 2.1R 处）。
const HIT_SLACK := 1.20
## 轮缘中心面离桌垫的高度（世界单位）。圆环与桌垫**不共面**（没有一个面贴在桌垫上，
## z-fighting 无从谈起），所以不必垫高，取一点小值即可：管子下半截沉在桌垫之下（看不见），
## 露出来的只是一道矮棱。抬得越低越好 —— 相机会把「离桌面的高度」投影成屏幕上的一段位移，
## 抬得越高，实体相对桌垫图案就越"漂"（实测抬 0.08 世界单位时，默认取景下屏幕上移约 17px）。
const PROPS_Y := 0.02

# 尺寸口径：**实物是世界常数，图案才跟 `_zoom`** —— 这条区别是故意的，不是漏改。
#
# **例外是"压在印刷图案上"的那两件：转盘轮缘与两摞牌堆**（`build_wheel` / `build_decks` 里
# 量真变换、随 `_zoom` 变）：它们必须与**印在桌垫上的**那块图案重合，而桌垫图案随 2D 镜头
# 缩放，不跟就会脱开 —— 所以**位置与尺寸都要跟**（牌堆的尺寸那一半是修复波 F 补的）。
# 手牌是**自由立在桌上的实物**：相机推近是"你凑近看"，
# 不是"桌子变大了"，实物不该跟着长 —— 所以它的尺寸写死在世界单位里。
#
# 手牌还多一层：它的**命中矩形**必须跟玩家看到的位置一致，那要过相机
#（`hand_rect` 是量真投影，不是常数）—— 尺寸是世界常数与命中盒跟相机，
# 这两件事互不矛盾：一个说"牌多大"，一个说"你在屏幕上点哪儿算点到它"。
#
# 摆放约定（物件 vs 2D 相机，2026-10-03 终审 I1 定案；批次 6 Task 3 + 修复波 F 修订）：
# **跟 2D 相机的只有"压在印刷图案上"的那两件 —— 转盘轮缘与两摞牌堆；
#   手牌一律不跟**。
#   轮缘 — 位置来自 `board.wheel_screen_pos()` / 半径来自 `board.wheel_screen_radius()`
#          （量真变换）：它必须贴**印在桌垫上的**那个轮盘，而桌垫图案随 2D 取景缩放 ⇒ 跟着走。
#   牌堆 — 位置来自 `board.deck_screen_pos()` / 尺寸来自 `board.deck_screen_size()`（同形）：
#          **同一个理由**（它要盖住印着的那摞卡背）⇒ 位置与尺寸都跟。修复波 F 补的正是尺寸
#          那一半 —— 原先只跟位置，抽卡推近 2× 时印刷图案整体胀大而摞不动，**只盖住图案的
#          约四分之一**（面积比），而那正是玩家盯着牌堆的那一刻。
#   手牌 — 位置走**画布常量**（`HAND_BASE_PX`）：它是**自由立在桌上的实物**，
#          不该因为"印出来的图案"变了而移动。相机推近是「你凑近看」，
#          不是「桌子被重新排版」。
# **代价**：2D 取景一变（`fit_overview` / `focus_grid` / 人数变化），桌垫图案整体滑动、而
# **不跟相机的手牌**纹丝不动 ——「手牌落在自己面前那条桌垫上」这些断言**只在全景取景下成立**。
# 必须继承这条决定（实物不跟相机）。
# **批次 8 起"抽卡推近"这个变量没了**：抽卡演出搬到屏幕层（`scripts/deck_reveal.gd`）、
# **相机全程不动** ⇒ 原先"抽卡那一刻图案滑动、实物不动"的错位从根上消失（用户 ① 报的正是它）；
# 与之配套的那条"演出期间 `game._process` 逐帧重推"也一并删掉（不再有逐帧的取景变化要跟）。
# 跟随本身仍在：取景 / 聚焦 / 人数变化之后，跟图案的两件由 `game._refresh_board_followers`
# 重推（位置与尺寸一起）；那条挂在**状态广播**上（`_refresh_table_props`）—— 不伴随广播的
# 纯镜头变化（摆拍用的 `focus_grid`）要跟着变，得自己再调一次。
# 本条原先挂的"轮缘要不要补每帧跟 `_zoom`"到这里结清：**要，而且与牌堆同一处升级**。

## 批次 7：**筹码堆（现金）与体力件（体力）整体退场** —— 身家读数搬到屏幕四角的四角身家条
##（大字身家 + 小字现金，见 table_hud.CORNER_SLOTS），体力归批次 9 的玩家道具弹窗。
## 理由是桌面减负（用户要求）：筹码只是"身家的量级示意"、与四角身家条重复；体力件是同一份
## 数据的第二个落点。**别再把它们加回来**：`layout_test` 里有"接口与节点都已退场"的反向契约。

var _t3: TableView3D
var _wheel_px := Vector2.ZERO
var _hit_r := 0.0                 # 命中半径（画布像素）
var _rim: MeshInstance3D
var _rim_mesh: TorusMesh

func setup(t3: TableView3D) -> void:
	_t3 = t3

## 在画布坐标 center_px、画面半径 radius_px（**都是画布像素**）处摆好转盘的轮缘实体。
##
## 幂等：节点只在第一次建，之后每次调用只**重算 transform 与 mesh 尺寸**。
## 为什么每次都要重算：半径是 `200 × _zoom`（BoardView.wheel_screen_radius），
## 而 `_zoom` 会被取景 / 抽卡推近 / 人数变化改动（**滚轮不碰它**：滚轮改的是 3D 视角 `view_t`，
## 与 2D 的 `_zoom` 无关）—— 只建一次的话，
## 实体就会跟桌垫上画出来的轮子脱开。game.gd 在每次状态广播时重调这里。
func build_wheel(center_px: Vector2, radius_px: float) -> void:
	if radius_px <= 0.0:
		return
	_wheel_px = center_px
	_hit_r = radius_px * HIT_SLACK
	# 画出来的轮子在桌面平面上的半径（世界单位）：**直接量真变换**，量出来的就是摆位用的那条映射。
	# 不要另写一份"画布像素 ÷ 某个尺寸"的推导 —— canvas_px_to_world 走的是 TEX_WINDOW_PX
	#（贴图窗口），不是 VP_SIZE；**窗口是裁出来的桌垫区**（批次 5 Task 2 起，两者数值已不同：
	# 批次 10 起是 2020×**1420.55** vs 2048²），它们是两个独立的旋钮 —— 窗口改了，位置仍走
	# 真变换（对的）、半径却会静默失配（不报错、只是轮缘与盘面对不上）。
	var r: float = (_t3.canvas_px_to_world(center_px + Vector2(radius_px, 0.0))
		- _t3.canvas_px_to_world(center_px)).length()
	if _rim == null:
		_rim = MeshInstance3D.new()
		_rim.name = "WheelRim"
		_rim_mesh = TorusMesh.new()
		# Godot 的 TorusMesh 躺在 XZ 平面（轴朝 Y），正是一张平桌上该有的朝向。
		# **两个半径是"环的径向范围"、不是"管子半径 + 环心半径"**：inner_radius = 孔洞边缘、
		# outer_radius = 外沿（默认 0.5 / 1.0 就是孔洞占外径一半的那个甜甜圈）。
		# 管子半径 = (outer - inner) / 2。出图核对过：按"管子半径"那套理解去填，
		# 会得到一个孔洞只有针尖大、几乎盖住整个轮子的胖甜甜圈。
		_rim_mesh.rings = 48
		_rim_mesh.ring_segments = 12
		_rim.mesh = _rim_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.55, 0.24)   # 铜金轮缘，接 WheelView 的金属外圈
		mat.metallic = 0.6
		mat.roughness = 0.35
		_rim.material_override = mat
		add_child(_rim)
	# 尺寸：环的径向范围直接乘比例（孔洞边缘 / 外沿），单位世界。
	_rim_mesh.inner_radius = r * RIM_INNER_R
	_rim_mesh.outer_radius = r * RIM_OUTER_R
	# 摆位：画布像素 → 桌面世界坐标（与桌垫同一套 UV 坐标系），再落到桌面上（见 PROPS_Y）。
	var w: Vector3 = _t3.canvas_px_to_world(center_px)
	w.y = _t3.table_mesh.global_position.y + PROPS_Y
	_rim.global_position = w      # canvas_px_to_world 给的是世界坐标，按世界坐标落位

## 命中判定：画布像素是否落在转盘上。
func wheel_hit(canvas_px: Vector2) -> bool:
	return canvas_px.distance_to(_wheel_px) <= _hit_r

# ---------------- 两摞实体牌堆（批次 6 Task 2） ----------------
#
# 桌垫上最后两处"贴片"（画布上印着的机会 / 命运两摞卡背，见 board_view._build_deck）的实体化。
# 每摞 = **若干层薄 BoxMesh 叠出厚度**，摆在画布坐标下那摞卡背的**中心**上
# （`board.deck_center` → `board._view_from_world` 折成画布像素 → `canvas_px_to_world`，
# 与其他物件同一条链）。
#
# 为什么是"叠几层薄板"而不是"一整块砖"：牌堆的辨识度全在**层与层的错缝**上 —— 等厚的方砖在
# 50° 俯角下只是一坨有影子的色块。错缝量对着出图定：每上一层往"远左"收一点（方向与量级同
# 画布上那 3 张错位卡背），叠出来的轮廓正好接住印着的那摞卡背。
#
# **位置与尺寸都跟印着的那块图案走**（`build_decks` 每次收到的是**当下取景**下的画布像素与
# 脚印），与转盘轮缘同一个理由：它要接住的正是那块印刷图案（见文件头"摆放约定"里那一条）。
# **唯一的刷新路径是状态广播**（`game._refresh_table_props` → `game._refresh_board_followers`）。
# 原先还有一条"抽卡演出期间逐帧重推"（批次 8 起删掉）：它兜的是抽卡那次 ≥2× 推近，
# 而演出已搬到屏幕层 `DeckReveal`、相机全程不动 ⇒ 前提消失，逐帧路已从 `game._process` 移除。
# **尺寸那一半是终审修复波 F 补的**：原先只有位置跟图案、尺寸写死世界常数，于是取景一变
# 印刷图案整体胀大 / 缩小而摞不动、**只盖住图案的约四分之一**（面积比），而那一刻正是玩家盯着牌堆。
# 现在两个"跟印刷"的物件（轮缘 / 牌堆）口径一致：**位置 + 尺寸都从 BoardView 取**
#（`deck_screen_pos` / `deck_screen_size`），3D 侧只把画布像素换算成世界单位（量真变换）。
#
# **身份不能丢**（brief 第 2 条）：实体摞盖住的正是画布上印着的卡面图案**与压在它正中的那块
# 牌名小牌**（`board_view._build_deck` 的 tplate 就在牌堆正中）。"只盖卡背、留住标签"这条路
# 走不通：标签在图案正中，而摞也该摆在正中，除非去挪 2D 那块标签 —— 那是 BoardView 的改动，
# 本批次 BoardView **共改两处**（`deck_screen_pos` / `deck_screen_size` 两个只读查询，
# 见 doc/development/开发台账.md；与 :225 那段的「那两处查询」同一口径）。
# 所以选**在摞顶面平贴一个 Label3D**：文字 + 配色两重信号，3D 端与 2D 端
# 都读得到（2D 端接近正俯视，平贴的文字最清楚）。被盖住的牌名小牌不影响识别；它下面那行
#「落在【机会】格时从这里抽卡」在摞的外面（图案下沿之下），仍看得见。

## 每摞的层数。**必须 > 1**：一层就是一整块砖，那正是这一条要治的"贴片感"；
## 也是「有厚度」那条断言的可执行判据。
const DECK_LAYERS := 5
## 单层厚度（世界单位）：比手中牌（0.030）薄得多 —— 一张牌不该和一块砖一样厚。
## 5 层叠起来 0.05 世界单位 ≈ 13 画布像素（全景取景下），一眼看得出是"一摞"。
const DECK_LAYER_T := 0.010
## 每上一层往"远左"收的画布量（**世界单位**，≈ 2.5 画布像素）：
## 与画布上那 3 张错位卡背的 (6,6) 同一方向（下层偏近右、顶层偏远左）。
## 4 层错开共 0.04 世界 ≈ 12 画布像素 —— 与印着的那摞（3 张错 12 像素）正好一个量级。
const DECK_LAYER_SHIFT := 0.010
## 单张牌的尺寸（世界单位，宽 × 厚 × 进深）—— **只在"没报脚印"时兜底**（见下）；
## 建 mesh 时的初值也用它，真正的尺寸在 `build_decks` 里当帧就被 `_apply_deck_footprint` 覆盖。
##
## **宽 / 进深不是准数**（终审修复波 F）：它们由 `board.deck_screen_size(deck)` 报的**画布像素
## 脚印**经真变换换算而来 ⇒ **跟着 2D 取景缩放**，与转盘轮缘同一条口径（`build_wheel` 量半径那套）。
## 这里这一份只留给"调用方没报脚印"（`size_px` 为空：旧调用 / 红跑）那一条路。
##
## 它的值 = 印在桌垫上那 3 张错缝卡背的整体脚印在**全景取景**下的世界尺寸：
## 单张 90×135、3 张各错 (6,6) ⇒ 整体 102×147（`_world` 局部单位）× 全景 `_zoom`(0.96374)
## ÷ 252.5（2020 画布像素 = TABLE_W 8 世界）⇒ **0.389 × 0.561**。
##（**批次 10 重取**：全景 `_zoom` = `MAT_WINDOW_W / MAT_RECT.size.x`，随桌垫留白收窄从 0.9116
##  变成 0.96374 ⇒ 同一份脚印落在桌垫上的世界尺寸大了 5.7%，兜底值跟着改
##（0.368×0.531 → 0.389×0.561）。**只有兜底这一路受影响**：正常路径每次都由
##  `deck_screen_size` 报的脚印覆盖，值本身不参与玩法 / 断言。
##  更早的历史：它是 0.40×0.58，**少乘了那个 `_zoom`**（大了约 8.7%）—— 那正是"抽卡推近下
##  盖不住图案"的一半成因，另一半是"尺寸根本没跟取景"（修复波 F 一起治了）。）
##
## **只剩一处对不齐，是既有的、核过的**：3 张错缝卡背是往 **+x / +y** 堆的（`center + (6,6)*(2-i)`），
## 所以那个脚印的**中心比 `deck_center` 偏 (6,6) 画布像素**（纵向再多 1.5，见 `_build_deck` 里那个 66），
## 而摞关于 `deck_center` 对称 ⇒ **近右那两条边各露约 6 画布像素印刷图案**（"从摞的近边露出来一条"，
## 出图里就是它）。要消掉得把 3 张卡背改成关于 `deck_center` 对称 —— 那是 `board_view._build_deck`
## 的改动（`BoardView` 本批次只准动"跟印刷图案"那两处查询），所以留着。
##
## **底直接落在桌面上**（`_place_deck` 里 y = 桌面，不再加 `PROPS_Y`）：一摞牌是"躺在桌上的"，
## 抬起来只会让它相对印刷图案在屏幕上往远端漂（`PROPS_Y` 那段说的"抬得越高越漂"）。
## 底下 5 层叠出来的 0.05 世界高仍在 ⇒ **顶层**的屏幕投影依旧往远端偏 **14~19 画布像素**
##（批次 6 Task 3 实测：全景取景 18.8、另一档取景 14.1 —— 投影是**射影**的，同一截高度在
## 不同取景下换算出的画布位移本来就不完全相等）——
## 但那是**顶层自己的位置**，不是"整摞要往上挪"的理由：
## 盖住印刷脚印靠的是**最下一层**（它就在桌面上、投影和图案同面）。
const DECK_SIZE := Vector3(0.389, DECK_LAYER_T, 0.561)
## 牌堆顶面那块牌名要不要**吃光**（`Label3D.shaded`）。默认 `false`（全亮、不吃光），
## 「读得出，但略像贴上去的」；旁边被台灯照着的手牌都有明暗。
##
## **批次 6 Task 3 试过 `true`、出图比对后保持 `false`**。量测（1280×800 真实窗口，固定屏幕
## 区域取亮度均值 `0.2126R + 0.7152G + 0.0722B`，区域就是牌名那一小块）：
##              2D「机会」            2D「命运」            3D「机会」
##   `false`  mean 0.367 p90 0.400    mean 0.177 p90 0.204   mean 0.332 p90 0.375   max 0.849
##   `true`   mean 0.377 p90 0.400    mean 0.165 p90 0.178   mean 0.343 p90 0.376   max 0.903
## ⇒ **两档肉眼几乎分不出**（区域均值差 ≤0.012；把两张图并排放大逐字比过，字形、明暗、描边
## 都看不出差），既没有"更像被灯照着的实物"这一收益，**就保持默认的 `false`** —— 少一项与光照
## 耦合的东西（灯的能量 / 衰减以后若再调，牌名可读性不该跟着变）。
## 原先的担心（"`true` 会让牌名掉进暗里"）**没有兑现**：Label3D 的 `modulate` 是自发光式的，
## 吃光之后这两块仍读得出。真要再评估，改这一个常量即可。
const DECK_LABEL_SHADED := false
## 牌面文字的量法（Label3D）：pixel_size × font_size = 一个字的边长（世界单位）。
## 0.0020 × 64 = 0.128：两个汉字并排 0.256 世界，占牌宽（全景取景下 0.368，见 `DECK_SIZE`）的 **70%**。
##（旧注释写"占牌宽（0.33）的 78%"、"（0.40）的 64%"—— 那两个数分别对应更早的两种口径；
##  修复波 F 把牌宽改成由 `deck_screen_size` 派生（全景 0.368）后按当前值重算。
##  字号是**对着出图**定的，要改它得连牌名与牌面的比例一起重核。）
const DECK_FONT_PS := 0.0020
## 两摞的**牌身**颜色：暗底、色相分明（远看一眼分得开）—— 机会 = 暗金（接 UIKit.ACCENT）、
## 命运 = 暗紫（接 board_view._build_deck 那个紫色 accent）。都压得够暗，不会在近黑的屋子里发亮。
const DECK_BODY_COLORS := {
	"机会": Color(0.43, 0.33, 0.13),
	"命运": Color(0.30, 0.25, 0.44),
}
## 两摞**牌名**的颜色：亮一档的同一族色相，压在深色牌身上仍读得出（配深描边）。
const DECK_LABEL_COLORS := {
	"机会": Color(0.97, 0.85, 0.52),
	"命运": Color(0.80, 0.75, 1.00),
}
## 牌堆名（也是节点名的后缀）由调用方给（`build_decks` 的字典键；节点名 = `Deck_<牌名>`）——
## 这里**不另立一份牌名表**：`board_view` 那两处硬编码的牌名是这套名字的唯一来源，
## 谁摆牌堆谁把名字传进来，多一份常量就多一处会漂开的数。

var _decks_root: Node3D
## 两摞的节点池：牌名 → {root}。
## **只建一次**：之后刷新只改 root 的 global_position 与那份共用 mesh 的尺寸
##（层与标签的局部位置只跟层数有关）。
## **不存 layers / mat / label**（终审修复波 G）：它们建完就没人读过 —— 层与标签挂在 root 下、
## 由 root 的 transform 一起带走，材质是逐摞一份、只在 `_make_deck` 里用过一次。
## 存着只会让人以为"刷新时还会改它们"。
## **批次 8 起连 `top_local` / `top_world` 也不存**：它们只服务于抽卡"从摞顶面抽出"的起点
##（`deck_top_px`），而演出已搬到屏幕层、不再需要起点（见文件头"摆放约定"）。
var _decks := {}
var _deck_mesh: BoxMesh              # 两摞共用一份：牌面尺寸完全一致

## 按 `decks`（**牌名 → 画布像素**中心，调用方从 `board.deck_screen_pos` 取）摆两摞实体牌堆；
## `size_px` 是这摞卡背在画布上的**整体脚印**（宽 × 进深，调用方从 `board.deck_screen_size` 取）。
##
## **幂等**：节点池只建一次，之后每次调用只**重算 root 的位置与牌面尺寸**（每次状态广播都会调它）。
## 为什么两者每次都要重算：印在桌垫上那块图案随 2D 取景（`_view_from_world`，含 `_zoom`）走，
## 摞要**盖住**它 —— 位置与尺寸都得跟（见文件头"摆放约定"与 `DECK_SIZE` 那段）。
##
## `size_px` 为空（`Vector2.ZERO`）时**保留 `DECK_SIZE` 那份世界常数**：那是没有脚印可跟的
## 兜底路（旧调用 / 红跑），不是正常路径 —— 正常路径 `game._refresh_board_followers` 每次都报脚印。
func build_decks(decks: Dictionary, size_px: Vector2 = Vector2.ZERO) -> void:
	if _t3 == null or decks.is_empty():
		return
	if _decks_root == null:
		_decks_root = Node3D.new()
		_decks_root.name = "Decks"
		add_child(_decks_root)
	for key in decks:
		var dname := String(key)
		var d: Dictionary = _decks.get(dname, {})
		if d.is_empty():
			d = _make_deck(dname)
			_decks[dname] = d
		_place_deck(d, decks[key] as Vector2)
	if size_px != Vector2.ZERO:
		_apply_deck_footprint(size_px, decks.values()[0])

## 把画布像素脚印折成世界尺寸、贴到两摞共用的那份牌面上（幂等，每次刷新都重算）。
##
## 为什么**量真变换**而不是"画布像素 ÷ 某个常数"：同 `build_wheel` 量半径那条 ——
## `canvas_px_to_world` 走的是 `TEX_WINDOW_PX`（贴图窗口），窗口一改，除常数就静默失配
##（窗口是裁出来的桌垫区，批次 10 起 2020×1420.55 与画布 2048² 从来就是两个旋钮）。
##
## 两摞共用**一份 mesh / 一份尺寸**：它们的脚印在画布上本来就是同一个（同尺寸卡背、同错缝量），
## 所以只量一次；参考点取第一摞的中心（映射是等比的，取哪一点都一样）。
func _apply_deck_footprint(size_px: Vector2, ref_px: Vector2) -> void:
	if _deck_mesh == null:
		return
	var o: Vector3 = _t3.canvas_px_to_world(ref_px)
	var dx: float = (_t3.canvas_px_to_world(ref_px + Vector2(size_px.x, 0.0)) - o).length()
	var dz: float = (_t3.canvas_px_to_world(ref_px + Vector2(0.0, size_px.y)) - o).length()
	_deck_mesh.size = Vector3(dx, DECK_LAYER_T, dz)

## 造一摞（节点只造一次）：5 层薄板 + 顶面平贴的牌名。
## 局部坐标原点 = **这摞牌堆的中心在地面的落点**（见 _place_deck）：层 0（最下）抬半层高，
## 层与层之间往"远左"收 DECK_LAYER_SHIFT（错缝），顶层再抬 DECK_LAYER_T 留给牌名。
func _make_deck(dname: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Deck_%s" % dname
	_decks_root.add_child(root)
	if _deck_mesh == null:
		_deck_mesh = BoxMesh.new()
		_deck_mesh.size = DECK_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DECK_BODY_COLORS.get(dname, Color(0.35, 0.30, 0.20))
	mat.roughness = 0.72
	mat.metallic = 0.0
	# 显式写死**不透明档**：批次 4 的教训 —— ALPHA 混合会进透明队列、不写深度、投影就废了，
	# 而 Task 1 刚把光照与阴影调到位（牌堆必须投得出影子）。别手滑改成透明。
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var half := float(DECK_LAYERS - 1) * 0.5
	for i in DECK_LAYERS:
		var mi := MeshInstance3D.new()
		mi.name = "Layer%d" % i
		mi.mesh = _deck_mesh
		mi.material_override = mat
		# 层 i：底层（i=0）往近右偏最多、顶层（i=LAYERS-1）不偏 —— 与画布上那 3 张卡背同方向，
		# 且**关于 root 对称**（±half × SHIFT），所以整摞的落点中心就是 root 那一点。
		var off := (half - float(i)) * DECK_LAYER_SHIFT
		mi.position = Vector3(off, DECK_LAYER_T * (float(i) + 0.5), off)
		root.add_child(mi)
	# 顶面：最上一层（i = LAYERS-1，off = -half × SHIFT）的**上表面中心** —— 牌名就平贴在这儿
	#（原先它还是抽卡的「抽出」起点，那个消费者已随批次 8 删除，见文件头"摆放约定"）。
	var top_local := Vector3(-half * DECK_LAYER_SHIFT, DECK_LAYER_T * float(DECK_LAYERS),
		-half * DECK_LAYER_SHIFT)
	var lab := Label3D.new()
	lab.name = "Name"
	lab.text = dname
	lab.font_size = 64
	lab.pixel_size = DECK_FONT_PS
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # 包围盒以原点为中心（居中压在顶层上）
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.modulate = DECK_LABEL_COLORS.get(dname, Color.WHITE)
	lab.outline_size = 10
	lab.outline_modulate = Color(0.02, 0.02, 0.03, 0.95)
	lab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 文字不投影（影子交给牌身）
	# Label3D 默认 `shaded = false`（全亮、不吃光）；批次 6 Task 3 试过 `shaded = true`
	#（保留描边）并出图对比：见下方常量区 `DECK_LABEL_SHADED` 那段的量测结论。
	lab.shaded = DECK_LABEL_SHADED
	# 平贴在摞顶面：Label3D 默认躺在 XY 平面、面朝 +Z；绕 X 转 **-90°** 之后法线朝上（+Y）、
	# 字头朝远端（-Z）—— 从近端的镜头看文字正是正的（转 +90° 才是倒的，那面朝下看不见）。
	# 不 billboard：它是一张印在牌面上的标签，不该随镜头转。
	lab.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	lab.position = top_local + Vector3(0.0, 0.001, 0.0)      # 抬 1mm：与顶层上表面不共面（免得 z-fighting）
	root.add_child(lab)
	# 只留**后面真会读**的一项（修复波 G）：`_place_deck` 读 root。层与标签由 root 的 transform
	# 一起带走、材质只在上面用过一次 —— 存进字典没人读，只会让人以为"刷新还会改它们"。
	# 批次 8 把 `top_local` / `top_world` 也一并去掉（它们只服务于已删的抽卡起点 `deck_top_px`）。
	return {"root": root}

## 把一摞摆到画布像素 center_px 上（层与标签的局部位置在 _make_deck 里已经摆好，这里只挪 root）。
##
## y **不加 `PROPS_Y`**：局部原点是"这摞在地面上的落点"，而层 0（最下）抬半层高、底面正好落在
## root 的 y 上 ⇒ `root.y = 桌面` 就是"最下一层躺在桌上"（见 `DECK_SIZE` 那段；牌堆是唯一
## 不加 PROPS_Y 的实物 —— 其余几件都得垫那 0.02 免得与桌垫共面闪，而牌堆的底面是**朝下的**
## 那一面、根本看不见，共面不会 z-fighting）。
func _place_deck(d: Dictionary, center_px: Vector2) -> void:
	var root: Node3D = d.root
	var w: Vector3 = _t3.canvas_px_to_world(center_px)
	w.y = _t3.table_mesh.global_position.y
	root.global_position = w

# ---------------- 筹码堆 / 体力件（批次 7 已整体退场） ----------------
#
# 原先这一段是自己现金（每 ¥5,000 一枚的筹码堆）与体力（一排用掉即灭的小件）的落地处。
# 桌面减负后两条一起删掉：身家读数在屏幕四角的四角身家条上（`table_hud.CORNER_SLOTS`），
# 体力归批次 9 的玩家道具弹窗。**别再加回来** —— `layout_test` 有"接口与节点都已退场"的反向契约。

# ---------------- 自己的手牌（道具） ----------------
#
# 一排**有厚度的实体卡**：近端、微微朝自己倾斜 —— 取代原来座位卡上那 5 个道具牌位。
# 命中判定（hand_hit / hand_rect）与状态反馈（set_hand_selected 选中 / set_hand_discard_pending
# 待确认丢弃）都在这儿；「点中之后选中谁、什么时候能出牌、右键丢弃谁」是 game.gd 的事
#（_on_table_click → _on_hand_clicked / _on_discard_clicked）。
# 约定：坐标一律 canvas_px_to_world（桌垫 UV 坐标系），
# 尺寸是世界常数（见 PROPS_Y 下面那段），刷新幂等（节点池只建一次）。

## 手牌上限 = 背包格数上限（与座位卡那排牌位一样是最多 5 个）。
const HAND_MAX := 5
## 卡的尺寸（世界单位）。**（批次 7：原以牌垫阶段按钮为地标，按钮已退场，改以桌垫下沿为地标）**
## **批次 5 Task 3 放大过（0.30/0.34 → 0.46/0.54，线性约 1.5 倍）**：
## 座位卡退场后桌垫前沿空出一条木纹留白（见 HAND_BASE_PX），批次 3 那条"再大就得压住
## 格子价格"的约束随之解除。今天实测（**批次 10 重取**：满手 5 张、3D 端取景、画布口径）：
## 整排的**屏幕包围盒**（命中盒并集）y ∈ [1724.6, 1899.4] / x ∈ [645.6, 1371.2]，
## 上沿在**桌垫下沿**（1734.3）之上 9.7 画布像素（牌是抬起来 + 倾斜的实物，投影必然往布边上
## 糊一点；批次 9 同口径是 47.0）、下沿离画布底（2048）还有 **148.6** 画布像素 ——
## 两条都是**量出来的**，不是估的（改尺寸 / 改桌垫必须重取）。
const HAND_CARD_W := 0.46        # 卡宽（世界单位；≈ 116 画布像素）
const HAND_CARD_D := 0.54        # 卡进深
const HAND_CARD_T := 0.030       # 卡厚：有厚度才投得出影子、看得出是"卡"而不是贴纸
## 相邻两张牌中心的画布间距。略大于卡宽（0.46 / 8 世界 × 2020 ≈ 116 画布像素）+ 扇形岔开的
## 投影增量：相邻两张几乎相接但不叠压 —— 叠压会让命中盒互相压住（点一张选到另一张）。
const HAND_STEP_PX := 138.0
## 扇形是**弧**不是直线：每远离中心一张，牌位往远端挪一点（外侧靠后，像摊开的一叠）。
const HAND_ARC_PX := 5.0
## 整排中心（画布像素）：自己面前那条**木纹留白**上（桌垫下沿之外、木桌之内）。
##
## **批次 10 重取（y 1862 → 1834）**：它是**画布常量**，而桌垫一缩、`fit_zoom`
##（= `MAT_WINDOW_W / MAT_RECT.size.x`：0.9116 → **0.96374**）就变 ⇒ 同一个画布像素落到另一个
## 桌垫相对位置；更何况木纹带本身也从 1.2 收到 0.7（带子变窄，整排必须往桌垫那侧挪）。
## 夹法 = 让整排（满手 5 张）在桌面上的**脚印**落在"桌垫下沿之外、木桌之内"那条带里、上下不贴线：
##   * 带子（画布 y）：桌垫下沿 = 1024 + 1420.55/2 = **1734.3** → 木桌外沿 = 1734.3 + 0.7×252.5
##     = **1911.0**（252.5 = 画布 2020px / 8 世界 ⇒ 0.7 世界 = 176.75 画布像素）；
##   * 整排脚印（5 张牌底面四角折回桌面平面）实测 **y ∈ [1745.2, 1900.3]**（高 155.1）——
##     离桌垫下沿 **10.9px**、离木桌外沿 **10.7px**。带子只有 176.8px 高，**两侧各 ~11px 就是
##     几何给出的上限**（居中即最大最小余量），**别指望再挤出余量**（要更多余量只能收卡片尺寸）；
##   * 牌心并集 y ∈ [1824, 1834]、世界 z ∈ [3.17, 3.21]（木桌半深 3.51 ⇒ 整排不越桌沿）；
##   * 命中盒并集（5 张）y ∈ [1724.6, 1899.4]：上沿在桌垫下沿**之上** 9.7px（见 HAND_CARD_W 那段）。
## **批次 5 Task 3 整体下移过（y 1551 → 1862）**。为什么必须落到桌垫**之外**：
## 放大到 1.5 倍之后，整排的屏幕包围盒高 174 画布像素，而桌垫下沿那条空档
##（近排格子下沿 1563.6 → 原阶段按钮上沿 1636.1）只有 72 像素、原按钮之下到桌垫下沿
##（1728.1 → 1800.6）又是 72 像素 —— **两个 72 都塞不下一张放大的牌**。
## 于是唯一能同时满足「明显更大」与「不压棋盘内容」的落点，就是桌垫下沿**之外**那条木纹留白
##（批次 5 Task 2 把窗口裁到桌垫之后才出现的空间；批次 7 前这条留白的上沿还横着牌垫阶段按钮）。
## 代价（已在设计里接受）：牌**不再压住任何近排格子** —— 批次 3 那条「牌底下那几格还剩
## 多少可点条带」的 R38/R40 实测值从 **11~19 画布像素（选中后外侧两张归零）** 变成
## **190.0（满手 5 张、未选中）/ 177.0（选中外侧那张，最坏档）**，牌盒与近排格子的相交处数为 0
##（`hud_test` 里那段断言已按新语义改写，实测数字也打印在那里）。这正是本条目要治的病。
## **批次 10 重取那两个数：77.0 / 63.4**（整排上移到木纹带正中 + `fit_zoom` 变大 ⇒ 近排格子
## 在画布上更靠下，缝窄了；见 `table_props.HAND_BASE_PX` 与 `hud_test` 那段的注释）。
##
## **别按"平面距离"推**：牌是抬起来又倾斜的实物，投影会把整排整体推低
##（与 PROPS_Y 那条坑同源）；也别按画布像素抄旧值（旧 1551 是"窗口 = 整张画布"时代的数、
##  1862 是"木纹带 1.2"时代的数）。
const HAND_BASE_PX := Vector2(1009.0, 1834.0)
## 每张牌朝自己倾斜的角度（绕 X 轴）：远边抬起、牌面转向镜头（相机在 +z 上方 50°）。
## 20° 是"一眼看得出是斜的、但没立起来"的位置：倾角越大牌在屏幕上越靠上、也越占高度。
const HAND_TILT_DEG := 20.0
## 扇形：每远离中心一张，绕 Y 轴向外岔开一点。8° 配合 HAND_STEP_PX 时相邻两张刚好相接。
const HAND_FAN_DEG := 8.0
## 选中的那张**抬起来**的高度（世界单位）。选中的反馈必须在**桌上这张牌自己**身上
##（座位卡那排牌位在批次 3 Task 6 就拆了，`board.set_item_selected` 今天空转）——抬起 + 提亮是它的反馈。
## 0.13 世界单位 ≈ 12 画布像素（放大后按同比例调过）。**这条只能对着"屏幕位移"定，别按世界尺寸推**：
## 抬高是竖直方向的位移，相机俯角 50° 把它压成 cos(50°) 倍，屏幕上只挪了十来像素。
## 抬起来只会**更远离**桌垫下沿那条木纹留白（往上挪），所以它不受"整排落在木纹留白里"那条约束。
const HAND_SEL_LIFT := 0.13
## 待确认丢弃时**牌身**染成的红（只改牌身材质色，**不动牌面贴图**：图标仍要认得出来）。
## 红色要压得住品质色（白/绿/蓝/紫/橙都染得红），所以饱和度取高、值取中上。
const HAND_DISCARD_COLOR := Color(0.86, 0.28, 0.26)

# ---- 批次 4 Task 2：手牌随视角淡出（看不见就点不到） ----
#
# 视角量 `view_t`（见 table_3d.gd）是**纯本地表现**：0 = 3D 第一人称（手里有牌、能出牌），
# 1 = 2D 桌面（只看地图）。手牌在这一端**淡出**，于是「出牌要回 3D」这条玩法意图不需要任何
# 玩法代码来保证 —— 只要一条规则：**看不见就点不到**（淡到 HAND_HIT_MIN_ALPHA 以下，
# `hand_hit` 直接返回 -1）。`game._on_table_click` 判手牌只走 `hand_hit`，所以 game.gd 一行不改：
# 左键选中 / 右键丢弃（那条也先取 `hi = hand_hit(...)` 再分左右键）在 2D 端自然都落空
# —— **丢弃与出牌一样要回 3D，不为它开特例**，否则「2D 端能丢牌、不能出牌」就成了半套规则。
#
# 窗口取 0.35→0.65：两端各留一段**完全**不透明 / **完全**看不见的稳定区，中间才是过渡。
## 从视角量的 0.35 起开始淡出。
const HAND_FADE_LO := 0.35
## 到 0.65 淡完（≈0）。两端各留一段稳定区：0.35 之前全不透明、0.65 之后完全看不见
##（滚轮一格 0.25 ⇒ 3D 端要滚两格才看得出变化，不会一滚就闪一下）。
const HAND_FADE_HI := 0.65
## 低于此不参与命中 —— 「看不见就点不到」那一条规则就落在这里。
##
## 取 0.15（≈ 只剩一成半）而不是 0：**这个阈值正是那条「看得见但点不到」窄带的原因**，
## 别读反了 —— 取 0 才会出现"看不见却还点得到"（那才是 bug）。数字钉住：
##   * `alpha = 0.15` 出现在 **view_t ≈ 0.576**（smoothstep(0.35,0.65,·) = 0.85 解得）；
##   * 隐藏阈值（`_apply_hand_alpha` 的 `a ≤ 0.02`，整排 `visible = false`）在 **view_t ≈ 0.625**。
##   ⇒ 那条带是 **(0.576, 0.625]**，宽 0.049 ≈ **1/5 个滚轮格**。
## **这条带可接受**：滚轮目标恒为 `VIEW_STEP = 0.25` 的倍数、再加上指数逼近，**视角永远停不在
## 带内**，只会被动画穿过几帧；反过来把命中阈值降到 0.02，会让"几乎看不清的牌"也可点 ——
## 那是更坏的取舍。
const HAND_HIT_MIN_ALPHA := 0.15

var _view_t := 0.0               # 当前视角量（由 TableView3D 推过来；手牌的显示与命中都只看它）

var _hand_root: Node3D
var _hand: Array[MeshInstance3D] = []
var _hand_body_mats: Array[StandardMaterial3D] = []   # 牌身品质色：逐张一份
var _hand_face_mats: Array[StandardMaterial3D] = []   # 牌面图标：逐张一份（贴图不同）
var _hand_mesh: BoxMesh
var _hand_face_mesh: PlaneMesh
var _hand_n := 0
var _hand_items: Array = []      # 最近一次 set_hand 的背包（重摆位置时要用，见 set_hand_selected）
var _hand_sel := -1              # 选中的那张（-1 = 都不选）；由 game.gd 同步过来
var _hand_disc := -1             # 待确认丢弃的那张（-1 = 无）；由 game.gd 同步过来

## 按背包摆手牌；items 每项形如 {"id": "招财猫", "charges": 3, "cd": 0}。
## 读的是**已同步**的状态（game.gd 用 _state_player(my_peer)），客户端同样可用。
##
## **幂等**：节点池只建一次，刷新只改 visible / 品质色 / 图标贴图 / transform。
func set_hand(items: Array) -> void:
	var n: int = clampi(items.size(), 0, HAND_MAX)
	_hand_items = items
	_hand_n = n
	if _hand_sel >= n:
		_hand_sel = -1               # 牌变少了：原先选中的那张已经不在了
	if _hand_disc >= n:
		_hand_disc = -1              # 同理：原先待丢弃的那张已经不在了
	if n <= 0 and _hand.is_empty():
		return                                  # 一直空手：连池子都不必建
	if _hand_root == null:
		_hand_root = Node3D.new()
		_hand_root.name = "Hand"
		add_child(_hand_root)
	while _hand.size() < n:
		_hand.append(_make_card())
	_apply_hand_layout()
	# 透明度由 `_apply_hand_layout` 末尾统一补贴（见那里的注释）—— 新建 / 重摆的牌不会以
	# 默认的不透明露到下一次状态广播之前。

## 选中的那张牌：抬起 + 提亮；i = -1 都不选。越界（含牌不够 5 张）当作不选。
##
## **不是**玩法状态：单一来源是 game.gd 的 selected_slot，这里只跟着画（_refresh_table_props
## 每次广播都按它重设一遍）—— 所以重摆手牌（set_hand）不会把选中态弄丢。
func set_hand_selected(i: int) -> void:
	_hand_sel = i if (i >= 0 and i < _hand_n) else -1
	_apply_hand_layout()

## 待确认丢弃的那张牌：**牌身染红**（i = -1 都不染）。**不动牌面贴图** —— 图标仍要认得出来。
##
## **不是**玩法状态：单一来源是 game.gd 的 `_discard_pending`，这里只跟着画
##（game._sync_hand_discard_pending 在设/清时立即贴一次，_refresh_table_props 每次广播再重放一遍）。
## 与选中态互斥由玩法侧保证（选中任意一张会清掉待丢弃）；万一同时给出，红色优先 —— 丢弃更"危险"。
func set_hand_discard_pending(i: int) -> void:
	_hand_disc = i if (i >= 0 and i < _hand_n) else -1
	_apply_hand_layout()

## 设当前视角量（由 `TableView3D._apply_camera` 推过来，见那里的注释）。
##
## **幂等且带早退**：值没变就直接返回 —— `_apply_camera` 每帧都调它，而摆相机本身就有早退，
## 这里同理（相同视角下重贴一遍 alpha 是白跑）。
##
## 注意「值没变就不用贴」的前提是**重摆手牌的那几条路会自己补贴**（`_apply_hand_layout` 末尾
## 统一调 `_apply_hand_alpha`）—— 少了那一笔，新建 / 重摆出来的牌会一直保持默认的不透明。
func set_view_t(t: float) -> void:
	var nt := clampf(t, 0.0, 1.0)
	if is_equal_approx(nt, _view_t):
		return
	_view_t = nt
	_apply_hand_alpha()

## 当前手牌的不透明度：3D 端 1，2D 端 0，中间是 HAND_FADE_LO→HI 的平滑过渡。
## smoothstep 而不是线性：两端多一段"几乎不变"的平缓区，滚轮走到头才明显淡掉。
func hand_alpha() -> float:
	return 1.0 - smoothstep(HAND_FADE_LO, HAND_FADE_HI, _view_t)

## 把 hand_alpha 贴到手牌上：整排的 visible + **逐张**材质的 alpha。
##
## 整排隐藏（而不是只把 alpha 调到 0）是给"淡完"那一段用的：alpha 0 的牌仍会参与排序与
## 阴影投射，白跑一份。牌身与牌面是**逐张一份**材质（品质色 / 图标各异，见 _make_card），
## 所以可以逐张改 —— 共用一份的话会把整排一起调淡（那不是本函数的问题，是材质本来就不共享）。
##
## **牌面贴图不动**：只改 alpha。贴图是"这是哪件道具"的唯一线索，染它没有意义。
func _apply_hand_alpha() -> void:
	var a := hand_alpha()
	var shown := a > 0.02
	# _hand_root 在 set_hand 之前是 null（一开始空手就不建池子）——
	# 这里必须先判空再写 visible，写成 `_hand_root.visible = _hand_root != null and shown`
	# 会在 set_hand 之前空访问崩掉（短路只保护右半边，左边那半照求值）。
	if _hand_root != null:
		_hand_root.visible = shown
	if not shown:
		return
	# 3D 端（a = 1.0）用**不透明**模式，只有淡出中（a < 1.0）才切到 ALPHA 混合：
	# 让实物无条件进 alpha 混合队列会改掉**深度写入与投影**行为 —— 批次 3 重开阴影正是为了让
	# 实物能投影，批次 6 还要重做光照，所以 3D 端必须走不透明。ALPHA 混合下 albedo_color.a 才
	# 真正起作用，淡出中必须切过去（不切就淡不动）。
	var body_mode: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_DISABLED \
		if a >= 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
	# 牌面**不能**跟着用 DISABLED：图标 PNG 带透明边，透明区在 DISABLED 下会渲染成一整块
	# 不透明方块，把图标糊在方块里（出图核对过，见 fix-wave-report 的对比图）。改用
	# **ALPHA_SCISSOR**（alpha 裁剪）：透明区照样被裁掉、图标不被糊住，而它仍在**不透明队列**
	# 里写深度、能投影 —— 正是"3D 端不进透明队列"想要的那一档。淡出中（要半透明）scissor
	# 做不到，只能切回 ALPHA 混合。
	var face_mode: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
		if a >= 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in _hand_body_mats.size():
		var m: StandardMaterial3D = _hand_body_mats[i]
		m.transparency = body_mode
		var bc := m.albedo_color
		bc.a = a
		m.albedo_color = bc
		if i < _hand_face_mats.size():
			var fm: StandardMaterial3D = _hand_face_mats[i]
			fm.transparency = face_mode
			var fc := fm.albedo_color
			fc.a = a
			fm.albedo_color = fc

## 按当前的 _hand_items / _hand_n / _hand_sel 把所有牌重摆一遍：
## 位置（扇形 + 弧 + 朝自己倾斜 + 选中抬起）、品质色（选中的提亮）、牌面图标。
func _apply_hand_layout() -> void:
	for i in _hand.size():
		var card := _hand[i]
		card.visible = i < _hand_n
		if not card.visible:
			continue
		var id := String((_hand_items[i] as Dictionary).get("id", ""))
		var d := ItemData.def(id)
		# 品质色是**数据契约**：键就是 "白"/"绿"/"蓝"/"紫"/"橙"（item_data.gd）。
		# 选中 → 提亮一档（不改品质色的语义，只是加亮）；待确认丢弃 → 染红（红色优先）。
		var q: Color = ItemData.QUALITY_COLORS.get(String(d.get("quality", "白")), Color.WHITE)
		if i == _hand_disc:
			_hand_body_mats[i].albedo_color = HAND_DISCARD_COLOR
		else:
			_hand_body_mats[i].albedo_color = q.lightened(0.35) if i == _hand_sel else q
		# 牌面：有图标素材就贴上（近端那点尺寸下，图标是"这是哪件道具"的唯一线索）；没有就只剩品质色
		var face := card.get_node_or_null("Face") as MeshInstance3D
		if face != null:
			var tex := _item_icon(String(d.get("icon", "")))
			face.visible = tex != null
			if tex != null:
				_hand_face_mats[i].albedo_texture = tex
		# 摆位：扇形（外侧岔开）+ 弧（外侧靠后）+ 朝自己倾斜
		var k := float(i) - float(_hand_n - 1) * 0.5
		var px := HAND_BASE_PX + Vector2(HAND_STEP_PX * k, -HAND_ARC_PX * absf(k))
		var w: Vector3 = _t3.canvas_px_to_world(px)
		# 卡心抬到"近边正好坐在桌面上"的高度：抬不够的话，倾斜后近边会切进桌子
		# （方块沉一半就只剩薄片：轮缘是管子、沉一半看不出来，牌是方块、不行）。选中的再额外抬 HAND_SEL_LIFT。
		# （批次 5 Task 3 起这一排落在**木桌**上而不是桌垫上，但"坐在桌面上"这条一字未改。）
		w.y = _t3.table_mesh.global_position.y + PROPS_Y + HAND_CARD_T * 0.5 \
			+ (HAND_CARD_D * 0.5) * sin(deg_to_rad(HAND_TILT_DEG)) \
			+ (HAND_SEL_LIFT if i == _hand_sel else 0.0)
		card.global_position = w
		# 欧拉序是默认的 YXZ：先绕自己的 X 倾斜、再绕世界 Y 岔开，正是"摊成扇形还都朝着我"
		card.rotation = Vector3(deg_to_rad(HAND_TILT_DEG), deg_to_rad(-k * HAND_FAN_DEG), 0.0)
	# 末尾统一补贴透明度（批次 4 Task 2）：本函数上面那一笔 `albedo_color = 品质色` 是**整份覆盖**，
	# 会把 alpha 写回 1.0 —— 半透明的牌于是会在视角不动时"弹"回不透明（选中、待确认丢弃、
	# 每次状态广播重摆都是这条路径）。放在这里而不是各调用点：重摆的每条路（set_hand /
	# set_hand_selected / set_hand_discard_pending）都经过本函数，一处收口最不容易漏。
	_apply_hand_alpha()

func _item_icon(icon: String) -> Texture2D:
	if icon == "":
		return null
	var path := "res://assets/icons/%s.png" % icon
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _make_card() -> MeshInstance3D:
	if _hand_mesh == null:
		_hand_mesh = BoxMesh.new()
		_hand_mesh.size = Vector3(HAND_CARD_W, HAND_CARD_T, HAND_CARD_D)
	var card := MeshInstance3D.new()
	card.name = "HandCard%d" % _hand.size()
	card.mesh = _hand_mesh
	# 牌身一件一份材质：品质色逐张不同，共用一份会把整排染成同色
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.62
	card.material_override = mat
	_hand_body_mats.append(mat)
	# 牌面图标：贴在顶面上的薄片。与牌身**分成两个材质** —— 图标要原色，
	# 而 albedo_color 是乘到 albedo_texture 上的，同一份材质会把图标也染成品质色。
	var face := MeshInstance3D.new()
	face.name = "Face"
	if _hand_face_mesh == null:
		_hand_face_mesh = PlaneMesh.new()
		# PlaneMesh 躺在 XZ 平面（法线 +Y），正是一张平放在牌顶上的贴片
		_hand_face_mesh.size = Vector2(HAND_CARD_W, HAND_CARD_D) * 0.78
	face.mesh = _hand_face_mesh
	# 抬 0.8mm：与牌顶面不共面（否则 z-fighting 闪）
	face.position = Vector3(0.0, HAND_CARD_T * 0.5 + 0.0008, 0.0)
	# 朝向不用动：PlaneMesh 自己的 UV 就是对的 —— 探针实测（get_mesh_arrays 逐顶点）：
	# 局部 (x, z) = (+0.5, -0.5) → uv=(1, 0)，即 z 为 **-0.5（远端）** 那条边是 v=0。
	# 远端在屏幕上就是"上"，贴图第一行也在上 ⇒ 图标正着；u 同样 +x → +u，不镜像。
	# （别凭印象给它转 180°：那样图标才是倒的。）
	var fmat := StandardMaterial3D.new()
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fmat.roughness = 0.75
	face.material_override = fmat
	_hand_face_mats.append(fmat)
	card.add_child(face)
	_hand_root.add_child(card)      # 摆位在 set_hand 里统一做（世界坐标，挂哪儿都行）
	return card

## 手上有几张牌（= 背包件数，封顶 HAND_MAX）。
func hand_count() -> int:
	return _hand_n

## 第 i 张牌在**画布像素**下的命中矩形（Task 5 点击判定用）。越界给空矩形。
##
## 为什么不是"以牌位为心的一块扁矩形"：牌是**抬起来、朝自己倾斜的实物**，而玩家的点击是
## 「屏幕点 → 3D 射线 → 打在**桌面平面**上 → 折成画布像素」（table_3d._unhandled_input）。
## 于是"看得见的那张牌"对应的画布区间被整体推到更远端（抬高 = 屏幕上更靠上 = 射线打得更远），
## 尺寸也略微被压。这里把牌的**八个角**（顶面 / 底面各四角）过一遍**同一条链路**
##（unproject_position → screen_to_viewport）取包围盒：长方体轮廓的极点必在这八个顶点里，
## 所以这个盒子盖得住整块看得见的牌。玩家点在任何看得见的位置，落的画布点都落在盒子里
## —— 不会"看着卡点下去却没选中"。
##
## 出图核对（把命中盒折回屏幕叠在截图上，逐像素数）：可见卡面 4358 个像素里 4339 个在盒内，
## 剩下 19 个是**座位卡那排槽位里的同名道具图标**（在盒子下方、不属于手牌）。
## 八角逐角 vs 只取顶面四角只差 0.1 画布像素（卡只有 0.022 厚）—— 真正拉开差距的是
## **抬高 + 倾斜**那一段：整个盒子比"把扁矩形画在牌位落点上"往远端挪了约 13 画布像素
##（测试里 `命中盒按抬起算` 那条钉的就是它）。
##
## 不缓存：相机变动（取景 / 滚轮推移视角）会改"你看到它的位置"，而实物的世界位置不动。
func hand_rect(i: int) -> Rect2:
	if i < 0 or i >= _hand_n:
		return Rect2()
	var card := _hand[i]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var n := 0
	for sx_v in [-0.5, 0.5]:
		for sy_v in [-0.5, 0.5]:
			for sz_v in [-0.5, 0.5]:
				# 局部角点 → 世界：牌自己的倾斜 / 扇形都在 global_transform 里
				var corner: Vector3 = card.global_transform * Vector3(
					HAND_CARD_W * float(sx_v), HAND_CARD_T * float(sy_v), HAND_CARD_D * float(sz_v))
				var px = _t3.screen_to_viewport(_t3.camera.unproject_position(corner))
				if px == null:
					continue
				var p: Vector2 = px
				mn = mn.min(p)
				mx = mx.max(p)
				n += 1
	if n < 4:
		return _hand_mat_rect(i)          # 相机 / 视口不可用（理论上不会）：退回桌面落点
	return Rect2(mn, mx - mn)

## 退化口径：牌位在**桌面平面**上的落点包围盒（不算抬高与倾斜）。
func _hand_mat_rect(i: int) -> Rect2:
	var card := _hand[i]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for sx_v in [-0.5, 0.5]:
		for sz_v in [-0.5, 0.5]:
			var p: Vector2 = _t3.world_to_canvas_px(card.global_transform * Vector3(
				HAND_CARD_W * float(sx_v), -HAND_CARD_T * 0.5, HAND_CARD_D * float(sz_v)))
			mn = mn.min(p)
			mx = mx.max(p)
	return Rect2(mn, mx - mn)

## 画布像素命中第几张牌；**-1 = 没命中**（本函数自己的约定，与 GameData 的哨兵值无关）。
## 扇形里相邻两张的命中盒可能压住一两个像素：取**离相机最近**的那张 —— 不透明物件里
## 它才是画在上面的那张，免得"看着是这张、点下去选中另一张"。
##
## 批次 4 Task 2 起多一条闸：**看不见就点不到** —— 手牌淡到 HAND_HIT_MIN_ALPHA 以下（2D 端
## 一带）直接返回 -1，连命中盒都不必算。这条闸就是「2D 端出牌要回 3D」的**全部**实现：
## `game._on_table_click` 判手牌只走本函数（左键选中 / **右键丢弃也走它** —— 先取 hi 再分
## 左右键），所以 2D 端点不到牌 = 既选不中也丢不掉。丢弃与出牌一样要回 3D，**不为丢弃开特例**：
## 只在 2D 端禁出牌、却留着丢弃，等于留半套规则，玩家会以为牌还能点。
## 命中的几何判据（hand_rect）不受影响：淡出只改显示与命中，不改牌在桌上的位置。
func hand_hit(canvas_px: Vector2) -> int:
	if hand_alpha() < HAND_HIT_MIN_ALPHA:
		return -1
	var best := -1
	var best_z := -INF
	for i in _hand_n:
		if not hand_rect(i).has_point(canvas_px):
			continue
		var z: float = _hand[i].global_position.z    # 相机在 +z：z 越大越近
		if z > best_z:
			best_z = z
			best = i
	return best

# ---------------- 棋子（小人）与当前行动者光环（批次 11 Task 1） ----------------
#
# 桌垫上那两处"印着的小人 / 印着的行动光环"的实体化（设计 §5.1 / §5.2）。原先它们是画布里的
# 2D Control（`board_view._make_token` 的 Kenney 棋子贴图 + 一只 64×64 的呼吸光环 Panel），
# **随桌垫一起倾斜** ⇒ 3D 下看着就是贴纸。现在：
#   * 棋子 = 一块**立在桌上的薄牌**（`BoxMesh`，正面平贴同一张棋子贴图），后倾 25°；
#   * 光环 = 一条**贴桌垫的 3D 环**（`TorusMesh` 压扁），套在当前行动者脚下、逐帧跟着它走。
# 棋子那几样动作也一并搬进来（原 2D 的 `play_move` / `_teleport_anim` / `_make_token` 的弹入，
# 见设计 §4.1 的四样动作）。
#
# **尺寸口径**（R4 裁定，见文件头"尺寸口径"那段）：棋子是**自由立在桌上的实物** ⇒ 尺寸写死
# 世界单位（与手牌 / 已退场立牌同一条约定）；**光环压在格子上** ⇒ 位置与尺寸都跟印刷图案
# （画布像素半径由 `board.token_ring_radius_px()` 报，这里量真变换换算）—— 与转盘轮缘同口径。
#
# **鼠标透明**：棋子不吃点击（点它脚下那格仍是"点格子"）。悬停命中由 `token_hit` 单独算
# （画布像素进、peer 出），与 2D 那套 `MOUSE_FILTER_IGNORE` + `_token_at_view` 同一条语义。

## 薄牌尺寸（世界单位：宽 × 高 × 厚）—— **写死**（见上面"尺寸口径"）。
## 取值出处：把原来印在桌垫上那枚棋子（44×50 `_world` 局部像素，见旧 `board_view._make_token`）
## 折成世界单位：44 × 全景 `_zoom`(0.96374) ÷ 252.5（2020 画布像素 = TABLE_W 8 世界）= **0.168**、
## 50 同理 = **0.191** ⇒ 取 0.17 / 0.20（立起来之后要压得住格子那一小块，比贴纸略高一档）。
## 厚度 0.022 与手牌（0.030）一个量级：有厚度才投得出影子、看得出是"牌"而不是贴纸。
const TOKEN_SIZE := Vector3(0.17, 0.20, 0.022)
## 后倾角（绕 X **负**角 = 顶边往远端倒 ⇒ 面朝近端镜头）。与已退场立牌同款 **25°**：
## 2D 端（近正俯视）与 3D 端（50° 俯角）**都能看见一块面**；直立薄板在 2D 端只剩一条线。
const TOKEN_LEAN_DEG := 25.0
## 牌身底色：暗底（比周围格子的底色深一档）—— 身份靠正面那张棋子贴图。
## 另外按 `TOKEN_BODY_TINT` 掺一点**玩家色**（见 `_place_token`）：素材在时它只是"牌边那一圈
## 淡淡的同色"，**素材缺失时（`UIKit.piece_tex` 拿不到）整块就只剩这个色** —— 与 2D 那套
## "素材缺失退回纯色圆片"的降级一致（那时它用的是 `GameData.PLAYER_COLORS`）。
const TOKEN_BODY_COLOR := Color(0.125, 0.135, 0.185)
const TOKEN_BODY_TINT := 0.25
## 命中盒的放宽量（画布像素，**四面**各放这么多）：棋子只有 0.17×0.20 世界（≈43×46 画布像素），
## 手指不容易点中；原 2D `_token_at_view` 也有 (10,14) 的容差 —— "好点中"这条一字未改。
## 它同时让"同一格两枚棋子的命中盒有交叠"，`token_hit` 的"取最近"那条判据才有用武之地。
const TOKEN_HIT_SLACK := Vector2(10.0, 14.0)
## 逐格走子时**竖直小跳**的高度（世界单位）。0.075 是薄牌高的三分之一、屏幕上约 19 画布像素
## （全景取景）—— 一眼看得出是"跳过一格"而不是"滑过去"。
const TOKEN_HOP := 0.075
## 走子每一步的**挤压**幅度（绕自身轴）：每步中段把 y 压到 `1-SQUASH`、x/z 各张 0.6 倍这么多，
## 两端回到 1（落地回弹）。原 2D 是 scale 1.28 的脉冲 —— 同一个意思：这一步有分量。
const TOKEN_SQUASH := 0.18
## 弹入（新棋子出现）：scale 0 → 1 的时长（TRANS_BACK/EASE_OUT）。局部原点在**下沿** ⇒
## 是"从桌面上长出来"，不是从中心炸开（见 `_make_token`）。
const TOKEN_POP_TIME := 0.35
## 传送：淡出时长 → 瞬移 → 淡入时长。原 2D `_teleport_anim` 是 0.16 / 0.22，一字未改。
const TOKEN_TP_OUT := 0.16
const TOKEN_TP_IN := 0.22

## 光环（当前行动者）：径向范围相对"画布上报的半径"的比例 —— 与轮缘的 `RIM_*` 同一条口径
## （内沿 / 外沿都是**环的径向范围**，不是管子半径）。取 0.60~1.0：比轮缘那圈细一点，
## 它压在自己那一格上，不该盖住格子的图案。
const RING_INNER_R := 0.60
const RING_OUTER_R := 1.00
## 压扁：`TorusMesh` 的管子截面是**圆形**（Y 向厚度 = 管径 = (outer - inner)），
## 压到 0.30 才像"贴在桌上的一道环"而不是一根甜甜圈。
const RING_FLATTEN := 0.30
## 环心离桌垫的高度：环压得越低越好（见 `PROPS_Y` 那条"抬得越高、屏幕上越漂"）。
const RING_Y := 0.008
## 呼吸脉冲：**亮度**在 0.45~1.0 之间来回，一个周期 1.1s。原 2D 是"scale 1→1.16→1 +
## alpha 1→0.55→1"（两半各 0.55s）—— 3D 里换成**只动亮度、不动几何**：
## 环的尺寸是"跟印刷图案"的量（`layout_test` 会把它折回画布像素比），缩放会让它量不准。
const RING_PULSE_TIME := 1.1
const RING_GLOW_LO := 0.45
const RING_GLOW_HI := 1.00

var _tokens_root: Node3D
## 节点池：peer -> `{root, plate, plate_mat, face, face_mat, idx, slot, tw}`。**只建一次**，
## 刷新只改 transform / 可见性 / 贴图（照手牌那份幂等约定；`tw` 是这枚棋子当前的补间）。
var _tokens := {}
## peer -> bool：**正在走子 / 传送**的棋子不由 `set_tokens` 抢位置 —— 状态广播可能在动画中途
## 到达，抢位置会让它瞬移回起点（同 2D 的 `_animating`）。
var _moving := {}
var _token_mesh: BoxMesh
var _token_face_mesh: PlaneMesh
var _ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D
var _ring_peer := GameData.NO_PEER
var _ring_phase := 0.0

## 按 `rows`（每项 `{peer, slot, idx}`）摆棋子：`idx` = 路径格号、`slot` = 玩家槽位 0~3。
##
## **幂等**：节点池只建一次，之后每次只改落点与贴图（每次状态广播都会调，与 `set_hand` 同）。
## 新 peer ⇒ 建一块 + **弹入**；正在走子 / 传送的那块**不动**（见 `_moving`）；
## 状态里没有了的 peer ⇒ 收掉（断线 / 出局后的名册变化）。
func set_tokens(rows: Array) -> void:
	if _t3 == null:
		return
	if _tokens_root == null:
		_tokens_root = Node3D.new()
		_tokens_root.name = "Tokens"
		add_child(_tokens_root)
	var seen := {}
	for row in rows:
		var r: Dictionary = row
		var peer := int(r.get("peer", GameData.NO_PEER))
		var slot := int(r.get("slot", 0))
		var idx := int(r.get("idx", 0))
		seen[peer] = true
		var tk: Dictionary = _tokens.get(peer, {})
		if tk.is_empty():
			tk = _make_token(peer)
			_tokens[peer] = tk
			_place_token(tk, idx, slot)
			_pop_token_in(tk)
		elif not bool(_moving.get(peer, false)):
			_place_token(tk, idx, slot)
	for peer in _tokens.keys():
		if not seen.has(peer):
			(_tokens[peer]["root"] as Node3D).queue_free()
			_tokens.erase(peer)
			_moving.erase(peer)

## 这枚棋子此刻在不在（悬停链路要它来降级：拿不到就别显信息条）。没建过的 peer 给 false。
func has_token(peer: int) -> bool:
	return _tokens.has(int(peer))

## 这枚棋子此刻是否正在走子 / 传送（`set_tokens` 会跳过它、不抢位置）。
func token_moving(peer: int) -> bool:
	return bool(_moving.get(int(peer), false))

## 造一块棋子薄牌（节点只造一次）。局部坐标：原点 = **板的下沿中点**（棋子"站"在桌上），
## x 向右、y 向上、z 朝近端镜头 —— 与已退场的立牌同一套局部约定。
func _make_token(peer: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Token_p%d" % peer
	# 后倾：绕 X **负**角 = 顶边往远端倒 ⇒ 牌面朝着近端镜头（2D 端近正俯视也看得见一块面）
	root.rotation = Vector3(deg_to_rad(-TOKEN_LEAN_DEG), 0.0, 0.0)
	_tokens_root.add_child(root)
	if _token_mesh == null:
		_token_mesh = BoxMesh.new()
		_token_mesh.size = TOKEN_SIZE
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	plate.mesh = _token_mesh
	plate.position = Vector3(0.0, TOKEN_SIZE.y * 0.5, 0.0)   # 板心抬半高 ⇒ 下沿落在原点
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = TOKEN_BODY_COLOR
	pmat.roughness = 0.62
	# 显式写死**不透明档**：3D 端留在不透明队列才有深度写入与投影（批次 4 的教训）。
	# 只有传送淡出的那 0.38s 切成 ALPHA，淡完切回（见 `_set_token_alpha`）。
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	plate.material_override = pmat
	root.add_child(plate)
	# 正面：棋子贴图（Kenney CC0 / `UIKit.piece_tex` 按槽位取色）。贴图带透明边 ⇒ 用
	# **ALPHA_SCISSOR**（透明区裁掉、仍在**不透明队列**里写深度、投得出影子）—— 同手牌牌面那条
	#（`_make_card` 里的 face）。抬 1mm：与板面不共面（免得 z-fighting 闪）。
	var face := MeshInstance3D.new()
	face.name = "Face"
	if _token_face_mesh == null:
		_token_face_mesh = PlaneMesh.new()
		# 方片，边长取薄牌的**宽**（0.17）：棋子贴图是正方形（512²），贴图里那个"小人"本身
		# 约 0.5 宽 × 0.88 高 —— 方片贴在板上，小人于是占板宽一半、板高约四分之三（对着出图核过）。
		_token_face_mesh.size = Vector2(TOKEN_SIZE.x, TOKEN_SIZE.x)
	face.mesh = _token_face_mesh
	# `PlaneMesh` 躺在 XZ 平面（法线 +Y）：绕 X **+90°** ⇒ 法线朝 +Z（朝着近端镜头）、
	# 贴图的上方朝 +Y。别用 -90°：那面朝下、从镜头这一侧看不见。
	face.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	face.position = Vector3(0.0, TOKEN_SIZE.y * 0.5, TOKEN_SIZE.z * 0.5 + 0.001)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color.WHITE
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fmat.roughness = 0.8
	face.material_override = fmat
	root.add_child(face)
	return {"root": root, "plate": plate, "plate_mat": pmat, "face": face, "face_mat": fmat,
		"idx": 0, "slot": 0, "tw": null}

## 把一块棋子的落点与正面贴图刷一遍（幂等，每次广播都走）。
## 落点 = 「格心 + 槽位偏移」→ 世界（`_token_world`），y **落在桌面上**（+ `PROPS_Y` 那点小抬）：
## 局部原点就在下沿 ⇒ 棋子是"站"在桌上，而不是插进桌垫或浮在空中。
func _place_token(tk: Dictionary, idx: int, slot: int) -> void:
	tk["idx"] = idx
	tk["slot"] = slot
	(tk["root"] as Node3D).global_position = _token_world(idx, slot)
	# 牌身掺一点玩家色（见 TOKEN_BODY_COLOR 那段）：贴图在时是"牌边一圈同色"，贴图缺时是全部身份
	(tk["plate_mat"] as StandardMaterial3D).albedo_color = \
		TOKEN_BODY_COLOR.lerp(GameData.PLAYER_COLORS[slot % 4], TOKEN_BODY_TINT)
	var tex := UIKit.piece_tex(slot)
	var face: MeshInstance3D = tk["face"]
	face.visible = tex != null
	if tex != null:
		(tk["face_mat"] as StandardMaterial3D).albedo_texture = tex

## 某格 + 某槽位的**棋子落点**（画布像素，**已过 2D 镜头变换**）。公式归 BoardView
##（`board.token_screen_pos` = `global_position + _view_from_world(slot_anchor(idx, slot))`），
## 与 `tile_screen_pos` / `deck_screen_pos` / `wheel_screen_pos` **同一条链**。
##
## **必须走镜头变换**（不是 `slot_anchor` 那份局部坐标）：棋子要坐在**印在桌垫上的**那一格上，
## 而印刷图案随 2D 镜头（`_zoom` / `_center`）走 —— 用局部坐标摆，全景取景下会整体偏开约一格
##（批次 11 Task 1 出图逮到）。**代价与轮缘 / 牌堆一样**：不伴随状态广播的纯镜头变化
##（摆拍用的 `focus_grid` / `fit_overview`）之后要重推一次，否则会跟印刷图案脱开
##（见文件头"摆放约定"）。
func _token_anchor_px(idx: int, slot: int) -> Vector2:
	if _t3.board == null:
		return Vector2.ZERO
	return _t3.board.token_screen_pos(idx, slot)

## 某格 + 某槽位的棋子落点的**世界坐标**（与 `_place_token` 同一条链，含桌面高度）。
func _token_world(idx: int, slot: int) -> Vector3:
	var w: Vector3 = _t3.canvas_px_to_world(_token_anchor_px(idx, slot))
	w.y = _t3.table_mesh.global_position.y + PROPS_Y
	return w

## 弹入：scale 0 → 1（局部原点在下沿 ⇒ 从桌面上长出来）。一次性过渡 ⇒ Tween（既有约定）。
func _pop_token_in(tk: Dictionary) -> void:
	var root: Node3D = tk["root"]
	root.scale = Vector3.ZERO
	var tw := create_tween()
	tk["tw"] = tw
	tw.tween_property(root, "scale", Vector3.ONE, TOKEN_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 掐掉一枚棋子上正在跑的补间（弹入 / 走子 / 传送共用一条 `tw`），并把 `_moving` 松开 ——
## 调用方（`play_token_move` / `set_token_teleport`）紧接着会重新置位，所以松开不会让它乱跑。
func _kill_token_tw(peer: int) -> void:
	var tk: Dictionary = _tokens.get(peer, {})
	if tk.is_empty():
		return
	var old = tk.get("tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	tk["tw"] = null
	_moving[peer] = false

## 逐格走子：每步 = 世界坐标补间 + **竖直小跳的弧** + 绕自身轴挤压 + 落地音效。
## `path` 为空表示"原地传送"（同 2D `play_move` 的旧语义：那时由 `set_token_teleport` 先给落点）。
##
## 每步的落点由**本节点那套链**重算（格心 + 槽位偏移 → 世界），所以走出来的每一格与印刷图案
## 严丝合缝。一步只用一个 `tween_method`：位置沿直线补间、y 叠一条 `sin(π·t)` 的弧（两端为 0 ⇒
## 每步落地、下一步再抬）、同时按同一条 t 挤压 —— 两条补间分别写 x/z 与 y 会互相覆盖同一个
## `global_position`，这是不能拆开的原因。
func play_token_move(peer: int, path: Array, step_time: float) -> void:
	var p := int(peer)
	if _t3 == null or not _tokens.has(p):
		return
	var tk: Dictionary = _tokens[p]
	_kill_token_tw(p)
	_moving[p] = true
	if path.is_empty():
		_token_teleport_anim(p, tk, -1)
		return
	var root: Node3D = tk["root"]
	var tw := create_tween()
	tk["tw"] = tw
	var slot := int(tk.get("slot", 0))
	var dur := maxf(float(step_time), 0.01)
	var prev := root.global_position
	for step in path:
		var target := _token_world(int(step), slot)
		var from := prev
		# 一步写成一个 `tween_method` 的闭包：`from` / `target` 都是循环体内的局部量，
		# GDScript 的 lambda **按值捕获**，所以每一步各自记住自己的起终点。
		tw.tween_method(func(t: float) -> void:
			root.global_position = Vector3(lerpf(from.x, target.x, t),
				target.y + TOKEN_HOP * sin(PI * t), lerpf(from.z, target.z, t))
			var s := 1.0 - TOKEN_SQUASH * sin(PI * t)          # 中段最扁、两端回到 1
			root.scale = Vector3(1.0 + (1.0 - s) * 0.6, s, 1.0 + (1.0 - s) * 0.6),
			0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(Fx.play.bind("tick", -8.0, randf_range(0.9, 1.2)))
		prev = target
	tw.finished.connect(func() -> void:
		_moving[p] = false
	)

## 传送（`传送` 类道具 / 送监 / 换位）：材质切 ALPHA → alpha 到 0 → 瞬移 → alpha 回 1 →
## **切回不透明**。
##
## **必须切模式**（照手牌 `_apply_hand_alpha` 那条先例）：3D 端留在不透明队列才有深度写入与
## 投影；淡出中不切 ALPHA 的话 `albedo_color.a` 根本不起作用（淡不动）。
func set_token_teleport(peer: int, idx: int) -> void:
	var p := int(peer)
	if _t3 == null or not _tokens.has(p):
		return
	_kill_token_tw(p)
	_moving[p] = true
	_token_teleport_anim(p, _tokens[p], int(idx))

func _token_teleport_anim(p: int, tk: Dictionary, target_idx: int) -> void:
	var root: Node3D = tk["root"]
	var tw := create_tween()
	tk["tw"] = tw
	if target_idx < 0:
		# 没给落点（`play_move(peer, [], t)` 那条旧路）：原地淡一下再回来，不瞬移
		tw.tween_interval(0.1)
		tw.finished.connect(func() -> void: _moving[p] = false)
		return
	var target := _token_world(target_idx, int(tk.get("slot", 0)))
	_set_token_alpha(tk, true, 1.0)
	tw.tween_method(func(a: float) -> void: _set_token_alpha(tk, true, a), 1.0, 0.0, TOKEN_TP_OUT)
	tw.parallel().tween_property(root, "scale", Vector3.ONE * 1.5, TOKEN_TP_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		root.global_position = target
		Fx.play("pop", -6.0))
	tw.tween_method(func(a: float) -> void: _set_token_alpha(tk, true, a), 0.0, 1.0, TOKEN_TP_IN)
	tw.parallel().tween_property(root, "scale", Vector3.ONE, TOKEN_TP_IN + 0.04) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_set_token_alpha(tk, false, 1.0)
		_moving[p] = false)

## 把一块棋子的不透明度贴到**两个材质**上（牌身 + 正面贴图），模式一起切。
##
## 牌身：不透明档 ⇄ ALPHA；正面贴图：ALPHA_SCISSOR（透明边裁掉、仍在不透明队列）⇄ ALPHA ——
## 与手牌 `_apply_hand_alpha` 同一套（那里逐张一份材质，这里一块棋子两份）。
## `fade = false` 时顺带把 alpha 复位成 `a`（正常路径是 1.0，即"淡完切回不透明"）。
func _set_token_alpha(tk: Dictionary, fade: bool, a: float) -> void:
	var pmat: StandardMaterial3D = tk["plate_mat"]
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade \
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	var pc := pmat.albedo_color
	pc.a = a
	pmat.albedo_color = pc
	var fmat: StandardMaterial3D = tk["face_mat"]
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade \
		else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var fc := fmat.albedo_color
	fc.a = a
	fmat.albedo_color = fc

## 一枚棋子当前的不透明度（**只读量**，给测试用：传送"淡到看不见"这件事没有别的可观察量）。
## 拿不到这枚棋子时给 1.0 —— "没有这块棋子"不该被读成"它淡到看不见了"。
func token_alpha(peer: int) -> float:
	var tk: Dictionary = _tokens.get(peer, {})
	if tk.is_empty():
		return 1.0
	return (tk["plate_mat"] as StandardMaterial3D).albedo_color.a

## 某枚棋子在**世界坐标**下的位置（= 薄牌的**板心**，也就是屏幕上看到的那块面正中）。
## 拿不到这枚棋子时返回 `Vector3.ZERO`（调用方先 `has_token` 或自己判零兜底）。
## 用途：飘字 / 飞钞的锚点从"画布坐标"换成"世界点 → 屏幕"（`game._token_screen_pos`）。
func token_world_pos(peer: int) -> Vector3:
	var tk: Dictionary = _tokens.get(peer, {})
	if tk.is_empty():
		return Vector3.ZERO
	var plate: MeshInstance3D = tk["plate"]
	if plate == null or not is_instance_valid(plate):
		return Vector3.ZERO
	return plate.global_position

## 画布像素命中哪枚棋子（**-1 = 没命中**，本函数自己的约定，与 GameData 的哨兵值无关）。
##
## 命中盒 = 薄牌八个角经 `unproject_position` → `screen_to_viewport` 折成画布像素的包围盒
## （**与 `hand_rect` / 已退场的 `_standee_rect` 同一条链**：薄牌是立着又后倾的实物，而玩家的
## 点击是"屏幕点 → 桌面平面 → 画布像素"，两者差着"实物离桌面的高度"那一段投影 —— 只按落点画个
## 扁矩形，玩家照着看得见的牌点就会点空），再四面放宽 `TOKEN_HIT_SLACK`（手指容差）。
## 两枚都压住时取**离相机最近**的那枚（相机在 +z：z 越大越近）—— 不透明实物里它画在上面。
## **不缓存**：相机一变（取景 / 滚轮推移视角）它就得重算。
func token_hit(canvas_px: Vector2) -> int:
	var best := -1
	var best_z := -INF
	for peer in _tokens:
		var rect := _token_rect(_tokens[peer])
		if rect.size == Vector2.ZERO or not rect.has_point(canvas_px):
			continue
		var z: float = (_tokens[peer]["root"] as Node3D).global_position.z
		if z > best_z:
			best_z = z
			best = int(peer)
	return best

## 一枚棋子的命中矩形（画布像素）：薄牌八角 → 世界 → 屏幕 → 画布取包围盒，再四面放宽。
## 相机 / 视口不可用（理论上不会）时退回"落点周围按薄牌宽度折出的一块"，别返回空矩形 ——
## 那会让整枚棋子忽然点不中（同 `hand_rect` 的 `_hand_mat_rect` 降级口径）。
func _token_rect(tk: Dictionary) -> Rect2:
	if _t3 == null or _t3.camera == null:
		return Rect2()
	var plate: MeshInstance3D = tk["plate"]
	if plate == null or not is_instance_valid(plate):
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var n := 0
	for sx_v in [-0.5, 0.5]:
		for sy_v in [-0.5, 0.5]:
			for sz_v in [-0.5, 0.5]:
				var corner: Vector3 = plate.global_transform * Vector3(
					TOKEN_SIZE.x * float(sx_v), TOKEN_SIZE.y * float(sy_v), TOKEN_SIZE.z * float(sz_v))
				var px = _t3.screen_to_viewport(_t3.camera.unproject_position(corner))
				if px == null:
					continue
				var p: Vector2 = px
				mn = mn.min(p)
				mx = mx.max(p)
				n += 1
	if n < 4:
		var c: Vector2 = _t3.world_to_canvas_px((tk["root"] as Node3D).global_position)
		var w_px: float = (_t3.canvas_px_to_world(Vector2(TOKEN_SIZE.x, 0.0)) \
			- _t3.canvas_px_to_world(Vector2.ZERO)).length()
		return Rect2(c - Vector2(w_px, w_px) * 0.5, Vector2(w_px, w_px))
	return Rect2(mn - TOKEN_HIT_SLACK, (mx - mn) + TOKEN_HIT_SLACK * 2.0)

## 当前行动者光环：`peer` = 本轮行动者；`GameData.NO_PEER` = 收起（结束时 / 没人在行动）。
##
## 幂等：节点只建一次，每次调用**重算尺寸**（半径跟印刷图案走，取景一变就得重算 —— 同
## `build_wheel` 那条）。**位置与呼吸交给 `_process`**：环要逐帧跟着棋子走（含走子动画期间，
## 那时棋子在动），而呼吸是**持续动画** —— 按项目约定手写 `_process` 相位，不用循环 Tween。
func set_ring(peer: int) -> void:
	if _t3 == null:
		return
	if _ring == null:
		_build_ring()
	_ring_peer = int(peer)
	if peer == GameData.NO_PEER or not _tokens.has(_ring_peer):
		_ring.visible = false
		return
	_apply_ring_size()
	_apply_ring_pose()      # 立刻摆到棋子脚下（不等下一帧 `_process`，免得"亮了但在原点"闪一下）
	_ring.visible = true

## 把环摆到当前行动者那枚棋子的**脚下**（只取 xz —— 环是贴在桌垫上的，不跟棋子抬起来的 y）。
## `set_ring` 与 `_process` 共用这一条。
func _apply_ring_pose() -> void:
	var tk: Dictionary = _tokens.get(_ring_peer, {})
	if tk.is_empty():
		return
	var root: Node3D = tk.get("root")
	if root == null or not is_instance_valid(root):
		return
	_ring.global_position = Vector3(root.global_position.x,
		_t3.table_mesh.global_position.y + RING_Y, root.global_position.z)

func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring_mesh = TorusMesh.new()
	_ring_mesh.rings = 40
	_ring_mesh.ring_segments = 10
	_ring.mesh = _ring_mesh
	_ring_mat = StandardMaterial3D.new()
	# 自发光：屋子里只有一盏台灯，环要像"亮着的一道圈"（原 2D 那只金圈也是这个意思）。
	# 亮度由 `_process` 呼吸（`emission_energy_multiplier`），材质本身始终不透明。
	_ring_mat.albedo_color = UIKit.ACCENT
	_ring_mat.emission_enabled = true
	_ring_mat.emission = UIKit.ACCENT
	_ring_mat.emission_energy_multiplier = RING_GLOW_HI
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)

## 按**画布像素**半径重算环的世界尺寸（幂等；`set_ring` 与取景变化后都要调）。
func _apply_ring_size() -> void:
	if _ring_mesh == null or _t3.board == null:
		return
	var r_px: float = _t3.board.token_ring_radius_px()
	if r_px <= 0.0:
		return
	# 画布像素 → 世界：**量真变换**（同 `build_wheel` 量半径那条 —— 别另写"像素 ÷ 某个常数"：
	# 那条链隔着贴图窗口与桌面尺寸两个旋钮，写死了就会静默失配）
	var o: Vector3 = _t3.canvas_px_to_world(Vector2.ZERO)
	var r: float = (_t3.canvas_px_to_world(Vector2(r_px, 0.0)) - o).length()
	_ring_mesh.inner_radius = r * RING_INNER_R
	_ring_mesh.outer_radius = r * RING_OUTER_R
	_ring.scale = Vector3(1.0, RING_FLATTEN, 1.0)   # 压扁（只压 Y ⇒ 径向尺寸不受影响）

## 光环的逐帧：① 跟着棋子走（只取 xz —— 走子时棋子会抬 y，而环是**贴在桌垫上**的，不该跟着飞）；
## ② 呼吸（亮度）。没人在行动 / 环收着时直接早退，不白跑。
func _process(delta: float) -> void:
	if _ring == null or not _ring.visible:
		return
	if _tokens.get(_ring_peer, {}).is_empty():
		return
	_apply_ring_pose()
	_ring_phase = fposmod(_ring_phase + delta, RING_PULSE_TIME)
	var k := 0.5 - 0.5 * cos(TAU * _ring_phase / RING_PULSE_TIME)
	_ring_mat.emission_energy_multiplier = lerpf(RING_GLOW_LO, RING_GLOW_HI, k)

# ---------------- 四块立牌：批次 9 已整体退场 ----------------
# 名字 / 身家 / 公开背包 / 倒计时 / "可被选中"高亮**全都有更稳的落点**：前两者与倒计时在
# **屏幕层四角身家条**（`table_hud.CORNER_SLOTS` + `game._refresh_corner_bars/_refresh_corner_timer`，
# 四角条在 3D / 2D 两端都常驻），公开背包在**玩家道具弹窗**（`scripts/player_popup.gd`），
# 高亮改由 `game._refresh_corner_highlight` 画在四角条上。**别再把它加回来**：
# `hud_test` 有"接口与节点都已退场"的反向契约。
