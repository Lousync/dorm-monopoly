extends SceneTree
## 二期 Task 2：**四个座位（3 个角色）+ 座位 ↔ peer 固化**
## godot --headless --path . --script tests/chars_test.gd
##
## Task 1 立的判据一条不丢（①~⑤ 与"不投影"），**逐条按三个角色重述**（原来只有 slot 1 一个），
## 另加本任务的两条：
##   ① `slot 1/2/3` 各坐一个人、**`slot 0`（近侧 = 「我」，相机就在那儿）一个人都没有**；
##   ② 每个人都站在**自己那把椅子**的锚点上（xz 与朝向都读一期 `seat_anchor(slot)`，不另算）；
##   ③ **脚底落在 `FLOOR_Y`、髋落在座面**（手摆坐姿对不对的唯一硬判据）；
##   ④ 角色**不与桌子相交** —— 逐件、对桌子的**实体体积**（底座 ∪ 桌面那一层）量体积相交；
##   ⑤ 材质**不是 `SHADING_MODE_UNSHADED`**、**底色只被压暗过**、**贴图还是自己那张**；
##   ⑥ **角色不许是画面里最亮的东西**（Ruling E2 的 J1）：三人的有效 albedo × 照度，
##      最亮那个也不许高过桌面那一笔（同一把尺子）；
##   ⑦ 三个人**两两不相交**（各在各自椅子上，互相不穿）；
##   ⑧ 不投影（房间的纪律：全场唯一投影源是那盏吊灯）。
##   **【本轮新增】** ⑨ **模型按棋子色选**（`CHAR_MODELS_BY_COLOR`）——喂进来的座位序里
##      **"色号"与"座位号"处处不等** ⇒ 按椅子号取模型的话这条必红；
##      ⑩ **同一个 peer 换椅子坐仍是同一张脸**（座位序轮转一格后逐家比对）；
##      ⑪ **同样的座位序再来一次 = 同一批节点实例**（`set_chars` 的早退；
##      去掉早退这条立刻红 —— 每次广播都把三个人整套重建）。
##   **【v0.8.0 改版：完全静止 + 头顶名牌】**（用户 2026-10-06 判图后拍板：人物不要乱动，
##      并且"靠角色本身认人"读不出来 ⇒ 加标识。**本条推翻了二期 spec §5.7 的旧定案**）
##      ⑫ **三个人一帧动画都不播**（`is_playing()` 全假 —— "完全静止"就是它）；
##      ⑬ **静止是选择、不是"没有动画"**（那条 `idle` 仍在模型里、且**真的静止**：同一分件在
##      两个真实时间点上的世界位置必须**一模一样** —— 只拍一帧既证明不了在动、也证明不了没动）；
##      ⑭ **取景四档下角色恒可见**（默认档 / 拉远端 / 推近端 / 2D 端 —— 走真接口
##      `snap_dolly` / `snap_view` 逐档量"可见 + 不透明"）。
##      **【v0.8.0 第三次改版】**：用户 2026-10-06 第三条「**2D 视角下人物不要消失**」⇒
##      **淡出整段取消**（`set_fade` / `FADE_*` / `_apply_fade` / `_process` 全删），
##      原先的 ⑮（`set_fade` 阈值契约）与 ⑯（`FADE_NEAR_DOLLY` == `DOLLY_MIN`）随之删除。
##      **为什么连 3D 端那两档一起取消**：淡出是为"读棋盘别被二期拖慢"付的账，而待机动画
##      已经退场（人物完全静止）、三个静止角色测不出成本 ⇒ 省不出东西，只留下"推近就消失"
##      这一种会被当成 bug 的表现。
##      ⑰ **头顶名牌**（棋子色牌 + 昵称、billboard 朝向镜头、立在头顶之上；
##      **当前行动者靠牌上一圈金边**表达 —— 原先那条"同一条 `idle` 提速"随"完全静止"一起退场）。
##   **【已删除】** 原 ⑱「淡出档上的反应丢掉播放」—— **没有淡出档了**（见 ⑭）。
##      它钉的那条契约（`react()` 在全隐档早退）随 `_faded_out()` 一起退场；而它后半段
##      真正有长期价值的那条 ——「**破产记忆活过重建**，不是靠"播放"活下来的」——
##      由 ⑯-b（重建后仍趴在座位上）继续守着。
##   **【fix round 3】**(c2) 的相位采样步长 **0.1 → 0.05**（终审 N-3：步长 0.1 能跨过比它更窄
##      的特征；均匀加密使可漏过的最窄特征宽度也减半，且不依赖"特征在哪"这个会漂的假设）。
##   **【fix round 2】(c2) 重做**（终审 Concerns 2：那条断言**按相位随机红**）：
##      ① **相位钉死** —— 原先 `react()` 后 `await process_frame` 再量，相位 = 若干个真实帧长、
##         随机器负载漂（出牌那条伸手动作在相位 0.02 s 净空 +0.803、0.14 s −0.163 ⇒ 抖 0.14 s
##         就从"分得很开"翻到"插进去"）。改成照 ⑬ 的手法 `seek(固定相位, true) + pause()`，
##         并对一串覆盖 [0,1] 的相位逐个量 ⇒ 读数与运行时机无关（连跑 N 次给出同一批数）。
##      ② **判据按姿态类分开** —— 判据 ③（"不许与桌子实体体积相交"）是**为坐姿发明的**，
##         抓的是"腿从座面下穿出去"那一类；而**出牌是伸手动作**，手落到**桌面平面以下、桌子
##         足迹以内**时**桌面把它挡住了**（俯视相机）⇒ 读作"把手放在桌上"，不是穿模。
##         三条一次性动作改判「**不许有看得见的穿模**」：进入桌子实体体积的分件必须**整件落在
##         桌面平面以下**；若在足迹内**顶面高过桌面平面** ⇒ 那才是看得见的穿模 = 真缺陷，报出来。
##         **坐姿（④）与破产收势（(f2)(g)）不适用这条放宽 —— 仍是零相交**（判据 ③ 原样）。
##
## 坐姿不是包里的 `sit`（腿是一整块刚体、无膝关节，`sit` 把腿平举 ⇒ 会捅进桌子 1.66 世界），
## 是**手摆**（普查 §5.2）：整体下移 `SEAT_ROOT_Y` + 腿竖直压到 `LEG_SQUASH`
## ⇒ 脚底回到地面、髋回到座面。下移**放在角色之上的外套节点**上（`idle` 有一条 `root`
## 常值轨道，一播就把 `root.position.y` 顶回 0）。

var fails := 0

## 本任务有人的三个座位（**0 号不算**：那是「我」）。
const CHAR_SLOTS := [1, 2, 3]
## 「我」的座位：0 号 = 近侧 = 相机这一侧 ⇒ **不渲染**（spec §5.1）。
const MY_SLOT := 0
## 一期椅子座面离地（`room.gd` 的比例表：座面 = `FLOOR_Y + 2.25` = 真实 0.45 m 座高）。
## **不是**本文件的实现常量 —— 它是房间那边的既有事实，这里拿它当坐姿的外尺。
const SEAT_H := 2.25

## 破产姿态的**实测读数**（判据同一把尺子量两次：刚破产时 / 一次整体重建之后）。返回：
##   * `top` / `low`：全部分件的世界 AABB 的最高点 / 最低点（"人还在座位上、看得见"靠它）；
##   * `head_y`：头分件的世界 y（**在桌面上方** = 从相机看没被桌子挡掉）；
##   * `hits` / `worst`：逐分件与**桌子实体体积**（底座 ∪ 桌面那一层）的相交件数 / 最近净空
##     —— 与 Task 1 立的判据 ③ **同一口径**（合并 AABB 不算数，那 5 mm 是浮在桌上的头）。
func _death_pose(w: Node3D, t3: Node) -> Dictionary:
	var out := {"top": -INF, "low": INF, "head_y": -INF, "hits": 0, "worst": INF}
	if w == null:
		return out
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	var tmat: MeshInstance3D = t3.get("table_mesh")
	if tbase == null or tbase.mesh == null or tmat == null or tmat.mesh == null:
		return out
	var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
	var tma: AABB = tmat.global_transform * tmat.mesh.get_aabb()
	var slab := AABB(Vector3(tma.position.x, tb.end.y, tma.position.z),
		Vector3(tma.size.x, tma.position.y - tb.end.y, tma.size.z))
	var head := w.find_child("head", true, false) as Node3D
	if head != null:
		out.head_y = head.global_position.y
	for n in w.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null or g.mesh == null:
			continue
		var a: AABB = g.global_transform * g.mesh.get_aabb()
		out.top = maxf(out.top, a.end.y)
		out.low = minf(out.low, a.position.y)
		var gp: float = maxf(_aabb_gap(a, tb), _aabb_gap(a, slab))
		out.worst = minf(out.worst, gp)
		if gp <= 0.0:
			out.hits = int(out.hits) + 1
	return out

## 桌子的**实体体积**与**桌面平面**（(c2) 的反应姿态判据与 (f2) 的破产收势读数共用这一处口径）。
##
##   * `tb`：底座（`TableBase`，从地板顶到木纹外框底面）；
##   * `slab`：**桌面那一层**（桌面的足迹 × [底座顶面, 桌面上表面]）—— 底座顶面到桌面上表面那一段
##     也是实木；不带它，"从桌面上方捅进去"这种穿法量不出来（判据 ④ 立这条时的原话）；
##   * `top`：**不透明桌面的那个平面**（`table_mesh` 那一片的 y）—— (c2) 的"从上方被桌面挡住"
##     量的就是它。
##
## **从场景里量、不写死数**：写死一个 0.0 等于把一期的几何重述一遍 —— 桌子挪了、判据还是绿的。
## 量不到（桌子还没建好）返回 `{}`，调用点据此跳过。
func _table_vol(t3: Node) -> Dictionary:
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	var tmat: MeshInstance3D = t3.get("table_mesh")
	if tbase == null or tbase.mesh == null or tmat == null or tmat.mesh == null:
		return {}
	var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
	var tma: AABB = tmat.global_transform * tmat.mesh.get_aabb()
	var slab := AABB(Vector3(tma.position.x, tb.end.y, tma.position.z),
		Vector3(tma.size.x, tma.position.y - tb.end.y, tma.size.z))
	return {"tb": tb, "slab": slab, "top": tma.position.y}

