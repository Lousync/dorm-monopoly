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
const CAM_DIST := 5.8            # 相机到注视点的水平距离。窗口恢复为整张画布后桌面回到 8×8，
                                 # 内容整体向近端挪了 0.68 个世界单位（新并入的顶部死区在远端），
                                 # 原来 4.4 会把近端的下家座位栏顶出屏幕底部 —— 必须拉远。

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

# 纹理窗口 = 整张画布。取景会把内容（含四条座位栏）铺满画布，裁掉任一边都可能
# 让某条座位栏既看不见也点不到（见 T4b/T4c）。比例目标推迟到批次 3（座位栏将换成桌上立牌）。
#
# 曾一度裁到 Rect2(0, 348, 2048, 1700) 让「棋盘铺满桌面」：上家的座位栏在画布 y∈[16,211]，
# 正好落在被裁掉的顶部，于是它在画布内、却在窗口外 —— 桌面上既看不见也点不到，
# 指向性道具（交换生 / 跑腿券 / 强拆令）选不中上家。交互优先于比例，恢复整张画布。
const TEX_WINDOW_PX := Rect2(0.0, 0.0, 2048.0, 2048.0)
# 桌面进深：与窗口同比例，否则贴图会被拉伸。
const TABLE_D := TABLE_W * TEX_WINDOW_PX.size.y / TEX_WINDOW_PX.size.x
const TABLE_SIZE := Vector2(TABLE_W, TABLE_D)

var board: BoardView
var viewport: SubViewport
var camera: Camera3D
var table_mesh: MeshInstance3D
var vignette: ColorRect        # 屏幕层暗角贴片（build_vignette 造，挂在调用方给的屏幕上）

var table_mat: StandardMaterial3D   # 桌面材质（取样窗口与 TEX_WINDOW_PX 同源）

## 实体物件层：与桌垫共用同一套 UV 坐标系，物件都挂这里（见设计稿 §五）。
## 桌垫（table_mesh）只是"印在桌上的画"；转盘 / 筹码 / 体力件 / 手牌这些有厚度、
## 能投影的实体一律挂 props，摆位走 canvas_px_to_world。
var props: Node3D

## 实体物件的构建与刷新（转盘 / 筹码堆 / 体力件 / 手牌，见 scripts/table_props.gd）。
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
	_build_table()
	_build_props()          # 实体物件层要在桌垫坐标系就绪之后建
	_build_table_props()    # 实体物件本身（转盘等）挂在 props 下
	_build_camera()
	_build_viewport()

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.06, 0.085)   # 桌面之外的暗色房间
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.45)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

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
	table_mat.uv1_scale = Vector3(1.0, TEX_WINDOW_PX.size.y / float(VP_SIZE.y), 1.0)
	table_mat.uv1_offset = Vector3(TEX_WINDOW_PX.position.x / float(VP_SIZE.x),
		TEX_WINDOW_PX.position.y / float(VP_SIZE.y), 0.0)
	table_mesh.material_override = table_mat
	add_child(table_mesh)

	# 一盏暖色顶灯（设计稿 §二：OmniLight3D 带阴影）。用点光而不是平行光：平行光在桌面上
	# 是均匀的，给不出纵深；点光吊在中心上方，桌面外圈自然压暗 —— Compatibility 没有 SSAO，
	# 氛围全靠它 + 屏幕层暗角（设计稿 §6.4 的七成目标）。
	# 灯压得比相机低、range 收紧：吊太高 / range 太宽 = 桌面上几乎均匀，纵深感出不来
	# （实测 y=3.4 / range=12 时中心与远端只差 14%）。y=2.4 / range=8.5 时中心 0.70、
	# 远端 0.48、四角 0.33 —— 中心亮、四周压暗。
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 2.4, 0.4)
	light.light_color = Color(1.0, 0.90, 0.78)    # 暖顶光
	light.light_energy = 2.4
	light.omni_range = 8.5
	light.omni_attenuation = 1.0
	# 批次 3：桌上已经有实体物件了（转盘 / 筹码 / 手牌，挂在 TableView3D.props），阴影重新打开
	# —— 物件才投得出影子。批次 2 曾因"场景里只有桌面板本身、没有任何投影物"而关掉：
	# 那时开了等于每帧白跑一张（双抛物面 = 2 个 pass）阴影图，画面一点不变。
	light.shadow_enabled = true
	add_child(light)

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
