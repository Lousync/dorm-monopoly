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
## 而 `_zoom` 会被取景 / 滚轮推拉 / 抽卡推近 / 人数变化改动 —— 只建一次的话，
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