## 一个人**在当前姿态下**与桌子实体体积的关系（**逐件、按几何顶点**量）。返回：
##   * `grew` / `grew_names`：**看得见的穿模**件数 —— 这一件在**足迹以内有高过桌面平面的几何**、
##     却**没有任何"足迹以外、也高过桌面"的几何** ⇒ 它在桌面上方那一截**与桌子外面接不上**，
##     是**从桌子里面长出来的**（(c2) 的判据量的就是它）；
##   * `buried`：**真的有几何进到桌子实体体积里**的分件数（足迹以内、桌面平面以下 —— 埋在木料里，
##     从上方看不见）；`deep`：进到多深（足迹以内最低的那个顶点）；
##   * `proud` / `proud_names`：那些"进了桌子"的分件里，**在足迹以内、又高过桌面平面**的最高那一点
##     高出桌面多少（**读数**：把"从桌沿外伸进来"那一档的几何高度记下来）；
##   * `lean`：只**越过桌沿**的分件数（足迹以内有顶点、但**都**在桌面平面以上）—— 那是"身子探到
##     桌沿上方那一段"，**不是穿模**（人比桌子宽、又只坐得离桌沿 23 cm，这是布局的既成事实）；
##   * `low`：全部分件世界 AABB 的最低点（核"没掉到地板以下"）；
##   * `hits` / `worst`：**AABB 口径**的相交件数 / 最近净空 —— **只作读数、不当判据**。
##
## ⚠ **为什么"进没进桌子"必须按几何顶点问、不能按 AABB 问**（本轮实测）：
## 这个包的 AABB 对**转过角度**的分件太松 —— `interact-right` 伸手那一帧（相位 0.70）实测
## `arm-right` 世界 AABB 是 `x[2.53, 5.81] × y[-0.905, 1.396]`，可它的**顶点**在桌子足迹以内
## 只有 `y ∈ [-0.905, +0.120]` 那一段。拿 AABB 的顶面（+1.396）去比桌面平面，会得出"这一件
## 高过桌面 1.4 世界 = 28 cm"的结论 —— 而**几何从来没有高过桌面 0.12**。同理，人坐着时
## `torso` / `head` / `arm-left` 都有顶点在足迹以内、但**全部高于桌面平面**（只是身子探过桌沿），
## 它们**没有一寸进到桌子里**。AABB 口径会把这三件一起判成"穿模"，那是**判据失真**，不是缺陷。
func _pose_pen(w: Node3D, vol: Dictionary) -> Dictionary:
	var out := {"hits": 0, "worst": INF, "buried": 0, "proud": -INF, "proud_names": "",
		"lean": 0, "low": INF, "deep": INF, "grew": 0, "grew_names": ""}
	if w == null or vol.is_empty():
		return out
	var tb: AABB = vol["tb"]
	var slab: AABB = vol["slab"]
	var top: float = vol["top"]
	for n in w.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null or g.mesh == null:
			continue
		var a: AABB = g.global_transform * g.mesh.get_aabb()
		out.low = minf(out.low, a.position.y)
		out.worst = minf(out.worst, maxf(_aabb_gap(a, tb), _aabb_gap(a, slab)))
		if _aabb_gap(a, tb) <= 0.0 or _aabb_gap(a, slab) <= 0.0:
			out.hits = int(out.hits) + 1
		# 逐顶点问（见上：AABB 对转过角度的分件太松）——四个问题一次问完：
		#   * `bury`：有没有几何**进到桌子实体体积里**（足迹以内、桌面平面以下）；
		#   * `above_in` / `above_out`：有没有几何**高过桌面平面**，分别在足迹以内 / 以外；
		#   * `deep` / `hi`：进到多深 / 在足迹以内最高到哪。
		var bury := false
		var above_in := false
		var above_out := false
		var hi := -INF
		var hi_at := Vector3.ZERO
		var any_in := false
		for s in g.mesh.get_surface_count():
			var arr := g.mesh.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in arr[Mesh.ARRAY_VERTEX]:
				var wp: Vector3 = g.global_transform * (v as Vector3)
				var in_fp: bool = wp.x >= tb.position.x and wp.x <= tb.end.x \
					and wp.z >= tb.position.z and wp.z <= tb.end.z
				if wp.y > top:
					if in_fp:
						above_in = true
					else:
						above_out = true
				elif in_fp:
					bury = true
				if not in_fp:
					continue
				any_in = true
				if wp.y > hi:
					hi = wp.y
					hi_at = wp
				out.deep = minf(out.deep, wp.y)
		if bury:
			out.buried = int(out.buried) + 1
			out.proud = maxf(out.proud, hi - top)
			out.proud_names += "%s(足迹内最高 %+.3f @x%.2f,z%.2f) " % [g.name, hi - top, hi_at.x, hi_at.z]
		elif any_in:
			out.lean = int(out.lean) + 1
		# **看得见的穿模**：足迹以内有高过桌面的几何，却**没有**任何"足迹以外、也高过桌面"的几何
		# ⇒ 这一件在桌面上方的部分**与桌子外面接不上** = 它是**从桌子里面长出来的**
		#（而不是从桌沿外伸进来的）。见 `_table_vol` 那段与 (c2) 的判据说明。
		if above_in and not above_out:
			out.grew = int(out.grew) + 1
			out.grew_names += "%s " % g.name
	return out

## **角色的"被照亮的 albedo"相对桌面那一笔的比值上限**（Task 1 的 J1，`CHAR_LIT_RATIO_MAX`）。
##
## **为什么是 1.0**：本档要的就是那句大白话 —— **角色不许亮过桌面**。
## ⚠ **与 phase 1 那条的唯一分歧，是故意的**：`layout_test` 拿**桌面最暗那个角**去比（从严），
## 可它两边**贴的是同一张木纹**（家具与木桌都用 `wood_floor.jpg`）⇒ 贴图在比值里**约掉了**，
## 它比的是"色调对色调"。角色**换了一张贴图**、约不掉 ⇒ 只能把贴图算进来；而一旦算进来，
## "最暗那个角"就变成"角色必须比**屋里最暗的那块木头**还暗"（实测要 `CHAR_TINT` 降到 0.25 才过），
## 那会把脸一起压黑 —— 与 spec §十 F8「不靠名牌、**靠角色本身认人**」直接冲突。
## ⇒ 这里对桌面取**最亮那个采样点**（"桌面自己的亮度"），是两边都公平的那一档。
const CHAR_LIT_RATIO_MAX := 1.0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 一棵子树里所有几何实例的世界 AABB 的并集（口径同 `layout_test._subtree_world_aabb`）。
func _subtree_world_aabb(root: Node) -> AABB:
	var out := AABB()
	var got := false
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as MeshInstance3D
		if g == null or g.mesh == null:
			continue
		var a: AABB = g.global_transform * g.mesh.get_aabb()
		out = a if not got else out.merge(a)
		got = true
	return out

## 两个世界 AABB 之间的**净空**（>0 = 分开多远；<0 = 重叠多深）。按"分得最开的那一维"量
## —— 与 `intersects()` 同一口径（只要有一维分得开就不相交），但能给一个可读的数。
func _aabb_gap(a: AABB, b: AABB) -> float:
	var g := -INF
	for k in 3:
		g = maxf(g, maxf(b.position[k] - a.end[k], a.position[k] - b.end[k]))
	return g

## 一棵子树里**逐实例透明度**的最大值（`GeometryInstance3D.transparency`；0 = 全亮、1 = 全隐）。
## 用它核"角色在四档取景下都是**不透明**的"（v0.8.0 第三次改版起没有淡出档 —— 见 ⑭）。
func _max_transparency(root: Node3D) -> float:
	var mx := 0.0
	if root == null:
		return mx
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi != null:
			mx = maxf(mx, gi.transparency)
	return mx

## 一张贴图在**某个面真正贴上去的那一块**上的平均色（在该面的 UV 区域上打 8×8 网格取样）。
##
## 为什么不取整张图集的平均：Kenney 的图集里**大片是没用到的背景** —— 实测角色-a 的整图平均亮度
## 只有 0.262，而"手臂"那一块是 **0.578** ⇒ 取整图平均会把角色量成"很暗"，判据就成了空转。
## **不翻 V**：glTF 的 UV 原点在左上，与本项目 `Image.get_pixel` 的取向一致
##（实测：翻 V 会把"头"那一块取成躯干那一块）。
func _surf_tex_avg(gi: MeshInstance3D, s: int, m: BaseMaterial3D) -> Variant:
	if gi == null or gi.mesh == null or m == null or m.albedo_texture == null:
		return null
	var img: Image = m.albedo_texture.get_image()
	if img == null:
		return null
	var arr := gi.mesh.surface_get_arrays(s)
	if arr.size() <= Mesh.ARRAY_TEX_UV or arr[Mesh.ARRAY_TEX_UV] == null:
		return null
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return null
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for uv in uvs:
		var u := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))   # 这个包的 UV 会超出 1（repeat）
		lo = lo.min(u)
		hi = hi.max(u)
	var acc := Vector3.ZERO
	var n := 0
	for iy in 8:
		for ix in 8:
			var u := Vector2(lerpf(lo.x, hi.x, (float(ix) + 0.5) / 8.0),
				lerpf(lo.y, hi.y, (float(iy) + 0.5) / 8.0))
			var px := img.get_pixel(
				clampi(int(u.x * float(img.get_width())), 0, img.get_width() - 1),
				clampi(int(u.y * float(img.get_height())), 0, img.get_height() - 1))
			acc += Vector3(px.r, px.g, px.b)
			n += 1
	return acc / float(maxi(n, 1))

