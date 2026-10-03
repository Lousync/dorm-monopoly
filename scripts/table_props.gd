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
# 唯一的例外是转盘轮缘（`build_wheel` 里量真变换、随 `_zoom` 变）：它必须与
# **印在桌垫上的**那个轮子重合，而桌垫图案随 2D 镜头缩放，不跟就会脱开。
# 筹码 / 体力件 / 手牌都是**自由立在桌上的实物**：相机推近是"你凑近看"，
# 不是"桌子变大了"，实物不该跟着长 —— 所以它们的尺寸写死在世界单位里。
#
# 手牌还多一层：它的**命中矩形**必须跟玩家看到的位置一致，那要过相机
#（`hand_rect` 是量真投影，不是常数）—— 尺寸是世界常数与命中盒跟相机，
# 这两件事互不矛盾：一个说"牌多大"，一个说"你在屏幕上点哪儿算点到它"。
#
# 摆放约定（物件 vs 2D 相机，2026-10-03 终审 I1 定案）：
# **只有转盘轮缘跟 2D 相机，筹码 / 体力件 / 手牌一律不跟**。
#   轮缘 — 位置来自 `board.wheel_screen_pos()` / 半径来自 `200 × _zoom`（量真变换）：它必须贴
#           **印在桌垫上的**那个轮盘，而桌垫图案随 2D 取景缩放 ⇒ 跟着走。
#   其余 — 位置走**画布常量**（`CHIP_BASE_PX` / `PIP_BASE_PX` / `HAND_BASE_PX`）：它们是
#           **自由立在桌上的实物**，不该因为"印出来的图案"变了而移动。相机推近是「你凑近看」，
#           不是「桌子被重新排版」。
# **代价（必须记住）**：抽卡动画会把 2D 取景推到 ≥2×（`board_view.gd` 的 `DECK_PUSH_FACTOR`），
# 那一刻桌垫图案整体滑动、而实物纹丝不动 ——「手牌不压座位栏 / 不压自己那排格子」这些断言
# **只在全景取景下成立**。批次 4 要连续移相机 ⇒ **必须继承这条决定**（实物不跟相机），
# 并为轮缘决定是否补每帧跟 `_zoom`（当前只在每次状态广播刷新，见 `game._refresh_table_props`）。

## 每 ¥5,000 一枚筹码。对着出图定：开局 ¥20,000 → 4 枚（正好半摞，一眼看出起始身家几何）；
## 常见的租金 / 罚款多在几百到几千，一档 5,000 意味着零星收支不动筹码堆、攒够一大笔才长一枚
## —— 筹码是「身家的量级」，不是记账本（精确到元的读数仍在座位卡上）。
const CHIP_PER := 5000
## 筹码堆上限：再多也只画这么多枚。近端桌面上还有体力件与（后续任务里）手牌，
## 堆到十枚以上既挤不下、也一枚一枚数不清，反而看不出身家差别。
const CHIP_MAX := 8
const CHIP_R := 0.10             # 单枚筹码半径（世界单位；≈ 半块地皮宽，出图核过）
const CHIP_H := 0.028            # 单枚厚度
const CHIP_STEP := 0.030         # 叠放间距：略大于厚度 —— 层间留一道缝，看出是一枚一枚摞的
const CHIP_LEAN_PX := 13.0       # 每上一枚往远端挪一点画布像素：斜着摞，正对镜头也数得清枚数
## 筹码堆底枚的画布像素位置：**自己面前的空桌垫**上。
##
## 全景取景下（四人围桌，画布 2048²）各处的画布范围实测（探针打出来的）：
## 绿绒嵌板 y∈[762,1646]、格子区 y∈[668,1740]、自己那条座位栏 y∈[1804,2032]、
## 转盘圆 y∈[1045,1364]、嵌板中心的同心圆装饰最远到 y≈1465。
## 于是「自己面前」的空档 = 嵌板下沿之内、转盘之下、装饰圈之外，y≈[1490,1640]。
##
## 取 1,530 而不是贴着空档下沿的 1,640：底枚的**平面**落点看着离下方那排格子还有 100 多
## 画布像素，但实体是抬在桌面之上的（PROPS_Y + 半厚），相机把"高度"投影成屏幕上的一段位移
## —— 出图实测：落在 1,600 时整摞的可见下沿与格子图案只差 1~2 像素（擦着），挪到 1,530
## 才空出约 20 像素的桌垫。**这条只能靠出图核，算平面距离会被骗。**
const CHIP_BASE_PX := Vector2(700.0, 1530.0)
const CHIP_COLOR := Color(0.85, 0.66, 0.28)   # 金色筹码

