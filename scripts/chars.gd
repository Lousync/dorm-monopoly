class_name GameChars
extends Node3D
## 3D 房间（二期）：**坐在椅子上的角色**（挂在 `Room/Chars` 下）。
##
## **只读表现层、绝不碰玩法** —— 与 `room.gd` / `table_props.gd` 同一条纪律：本文件不发 `@rpc`、
## 不改状态机、不读 `hp/htiles`。房间（一期）把四把椅子的锚点交出来，这里只负责
## 「把人摆到那把椅子上去」——**座位坐标一个数都不自己算**。
##
## 素材 = Kenney「Blocky Characters 2.0」（CC0，GLB，`assets/models/chars/`；普查 §一）。
## **它没有 `Skeleton3D`** —— 是「6 块刚体分件（`root` / `leg-*` / `torso` / `arm-*` / `head`）
## + `AnimationPlayer` 动**节点变换**」⇒ 摆姿势用 `rotation` / `scale`，不是 `set_bone_pose`
## （普查 §三）。**没有蒙皮 ⇒ 也没有"骨骼动画很贵"那个成本**。
##
## **二期 Task 2：座位上的人齐了** —— `slot 1/2/3` 各坐一个（**`slot 0` 仍为空**：那是「我」，
## 相机就在那儿，spec §5.1）。谁坐哪把椅子由 `set_chars(seats)` 喂进来，**那份座位序与
## `room.set_seats()` 是同一份**（`game.gd:_refresh_players()` 同一处喂）—— 各写一份就会坐错位。
## 逐座位选模型（按棋子色，见 `CHAR_MODELS_BY_COLOR`）已做；**动画播放 / 随取景淡出**
## 仍归后面的任务，这里一行都不提前写。
##
## ⚠ **静态依赖纪律**：`tests/layout_test.gd` 静态引用 `GameRoom` ⇒ `room.gd` 的整条静态依赖链
## （含本文件）会在 `--script` 启动时、**autoload 注册之前**被编译。所以本文件**不许静态引用
## autoload 链上的任何东西**（`UIKit` → `Fx` / `Net`）—— 要就照 `room.gd._ui_kit_tex()` 那样
## 运行时 `load()`。**本文件只用 `GameData`**（`class_name`，纯数据、不引 autoload：
## `NO_PEER` / `PLAYER_COLORS` 的下标）—— **连 `GameRoom` 都不写**（见 `seat_pose()`：
## 座位坐标直接读椅子锚点，正是为了不形成类名环）。

## 总开关（同 `room.gd.ROOM_ENABLED` 的用法）：置 false 就整层不建 —— 角色出任何问题都可以
## 先关掉它，不影响对局，也不影响一期的房间。
const CHARS_ENABLED := true

## 角色的缩放。**与一期家具不是同一个比例族**（普查 §六）：家具 1 模型单位 ≈ 1.95 m、
## 这个包 1 模型单位 ≈ 0.65 m ⇒ **`FURNITURE_SCALE = 10.0` 绝不能复用**
## （×10 的人 = 5.4 m 高，比整间屋子还高）。
##
## 取值 = **座面高 2.25（世界）÷ 髋枢轴 0.800（模型单位）= 2.8125** —— 拿"坐上去"当标尺反推。
## **旁证（普查 §6.4）**：这个比例下每一项都落到整数（髋 `0.800 × 2.8125 = 2.25` = 座面；
## 腿 `0.8 × 2.8125 = 2.25` = 座面高 ⇒ 脚正好落地）⇒ 它是**这个包作者自己的比例**，不是凑的。
## 旁证的另一面："腿的下沿落座面"那套口径（`2.25 / 0.600 = 3.75`）出图看是个**巨人**（站立 2.03 m），
## 已否决（普查 §6.3 的表）。
const CHARS_SCALE := 2.8125

## 坐姿的**整体下移**（模型单位，负 = 往下）：髋枢轴 `1.000 → 0.800`，正好落到座面（普查 §5.2）。
## **这正是包自带 `sit` 的那一键**（作者设的座面就是 `0.8`）——我们不用的只是 `sit` 的**腿**
## （它把腿平举，见 `LEG_SQUASH`）。
##
## ⚠ **它必须加在角色之上的"外套节点"上**，不能加在 GLB 的 `root` 上：导入器把 `idle` 里
## `root` 的**常值轨道压成 1 帧**留着（普查 §3 细节 3）⇒ **一播 `idle` 就把 `root.position.y`
## 写回 0**，坐姿被顶掉（普查 §5.3 实测）。外套节点 `AnimationPlayer` 够不着它。
const SEAT_ROOT_Y := -0.2