## 一棵子树**最亮那一件的有效 albedo 亮度** = `albedo_color`（色调）⊙ 它那一块贴图的平均色。
##
## **从材质上读，不读 `GameChars.CHAR_TINT`**（同 `layout_test._subtree_albedo_lum` 那条理由）：
## 读常量等于把实现重述一遍，色调改成什么值都照样过 —— 那正是要避免的永真断言。
func _subtree_lit_albedo_lum(root: Node) -> Dictionary:
	var mx := -1.0
	var log := ""
	var n_surf := 0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as MeshInstance3D
		if gi == null or gi.mesh == null:
			continue
		for s in gi.mesh.get_surface_count():
			var m := gi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			n_surf += 1
			var avg = _surf_tex_avg(gi, s, m)
			var eff: Color = m.albedo_color
			if avg != null:
				eff = Color(m.albedo_color.r * avg.x, m.albedo_color.g * avg.y, m.albedo_color.b * avg.z)
			mx = maxf(mx, eff.get_luminance())
			log += "%s:%.3f " % [gi.name, eff.get_luminance()]
	return {"lum": mx, "log": log, "n": n_surf}

## 一点吃到的**相对照度**（口径与 `layout_test._mat_sample_irradiance` **逐项相同** ——
## 「尺子只能用一把」：GLES3 的 `max(1 − (d/range)^4, 0)^2 × d^(−衰减指数) × 能量 × N·L` + 环境光那一份）。
func _irradiance(light: OmniLight3D, p: Vector3, ambient: float) -> float:
	var d: float = light.global_position.distance_to(p)
	d = maxf(d, 0.0001)
	var nd: float = d / light.omni_range
	nd = nd * nd
	nd = nd * nd
	var shape: float = maxf(1.0 - nd, 0.0)
	shape = shape * shape
	var decay: float = pow(maxf(d, 0.0001), -light.omni_attenuation)
	var cos_i: float = clampf((light.global_position.y - p.y) / d, 0.0, 1.0)
	return light.light_energy * shape * decay * cos_i + ambient

## 喂进去的座位序（**故意让"色号"与"座位号"处处不等** —— 见断言 ⑨：
## 按椅子号取模型的话，slot 1 会拿到 `model_for_color(1)` = g，与期望的 **p** 不同 ⇒ 必红
## —— 调色板现在是 `k / g / n / p`，slot 1 的色号是 3 ⇒ 期望 `p`）。
func _seats() -> Array:
	return [
		{"peer": 2, "color": 1, "name": "乙"},   # slot 0 = 我（近侧，不渲染）
		{"peer": 3, "color": 3, "name": "丙"},   # slot 1 右
		{"peer": 4, "color": 0, "name": "丁"},   # slot 2 远（**居中、正对镜头**那把）
		{"peer": 5, "color": 2, "name": "戊"},   # slot 3 左
	]

## 同一批人**换椅子坐**（把 1/2/3 号座位上的人轮转一格）：用来验"同一 peer 仍是同一张脸"。
func _seats_rotated() -> Array:
	return [
		{"peer": 2, "color": 1, "name": "乙"},
		{"peer": 5, "color": 2, "name": "戊"},
		{"peer": 3, "color": 3, "name": "丙"},
		{"peer": 4, "color": 0, "name": "丁"},
	]