const PIP_SIZE := Vector3(0.115, 0.055, 0.115)   # 一件体力小件（方块，坐得起、投得出影子）
const PIP_STEP_PX := 42.0                        # 相邻两件的间距（画布像素）
## 与筹码同一排、落在玩家右手边（筹码在左、体力在右，各占自己面前的一半）。y 同 CHIP_BASE_PX。
const PIP_BASE_PX := Vector2(1180.0, 1530.0)
const PIP_LIT := Color(0.95, 0.78, 0.35)         # 还有的体力：亮金
const PIP_SPENT := Color(0.22, 0.20, 0.18)       # 用掉的：熄灭

var _t3: TableView3D
var _wheel_px := Vector2.ZERO
var _hit_r := 0.0                 # 命中半径（画布像素）
var _rim: MeshInstance3D
var _rim_mesh: TorusMesh

# 筹码堆 / 体力件的**节点池**：只建一次，之后刷新只改 visible / 材质色 / transform。
# 为什么用池而不是像转盘那样"一个节点"：它们按数值个数变化（金额几档、体力几点），
# 而这两个刷新点都被 game.gd 每次状态广播调用（见 _refresh_table_props）——
# 每次重建节点树（brief 原稿的 queue_free + new）等于每广播都造一堆 MeshInstance3D。
var _chips_root: Node3D
var _chips: Array[MeshInstance3D] = []
var _chip_mesh: CylinderMesh          # 所有筹码共用一份：尺寸完全一致
var _pips_root: Node3D
var _pips: Array[MeshInstance3D] = []
var _pip_mats: Array[StandardMaterial3D] = []   # 亮 / 灭只改颜色，材质一件一份
var _pip_mesh: BoxMesh

func setup(t3: TableView3D) -> void:
	_t3 = t3

## 金额 → 筹码枚数。**静态纯函数**：与节点、场景无关，可以无头单测。
static func chip_count(money: int) -> int:
	if money <= 0:
		return 0
	return clampi(money / CHIP_PER, 0, CHIP_MAX)

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
	#（贴图窗口），不是 VP_SIZE；今天二者数值相同（窗口 = 整张画布），但它们是两个独立的旋钮，
	# 窗口一旦被裁，位置仍走真变换（对的）、半径却会静默失配（不报错、只是轮缘与盘面对不上）。
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

# ---------------- 自己的现金（筹码堆）与体力（小件排） ----------------
#
# 两者读的都是**已同步**的状态（game.gd 用 _state_player(my_peer)，客户端同样可用），
# 与 build_wheel 同一套约定：只负责"摆在哪、长什么样"，一个玩法数字都不碰。
#
# 坐标：一律 canvas_px_to_world（桌垫 UV 坐标系），y 抬到桌垫之上（见 PROPS_Y）。
# 画布 y 越大 = 越靠近镜头（相机在 +z），所以"自己面前"就落在画布的近端；但近端那片
# 画布上还画着自己的座位卡（UI），实体的落点必须避开它（见 CHIP_BASE_PX）。

## 按金额在自己面前摆一摞筹码。枚数 = chip_count(money)，0 元 = 一枚都不露。
##
## **幂等**：节点池只建一次，刷新只改 visible 与 global_position —— 每次状态广播都会调它。
func set_chips(money: int) -> void:
	var n := chip_count(money)
	if n <= 0 and _chips.is_empty():
		return                                  # 一直没钱：连池子都不必建
	if _chips_root == null:
		_chips_root = Node3D.new()
		_chips_root.name = "Chips"
		add_child(_chips_root)
	while _chips.size() < n:
		_chips.append(_make_chip())
	for i in _chips.size():
		var chip := _chips[i]
		chip.visible = i < n
		if not chip.visible:
			continue
		# 第 i 枚：画布上往远端挪一点（斜摞），世界坐标里往上抬一层
		var w: Vector3 = _t3.canvas_px_to_world(
			CHIP_BASE_PX + Vector2(0.0, -CHIP_LEAN_PX * float(i)))
		# 底枚的下表面正好落在 PROPS_Y 上：既不与桌垫共面（不会 z-fighting），也不浮空
		w.y = _t3.table_mesh.global_position.y + PROPS_Y + CHIP_H * 0.5 + CHIP_STEP * float(i)
		chip.global_position = w