## 腿的**竖直压短**（`leg-*` 的 `scale.y`）：腿是一整块刚体、**没有膝关节**，所以"坐"只能靠压短 ——
## `1.000 → 0.800` ⇒ 脚正好落回地面（普查 §5.2）。**腿保持竖直（不转）**，因此根本够不到桌沿；
## 包自带的 `sit` 把腿**平举**，会越过桌沿 `1.66` 世界 = **33 cm 捅进桌子底座**（普查 §7.1）。
## 留在分件自己身上是安全的：**这个包里没有任何 `scale` 轨道**，动画顶不掉它（普查 §5.3）。
const LEG_SQUASH := 0.8

## 角色的**色调**（本轮 fix round：把角色收进房间的暗色调）。乘在模型自带 `albedo_color` 上 ——
## 而在 Godot 里 `albedo_color` **乘在 `albedo_texture` 上** ⇒ 压暗整张贴图，一张不丢（`_shade`）。
##
## **病因（出图实证，Ruling E2）**：这个包的贴图是 Kenney 展示用的**高饱和亮色** ——
## 实测「网格真正贴上去那一块」的平均色：手臂 `0.754/0.543/0.407`（有效 albedo 亮度 **0.58**）、
## 躯干 `0.536/0.364/0.284`（0.40）、裤腿 `0.240/0.496/0.389`（0.43）、头 `0.329/0.312/0.321`（0.32）。
## 而屋里最亮的**木头外框**只有 **0.16**、家具只有 **0.08**（同一把尺子：色调 ⊙ 贴图那一块的平均色）
## ⇒ 角色是画面上**唯一发亮的东西**，读作"桌上摆了个玩偶"、"灰头 + 橙身"（Ruling E2）。
##
## **做法 = 一期 Task 8 对家具做的同一手**（那次能整片换材质是因为家具是纯色、无所谓；角色有脸、
## 有衣服，只能乘法压暗）。
##
## **取值**：`0.29/0.25/0.21`（亮度 **0.264**）—— 与一期家具的 `FURN_ALBEDO`（`0.34/0.27/0.21`，
## 亮度 0.281）**同族、略暗一点**。
##
## ⚠ **本任务（Task 2）把它从 `0.36/0.30/0.26` 调到 `0.29/0.25/0.21`（≈ ×0.81）** —— 理由**不是**
## 观感变了，而是**判据的适用面变宽了**：见 `CHAR_MODELS_BY_COLOR` 那段，**左座吃到的照度是
## 右座的 1.385 倍**，Task 1 的取值只按右座留了余量（实测 0.826）；三个座位一起来，**最坏那个
## 座位**才是判据要守的。降下来之后**实测**（`chars_test` 的"最坏座位 × 全部色号"那一段）：
## `k 0.728 / g 0.744 / n 0.910 / p 0.837`，最坏 **0.910** —— 与 Task 1 当年的 0.826 同档有余量。
##
## **代价（如实记）**：数值上暗了约 19%，但**实测的脸并不比 Task 1 验收时暗** —— 判据把"亮脸的
## 模型"整个挡在门外（`CHAR_MODELS_BY_COLOR` ①），选出来的这四个贴图本身就更暗、压得少；
## 实测头部那块 0.10~0.12，而 Task 1 验收的 `character-a` 是 **0.116** ⇒ **观感同档**，
## 变的是"哪个模型"，不是"暗了多少"。
##
## **判据（可执行，`chars_test` 钉着）**：三个人里**最亮的那一笔**（各自的有效 albedo × 各自
## 座位上的照度）**不许高过桌面那一笔**（同一把照度代理式、同一把 albedo 尺子）；
## **改回 `Color(1,1,1)`（= 不压暗）这条立刻红**。
const CHAR_TINT := Color(0.29, 0.25, 0.21)