func _run() -> void:
	root.size = Vector2i(1280, 800)
	# 用运行时 load() 取 TableView3D（同 layout_test / hud_test）：`--script` 入口的静态依赖链
	# 在 autoload 注册之前编译，静态写类名会把 game/BoardView 那条链（依赖 `Fx`）拽进来。
	var t3 = load("res://scripts/table_3d.gd").new()
	root.add_child(t3)
	await process_frame
	await process_frame

	print("== 二期 Task 2：角色层（三个座位 1/2/3，slot 0 仍为空）==")
	var room: Node = t3.get_node_or_null("Room")
	_check(room != null, "房间在（一期：ROOM_ENABLED 的那一层）")
	var chars: Node = room.get_node_or_null("Chars") if room != null else null
	# 契约：`CHARS_ENABLED` 为 true 时角色层在；置 false 时**一个节点都不留**（变红口子）。
	_check(chars != null == GameChars.CHARS_ENABLED,
		"CHARS_ENABLED=%s 时角色层%s存在" % [GameChars.CHARS_ENABLED, "" if chars != null else "不"])
	if chars == null:
		_check(false, "角色层缺了（CHARS_ENABLED=false 时这是对的）⇒ 下面整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return
	# **先断言"还没喂座位序时一个角色都没有"**：摆人一律由 `set_chars()` 驱动（不在 `_ready`）——
	# 这条同时钉住了"不在 `_ready` 里摆人"这件事（否则房间一生出来就有人、状态还没来）。
	_check(chars.get_node_or_null("Char1") == null,
		"**没喂座位序时一个角色都没有**（摆人由 `set_chars()` 驱动，不在 `_ready` —— `_ready` 那刻还没有状态）")
	# 喂之前先记一下：`char_peers()` 在没喂过的时候应当是空的（没有半个座位的故事）。
	_check(chars.char_peers().is_empty() and chars.char_model(1) == "",
		"没喂过座位序时 `char_peers()` 为空、`char_model()` 为 \"\"（实得 %s / \"%s\"）"
			% [str(chars.char_peers()), chars.char_model(1)])

	# ---- 喂座位序（走 `game.gd:_refresh_players()` 喂的**同一个接口、同一份序**）----
	var seats := _seats()
	chars.set_chars(seats)
	await process_frame

	# ① 三个座位上有人、`slot 0` 没有人
	var c: Array = []          # c[i] = 第 i 把椅子上的外套节点（null = 没人）
	var missing: Array = []
	for i in seats.size():
		c.append(chars.get_node_or_null("Char%d" % i) as Node3D)
		if i != MY_SLOT and c[i] == null:
			missing.append(i)
	_check(missing.is_empty() and c.size() == 4,
		"`slot %s` 上各坐着一个人（缺 %s）" % [str(CHAR_SLOTS), str(missing)])
	_check(c[MY_SLOT] == null,
		"`slot %d`（近侧 =「我」）**一个人都没有** —— 相机就在那儿（spec §5.1）" % MY_SLOT)
	if not missing.is_empty():
		_check(false, "有座位空着 ⇒ 下面几条整段跳过")
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1 if fails > 0 else 0)
		return

	# ② 每个人都站在**自己那把椅子**的锚点上（位置 + 朝向都读一期留的 `seat_anchor(slot)`）
	var pos_bad: Array = []
	var face_bad: Array = []
	var pos_log := ""
	for i in CHAR_SLOTS:
		var an: Transform3D = room.seat_anchor(i)
		var cp: Vector3 = c[i].global_position
		var to_center := Vector3(-an.origin.x, 0.0, -an.origin.z).normalized()
		var facing: Vector3 = (c[i].global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		var d: float = facing.dot(to_center)
		if absf(cp.x - an.origin.x) >= 0.001 or absf(cp.z - an.origin.z) >= 0.001:
			pos_bad.append(i)
		if d <= 0.95:
			face_bad.append(i)
		pos_log += "slot%d 人(%.3f,%.3f)/锚点(%.3f,%.3f) 朝向点积%+.3f | " % [i, cp.x, cp.z, an.origin.x, an.origin.z, d]
	print("  [实测] %s" % pos_log)
	_check(pos_bad.is_empty(),
		"三个人都站在**自己那把椅子**的座位锚点上（越位 %s —— 座位坐标全部来自一期接口 `seat_anchor(slot)`，不另算）"
			% str(pos_bad))
	_check(face_bad.is_empty(),
		"三个人都面朝桌心（正面 = `+Z`，与 `seat_anchor` 天然对齐、不用补 180°；点积 <0.95 的座位 %s）"
			% str(face_bad))

	# ③ 手摆坐姿：脚底落地面、髋落座面（**三个人逐个量**）
	var parts_bad: Array = []
	var feet_bad: Array = []
	var hip_bad: Array = []
	var pose_log := ""
	var ab: Array = []        # 每个人的世界 AABB
	for i in CHAR_SLOTS:
		var leg_l := c[i].find_child("leg-left", true, false) as Node3D
		var leg_r := c[i].find_child("leg-right", true, false) as Node3D
		if leg_l == null or leg_r == null or c[i].find_child("root", true, false) == null \
				or c[i].find_child("torso", true, false) == null:
			parts_bad.append(i)
		var a := _subtree_world_aabb(c[i])
		ab.append(a)
		var feet: float = a.position.y
		var hip: float = leg_l.global_position.y if leg_l != null else -9999.0
		var seat_y: float = GameRoom.FLOOR_Y + SEAT_H
		if absf(feet - GameRoom.FLOOR_Y) > 0.05:
			feet_bad.append(i)
		if leg_l == null or absf(hip - seat_y) > 0.05:
			hip_bad.append(i)
		pose_log += "slot%d 脚底%.4f(Δ%+.4f) 髋%.4f(Δ%+.4f) | " % [i, feet, feet - GameRoom.FLOOR_Y,
			hip, hip - seat_y]
	print("  [实测] %s（地板 %.4f / 座面 %.4f）" % [pose_log, GameRoom.FLOOR_Y, GameRoom.FLOOR_Y + SEAT_H])
	_check(parts_bad.is_empty(),
		"手摆坐姿要动的分件都在（`leg-left` / `leg-right` / `root` / `torso` —— 这个包没有 `Skeleton3D`；缺的座位 %s）"
			% str(parts_bad))
	_check(feet_bad.is_empty(),
		"**三个人的脚底都落在 FLOOR_Y**（差 >0.05 的座位 %s）—— 手摆坐姿对不对的唯一硬判据" % str(feet_bad))
	_check(hip_bad.is_empty(),
		"**三个人的髋枢轴都落回座面**（= 腿分件节点原点，一期座面离地 %.2f；越界座位 %s）" % [SEAT_H, str(hip_bad)])

	# ④ 角色**不与桌子相交** —— 逐件、对桌子的**实体体积**（Task 1 重述过的口径，见文件头 ④）。
	#    **为什么必须逐件**：合并 AABB 的头尾把"脚下的 y"与"头顶的 y"并成一个盒子，
	#    于是"离桌子最近"变成"头（浮在桌面上方）的近侧边离底座多远" —— 那不是要求。
	#    **为什么必须带桌面那一层**：底座顶面到桌面上表面那一段也是实木；不带它，
	#    "从桌面上方捅进去"这种穿法量不出来。
	var tbase := t3.get_node_or_null("TableBase") as MeshInstance3D
	# 桌面那一片：走 `table_3d.table_mesh` 这个成员（它没起过节点名 ⇒ 不能按名字找；
	# `layout_test` 量"桌面各位置亮度"用的也是它）。
	var tmat: MeshInstance3D = t3.get("table_mesh")
	_check(tbase != null and tbase.mesh != null and tmat != null and tmat.mesh != null,
		"（前提）桌子底座 `TableBase` 与桌面 `table_mesh` 都在（一期）")
	if tbase != null and tbase.mesh != null and tmat != null and tmat.mesh != null:
		var tb: AABB = tbase.global_transform * tbase.mesh.get_aabb()
		var tma: AABB = tmat.global_transform * tmat.mesh.get_aabb()
		# 桌面那一层：桌面的足迹 × [底座顶面, 桌面上表面]
		var slab := AABB(Vector3(tma.position.x, tb.end.y, tma.position.z),
			Vector3(tma.size.x, tma.position.y - tb.end.y, tma.size.z))
		var hits := 0
		var worst := INF
		var p_log := ""
		for i in CHAR_SLOTS:
			for n in c[i].find_children("*", "GeometryInstance3D", true, false):
				var g := n as MeshInstance3D
				if g == null or g.mesh == null:
					continue
				var a: AABB = g.global_transform * g.mesh.get_aabb()
				var bad: bool = a.intersects(tb) or a.intersects(slab)
				if bad:
					hits += 1
				# 净空 = 与"底座 ∪ 桌面那一层"里更近那一块的分开距离（负 = 重叠）
				worst = minf(worst, maxf(_aabb_gap(a, tb), _aabb_gap(a, slab)))
				p_log += "slot%d/%s:%+.3f%s " % [i, g.name, maxf(_aabb_gap(a, tb), _aabb_gap(a, slab)),
					"∩" if bad else ""]
		print("  [实测] 逐件净空（与世界单位；正 = 分开、负 = 重叠）：%s" % p_log)
		_check(hits == 0,
			"**三个人都不与桌子相交**：逐件世界 AABB 与桌子实体体积（底座 x∈[%.3f, %.3f] y∈[%.3f, %.3f] + "
				% [tb.position.x, tb.end.x, tb.position.y, tb.end.y]
				+ "桌面那一层 y∈[%.3f, %.3f]）都不相交（相交 %d 件；最近那件还差 %+.3f 世界 = 真实 %.1f mm）"
				% [slab.position.y, slab.end.y, hits, worst, worst * 200.0])

	# ⑤ 三个人**两两不相交**（各自在自己椅子上 —— 相邻两把椅子的盒子不许碰）
	var pair_bad: Array = []
	var pair_log := ""
	for x in CHAR_SLOTS.size():
		for y in range(x + 1, CHAR_SLOTS.size()):
			var i: int = CHAR_SLOTS[x]
			var j: int = CHAR_SLOTS[y]
			var gp := _aabb_gap(ab[x], ab[y])
			if gp <= 0.0:
				pair_bad.append("%d-%d" % [i, j])
			pair_log += "%d-%d:%+.3f " % [i, j, gp]
	print("  [实测] 两两净空：%s" % pair_log)
	_check(pair_bad.is_empty(),
		"三个人**两两不相交**（世界 AABB 分开着；相交的对 %s）—— 每人只占自己那把椅子" % str(pair_bad))

	# ⑥ 材质：**不是 UNSHADED**（会被房间的灯照亮）、**底色只被压暗过**、**贴图还在**（普查 §7.2）
	#    包自带 `KHR_materials_unlit` ⇒ Godot 导成 `SHADING_MODE_UNSHADED`。
	#    ⚠ **逐面两条各守一半**：整片覆盖（`room.gd._paint()` 那一手）换上去的材质**自己就受光**、
	#      也**自己带贴图**（木地板的木纹）⇒ 单看 `shading_mode` / "有没有贴图"照样绿。
	#      ⇒ 必须比**"底色是不是自己那份压暗来的" + "贴图还是不是自己那张"**。
	var surfaces := 0
	var missing_m := 0
	var unshaded := 0
	var textured := 0
	var tex_own := 0
	var foreign := 0
	var mat_log := ""
	for i in CHAR_SLOTS:
		for n in c[i].find_children("*", "GeometryInstance3D", true, false):
			var gi := n as MeshInstance3D
			if gi == null or gi.mesh == null:
				continue
			for s in gi.mesh.get_surface_count():
				surfaces += 1
				var m := gi.get_active_material(s) as BaseMaterial3D
				var own := gi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null:
					missing_m += 1
					continue
				if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					unshaded += 1
				if m.albedo_texture != null:
					textured += 1
				# 底色只许是"自己那份 × 一个压暗系数"：三维都 ≤ 自己那份（**改成 >1 立刻红**）
				if own != null and (m.albedo_color.r > own.albedo_color.r + 0.001
						or m.albedo_color.g > own.albedo_color.g + 0.001
						or m.albedo_color.b > own.albedo_color.b + 0.001):
					foreign += 1
				# **贴图还是角色自己那张**（不是"有贴图就行"）
				if own != null and own.albedo_texture != null and m.albedo_texture == own.albedo_texture:
					tex_own += 1
				mat_log += "s%d/%s:shade%d,tex%s,albedo%s " % [i, gi.name, m.shading_mode,
					"有" if m.albedo_texture != null else "无", m.albedo_color]
	print("  [实测] 角色材质（%d 个面）：%s" % [surfaces, mat_log])
	_check(surfaces > 0 and missing_m == 0,
		"（前提）三个角色的每个面都有材质可量（%d 个面，取不到材质 %d 个）" % [surfaces, missing_m])
	_check(surfaces > 0 and unshaded == 0 and foreign == 0,
		"角色材质**不是 UNSHADED**、且**底色只被压暗过**（%d 个面：UNSHADED %d / 底色不是压暗 %d —— "
			% [surfaces, unshaded, foreign]
			+ "包自带 KHR_materials_unlit，不调就不响应一期的光照契约；整片覆盖会被贴图那条拦下）")
	_check(surfaces > 0 and tex_own == surfaces,
		"角色**贴图还在、而且是自己那张**（%d/%d 个面的贴图与模型自带的同一张；任意贴图 %d/%d —— "
			% [tex_own, surfaces, textured, surfaces]
			+ "照抄 room.gd 的整片覆盖会把脸 / 衣服换成房间的木地板，那样「有贴图」那一栏仍是有的、只有这条拦得住）")

	# ⑦ **角色不许是画面里最亮的东西**（Task 1 的 J1 判据；本任务起**取三人里最亮的那个**）
	#
	# 判据 = **同一把尺子**（同 `layout_test` 的照度代理式）× 同一把 albedo 尺子
	#（色调 ⊙ 贴图那一块的平均色）：三人里最亮的那笔必须 ≤ `CHAR_LIT_RATIO_MAX` × 桌面那笔。
	# albedo **从材质上读**（不读 `GameChars.CHAR_TINT`）—— 读常量等于把实现重述一遍。
	var lamp: OmniLight3D = t3.get("lamp_light")
	var wenv: WorldEnvironment = null
	for ch in t3.get_children():
		if ch is WorldEnvironment:
			wenv = ch
	var amb := 0.0
	if wenv != null:
		amb = wenv.environment.ambient_light_energy * wenv.environment.ambient_light_color.get_luminance()
	var cl: Array = []
	var max_idx := 0
	for x in CHAR_SLOTS.size():
		cl.append(_subtree_lit_albedo_lum(c[CHAR_SLOTS[x]]))
		if cl[x]["lum"] > cl[max_idx]["lum"]:
			max_idx = x
	var wm := (t3.wood_mesh as MeshInstance3D).material_override as StandardMaterial3D
	var wavg = _surf_tex_avg(t3.wood_mesh, 0, wm)
	var wood_lum := -1.0
	if wm != null and wavg != null:
		wood_lum = Color(wm.albedo_color.r * wavg.x, wm.albedo_color.g * wavg.y,
			wm.albedo_color.b * wavg.z).get_luminance()
	var corners := [
		t3.table_mesh.global_transform * Vector3(-t3.TABLE_SIZE.x * 0.5, 0.0, -t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(t3.TABLE_SIZE.x * 0.5, 0.0, -t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(-t3.TABLE_SIZE.x * 0.5, 0.0, t3.TABLE_SIZE.y * 0.5),
		t3.table_mesh.global_transform * Vector3(t3.TABLE_SIZE.x * 0.5, 0.0, t3.TABLE_SIZE.y * 0.5),
		Vector3(0.0, t3.table_mesh.global_position.y, 0.0),
	]
	var char_lit := -1.0
	var tab_lit := -1.0
	var lit_log := ""
	if lamp != null and wood_lum >= 0.0:
		for x in CHAR_SLOTS.size():
			var l: float = cl[x]["lum"] * _irradiance(lamp, ab[x].get_center(), amb)
			lit_log += "slot%d albedo%.3f×照度%.3f=%.4f | " % [CHAR_SLOTS[x], cl[x]["lum"],
				_irradiance(lamp, ab[x].get_center(), amb), l]
			char_lit = maxf(char_lit, l)
		for p in corners:
			tab_lit = maxf(tab_lit, wood_lum * _irradiance(lamp, p, amb))
	print("  [实测] %s木头外框有效 albedo 亮度 %.3f / 环境光那一份 %.4f" % [lit_log, wood_lum, amb])
	_check(lamp != null and cl[max_idx]["lum"] >= 0.0 and wood_lum >= 0.0,
		"（前提）三人的 albedo、木桌的 albedo、吊灯都量得到（最亮那件 %.3f / 木桌 %.3f / 灯 %s）"
			% [cl[max_idx]["lum"], wood_lum, "在" if lamp != null else "缺"])
	if lamp != null and char_lit >= 0.0 and tab_lit >= 0.0:
		var ratio: float = char_lit / maxf(tab_lit, 0.0001)
		_check(ratio <= CHAR_LIT_RATIO_MAX,
			"**角色不再是画面里最亮的东西**：三人里最亮那笔 albedo × 照度 %.4f ≤ %.2f × 桌面那一笔 %.4f"
				% [char_lit, CHAR_LIT_RATIO_MAX, tab_lit]
				+ "（实得比值 %.3f；把 `CHAR_TINT` 改回 (1,1,1) 这条立刻红）" % ratio)

	# ⑦-b **最坏座位 × 调色板里的每一个模型**（本任务新增 —— 上一段只量了"这一份座位序上"的三个人，
	#     而哪家坐哪把椅子由各家的**棋子色**决定 ⇒ 判据必须对**每一个色号**都成立，不能靠这一份
	#     座位序恰好把最亮的那件模型放在了别处而侥幸过线）。
	#     **为什么是 slot 3**：吊灯在 `LAMP_LIGHT_POS.x = -4.13`（桌子偏左上方）⇒ 左座吃到的照度
	#     最大（实测 1.339，右座 0.967 —— 差 1.385 倍）。Task 1 只有右座那一个人，取值是按右座留的
	#     余量；三个座位一起来，左座才是判据要守的那一个。
	if lamp != null and wood_lum >= 0.0 and tab_lit > 0.0:
		var sweep_bad: Array = []
		var sweep_log := ""
		for color in GameData.PLAYER_COLORS.size():
			var trial: Array = [{"peer": 2, "color": 1, "name": "乙"}]
			for k in CHAR_SLOTS.size():
				# 让**色号 color** 正好坐在最亮的 slot 3 上，另两个座位填别的色号（凑齐三个人）。
				var cc: int = (color + 1 + k) % GameData.PLAYER_COLORS.size() if k < 2 else color
				trial.append({"peer": 10 + cc, "color": cc, "name": "试%d" % cc})
			chars.set_chars(trial)
			await process_frame
			var ct := chars.get_node_or_null("Char%d" % CHAR_SLOTS[2]) as Node3D
			if ct == null:
				sweep_bad.append(color)
				continue
			var clum: float = _subtree_lit_albedo_lum(ct)["lum"]
			var lit: float = clum * _irradiance(lamp, _subtree_world_aabb(ct).get_center(), amb)
			var rr: float = lit / tab_lit
			sweep_log += "色%d→%s albedo%.3f×照度=%.4f(比值%.3f) | " % [color, chars.char_model(CHAR_SLOTS[2]),
				clum, lit, rr]
			if rr > CHAR_LIT_RATIO_MAX:
				sweep_bad.append(color)
		print("  [实测] 最坏座位（slot %d）× 全部色号：%s" % [CHAR_SLOTS[2], sweep_log])
		_check(sweep_bad.is_empty(),
			"**每一个色号的模型放在最亮的座位上也不亮过桌面**（越线的色号 %s —— 判据要按最坏座位收敛："
				% str(sweep_bad) + "吊灯挂在桌子偏左上方，实测左座照度是右座的 1.385 倍）")
		chars.set_chars(seats)      # 复位（下面 ⑨~⑪ 与末段读数要的仍是这一份座位序）
		await process_frame
		c = []
		for i in seats.size():
			c.append(chars.get_node_or_null("Char%d" % i) as Node3D)

	# ⑧ 影子：**不投影**（房间的纪律：全场唯一投影源是那盏吊灯）
	var casting := 0
	for i in CHAR_SLOTS:
		for n in c[i].find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casting += 1
	_check(casting == 0, "三个角色都不投影（违规 %d 个 —— 吊灯仍是全场唯一投影源）" % casting)

	# ⑨ **模型按棋子色选**（本轮新增）：喂进来的座位序里色号与座位号**处处不等** ⇒
	#    按椅子号取模型的话，slot 1 会拿到 `model_for_color(1)`（g）而不是期望的 **p** ⇒ 必红
	#    —— 调色板是 `k / g / n / p`（没有 `d`，那是上一个调色板的残留），slot 1 色号 3 ⇒ `p`。
	#    另外比一下**真正实例化出来那个节点的名字**（不只是自己记的那个字符串）。
	var model_bad: Array = []
	var mm_log := ""
	var peer_model := {}      # peer -> 模型（给 ⑩ 用）
	for i in CHAR_SLOTS:
		var color := int((seats[i] as Dictionary).get("color", 0))
		var want: String = GameChars.model_for_color(color)
		var got: String = chars.char_model(i)
		# 真正加载进来那个 GLB 的根节点名（`character-a.glb` → `character-a`）
		var inst_name := String((c[i].get_child(0) as Node).name) if c[i].get_child_count() > 0 else ""
		var ok: bool = got == want and got != GameChars.model_for_color(i) \
			and inst_name.begins_with(want.get_basename())
		if not ok:
			model_bad.append(i)
		peer_model[int((seats[i] as Dictionary).get("peer", 0))] = got
		mm_log += "slot%d(色%d)→%s（按座位号会是 %s）/实例节点 %s | " % [i, color, got,
			GameChars.model_for_color(i), inst_name]
	print("  [实测] 模型：%s" % mm_log)
	_check(model_bad.is_empty(),
		"**模型按各家的棋子色选**（=`CHAR_MODELS_BY_COLOR[color]`，而且**不是**按椅子号取；"
			+ "实例化出来的 GLB 根节点名也与之一致；不符的座位 %s）" % str(model_bad))
	_check(chars.char_peers() == [GameData.NO_PEER, 3, 4, 5],
		"`char_peers()` 逐槽位给出 peer（slot 0 = `NO_PEER`，那是「我」）：实得 %s" % str(chars.char_peers()))

	# ⑩ **同一个 peer 换椅子坐仍是同一张脸**：座位序轮转一格（三个人的椅子全换了）后逐家比对。
	#    这条是"重广播 / 重连 / 换轮次不许换脸"的可执行版。
	var before := peer_model.duplicate()
	chars.set_chars(_seats_rotated())
	await process_frame
	var swapped: Array = []
	var f_log := ""
	for i in CHAR_SLOTS:
		var p := int((_seats_rotated()[i] as Dictionary).get("peer", 0))
		var got2: String = chars.char_model(i)
		if got2 != String(before.get(p, "")):
			swapped.append(p)
		f_log += "peer %d 换到 slot%d：%s → %s | " % [p, i, before.get(p, "?"), got2]
	print("  [实测] %s" % f_log)
	_check(swapped.is_empty(),
		"**同一个 peer 换椅子坐仍是同一张脸**（轮转座位序后逐家比对；换脸的是 peer %s —— "
			% str(swapped) + "模型按棋子色定，所以与坐哪把椅子无关）")
	_check(chars.char_peers() == [GameData.NO_PEER, 5, 3, 4],
		"轮转后 `char_peers()` 跟着座位序走（实得 %s）—— 人与椅子一起换，不是只换椅子"
			% str(chars.char_peers()))

	# ⑪ **早退**（本轮新增）：同样的座位序再来一次 ⇒ **同一批节点实例**（不重建）。
	#    `_refresh_players()` 每次状态广播都调 `set_chars()` —— 少了早退，每次广播都要
	#    重新 load + 实例化 + 复制材质。**去掉早退这条立刻红**（拿到的是新节点）。
	chars.set_chars(_seats())
	await process_frame
	var again: Array = []
	for i in seats.size():
		again.append(chars.get_node_or_null("Char%d" % i) as Node3D)
	# 轮转那一次本来就会重建（指纹变了）⇒ 这里先确认"确实换过一批"，再确认"同样的序不再换"。
	chars.set_chars(_seats())
	await process_frame
	var same := true
	for i in CHAR_SLOTS:
		var now := chars.get_node_or_null("Char%d" % i) as Node3D
		# `is_same(a, b)` 是**全局函数**（Godot 4 起：比较是不是同一个实例），不是节点上的方法。
		if now == null or not is_same(now, again[i]):
			same = false
	_check(same,
		"**同样的座位序再来一次 = 同一批节点实例**（`set_chars` 的早退：每次广播都调它，"
			+ "少了早退就会把三个人整套重建 —— 那条注释里写的成本）")

	# ================= 二期 Task 3（改版）：完全静止 / 取景四档恒可见 =================
	#
	# 节点在前面 ⑩ ⑪ 里重建过 ⇒ 这里重新取一遍（旧引用已 `queue_free`）。
	var t: Array = []
	for i in seats.size():
		t.append(chars.get_node_or_null("Char%d" % i) as Node3D)

	# ⑫ **一帧动画都不播**（v0.8.0 改版的核心：用户要的是"人物不要乱动"）。
	#    判据 = 三个播放器 `is_playing()` **全假**。原先那条"三个人都在播 `idle`、且
	#    `loop_mode` 是 `LOOP_LINEAR`"整段退场 —— 待机没了，循环标记也就无从谈起。
	#    **变红口子**：在 `_place` 里加回 `ap.play("idle")` ⇒ 这条立刻红。
	var play_bad: Array = []
	var anim_log := ""
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		if ap == null or ap.is_playing():
			play_bad.append(i)
		anim_log += "slot%d 在播%s/当前\"%s\" | " % [i,
			("是" if (ap != null and ap.is_playing()) else "否"),
			(ap.current_animation if ap != null else "无")]
	print("  [实测] %s" % anim_log)
	_check(play_bad.is_empty(),
		"**三个人一帧动画都不播（完全静止）**（还在播的座位 %s —— 待机随本改版一起退场；"
			% str(play_bad) + "在 `_place` 里加回 `play()` 这条立刻红）")

	# ⑬ **静止是"选择"、不是"没有动画"，而且真的静止**（两半都钉，缺一半就能骗过去）：
	#    ① **那条 `idle` 仍在模型里** —— 否则"不播"可能只是"没得播"，这条断言就失去了意义
	#      （将来素材换了、动画名变了，这一半会先红，指向真正的原因）；
	#    ② **同一分件在两个真实时间点上的世界位置一模一样** —— 口径与旧版 ⑬ 的"两帧比对"同源，
	#      但方向相反：旧版要求"必须不同"（证明在动），新版要求"必须完全相同"（证明静止）。
	#      ⚠ 用**真实时间**（`create_timer`）而不是 `seek()`：`seek()` 是主动摆相位，
	#      证明不了"没人来动它"。⚠ 也不能只 `await process_frame` 一两次 —— headless 下每帧的
	#      delta 只有零点几毫秒，等帧量出来的位移会随机器而变（旧版注释里那条假红的成因）。
	var still_bad: Array = []
	var move_log := ""
	# 顺手把**静止姿**的头位置记下来：此刻还没人碰过任何动画 ⇒ 这是后面 (e) 那条
	# "反应播完回到静止姿"的**基准**（那一段之前已经被 (c2) 用 `seek+pause` 摆过相位，
	# 到那时再量"静止姿"量到的其实是个伸手中途的相位 —— 必须在**这里**记）。
	var rest_head := {}
	for i in CHAR_SLOTS:
		var ap: AnimationPlayer = chars.char_player(i)
		var head := t[i].find_child("head", true, false) as Node3D
		if ap == null or head == null or not ap.has_animation("idle"):
			still_bad.append(i)
			continue
		var p0: Vector3 = head.global_position
		await create_timer(0.35).timeout
		await process_frame
		var p1: Vector3 = head.global_position
		var d: float = p0.distance_to(p1)
		if d > 0.0001:
			still_bad.append(i)
		rest_head[i] = p1
		move_log += "slot%d head 0.35s 前后位移 %.6f 世界 | " % [i, d]
	print("  [实测] %s" % move_log)
	_check(still_bad.is_empty(),
		"**待机那条 `idle` 仍在模型里、但没人播它；且分件真的静止**（不对的座位 %s —— "
			% str(still_bad) + "①里 `has_animation(\"idle\")` 为假说明素材换了（先修这一头）；"
			+ "②里位移不为 0 说明有东西在动它）")

	# ⑭ **取景四档下角色恒可见**（v0.8.0 第三次改版：**淡出整段取消**）。
	#    用户 2026-10-06 第三条：「2D 视角下人物不要消失」。
	#
	#    **为什么连 3D 端那两档一起取消**（不只是 2D）：淡出当初是为"读棋盘那一档别被二期拖慢"
	#    付的账（spec §六），而 v0.8.0 第二次改版已经把待机动画整段退场（人物完全静止）——
	#    二期实测 `CHARS_ENABLED` 开/关在同一会话里 p50 只差 0.02 ms ⇒ 只剩三个静止角色的
	#    绘制调用，省不出东西。留一条"推近就消失"只会让人以为出 bug 了。
	#
	#    **走真接口**（`snap_dolly` / `snap_view`），不直调内部量 —— 量的就是"玩家自己滚到那一档
	#    会看到什么"。四档：默认档 / 拉远端 / 推近端 / 2D 端，**每一档都必须看得见且不透明**。
	var frames := 4
	var fade_log := ""
	var view_tiers := [
		["默认档", 0.0, 1.0],
		["拉远端", 0.0, 1.4],
		["推近端", 0.0, 0.7],
		["2D端", 1.0, 1.0],
	]
	var tier_bad: Array = []
	for tier in view_tiers:
		var tname := String(tier[0])
		t3.snap_view(float(tier[1]))
		t3.snap_dolly(float(tier[2]))
		for k in frames:
			await process_frame
		for i in CHAR_SLOTS:
			var tr_hi := _max_transparency(t[i])
			if t[i] == null or not t[i].visible or tr_hi > 0.001:
				tier_bad.append("%s/slot%d" % [tname, i])
			fade_log += "%s slot%d 可见%s/透明度%.2f | " % [tname, i,
				("是" if t[i].visible else "否"), tr_hi]
	print("  [实测] 取景四档恒可见：%s" % fade_log)
	_check(tier_bad.is_empty(),
		"**四档取景下角色都看得见、且不透明**（不对的 %s —— 用户「2D 视角下人物不要消失」；"
			% str(tier_bad) + "把 `set_fade()` 那套加回去这条立刻红）")
	# 复位到默认档（后面几段按默认档读）
	t3.snap_view(0.0)
	t3.snap_dolly(1.0)
	for k in frames:
		await process_frame

	# ⑰ **头顶名牌：v0.8.0 第四次改版已整体删除**（用户 2026-10-06：「人物顶部铭牌去掉」）。
	# 它守的三件事现在各有归处，**一条都没丢**：
	#   * **"色随 `p.color` 走、不随座位序号走"** ⇒ 桌面立牌（`tests/placard_test.gd` ② 与
	#     `hud_test` 那条"牌面按各家的棋子色上色"，两处都是拿**真状态**喂的）；
	#   * **"当前行动者"** ⇒ 桌面立牌那块牌面上的一圈金边（`placard_test` ⑥ +
	#     `hud_test` 的选目标段）—— 角色层**不再有行动者这个概念**（`set_actor` 一并删了）；
	#   * **"名牌挂在角色之上、随角色一起动"** ⇒ 随载体一起消失（它本来就是为"头顶挂一块"
	#     这件事存在的）。
	# ⚠ **别把它加回来**：`chars.gd` 里 `Tags/Tag{i}`、`char_tag()`、`_make_tag()` 都已删除，
	# 加回来就等于"人物头顶又冒出铭牌"。

	# ================= 二期 Task 4：四个玩法事件的反应 =================
	#
	# **断言按动画名的字面值核**（**不读** `GameChars.REACT_ANIMS` —— 读那张表等于把实现重述一遍，
	# 改个名字永远绿）：名字写错 / 编一条不存在的都该红。四条名字全部是普查**实测存在**的
	#（普查 §三 的 27 条清单 + §5.4 建议表）：
	#   出牌 `interact-right` / 付钱 `holding-left` / 被抢地 `emote-no` / 破产 `die`。
	# 此时座位序仍是 `_seats()`：slot1=peer3（色3）/ slot2=peer4（色0）/ slot3=peer5（色2）。
	print("== 二期 Task 4：四个事件的反应（四个名字全部实测）==")

	# (a) 出牌 → `interact-right`（0.6667 s，幅度与时长都够、首尾闭合）
	chars.react(3, "play")
	await process_frame
	var ra1: AnimationPlayer = chars.char_player(1)
	_check(ra1 != null and ra1.current_animation == "interact-right",
		"**出牌 → `interact-right`**（实得 \"%s\" —— 名字写错 / 换一条不存在的，这条立刻红）"
			% (ra1.current_animation if ra1 != null else "<没有播放器>"))

	# (b) 付钱 → `holding-left`（0.1667 s，与既有**飞钞**演出同一拍）
	chars.react(4, "pay")
	await process_frame
	var ra2: AnimationPlayer = chars.char_player(2)
	_check(ra2 != null and ra2.current_animation == "holding-left",
		"**付钱 → `holding-left`**（实得 \"%s\" —— 与飞钞同拍；⚠ 换成 `pick-up` 会红："
			% (ra2.current_animation if ra2 != null else "<没有播放器>")
			+ "那一条**不闭合**、结束在弯腰姿态，是包里唯二不闭合的两条之一）")

	# (c) 被抢地 → `emote-no`（0.6667 s。**包里没有"后仰 / 拍桌"** ⇒ 摇头是可读的"不"）
	chars.react(5, "rob")
	await process_frame
	var ra3: AnimationPlayer = chars.char_player(3)
	_check(ra3 != null and ra3.current_animation == "emote-no",
		"**被抢地 → `emote-no`**（实得 \"%s\"）"
			% (ra3.current_animation if ra3 != null else "<没有播放器>"))

	# (c2) **反应姿态：相位钉死 + 判据按姿态类分开**（终审 Concerns 2 / fix round 2 重做）
	#
	# ① **为什么必须钉相位**：原先这条在 `react()` 之后 `await process_frame` 就量 ——
	#    相位 = 若干个真实帧长，**随机器负载漂**。而出牌那条伸手动作**在某个相位上确实会进桌子**：
	#    实测相位 0.02 s ⇒ 净空 +0.803 / 0.14 s ⇒ −0.163 / 0.16 s ⇒ +0.11 —— 相位抖 0.14 s，
	#    读数就从"分得很开"翻到"插进去" ⇒ 这条**按相位随机红**（未改的基线同样会红）。
	#    ⇒ 照 ⑬ 的手法把相位**钉死**（`seek(固定相位, true) + pause()`），并对一串覆盖 [0,1] 的
	#    相位逐个量：同样的相位 ⇒ 同样的数，**与运行时机无关**（连跑多次必须给出同一批读数）。
	# ② **为什么判据要按姿态类分开**（控制者裁定）：判据 ③（"不许与桌子实体体积相交"）是
	#    **为坐姿发明的** —— 它抓的是"腿从座面下穿出去"那一类。而**出牌是伸手动作**：
	#    手**本来就该伸到桌子这边来**；当它落到**桌面平面以下、又在桌子足迹以内**时，
	#    **桌面把它挡住了**（相机是俯视），读作"把手放在桌上"，**不是穿模**。
	#    **坐姿（④）与破产收势（(f2)(g)）不适用这条放宽 —— 仍是零相交**（判据 ③ 原样）。
	# ③ **放宽后的判据到底钉什么**（本轮实测把控制者给的措辞收窄了，**理由如下、读数如下**）：
	#    控制者给的措辞是「凡进入桌子实体体积的分件必须**整件**落在桌面平面以下」。**这条措辞
	#    在本房间里是过严的**，两条读数都能证明：
	#      (a) **它把"探过桌沿"判成穿模**。人坐着时 `torso` / `head` / `arm-left` 都有顶点落在
	#          桌子足迹以内、但**全部高于桌面平面**（出牌那一档实测 `torso` 足迹内 6 个顶点全在
	#          y = +0.748）—— 那是"身子探到桌沿上方"，**一寸没进桌子**；而桌子是实心木料，
	#          "高于桌面平面"的几何**根本不在实体体积里**，谈不上"进入体积"。
	#      (b) **它把"从桌沿外伸进来"判成穿模**。伸手那条（`interact-right`）实测：相位 0.20 时
	#          `arm-right` 的几何**从桌沿外伸进桌面上方**（足迹内最高 +0.787 @x2.45,z-1.13），
	#          相位 0.80 时整段**埋进桌面以下**（最深 −1.824）—— 这正是控制者自己写的
	#          "把手放在桌上"那一档。而**任何从上方进入桌子的动作都必然同时有高于桌面的几何**
	#          （不然它进不去）⇒ 这条措辞等价于"伸手动作一律不许"，把要保的表现一起否掉了。
	#    ⇒ 按控制者的授权（"若某条要求对你的实现是ill-posed，就说出来，改钉这条断言真正能抓的
	#      失效模式"），本断言钉的是**"没有从桌子里面长出来的东西"**（可执行、无阈值）：
	#      **足迹以内高过桌面平面的几何，必须同时在这张桌子的足迹以外、也高过桌面** ——
	#      即它必须是**从桌沿外伸进来的**（可一路看回人身上），而不是**从桌子里冒出来的**。
	#      **变红口子**：往角色身上挂一个盒子，让它同时满足"进了桌子实体体积"+"在足迹以内高出
	#      桌面"+"在足迹以外没有任何高出桌面的几何"（例如桌心那个位置一根柱子）⇒ 这条立刻红。
	#    （**如实记**：本轮三条动作**没有**这种几何；见下面那一行读数。）
	var vol := _table_vol(t3)
	_check(not vol.is_empty(), "（前提）桌子的实体体积量得到（(c2) 的反应姿态判据要用它）")
	# 采样的**归一化相位**（0 = 起手、1 = 收势）：步长 **0.05**（21 个点）—— 出牌那条从 +0.80 翻到
	# −0.16 只用 0.21 个相位，可步长 0.1 时**理论上**仍能从更窄的一道缝里漏过去（终审 N-3）：
	# 任何比步长更窄的特征都可能整段落在两个采样点之间。⇒ 步长减半 —— 每条动作多采 10 帧
	# （代价可忽略），而**能漏过去的最窄特征宽度也跟着减半**。
	# **为什么是均匀加密、而不是"只在观测到的极值附近加密"**：那些极值（出牌最深 @0.80 /
	# 足迹内最高 @0.20）是**当前这条动画的**读数，动画或判据一改就会漂 —— 均匀步长不依赖
	# "特征出现在哪"这个会被改动的假设。（读数见 `c2_log`，逐相位可查。）
	var react_phases := [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5,
		0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0]
	# 三条一次性动作 → 座位（座位序仍是 `_seats()`：slot1=peer3 / slot2=peer4 / slot3=peer5）。
	var react_kinds := [["play", 1], ["pay", 2], ["rob", 3]]
	# 三条动作的**动画名字面值**（同 (a)~(c)：不读 `GameChars.REACT_ANIMS` —— 读那张表等于把实现重述）
	var react_anims := {"play": "interact-right", "pay": "holding-left", "rob": "emote-no"}
	var c2_log := ""
	var grew_bad: Array = []
	var floor_bad: Array = []
	if not vol.is_empty():
		for pair in react_kinds:
			var kind := String(pair[0])
			var slot := int(pair[1])
			var peer := int((seats[slot] as Dictionary).get("peer", GameData.NO_PEER))
			chars.react(peer, kind)          # 真入口（与 gameplay 触发的是同一个函数、同一条链）
			await process_frame
			var ap: AnimationPlayer = chars.char_player(slot)
			var a: Animation = null
			if ap != null:
				a = ap.get_animation(String(react_anims[kind]))
			if a == null:
				grew_bad.append("%s@slot%d 没有播放器 / 没有这条动画" % [kind, slot])
				continue
			var worst := INF
			var worst_ph := -1.0
			var hits := 0
			var buried := 0
			var grew := 0
			var proud := -INF
			var proud_ph := -1.0
			var proud_names := ""
			var lean := 0
			var low := INF
			var deep := INF
			var deep_ph := -1.0
			var grew_ph := -1.0
			var grew_names := ""
			for ph in react_phases:
				# **相位钉死**：seek 到固定相位再 pause —— `_process` 不会把它推走，读数可复现
				ap.seek(float(ph) * a.length, true)
				ap.pause()
				await process_frame
				var m := _pose_pen(t[slot], vol)
				low = minf(low, float(m.low))
				if float(m.deep) < deep:
					deep = float(m.deep)
					deep_ph = float(ph)
				if float(m.worst) < worst:
					worst = float(m.worst)
					worst_ph = float(ph)
				if int(m.buried) > 0 and float(m.proud) > proud:
					proud = float(m.proud)
					proud_ph = float(ph)
					proud_names = String(m.proud_names)
				if int(m.grew) > 0 and grew == 0:
					grew_ph = float(ph)
					grew_names = String(m.grew_names)
				buried = maxi(buried, int(m.buried))
				hits = maxi(hits, int(m.hits))
				lean = maxi(lean, int(m.lean))
				grew = maxi(grew, int(m.grew))
			c2_log += "%s(slot%d %s 时长%.4f)：进桌子最深 %+.3f@相位%.2f / 进桌子的分件最多 %d 件 / 足迹内高出桌面最高 %+.3f（相位%.2f %s）/ 只探过桌沿的分件 %d 件 / AABB 口径最近净空 %+.3f@相位%.2f / 最低分件 %+.3f | " % [
				kind, slot, String(react_anims[kind]), a.length, deep, deep_ph, buried, proud,
				proud_ph, proud_names, lean, worst, worst_ph, low]
			if grew > 0:
				grew_bad.append("%s@相位%.2f：%s（桌面上方那一截与桌子外面接不上）"
					% [kind, grew_ph, grew_names])
			if low < GameRoom.FLOOR_Y - 0.001:
				floor_bad.append("%s(最低分件 %.3f)" % [kind, low])
			# 复位：把这条动作**重新播起来** —— 后面 (d)~(f) 读的仍是"三条动作刚播出去"那一态
			#（上面每个采样点都 `pause()` 过，不复位的话人会僵在末相位上）。
			chars.react(peer, kind)
	print("  [实测] 反应姿态（相位钉死 %s，桌面平面 y=%.3f）：%s"
		% [str(react_phases), float(vol.get("top", 0.0)), c2_log])
	_check(grew_bad.is_empty(),
		"出牌 / 付钱 / 被抢地**没有看得见的穿模**：**在桌子足迹以内、高过桌面平面**的几何，"
			+ "必须同时**在这张桌子的足迹以外、也高过桌面**（= 它是从桌沿外伸进来的）；"
			+ "在足迹以内高出桌面、却在足迹以外没有任何高出桌面的几何 ⇒ 这一件是**从桌子里面长出来的**。"
			+ "越界的 %s" % str(grew_bad))
	_check(floor_bad.is_empty(),
		"出牌 / 付钱 / 被抢地**三条动作都不掉到地板以下**（越界 %s）" % str(floor_bad))

	# (d) **幅度含蓄**：反应速度**统一 = `REACT_SPEED_SCALE`（0.6× 慢放）** —— 既不许"放大一点
	#     看得清"（那会让四家同时动变马戏团），也不许随手乱调（2026-10-06 实机"快得像闪了一下"
	#     ⇒ 定案慢放到 0.6×）。这条从"恒 1.0"改成"恒 `REACT_SPEED_SCALE`"：防的是**乱调**。
	# (e) 一次性小动作**播完回到静止姿** —— 不回位的话人僵在末帧的伸手姿态。
	#     ⚠ **基准取 ⑬ 那一刻量到的静止姿**（`rest_head`），不能在这里现量：本段之前 (c2) 已经
	#     用 `seek+pause` 把这个人摆过好几个相位，那时量到的"静止姿"是个伸手中途的相位。
	#     ⚠⚠ **这条断言是本改版抓出来的一个真缺陷**：`AnimationPlayer.stop()` **不复位姿态**
	#     （实测：`stop()` 之后分件仍停在末帧，slot1 的世界 AABB 深 6.89 vs 静止姿 4.5）。
	#     旧版靠 `play(idle)` 逐帧把残留姿态盖掉，改版后没有第二条动画可盖 ⇒ 必须显式还原。
	var head1 := t[1].find_child("head", true, false) as Node3D
	var rest1: Vector3 = rest_head.get(1, Vector3.ZERO)
	chars.react(3, "play")
	var rap: AnimationPlayer = chars.char_player(1)
	_check(rap != null and is_equal_approx(rap.speed_scale, GameChars.REACT_SPEED_SCALE),
		"**反应速度 == REACT_SPEED_SCALE（%.2f）**（慢放统一，实得 %.2f —— 「顺手放大」/「随手乱调」都红）"
			% [GameChars.REACT_SPEED_SCALE, (rap.speed_scale if rap != null else -1.0)])
	await create_timer(1.5).timeout
	await process_frame
	var back_head: Vector3 = head1.global_position if head1 != null else Vector3.ZERO
	var back_d: float = rest1.distance_to(back_head)
	_check(rap != null and not rap.is_playing() and back_d <= 0.0001,
		"一次性动作播完**回到静止姿**（在播 %s / 分件相对静止姿位移 %.6f —— 不回位的话人僵在末帧的"
			% [("是" if (rap != null and rap.is_playing()) else "否"), back_d]
			+ "伸手姿态；`stop()` 自己不复位，得靠 `_rest_pose()` 把快照写回去）")

	# (f) 破产 → `die` + **停在末帧**。
	#     ⚠ **名字要读 `assigned_animation`**：实测 Godot 4.6 里 `current_animation` 在
	#     "暂停 / 播完停下"两种状态下都会被清成 `""`（`assigned_animation` 留得住）——
	#     拿 `current_animation` 核这条**必然假红**（第一版就是这么红的，探针量出来的）。
	#     两条一起核：① 名字对；② **真的停在末帧**（位置 ≈ 时长、已不在播）—— 只核名字的话，
	#     `play()` 之后直接 `pause()`（停在第 0 帧、还是坐姿）照样绿。
	var ra_top0: float = _subtree_world_aabb(t[2]).end.y    # 静止姿的最高点（下面 f3 的参照）
	chars.react(4, "die")
	await process_frame
	var ra4: AnimationPlayer = chars.char_player(2)
	var ra4_a: Animation = null
	if ra4 != null:
		ra4_a = ra4.get_animation("die")
	var ra4_len: float = ra4_a.length if ra4_a != null else -1.0
	var ra4_pos: float = ra4.current_animation_position if ra4 != null else -1.0
	_check(ra4 != null and ra4.assigned_animation == "die" and ra4_a != null \
			and absf(ra4_pos - ra4_len) <= 0.001 and not ra4.is_playing(),
		"**破产 → `die`，并停在末帧**（实得 assigned=\"%s\" 在播 %s 位置 %.4f / 时长 %.4f —— "
			% [(ra4.assigned_animation if ra4 != null else "<没有播放器>"),
				("是" if (ra4 != null and ra4.is_playing()) else "否"), ra4_pos, ra4_len]
			+ "⚠ `play()` 之后直接 `pause()` 停在的是**第 0 帧**，必须先 `seek(时长)`）")

	# (f2) **破产的人留在座位上、看得见、不穿模** —— spec §九④ 定案的那一条
	#（"留在座位上"，明确否掉"消失：消失等于这家没了"）。
	# ⚠ **这一条正是简报那条"`die` 的末帧正是趴着"不成立的地方**（实测）：`die` 的末帧把
	# **整个人绕脚底转 −90°**（站着的人 = 倒在地上），可我们的人是**坐着**的 ⇒ 末帧实测：
	# 头落到 **y = −4.12**（地板 −3.70 以下）、躯干躺到 **z ∈ [−12.5, −5.2]**（椅子后面 1.5 m，
	# **远墙在 z = −9**）⇒ 出图看就是**对面那把椅子空了**。`chars.gd` 因此摘掉了那一条轨、
	# 改用手摆的**座位收势**（`_slump`，角度顶在"不与桌子实体体积相交"的几何上限附近）。
	# 这三条钉的就是"摘对了吗"：人还在锚点上 / 头在桌面上方 / 没有分件落地板以下或插进桌子。
	# **变红口子**：把 `_pose_die` 里那句 `_die_without_fall(ap)` 去掉（退回整体倒地），这三条一起红。
	var dp: Dictionary = _death_pose(t[2], t3)
	# 破产收势这一行是**四条反应里最后一条**的穿透读数（(c2) 那张表的第 4 行）：它**不适用**
	# (c2) 的放宽 —— 收势是"坐在座位上歪倒"，不是伸手 ⇒ **判据 ③ 原样：零相交**。
	print("  [实测] 破产收势（`die` 末帧，判据 ③ 原样·零相交）：相交 %d 件 / 最近净空 %+.3f / 最高点 %+.3f / 最低分件 %+.3f"
		% [int(dp.hits), float(dp.worst), float(dp.top), float(dp.low)])
	var an2: Transform3D = room.seat_anchor(2)
	var off: Vector2 = Vector2(t[2].global_position.x - an2.origin.x,
		t[2].global_position.z - an2.origin.z)
	_check(off.length() <= 0.001,
		"破产那家**还在自己那把座位上**（世界 xz 与 `seat_anchor(2)` 的偏差 %.4f —— "
			% off.length() + "倒地那一条会把整个人搬到椅子后面 1.5 m 去，这条立刻红）")
	_check(float(dp.head_y) > 0.0,
		"破产那家的头**在桌面上方（看得见）**（头 y=%.3f vs 桌面 y=0.000 —— 退回整体倒地时它是 −4.12）"
			% float(dp.head_y))
	_check(float(dp.low) >= GameRoom.FLOOR_Y - 0.001,
		"破产那家**没有落到地板以下**（最低分件 y=%.3f vs 地板 %.2f）" % [float(dp.low), GameRoom.FLOOR_Y])
	_check(int(dp.hits) == 0,
		"破产那家**不插进桌子的实体体积**（逐件、与判据 ③ 同一口径：相交 %d 件，最近净空 %+.3f 世界）"
			% [int(dp.hits), float(dp.worst)])
	# (f3) **`die` 自己的内容真的落在身上**：这条动画的收势是"举双手"（实测世界最高点由**手臂**
	#      撑着），与待机（最高点是头）不同 ⇒ 最高点必须抬起来。只核名字的话，
	#      "play 了 die 但一条轨都没生效"照样绿。
	_check(float(dp.top) > ra_top0 + 0.5,
		"**`die` 自己的动作真的落在身上**（世界最高点：待机 %.3f → 破产 %.3f，抬了 %.3f 世界 = %.0f cm"
			% [ra_top0, float(dp.top), float(dp.top) - ra_top0, (float(dp.top) - ra_top0) * 200.0]
			+ " —— `die` 里手臂转 180°（举双手），那是它自己的内容，不是我们摆的）")
	_check(chars.char_dead(2),
		"破产**被记住了**（`char_dead` —— 不记住的话，一次整体重建就把他**复活**了）")

	# 停住的那一帧**不许再往前跑**（真等一小段真实时间再量一次）：只比"位置==时长"的话，
	# 一条**没 pause、自己播完停在末帧**的实现也是绿 —— 这条把"停"这件事本身钉住。
	await create_timer(0.3).timeout
	var ra4_pos2: float = ra4.current_animation_position if ra4 != null else -1.0
	_check(ra4 != null and is_equal_approx(ra4_pos2, ra4_pos),
		"破产那家**定在末帧不动**（0.3 s 之后位置 %.4f，与刚播完时 %.4f 相同）" % [ra4_pos2, ra4_pos])

	# (g) **一次整体重建之后仍然是"留在座位上"的那一副**（这是最容易漏的那一半：
	#     `set_chars` 重建会把新人摆成**静止姿** ⇒ 破产的那一家若不按 `_dead_peers` 重新摆回末帧，
	#     他就会**复活**成端坐着的样子，而 HUD 已经说他出局了）。
	# ⚠ 原版这里走的是"`set_fade(1.0) → set_fade(0.0)` 的淡出往返"；**淡出已整段取消**
	#（v0.8.0 第三次改版，见 ⑭）⇒ 改成**座位序轮转一格**触发一次真重建 —— 测的东西更硬：
	#     连"人换了椅子"也一并覆盖（记忆的载体是 `peer`，不是插槽）。
	# **变红口子**：把 `_apply_poses()` 里 `char_dead` 那一支拿掉 ⇒ 重建之后这一家坐正了，本段全红。
	var seats_rot := _seats_rotated()
	chars.set_chars(seats_rot)
	await process_frame
	var rb_slot := -1
	for i in seats_rot.size():
		if int((seats_rot[i] as Dictionary).get("peer", GameData.NO_PEER)) == 4:
			rb_slot = i
	var rb_w := chars.get_node_or_null("Char%d" % rb_slot) as Node3D if rb_slot >= 0 else null
	var rb_ap: AnimationPlayer = chars.char_player(rb_slot) if rb_slot >= 0 else null
	var rbp: Dictionary = _death_pose(rb_w, t3) if rb_w != null else {}
	_check(rb_slot >= 0 and chars.char_dead(rb_slot) and rb_ap != null \
			and rb_ap.assigned_animation == "die" and not rb_ap.is_playing() \
			and float(rbp.get("top", 0.0)) > ra_top0 + 0.5,
		"破产那家**活过一次整体重建**（座位序轮转一格 ⇒ 人换到 slot%d，仍趴在座位上："
			% rb_slot + "最高点 %.3f vs 静止姿 %.3f —— 记忆的载体是 `peer`，不是播放器）"
			% [float(rbp.get("top", 0.0)), ra_top0])
	# 摆回原座位序（下面 (h) 与末段的读数都按原序）
	chars.set_chars(seats)
	await process_frame

	# (h) 已经破产的那家**不再做别的动作**（破产是终局表现，不能被后来的付钱 / 摇头顶掉）
	chars.react(4, "pay")
	await process_frame
	var rah: AnimationPlayer = chars.char_player(2)
	var rah_pos: float = rah.current_animation_position if rah != null else -1.0
	_check(rah != null and rah.assigned_animation == "die" and absf(rah_pos - ra4_len) <= 0.001,
		"已经破产的那家**不再做别的动作**（实得 assigned=\"%s\" 位置 %.4f —— 破产是终局表现）"
			% [(rah.assigned_animation if rah != null else "<没有播放器>"), rah_pos])

	# 供报告的原始读数。⚠ 节点在 ⑩ ⑪ 里**重建过**（那两条本来就要换一批实例）⇒ 这里重新取一遍，
	# 别用早先那批引用（旧引用已经 `queue_free` 了，读它会报 `previously freed`）。
	for i in CHAR_SLOTS:
		var cc := chars.get_node_or_null("Char%d" % i) as Node3D
		var aa := _subtree_world_aabb(cc)
		var leg := cc.find_child("leg-left", true, false) as Node3D
		print("  [实测] slot%d 模型 %s / 世界 AABB %s..%s（尺寸 %s）/ 腿 scale %s"
			% [i, chars.char_model(i), aa.position, aa.end, aa.size,
				leg.scale if leg != null else Vector3.ZERO])

	if fails == 0:
		print("CHARS TEST: PASS")
		quit(0)
	else:
		print("CHARS TEST: %d FAILURES" % fails)
		quit(1)