func _make_chip() -> MeshInstance3D:
	if _chip_mesh == null:
		_chip_mesh = CylinderMesh.new()
		# CylinderMesh 立在 XZ 平面（轴朝 Y）—— 一枚平放在桌上的筹码就是这个朝向。
		_chip_mesh.top_radius = CHIP_R
		_chip_mesh.bottom_radius = CHIP_R
		_chip_mesh.height = CHIP_H
		_chip_mesh.radial_segments = 24
	var chip := MeshInstance3D.new()
	chip.name = "Chip%d" % _chips.size()
	chip.mesh = _chip_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CHIP_COLOR
	mat.metallic = 0.55
	mat.roughness = 0.35
	chip.material_override = mat
	_chips_root.add_child(chip)      # 摆位在 set_chips 里统一做（世界坐标，挂哪儿都行）
	return chip

## 自己面前一排体力小件：还有的亮、用掉的熄灭。cap = _stamina_cap(p)（5，带充电宝是 6）。
##
## **幂等**：池子按见过的最大上限长，刷新只改 visible / 颜色 / 位置。
func set_stamina(cur: int, cap: int) -> void:
	var n := maxi(cap, 0)
	if n <= 0 and _pips.is_empty():
		return
	if _pips_root == null:
		_pips_root = Node3D.new()
		_pips_root.name = "Stamina"
		add_child(_pips_root)
	while _pips.size() < n:
		_pips.append(_make_pip())
	for i in _pips.size():
		var pip := _pips[i]
		pip.visible = i < n
		if not pip.visible:
			continue
		# 按**序号**分亮灭：第 cur 件之后全灭（cur 大于上限时也只亮到 n，不溢到别处）
		_pip_mats[i].albedo_color = PIP_LIT if i < mini(cur, n) else PIP_SPENT
		var w: Vector3 = _t3.canvas_px_to_world(PIP_BASE_PX + Vector2(PIP_STEP_PX * float(i), 0.0))
		# 方块要**坐在**桌垫上：中心抬到半高。像轮缘那样只写 PROPS_Y 的话，下半截会陷进桌子里
		# （轮缘是管子，沉一半看不出来；方块沉一半就只剩一层薄片）。
		w.y = _t3.table_mesh.global_position.y + PROPS_Y + PIP_SIZE.y * 0.5
		pip.global_position = w

func _make_pip() -> MeshInstance3D:
	if _pip_mesh == null:
		_pip_mesh = BoxMesh.new()
		_pip_mesh.size = PIP_SIZE
	var pip := MeshInstance3D.new()
	pip.name = "Pip%d" % _pips.size()
	pip.mesh = _pip_mesh
	# 一件一份材质：亮 / 灭是逐件改自己的颜色，共用一份材质会把整排一起点亮
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PIP_SPENT
	mat.roughness = 0.55
	pip.material_override = mat
	_pips_root.add_child(pip)
	_pip_mats.append(mat)
	return pip

# ---------------- 自己的手牌（道具） ----------------
#
# 一排**有厚度的实体卡**：近端、微微朝自己倾斜 —— 取代原来座位卡上那 5 个道具牌位。
# 命中判定（hand_hit / hand_rect）与状态反馈（set_hand_selected 选中 / set_hand_discard_pending
# 待确认丢弃）都在这儿；「点中之后选中谁、什么时候能出牌、右键丢弃谁」是 game.gd 的事
#（_on_table_click → _on_hand_clicked / _on_discard_clicked）。
# 与筹码 / 体力件同一套约定：坐标一律 canvas_px_to_world（桌垫 UV 坐标系），
# 尺寸是世界常数（见 PROPS_Y 下面那段），刷新幂等（节点池只建一次）。