## **头部额外缩放**（本轮 fix round 的有界实验，见 `.superpowers/sdd/3D房间-二期-实施计划/fix-chars-t1-report.md`）。
## `head` 节点自己带一层嵌套 `scale 0.1`（导入器把模型的比例搬到了节点上），这里**再乘一个小系数**，
## 让"头几乎占可见身高四成"的**吉祥物剪影**收一点。
##
## **值 = 0.82**。实验口径：近景摆拍比对 `1.0`（原样）/ `0.8` / `0.72` 三档 + 拉远端（屋子那一档）
## 比对 `1.0` 对 `0.82` —— 两处都是 1.0 的头明显更大更"玩偶"；**保留 0.82**。
## `0.72` 那档**过头了**：头与肩之间露出缝（脖子那一截空了），取 0.8~0.82 这一档。
## **它是"乘"不是"设"**（`head.scale *= HEAD_SHRINK`）：模型自带的 0.1 是导入器的比例，
## 覆盖掉会把头放大十倍。
const HEAD_SHRINK := 0.82

## **一个棋子色 = 一个固定模型**（下标 = `GameData.PLAYER_COLORS` 的下标，= `st` 里各家的 `p.color`）。
## ⇒ **同一个 peer 永远拿到同一张脸**：重广播 / 重连 / 换轮次都不换脸（本任务的硬要求）。
##
## ⚠ **为什么是 4 个而不是 3 个**（与计划书的字面「18 个里挑 3 个」不同，理由如下）：
## 棋盘上 4 家各占一个**棋子色**（`PLAYER_COLORS` 4 个），而同时露脸的只有 3 家
## （`slot 0` = 我，不渲染）。**若只挑 3 个模型按色号取，4 个色号 → 3 个模型按鸽笼原理必然撞车**
## ⇒ 四人局里那两家会**长得一模一样**（哪两家撞取决于当局用到了哪些色号，实测 4 种色号组合里
## 有 2 种会撞 = 一半的对局），而 spec §十 F8 的定案是「**四家各有模型**、靠角色本身认人」
## ⇒ 那正是本任务要保住的东西。4 个模型一一对应，**永不撞车**（同一局 4 个色号互不相同）。
##
## **这 4 个是怎么挑出来的**（口径可复现，逐项读数见 `task-2-report.md`）：把 18 个模型按
## 「色调 ⊙ 那一块贴图的平均色」逐件量一遍，再筛三关：
##  ① **不许亮过桌面**（Ruling E2 的 J1 判据）—— ⚠ **门槛要按"最亮的那个座位"算，不是 Task 1
##     那个座位**：吊灯在 `LAMP_LIGHT_POS.x = -4.13`（灯挂在桌子**偏左**上方），实测**左座
##     （slot 3）吃到的照度是右座（slot 1）的 1.385 倍**。Task 1 只做了右座 ⇒ 那时 `CHAR_TINT`
##     的余量是"右座的余量"（实测比值 0.826），**换到左座同一个人就会红**
##     （拿 Task 1 的 `character-a` 放左座实算 1.145）⇒ 本任务起判据必须按**最坏座位**收敛。
##     在左座上要过线，"最亮那件"的有效 albedo 得 ≤ 0.159 ⇒ **18 个里只有 8 个合格**
##     （脸最亮的 `a/c/d/e/i` 全出局）—— 这不是挑色，是**房间的灯**定下来的。
##  ② **脸不能被压黑**（spec §十 F8 要认人）：剩下的 8 个里取**头部那块最亮**的；
##  ③ 再在池子里取**两两最不像**的一组（按头 / 躯干 / 双臂 / 双腿各自那块贴图的 8×8 / 4×4
##     取样签名求最小两两距离，最大化它）—— 排掉了近似的 `g`/`h` 双胞胎（同脸、只差胸前
##     一道红 / 紫条纹，压暗后基本读不出差别）。
## **成品**：`k`（棕发棕脸 + 砖红上衣，胡子）/ `g`（蓝灰 + 胸前红闪电）/ `n`（**绿身子 + 红腰带、
## 一张白脸** —— 四个里最好认的一张脸）/ `p`（紫蓝马甲 + 金背带）。四个头都还亮（压暗后
## 0.10~0.12，与 Task 1 验收时的 `character-a` 头 0.116 同档）。
## **顺带对上两个棋子色**（不是挑选条件，是巧）：蓝 → `g`、绿 → `n`；橙 / 黄没有对应的模型
## （包里没有橙人 / 黄人），按"先保脸再配色"的原则**不为配色牺牲脸**。
const CHAR_MODELS_BY_COLOR := [
	"character-k.glb",   # 0 橙：砖红上衣 + 棕发棕脸（暖色一族里最像橙的）
	"character-g.glb",   # 1 蓝：蓝灰身子 + 胸前一道红闪电
	"character-n.glb",   # 2 绿：**绿身子 + 红腰带**，一张白脸（四个里最好认的一张脸）
	"character-p.glb",   # 3 黄：紫蓝马甲 + 金背带（暖金那一笔在背带上）
]

