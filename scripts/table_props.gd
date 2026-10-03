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
## 而 `_zoom` 会被取景 / 滚轮推拉 / 抽卡推近 / 人数变化改动 —— 只建一次的话，
## 实体就会跟桌垫上画出来的轮子脱开。game.gd 在每次状态广播时重调这里。
func build_wheel(center_px: Vector2, radius_px: float) -> void:
	if radius_px <= 0.0:
		return
	_wheel_px = center_px
	_hit_r = radius_px * HIT_SLACK
	# 画布像素 → 世界单位。与 TableView3D.canvas_px_to_world 同一条换算：
	# 桌面 TABLE_SIZE.x 个世界单位铺满 VP_SIZE.x 个画布像素。
	var px_to_world: float = _t3.TABLE_SIZE.x / float(_t3.VP_SIZE.x)
	var r: float = radius_px * px_to_world     # 画出来的轮子在桌面平面上的半径（世界单位）
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