## 手牌上限 = 背包格数上限（与座位卡那排牌位一样是最多 5 个）。
const HAND_MAX := 5
## 卡的尺寸（世界单位）。**是照着出图定的、不是拍的**：出图实测卡进深每 0.10 世界单位
## ≈ 12 屏幕像素高（近端透视把它放大了），而手牌能落的那条空档只有 ~34 像素高
##（见 HAND_BASE_PX）—— 再大就得压住格子价格或座位卡。0.40 与 0.50 两版都出图比过。
const HAND_CARD_W := 0.30        # 卡宽（世界单位；≈ 一块地皮宽，出图看着不喧宾夺主）
const HAND_CARD_D := 0.34        # 卡进深
const HAND_CARD_T := 0.022       # 卡厚：有厚度才投得出影子、看得出是"卡"而不是贴纸
## 相邻两张牌中心的画布间距。略大于卡宽（0.30 × 256 ≈ 77 画布像素）+ 扇形岔开的投影增量：
## 相邻两张几乎相接但不叠压 —— 叠压会让命中盒互相压住（点一张选到另一张）。
const HAND_STEP_PX := 96.0
## 扇形是**弧**不是直线：每远离中心一张，牌位往远端挪一点（外侧靠后，像摊开的一叠）。
## 只挪 3 画布像素：挪多了最外那两张的远边会顶上格子行。
const HAND_ARC_PX := 3.0
## 整排中心（画布像素）：自己面前的近端空桌垫上。
##
## 出图 + 探针实测（围桌全景、窗口 1280×800）：近端那排格子屏幕 y∈[567,606]（价格行到 ~596）、
## 自己那张座位卡面板屏幕 y∈[640,715]、筹码 / 体力件屏幕 y∈[505,555]。
## 于是"自己面前的空桌垫"只剩中间那条约 34 像素高的缝。牌位就取在这条缝里：y=1729 时
## 整排的可见范围屏幕 y≈[596,638] —— 只擦到自己那排格子的**下边框**（价格行 596 之上都不挡），
## 离座位卡面板还差约 2 像素，更不碰筹码 / 体力件。**别按"平面距离"挪它**：牌是抬起来又
## 倾斜的实物，投影会把它整体推高（与 PROPS_Y 那条坑同源），只能对着出图定。
const HAND_BASE_PX := Vector2(1024.0, 1729.0)
## 每张牌朝自己倾斜的角度（绕 X 轴）：远边抬起、牌面转向镜头（相机在 +z 上方 50°）。
## 20° 是"一眼看得出是斜的、但没立起来"的位置：倾角越大牌在屏幕上越靠上、也越占高度 ——
## 它和牌尺寸一起被上面那条缝反过来钉住。
const HAND_TILT_DEG := 20.0
## 扇形：每远离中心一张，绕 Y 轴向外岔开一点。8° 配合 HAND_STEP_PX 时相邻两张刚好相接。
const HAND_FAN_DEG := 8.0
## 选中的那张**抬起来**的高度（世界单位）。选中的反馈必须在**桌上这张牌自己**身上
##（Task 6 会拆掉座位卡那排牌位，board.set_item_selected 届时空转）——抬起 + 提亮是它的反馈。
## 0.10 世界单位 ≈ 12 画布像素 ≈ 10 屏幕像素。**这条只能对着"屏幕位移"定，别按世界尺寸推**：
## 抬高是竖直方向的位移，相机俯角 50° 把它压成 cos(50°) 倍，屏幕上只挪了约 10 像素
##（0.05 那版实测只挪 6 画布像素，选中的牌与邻牌几乎分不出来）。
const HAND_SEL_LIFT := 0.10
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
		# 卡心抬到"近边正好坐在桌垫上"的高度：抬不够的话，倾斜后近边会切进桌子
		# （方块沉一半就只剩薄片 —— 同体力件那条注释）。选中的再额外抬 HAND_SEL_LIFT。
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
## 不缓存：相机推拉（滚轮）会改"你看到它的位置"，而实物的世界位置不动。
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