## 「我」的座位号：**0 = 近侧 = 相机所在那一侧**（spec §5.1）⇒ 这个座位上**不出人**
## （一期只在那一侧留椅背 + 名牌）。`set_chars()` 跳过它，`char_peers()` 在那里给 `NO_PEER`。
const MY_SLOT := 0

## 一期那四把椅子（`Room/Seats`）—— 座位坐标的**唯一来源**（见 `seat_pose()`）。
var _seats: Node3D

## 每个 slot 上的**角色外套节点**（`Node3D`），**下标 = 椅子号**（与 `seat_anchor(slot)` 同一序）；
## 没人的槽位是 `null`。与 `_char_peers` / `_char_models` 三者**同进同出**（都在 `set_chars` 里重建）。
var _chars: Array = []
## 每个 slot 上的 peer（`GameData.NO_PEER` = 这个座位上没人）。`char_peers()` 直接返回它。
var _char_peers: Array = []
## 每个 slot 上的模型文件名（`""` = 这个座位上没人）。`char_model()` 直接返回它。
var _char_models: Array = []
## 上一次喂进来的那份座位序的指纹（**早退用**，与 `room.gd.set_seats` 同款同序）。
## `_refresh_players()` 每次状态广播都会调 `set_chars()` —— 少了这条早退，每次广播都会把
## 三个人**整套重建一遍**（重新 `load()` GLB + 重新实例化 + 重新复制材质）。
var _char_key := ""

## 建角色层。**只建节点，不摆人** —— 摆人要读座位锚点的 `global_transform`，那要求整棵子树
## **已经入树**；而 `build()` 是 `table_3d._init()` 里调的，那时还没入树（读全局量会打
## `Condition "!is_inside_tree()" is true` 并**静默写错值**，同一期 `_build_furniture` 那条）。
##
## **摆人一律由 `set_chars()` 驱动**（`game.gd:_refresh_players()` 每次状态广播喂一份座位序）
## —— **不在 `_ready()` 里摆**：`_ready` 那一刻还没有任何状态，"谁坐哪"根本无从谈起
## （一期 Task 5 的 `set_seats()` 就是同一条理由，同一处喂）。
static func build(parent: Node3D, seats: Node3D) -> GameChars:
	if not CHARS_ENABLED:
		return null
	var c := GameChars.new()
	c.name = "Chars"
	# **先塞座位表、再加进树**：父节点已经在树里时 `add_child()` 会**同步**触发 `_ready()`,
	# 那时 `_seats` 还是空的（这一身位是给"房间建完就入树"的场景留的）。
	c._seats = seats
	parent.add_child(c)
	return c

## 喂座位序：`[{peer, color, name}, …]`，**下标 = 椅子号**（与 `room.set_seats()` 逐项相同，
## 都由 `game.gd:_refresh_players()` 从 `_seat_peers()` 推出来）。
##
## **`MY_SLOT`（0 = 我）不出人**；其余每把椅子按**那一家的棋子色**选模型（`CHAR_MODELS_BY_COLOR`）。
## **顺序 / 颜色 / 名字一字未变时直接返回**（与 `room.set_seats` 同款早退：本函数每次广播都调，
## 少了它每次广播都要把三个人整套重建）。
func set_chars(seats: Array) -> void:
	# ⚠ 座位锚点是 `global_transform` ⇒ **只在入树之后调**（同 `room.seat_anchor` 那条）。
	# 不入树就读全局量会打 ERROR 并**静默写错值** ⇒ 这里宁可什么都不做（也**不记指纹**：
	# 下一次带着正确的树再来一次，仍然会建）。
	if not is_inside_tree():
		push_warning("角色层还没入树：set_chars() 要在入树之后调（座位锚点才读得准）")
		return
	var key := ""
	for s in seats:
		var d: Dictionary = s
		key += "%d/%d/%s|" % [int(d.get("peer", GameData.NO_PEER)),
			int(d.get("color", 0)), String(d.get("name", ""))]
	if key == _char_key:
		return
	_char_key = key
	_clear()
	for i in seats.size():
		if i == MY_SLOT:
			# 「我」这一侧不出人（spec §5.1）：三个数组都记一个"空位"，下标才对得上椅子号。
			_chars.append(null)
			_char_peers.append(GameData.NO_PEER)
			_char_models.append("")
			continue
		var color := int((seats[i] as Dictionary).get("color", 0))
		var model := model_for_color(color)
		_chars.append(_place(i, model))
		_char_peers.append(int((seats[i] as Dictionary).get("peer", GameData.NO_PEER)))
		_char_models.append(model)

## 第 `slot` 把椅子上那个人**是哪一家**（`GameData.NO_PEER` = 那个座位上没人）。
##
## **返回的是逐槽位的数组**（下标 = 椅子号，长度 = 上一次喂进来的座位数）⇒ 与房主的
## `game._seat_peers()` **逐位对齐**（`slot 0` 是 `NO_PEER` —— 那是「我」，不渲染）。
## 房主那份里 `slot 0` 是**我自己的 peer**，所以两者**只在第 0 位不同**（`hud_test` 钉着这条）。
func char_peers() -> Array:
	return _char_peers

## 第 `slot` 把椅子上那个人**用的哪个模型**（`""` = 那个座位上没人）。测试用它核对
## "按棋子色选、不是按椅子号选"（同一份座位序里让"色号"与"座位号"处处不等）。
func char_model(slot: int) -> String:
	if slot < 0 or slot >= _char_models.size():
		return ""
	return String(_char_models[slot])

## 棋子色 → 模型文件名（`CHAR_MODELS_BY_COLOR` 的查表，越界钳到最后一档，同
## `room.gd._refresh_nameplates` 对色号的处理）。**纯查表、无副作用** ⇒ 测试可以直接引用它。
static func model_for_color(color: int) -> String:
	return CHAR_MODELS_BY_COLOR[clampi(color, 0, CHAR_MODELS_BY_COLOR.size() - 1)]

## 拆掉当前所有角色（**先 `remove_child` 再 `queue_free`**：`queue_free` 要到帧末才真的释放，
## 只调它的话紧接着的 `get_node_or_null("Char1")` 还会找到**旧人**——测试与出图都会读错）。
func _clear() -> void:
	for c in _chars:
		if c != null and is_instance_valid(c):
			remove_child(c)
			c.queue_free()
	_chars.clear()
	_char_peers.clear()
	_char_models.clear()

## 第 `slot` 把椅子上**人该站的那一点**（位置 + 朝向）。
##
## = 一期 `GameRoom.seat_anchor(slot)` 的同一个变换（朝向一个字不改：角色正面 = `+Z`，
## 普查 §4.3 量出来的，与"椅子绕 Y 转到自己的 `+z` 指向桌心"天然对齐 ⇒ **不用补 180°**，
## 那是这里最直觉、也最容易多绕一次的错），再沿**它自己的 −Y** 下移 `SEAT_ROOT_Y × CHARS_SCALE`
## （世界单位）把坐姿偏移带上。
##
## ⚠ **读的是座位节点的 `global_transform`** —— 与 `GameRoom.seat_anchor(slot)` 是**同一个**变换
## （一期那个方法就是 `return (seats.get_child(slot) as Node3D).global_transform`，一个数都不算）。
## 这里直接读同一处，是为了**不把 `GameRoom` 写成本文件的静态依赖**（`room.gd` 已经静态引用本文件，
## 再反向引用会形成类名环）。**座位坐标仍然只有一处来源：椅子的锚点。**
func seat_pose(slot: int) -> Transform3D:
	if _seats == null or slot < 0 or slot >= _seats.get_child_count():
		return Transform3D()
	var anchor := (_seats.get_child(slot) as Node3D).global_transform
	# `translated_local`：沿**锚点自己的** Y 轴挪（椅子只绕 Y 转 ⇒ 与世界 Y 同向；
	# 但写成局部的那一版，将来椅子要是加了倾角也不会错）。
	return anchor.translated_local(Vector3(0.0, SEAT_ROOT_Y * CHARS_SCALE, 0.0))

## 把 `model` 这个人摆到第 `slot` 把椅子上。返回**外套节点**（没摆成给 null）。
func _place(slot: int, model: String) -> Node3D:
	var packed: PackedScene = load("res://assets/models/chars/%s" % model)
	if packed == null:
		push_warning("角色缺模型：%s（跳过）" % model)
		return null
	# **外套节点**：坐姿的整体下移放在它身上（见 `SEAT_ROOT_Y` 那段）——`AnimationPlayer`
	# 够不着它，`idle` 顶不掉。它也是将来"随取景淡出 / 停播"要按的锚（Task 3）。
	var wrapper := Node3D.new()
	wrapper.name = "Char%d" % slot
	add_child(wrapper)
	wrapper.transform = seat_pose(slot)
	var mi := packed.instantiate() as Node3D
	wrapper.add_child(mi)
	# **缩放只改变外形，不改"站哪儿"**（同一期家具那条纪律）：外套节点的位置活在房间那一系里，
	# 与它子节点的 `scale` 无关。模型的原点在脚底 ⇒ 绕着它放大不会陷进地板。
	mi.scale = Vector3.ONE * CHARS_SCALE
	# 腿：**竖直压短**（不转）—— 手摆坐姿的另一半，见 `LEG_SQUASH`。
	# 走 `find_child` 而不是写死 `root/leg-left`：层级见普查 §三（`character-a → root → leg-*`），
	# 将来导入器多包一层时这里不会静默失效（腿没被压到 ⇒ 脚到不了地面，`chars_test` 立刻红）。
	for nm in ["leg-left", "leg-right"]:
		var leg := mi.find_child(nm, true, false) as Node3D
		if leg != null:
			leg.scale = Vector3(1.0, LEG_SQUASH, 1.0)
	# 头：**再乘一个小系数**（见 `HEAD_SHRINK`）。走 `find_child` 与腿同一条理由（层级见普查 §三）。
	var head := mi.find_child("head", true, false) as Node3D
	if head != null:
		head.scale *= HEAD_SHRINK
	_shade(mi)
	_no_shadow(mi)
	return wrapper

## 角色材质：**只调光照参数、绝不碰 `albedo_texture`**（普查 §7.2 那条硬约束）。
##
## **为什么必须调**：这个包自带 `KHR_materials_unlit` ⇒ Godot 导成 `SHADING_MODE_UNSHADED`
## ⇒ 角色**不响应一期的光照契约**（吊灯 + `FILL_LIGHT_POS` 那盏补光），会是屋里唯一
## 不随房间明暗变化的东西，与"暗木 + 灰墙"的层次脱节。
##
## **为什么不能照抄 `room.gd._paint()`**：那把**整份材质换掉**（家具是纯色、无所谓），套到角色
## 身上会把**贴图（脸 / 衣服）一起抹掉** —— 换来的是一块暗木头。⇒ 这里动两项：`shading_mode`
## （受光）与 `albedo_color`（色调，见 `CHAR_TINT`）；**`albedo_texture` / uv 那一套一概不碰**。
##
## ⚠ **`albedo_texture` 一个字节都不许动** —— `chars_test` 有一条钉着"贴图还是角色自己那张"，
## 而角色**只靠贴图认人**（spec §十 F8）。色调一律走 `albedo_color`（它在 Godot 里乘在贴图上）。
##
## 做法照 `room.gd._dim_subtree()`：**按面覆盖 + 先复制一份**。复制那一步不是可选的：
## `instantiate()` 出来的材质与 `PackedScene` **共用同一份资源**，直接改会污染缓存里的那份
## （同一场景第二次实例化就带着上一次的改动）；每个 `MeshInstance3D` 复制自己那份 ⇒ 角色之间也不串。
static func _shade(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as MeshInstance3D
		if gi == null or gi.mesh == null:
			continue
		for s in gi.mesh.get_surface_count():
			var src := gi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			# **色调**：乘在自带底色上（在 Godot 里 `albedo_color` 是乘在 `albedo_texture` 上的）
			# ⇒ 整张脸 / 衣服一起压暗，而贴图本身一个字节没动（见 `CHAR_TINT` 那段）。
			m.albedo_color = Color(src.albedo_color.r * CHAR_TINT.r, src.albedo_color.g * CHAR_TINT.g,
				src.albedo_color.b * CHAR_TINT.b, src.albedo_color.a)
			gi.set_surface_override_material(s, m)

## 一棵子树里的几何实例**逐个关投影**（房间的纪律：全场唯一投影源是那盏吊灯）。
## 与 `room.gd._no_shadow` 同一条理由：`instantiate()` 出来的节点不继承父级的 shadow 设置。
##
## **角色的决定：不投影**（本任务的一个明确取舍）。理由是可执行的，不是"顺手"：
## `layout_test` 那条「房间物件一律不投影」扫的正是 `Room` **整棵子树** —— 角色一投影，
## 那条立刻红；而一期立的"只有一处投影源"是**影子预算**的合同（多一个投影物件 = 多一张
## 阴影图），角色没有"非投影不可"的实测理由（吊灯本来就打在它们身上）。
static func _no_shadow(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
