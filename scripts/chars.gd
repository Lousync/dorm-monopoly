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
## 逐座位选模型（按棋子色，见 `CHAR_MODELS_BY_COLOR`）已做。
##
## **二期 Task 3（v0.8.0 改版）：完全静止 + 头顶名牌** —— 用户 2026-10-06 判图后拍板：
## **人物不要乱动**，并且"靠角色本身认人"读不出来 ⇒ 加标识。**本条推翻了二期 spec §5.7
## 的旧定案**（"不改名牌、靠角色本身认人"）。于是：
##   ① **一帧动画都不播** —— 待机 `idle` 整条退场（模型停在自己导入时的静止姿，叠加手摆坐姿
##      就是"坐着的静止人"）；连带那条"当前行动者 = 同一条 `idle` 提速 1.4×"也一起退场；
##   ② **头顶浮动名牌**（`Tags/Tag{i}`）：**棋子色牌 + 昵称**、整块 `billboard` 朝向镜头、
##      立在**头顶之上**（牌底边按模型的**世界 AABB 顶**算，不是写死的数）；
##   ③ **当前行动者靠牌上一圈金边**表达（静止的，不闪）—— 替掉原来的提速线索；
##   ④ **取景不淡出**（v0.8.0 第三次改版：用户第三条「2D 视角下人物不要消失」）——
##      四档取景下人都看得见。原先那套"读棋盘那几档全隐 + 停播"整段删除，理由见 `_apply_poses`。
## 四条都**只读表现层**：行动者读 `st.turn`，取景读 `view_t` / `dolly`。
##
## ⚠ **名牌为什么挂在 `Chars/Tags` 下、而不是挂在 `Char{i}` 里**：`chars_test` 有一整批断言
## 拿**角色子树的 AABB**去量落位 / 穿模 / 破产收势（`_subtree_world_aabb(Char{i})`）—— 名牌一进去，
## 那个"最高点"就变成牌顶，几条判据会**悄悄换了对象**（一期 `layout_test` 把 `Nameplate`
## 从家具那一批里剔出去，就是同一个理由）。挂成**兄弟节点**则各量各的，谁也不用剔谁。
## 名牌没有这个问题：它一直可见（v0.8.0 第三次改版起不再随取景淡出）。
##
## **二期 Task 4：四个玩法事件各有一动**（`react()`）—— 出牌 / 付钱 / 被抢地 / 破产，
## **四条动画名全部是普查实测存在的**（见 `REACT_ANIMS`）；破产那一条**停在 `die` 的末帧**
## （= 躺下 / 趴着）并且**记住**，spec §5.4 定的"破产的人留在座位上趴着"就是它（见 `_dead_peers`）。
## 事件同样**只读表现层**（`game.gd` 从已同步的状态读边沿）—— 一处 `@rpc` 都没新增。
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

# ---------------- 二期 Task 3（改版）：头顶名牌 / 取景四档恒可见 ----------------
#
# 本节的契约（v0.8.0 改版后）：
#   ① **完全静止** —— 本文件**不播任何动画**（`_place` 里没有 `play()`；一次性反应播完 `stop()`）；
#   ② **头顶名牌**（`Tags/Tag{i}`）—— 棋子色牌 + 昵称 + billboard；行动者多一圈金边；
#   ③ **取景不淡出**（四档都看得见，见 `_apply_poses` 那段）。
# **一行玩法都不碰**：行动者是从表现层**读**来的（`game.gd:_refresh_players` 里的 `st.turn`），
# 取景也是从**表现层读**来的（往上找那个暴露 `view_t` / `dolly` 的祖先）⇒ 没有新的状态、
# 没有新的 `@rpc`。

# ---------------- 二期 Task 3（改版）：头顶名牌 / 取景四档恒可见 ----------------
#
# 本节的契约（v0.8.0 改版后）：
#   ① **完全静止** —— 本文件**不播任何动画**（`_place` 里没有 `play()`；一次性反应播完 `stop()`）；
#   ② **头顶名牌**（`Tags/Tag{i}`）—— 棋子色牌 + 昵称 + billboard；行动者多一圈金边；
#   ③ **取景不淡出**（四档都看得见，见 `_apply_poses` 那段）。
# **一行玩法都不碰**：行动者是从表现层**读**来的（`game.gd:_refresh_players` 里的 `st.turn`），
# 取景也是从**表现层读**来的（往上找那个暴露 `view_t` / `dolly` 的祖先）⇒ 没有新的状态、
# 没有新的 `@rpc`。

## ---------------- 头顶名牌（`Tags/Tag{i}`） ----------------
#
## **它为什么存在**：用户 2026-10-06 判图后说「加个标识，不然我不知道他是谁」——
## 二期 spec §5.7 当初定的"靠角色本身认人"（四个模型按棋子色一一对应、永不撞车）**读不出来**。
## 原因也是量得出来的：`CHAR_TINT` 为了"角色不许是画面里最亮的东西"把整张贴图压到
## `0.29/0.25/0.21`（Task 2 那段），加上屋里只有一盏吊灯 ⇒ 蓝 / 红 / 绿三个人在**背对镜头**
## 的那两把椅子上都是**一团暗褐色**，只能靠正面那张脸认——而正面只有对面那一家露得出来。
##
## **做法 = 一期椅背名牌的同一套语言**（BoxMesh 薄牌 + Label3D），只改三处：**billboard 朝向镜头**、
## **立在头顶之上**、**行动者多一圈金边**。颜色仍取 `GameData.PLAYER_COLORS`（与 HUD 名册条、
## 椅背名牌、棋盘色条同一个来源 ⇒ 同一家在哪都是同一个色）。
##
## ⚠ **牌子要"亮"是故意的**：屋里唯一的亮色就是它，而它的职责就是**被认出来** ——
## 与一期椅背名牌同一条口径（`layout_test` 那批"家具不许是最亮的东西"的断言里，
## 名牌是被**点名剔除**的："名牌是另一码事（棋子色，故意的亮）"）。名牌挂在 `Chars/Tags` 下，
## 不在 `Char{i}` 里 ⇒ 角色那几条 AABB 断言的对象不变（见文件头那段）。

## 牌面尺寸（世界单位）。取 **1.7 × 0.52** —— 参照是模型的头（`head` 0.8 模型单位
## × `CHARS_SCALE` 2.8125 = **2.25 世界宽**）：牌子略窄于头，挂在头顶不显得比人还重。
const TAG_W := 1.7
const TAG_H := 0.52

## 牌底边离**模型世界 AABB 顶**的净空（世界单位）。**不写死"头顶在第几米"** ——
## 位置由 `_tag_top()` 从模型实测的 AABB 顶算出来，`SEAT_ROOT_Y` / `CHARS_SCALE` /
## `HEAD_SHRINK` 哪一个改了，牌子都跟着走。
const TAG_GAP := 0.28

## 行动者那一圈金边的**单边宽度**（世界单位；牌面每边各外扩这么多）。
const TAG_RIM := 0.075
## 金边色（行动者专用）。取自转盘那一族的暖金（`table_props.WHEEL_GOLD` 同调），
## 在暗屋里与棋子色都拉得开。
const TAG_ACTOR_GOLD := Color(0.95, 0.78, 0.35)

## 牌面 / 金边**自带的光**（`emission_energy_multiplier`）。屋里只有一盏吊灯，纯反光的牌子
## 在背光那两把椅子上会糊掉 ⇒ 给一点自发光让"棋子色 + 金边"稳定读出来。
## **不取更大**：再大就把牌子变成画面里最亮的东西，压过桌面（一期 Task 8 那条判据管的是家具，
## 但同一条观感纪律在这里一样成立）。
const TAG_EMIT := 0.55

## 名字的字号与**世界尺寸**。`pixel_size` 是"1 像素 = 多少世界单位"，所以世界字高 ≈
## `TAG_FONT_SIZE × TAG_FONT_PS`。名字长的时候按 `_make_tag()` 里那条式子**自动缩**，
## 保证整串字不出牌面。
const TAG_FONT_SIZE := 64
const TAG_FONT_PS := 0.0045

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

## 每个 slot 上的 `AnimationPlayer`（**下标 = 椅子号**，与 `_chars` / `_char_peers`
## 三者**同进同出**）。`null` = 这个座位上没人 / 模型里没找到播放器。
## **改版后没人靠它播待机了** —— 它只剩两个用处：`react()` 播**一次性**反应、
## `_pose_die()` 停破产末帧。
var _char_players: Array = []

## 每个 slot 上那个人的**静止姿快照**（`[[Node3D, Transform3D], …]`）：`_place()` 摆完手摆坐姿、
## **还没有任何动画碰过**的那一瞬间，把模型子树里每个 `Node3D` 的 `transform` 记下来。
##
## **为什么需要它**（本改版实测到的坑）：`AnimationPlayer.stop()` **不会把姿态复位** ——
## 实测：一次性反应播完 `stop()` 之后，分件仍停在**末帧**（slot1 的世界 AABB 深 6.89，
## 而同一个模型在静止姿上是 4.5；"在播 否"却仍是伸手姿态）。旧版之所以看不出来，
## 是因为 `_react_finished` 紧接着 `play(idle)` —— 待机那条动画**逐帧重写**了躯干 / 双臂 / 头，
## 把残留姿态盖掉了。改版后**没有第二条动画来盖** ⇒ 必须**自己记、自己还原**
##（`_rest_pose`），否则打一次牌那个人就永远伸着手。
var _rest_xf: Array = []

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
			# 「我」这一侧不出人（spec §5.1）：六个数组都记一个"空位"，下标才对得上椅子号。
			_chars.append(null)
			_char_peers.append(GameData.NO_PEER)
			_char_models.append("")
			_char_players.append(null)
			_rest_xf.append(null)
			continue
		var sd: Dictionary = seats[i]
		var color := int(sd.get("color", 0))
		var model := model_for_color(color)
		_chars.append(_place(i, model))
		_char_peers.append(int(sd.get("peer", GameData.NO_PEER)))
		_char_models.append(model)
		_char_players.append(_find_player(_chars[i]))
	# 新摆的这批人要**立刻**带上"谁趴着"（不能等下一次广播：重建之后的那几帧
	# 破产那家会端坐起来，而出图恰好抓的就是这几帧）。
	_apply_poses()

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
	_char_players.clear()
	_rest_xf.clear()

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
	# 够不着它，动画顶不掉。
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
	# ⚠ **只动 `scale.y`，不整份赋值**（本轮 fix round，终审 findings ⑤）：导入器把模型的比例搬到了
	# 节点上（同 `head` 自带 0.1 那条，普查 §三）⇒ `leg.scale = Vector3(1, LEG_SQUASH, 1)` 会把
	# `leg-*` 自带的 x/z **静默清成 1.0**。今天无害（普查 §4.1 实测腿节点是单位缩放，出图那条读数
	# 也仍是 `(1.0, 0.8, 1.0)`），但哪天导入器改了 `leg-*` 的缩放，这里会悄悄改外形，而先红的
	# 是脚底 / 髋那两条落位断言 —— 病因会指错方向。与 `head.scale *= HEAD_SHRINK` 同一条纪律：
	# **只碰要碰的那一根轴**。
	for nm in ["leg-left", "leg-right"]:
		var leg := mi.find_child(nm, true, false) as Node3D
		if leg != null:
			leg.scale.y = LEG_SQUASH
	# 头：**再乘一个小系数**（见 `HEAD_SHRINK`）。走 `find_child` 与腿同一条理由（层级见普查 §三）。
	var head := mi.find_child("head", true, false) as Node3D
	if head != null:
		head.scale *= HEAD_SHRINK
	_shade(mi)
	_no_shadow(mi)
	# **静止姿快照**：就在这一刻（手摆坐姿都摆完了、还没有任何动画碰过）把整棵子树的
	# `transform` 记下来 —— 一次性反应播完要靠它还原（见 `_rest_xf` 那段那个实测到的坑）。
	# ⚠ **必须在任何 `play()` 之前**：一旦播过，被动画碰过的分件就再也回不到"出厂值"了。
	_rest_xf.append(_snapshot(mi))
	# ---- 完全静止（v0.8.0 改版）：**这里一个 `play()` 都没有** ----
	# 待机 `idle` 整条退场（用户 2026-10-06："玩家人物不要乱动"）。模型停在自己导入时的
	# **静止姿**（= 节点默认 TRS，普查 §4.1 那张表里"静止姿"那一行），叠加上面那三处手摆
	# （外套节点 −0.2 / 腿压短 / 头收一点）就是"坐着的静止人"。
	# ⚠ **别在这里加回 `play()`**：`chars_test` ⑫（一帧动画都不播）与 ⑬（分件真的静止）
	# 两条会立刻红 —— 那正是本改版要守住的东西。
	return wrapper

## 一棵子树里每个 `Node3D` 的 `transform` 快照（静止姿的唯一记录，见 `_rest_xf` 那段）。
static func _snapshot(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Node3D", true, false):
		out.append([n, (n as Node3D).transform])
	return out

## 把第 `slot` 个人**还原到静止姿**（一次性反应播完之后走它）。
##
## **为什么不是 `ap.stop()` 就完事**：实测 `AnimationPlayer.stop()` **不复位姿态**
##（分件停在末帧，见 `_rest_xf` 那段）⇒ 得把快照里那几个 `transform` 一个个写回去。
## 只碰**快照里记下的那些节点**（模型自带的分件）—— 外套节点 / 名牌都不在里面。
func _rest_pose(slot: int) -> void:
	if slot < 0 or slot >= _rest_xf.size():
		return
	var rec = _rest_xf[slot]
	if rec == null:
		return
	for e in rec as Array:
		var pair := e as Array
		var n := pair[0] as Node3D
		if n != null and is_instance_valid(n):
			n.transform = pair[1]

## 名牌用的一块四边形（**默认单面**：billboard 保证永远正面朝镜头，背面看不见也就不用管）。
static func _tag_quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q

## 名牌用的材质：棋子色（或金边色）+ **一点自发光**（见 `TAG_EMIT`）+ billboard。
## **不是 UNSHADED**：与房间同一条纪律（`room._lit_mat` 那段），牌面也要能吃到吊灯那一层。
static func _tag_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = TAG_EMIT
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m

## 模型子树里的 `AnimationPlayer`（`null` = 没有）。走 `find_children` 按**类型**找，
## 不写死节点名：导入器给它的名字将来若变，这里不会静默失效（`chars_test` 有一条钉着"找到播放器"）。
static func _find_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null

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

# ---------------- 行动者的表达：**已整体搬到桌面立牌** ----------------
#
# 用户 2026-10-06：「**人物顶部铭牌去掉**」。角色层原先靠两种东西表达"轮到我了"：
#   ① 待机动画提速 1.4×（第二次改版已随"完全静止"退场）；
#   ② 头顶名牌上的一圈金边（第三次改版加的）。
# **两次都退场了**，这条表达现在**在桌面立牌上**：牌面就是名册格烘出来的那块 Control，
# 行动者那 1px 金边由 `game._apply_corner_style` 照旧刷（判据仍是 `_op_owner` / `_hl_peers`）。
# ⇒ 本文件**没有**行动者这个概念了：`set_actor` / `actor_peer` / `_apply_actor` 一并删除，
# `game.gd` 那处喂入也删了。角色的职责收敛成一条：**把四个人坐对、坐着不动**。

## 第 `slot` 把椅子上的 `AnimationPlayer`（`null` = 没人 / 没找到）。
## **改版后没人靠它播待机了**（见 `_char_players`）—— 测试与 `react` / `_pose_die` 用它。
func char_player(slot: int) -> AnimationPlayer:
	if slot < 0 or slot >= _char_players.size():
		return null
	var ap := _char_players[slot] as AnimationPlayer
	return ap if ap != null and is_instance_valid(ap) else null

## 把「谁趴着」刷到每个座位上（`set_chars` 重建之后调它）。
##
## **为什么必须有这一条**：`set_chars` 是**整套重建**（`_place` 每次都摆的是**静止姿**），
## 而"破产了"这件事记在 `_dead_peers` 里、**与播放器无关** ⇒ 重建之后必须按它把趴着的那家
## 重新摆回 `die` 末帧，否则他会**复活**成端坐的样子（HUD 却已经说他出局了）。
## 没趴下的那些不用管：新人本来就停在静止姿。
##
## **这里也是"随取景淡出"整段退场之后留下的那一半**（v0.8.0 第三次改版）：
## 原先 `_apply_fade()` 每次都要遍历所有槽位做三件事（显隐 / 透明度 / 姿态），
## 前两件随"取景不淡出"一起作废，只剩"姿态"这一件 —— 就是本函数。
## **谁调用它**：`set_chars()`（每次重建之后）。
## `react(die)` 不走它（那一支当场就 `_pose_die` 了，不必绕一圈）。
func _apply_poses() -> void:
	for i in _chars.size():
		var w := _chars[i] as Node3D
		if w == null or not is_instance_valid(w):
			continue
		if not char_dead(i):
			continue
		var ap := _char_players[i] as AnimationPlayer if i < _char_players.size() else null
		if ap != null and is_instance_valid(ap):
			_pose_die(ap, w)

# ---------------- 二期 Task 4：四个玩法事件的反应（出牌 / 付钱 / 被抢地 / 破产） ----------------
#
# **四个事件 → 四条动画，名字全部是普查实测存在的**（`doc/development/chars-导入与动画普查.md`
# §三 的 27 条清单 + §5.4 的建议表）。**写错名字 / 编一条不存在的 ⇒ `chars_test` 立刻红**
#（它按**字面名字**断言，不读本文件这张表 —— 读表等于把实现重述一遍，改个名永远绿）。
#
# **事件从哪来**：全部由 `game.gd` 从**已同步的状态**里读**边沿**，再调 `react()` ——
#   * 出牌 = 那一家本回合的 `item_used` 由假变真（`_use_item` 里置、`_item_turn_start` 里清）；
#   * 付钱 = 金钱差分 < 0（就是既有**飞钞**那一拍，`_money_flies`）；
#   * 被抢地 = `st.tiles[i].owner` 从某个**还活着**的玩家变成别人（易主：强拆令 / 交换课表 / 抄家…）；
#   * 破产 = `alive` 由真变假。
# ⇒ **一处 `@rpc` 都没新增、状态机一行没改**（spec §5.5 那条纪律）。本文件仍然只**认识 peer**，
# 不读 `st`、不认玩法（它连"什么叫出牌"都不知道 —— 那是 `game.gd` 的活）。
#
# **幅度 = 含蓄**（用户 2026-10-06 定案，spec §九 开放问题 5）：这四条都是 0.17~0.67 s 的小动作，
# **只许慢放、不许加速** —— 用户 2026-10-06 实机说"快得就像闪了一下"，故统一套 `REACT_SPEED_SCALE`
# = **0.6× 慢放**（见那条）；但**绝不"放大一点看得清"**（本作调性克制，四家同时动起来会变马戏团）。
# `chars_test` 有一条钉着"反应速度 == `REACT_SPEED_SCALE`"（既防加速、也防随手乱调）。

## 事件 → 动画（**只放实测存在的名字**，逐条依据见普查 §5.4）：
##   * `play` **出牌**（出道具）= **`interact-right`**：0.6667 s，幅度与时长都够、**首尾闭合**；
##   * `pay` **付钱** = **`holding-left`**：0.1667 s，与既有**飞钞**演出同一拍。
##     ⚠ **绝不能用 `pick-up`**（0.3333 s）—— 它是这个包里**唯二"首尾不闭合"**的两条之一，
##     结束在**弯腰**姿态：想停末帧得手动回位，想循环得另接（普查 §三 实测细节 2）；
##   * `rob` **被抢地**（名下地产易主）= **`emote-no`**：0.6667 s。**包里没有"后仰 / 拍桌"**
##     这类细分动作 ⇒ 用**摇头**表达否认可读（普查 §5.4 建议表）；
##   * `die` **破产** = **`die`**：0.3333 s。⚠ 它是**不闭合**的那条（末帧不是静止姿）⇒ 要
##     `seek(末帧) + pause()` **定住**，并且要**记住**（见 `_dead_peers`）。
##     ⚠⚠ **它的"倒地"那一条在坐着的人身上不能用**（本任务实测，见 `_pose_die`）：
##     那条轨把整个人**绕脚底**转 −90°，站着的人是"倒在地上"，坐着的人是"**落到地板以下、
##     房间之外**"＝**人不见了**（而 spec §九④ 明确否掉"消失"）。⇒ 摘掉那一条 + 手摆收势。
const REACT_ANIMS := {
	"play": "interact-right",
	"pay": "holding-left",
	"rob": "emote-no",
	"die": "die",
}

## `die` 这一条的键（它与其他三条的处理不同：**停末帧 + 记进 `_dead_peers`**）。
const REACT_DIE := "die"

## 反应动画的**播放速度**（< 1 = 慢放）。用户 2026-10-06 实机：「拿取 / 使用卡牌时动画有点快，
## 买地皮 / 房子时快得就像闪了一下」——素材本身短（付钱 `holding-left` 仅 0.1667 s），
## 统一慢放到 0.6× 后：出牌 / 被抢 **0.6667 → 1.111 s**、付钱 **0.1667 → 0.278 s**、
## 破产 0.3333 → 0.556 s（破产走 `seek` 末帧，倍率对它无感）。
## **它是"统一倍率"而不是逐条改时长**（四条一起慢、比例不变）；换更长的素材方案已否
##（普查 §5.4：包里唯一更长的 `pick-up` 首尾不闭合、要手摆回位）。
## ⚠ **别调回 1.0，也别"顺手放大"**：`chars_test` 钉着 `== REACT_SPEED_SCALE`（既防加速、也防乱调）。
const REACT_SPEED_SCALE := 0.6

## **破产收势的三个角度**（度，见 `_pose_die` / `_slump`）：腰往前折 / 上身侧倒 / 再低头。
##
## **为什么要有它们**：`die` 自己的末帧是"整个人绕脚底倒地"（实测落到地板以下、房间之外
## ⇒ 看上去就是人不见了），而"留在座位上"这个已定案的表现，这个包里**没有任何一条动画**
## 给得出（普查 §5.4：没有后仰 / 拍桌 / 低头这类细分动作）。⇒ **手摆**，同 `LEG_SQUASH` /
## `HEAD_SHRINK` 那两条一样，摆完由 `chars_test` 钉住（头在桌面上方、不与桌子实体体积相交、
## 人仍在座位锚点的 xz 上、没掉到地板以下）—— **不是随手挑的数，是照着这几条判据收敛出来的**。
##
## **收敛过程（实测，逐档读数见 task-4-report）**：
## ① 桌子是**从地板到桌面的一整块实体**（底座 AABB y∈[−3.70, −0.01]、z∈[−3.48, 3.48]），
##    而人就坐在它前面 1.15 世界（23 cm）处 ⇒ **腰往前折过 15° 就把躯干插进桌子**
##    （实测：20° 起躯干 ∩ 桌子 −0.10；25° 起连头也进去）；
## ② 但**往前折少了看不出"倒"** ⇒ "倒下去"这一下主要由**侧倒**给：绕 Z 转不改变 z，
##    人一直在桌沿之外 ⇒ 侧倒不受那条限制（实测：腰 15°+侧 30° 就已经让**头**插进去了，
##    因为前折把头顶到了桌沿上方；**侧倒单独可以很大**）；
## ③ 于是取 **腰 5° + 侧 45° + 低头 12°**：实测头落在 **y = 0.22**（桌面上方，看得见）、
##    全部分件与桌子实体体积**最近净空 +0.205**、最低分件 y = −3.56（地板 −3.70 之上）、
##    人仍在座位锚点的 xz 上（偏差 0.0000）。
## **它是"倒"不是"趴"** —— 几何上"趴到桌上"做不到（桌子是实体，趴上去就埋进去了），
## 这一条如实记在 task-4-report 的 Concerns 里，等控制者裁决。
const DIE_SLUMP_DEG := 5.0    # 腰往前折（顶在"不插进桌子"的上限附近）
const DIE_ROLL_DEG := 45.0    # 上身侧倒（破产那一下"倒下去"的主要来源）
const DIE_HEAD_DEG := 12.0    # 头再低一点

## 已经**趴下**的那几家（peer -> true）。破产是一次性、但**永久**的表现：
## `die` 停末帧之后这个人就一直趴着 —— 而 `set_chars`（重建）会把新人摆成**静止姿**
## ⇒ 不记住就会**复活**（spec §5.4 要的是"留在座位上趴着"）。
##
## 记的是 **peer 而不是椅子号**：座位序会随 `_seat_peers()` 轮转（`set_chars` 重建），
## 而"这家破产了"与坐哪把椅子无关（同 `CHAR_MODELS_BY_COLOR` 那条"按人定、不按椅子定"）。
var _dead_peers := {}

## 播某个玩家的反应动画（`kind` ∈ `REACT_ANIMS` 的键）。
##
## **读不到就什么都不做**（找不到这个 peer / 这条动画时只 `push_warning` 一条）：
## 事件是从**已同步的状态**读来的，允许"人还没摆上椅子"这种时序（广播可能早一帧）。
##
## ⚠ **`speed_scale` 统一走 `REACT_SPEED_SCALE`（0.6× 慢放）** —— 这不是"放大看得清"，是**放慢**
##（用户 2026-10-06 实机："快得就像闪了一下"）。四条一起慢、比例不变；`chars_test` 钉着它。
##
## ⚠ **v0.8.0 第三次改版：这条早退整段删除**。原先它规定"已经淡到全隐 + 停播那一档时，
## 反应一律丢掉、不排队"（终审 findings ①）—— 现在**没有淡出档了**（见 `_apply_poses`：
## 四档取景下人都看得见），所以事件到了就照常播，没有"丢掉"这回事。
##
## 留下这一条留档，是因为它当年钉出的那件事仍然值得记：**"在读棋盘那一档不许逐帧求值"**
## 是二期对性能的承诺（spec §六），而当时 `react()` 不看淡出档 ⇒ 会在一个 `visible = false`
## 的节点上重新开播、再也没人停它 ⇒ 那条承诺**静默失效**。今天这个矛盾消失了：
## 人物完全静止（待机退场）+ 不再淡出 ⇒ 只剩三个静止角色的绘制调用，测不出成本。
func react(peer: int, kind: String) -> void:
	var i := _slot_of_peer(peer)
	if i < 0:
		return
	var ap := char_player(i)
	if ap == null:
		return
	# 已经趴下的那家不再做别的动作：破产是**终局**表现，不能被后来的付钱 / 摇头顶掉。
	if kind != REACT_DIE and _dead_peers.has(peer):
		return
	var anim := String(REACT_ANIMS.get(kind, ""))
	if anim == "" or ap.get_animation(anim) == null:
		push_warning("角色没有 `%s` 这条动画（事件 `%s` 播不出来）" % [anim, kind])
		return
	# 慢放（见 `REACT_SPEED_SCALE`）：四条反应统一套上。`animation_finished` 按**实际时长**发 ⇒
	# 一次性动作的收尾（`_react_finished`）不用另算时长；`die` 走 `seek(末帧)`，倍率对它无感。
	ap.speed_scale = REACT_SPEED_SCALE
	if kind == REACT_DIE:
		_dead_peers[peer] = true
		_pose_die(ap, _chars[i] as Node3D)
		return
	# 三条**一次性小动作**：播完**自己回到静止姿** —— 不回来的话人僵在末帧的伸手姿态。
	# 一次性连接 `CONNECT_ONE_SHOT` 就够：这个包里除 `walk`/`sprint` 之外的动画都是 `LOOP_NONE`
	# ⇒ 播完**必发** `animation_finished`（`animation_finished` 对 `LOOP_NONE` 的动画一定会发）。
	# ⚠ **信号带一个参数**（`animation_finished(anim_name)`）⇒ 回调的签名必须**先接住它**
	#（少写一个参数是一条 SCRIPT ERROR，而表现只是"动作播完人僵住" —— 出图 / 断言都看得见）。
	#
	# ⚠ **接之前先断同名的那一个**：同一个人连着两次反应（同一帧里又出牌又付钱、或一条还在
	# 播就又被叫了一次）时，`connect` 会报 `already connected to given callable` ——
	# **那是一条 ERROR，且第二次的连接不生效**（本项目对 ERROR 零容忍；`chars_test` 里
	# "连着两次 react"那一档当场把它抓出来了）。断开再连，永远只有一条待发的回位。
	ap.play(anim)
	var cb := _react_finished.bind(ap, peer)
	if ap.animation_finished.is_connected(cb):
		ap.animation_finished.disconnect(cb)
	ap.animation_finished.connect(cb, CONNECT_ONE_SHOT)

## 一次性动作播完 → **回到静止姿**（除非这一家已经趴下了，见 `_dead_peers`）。
##
## **改版后是 `stop()` + `_rest_pose()`**：`stop()` 只是"别播了"，**它不复位姿态**
##（实测，见 `_rest_xf` 那段），所以紧接着要把静止姿快照写回去。
## 旧版在这里 `play(idle)` —— 待机那条动画会把残留姿态**逐帧盖掉**，所以当年看不出这个问题；
## 改版后没有第二条动画来盖，只剩 `_rest_pose()` 这一条路。
## 第一个参数是信号自带的动画名（用不到，接住它是为了签名对得上）。
func _react_finished(_anim: StringName, ap: AnimationPlayer, peer: int) -> void:
	if ap == null or not is_instance_valid(ap) or _dead_peers.has(peer):
		return
	ap.stop()
	_rest_pose(_slot_of_peer(peer))

## 把某人的播放器**停在 `die` 的末帧**（= 躺下 / 趴着）—— 但**先把"整体倒地"那一条摘掉**、
## 再补一个**座位上的收势**。两条都是实测逼出来的（见下）。
##
## ⚠ **光 `pause()` 没用**：`play()` 之后紧接着 `pause()` 停在的是**第 0 帧**（还是坐姿），
## ⇒ 必须 `seek(时长, true)` 先走到末帧（第二个参数 `true` = 立刻把姿态落到分件节点上）。
##
## ⚠⚠ **为什么必须摘掉 `root` 的旋转轨（本任务实测，是本简报里唯一站不住的一条）**：
## `die` 的末帧把**整个 `root` 绕"脚"转 −90°**（普查 §三 的层级里 `root` 的原点就在脚底），
## 对**站着**的人那是"倒在地上"；可我们的人是**坐着**的、脚下就是地板，实测末帧：
## `root` 局部 −90°、头落在 **y = −4.12**（地板 −3.70 **以下** 0.42）、躯干躺在
## **z ∈ [−12.5, −5.2]**（椅子后面 1.5 m，**远墙在 z = −9 ⇒ 有一截穿墙**）。
## ⇒ 表现是**人不见了**（出图实证：对面那把椅子空了）—— 而 spec §九④ 明确否掉的正是"消失"：
## 「消失等于'这家没了'，趴着才是'他输光了'」。**简报那条"die 的末帧正是趴着"只对站着的人生效。**
##
## **做法**：`die` 复制一份、**只摘掉 `root` 的旋转轨**（`_die_without_fall`，手法同「复制一份再换回库里」），
## 保留它自己的其余内容（手臂 180°＝举双手、头、`root` 的微量位移），再手摆一个
## **座位上的收势**（`_slump`：前折 + 侧倒 + 低头）—— 与 `HEAD_SHRINK` / `LEG_SQUASH`
## 同一条思路（这个包没有"弯腰"这条动画，普查 §5.4：**包里没有后仰 / 拍桌 / 低头这类细分动作**）。
## **实测这一摆**：头仍在桌面上方、各分件与桌子实体体积留有余量（最近 +0.205）、
## 人仍在座位锚点的 xz 上、最低分件在地板之上（四条都由 `chars_test` 钉着），
## 出图看得见"**人歪倒在座位上**"（出图前后对比：不摘那一条轨时对面那把椅子是**空的**）。
##
## **Godot 4.6 实测的口径（`chars_test` 钉着）**：`play()+seek(末帧)+pause()` 之后 --
## `assigned_animation == "die"`（**名字留得住**，`current_animation` 会变成 `""`）、
## `is_playing() == false`、`current_animation_position == 时长`。
## ⇒ **量 die 的名字要读 `assigned_animation`**：`current_animation` 在"暂停 / 播完停下"
## 这两种状态下都会被清成 `""`，拿它核名字必假红（第一版就是这么红的）。
func _pose_die(ap: AnimationPlayer, w: Node3D) -> void:
	var a := ap.get_animation(REACT_DIE)
	if a == null:
		return
	_die_without_fall(ap)
	ap.play(REACT_DIE)
	ap.seek(a.length, true)
	ap.pause()
	_slump(w)

## **座位上的收势**（手摆，见 `_pose_die`）：腰往前折 `DIE_SLUMP_DEG` + 上身侧倒 `DIE_ROLL_DEG`
## + 头再低 `DIE_HEAD_DEG`。
## 腿不在这一支里（`root` → `leg-*` 与 `torso` 是**并列**的两支，普查 §三）⇒ 腿照旧坐着、不穿桌子。
func _slump(w: Node3D) -> void:
	if w == null or not is_instance_valid(w):
		return
	var torso := w.find_child("torso", true, false) as Node3D
	if torso != null:
		torso.rotation.x = deg_to_rad(DIE_SLUMP_DEG)
		torso.rotation.z = deg_to_rad(DIE_ROLL_DEG)
	var head := w.find_child("head", true, false) as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(DIE_HEAD_DEG)

## `die` 的**去掉"整体倒地"那一条**的副本（装回本实例的库里，同名覆盖 —— 同「复制一份再换回库里」的手法）。
## 摘掉的是 `root` 的**旋转**轨（那条把整个人绕脚底转 −90°，见 `_pose_die` 那段实测）；
## 其余一条不动（`root` 的位移、`torso` / `arm-*` / `head` / `leg-*` 全部保留）。
##
## **为什么是"复制一份再换回去"**：`instantiate()` 出来的动画资源与 `PackedScene` 共用同一份
## ⇒ 就地删轨会污染缓存（同 `_shade` 那条理由）。
static func _die_without_fall(ap: AnimationPlayer) -> bool:
	var src := ap.get_animation(REACT_DIE)
	if src == null:
		return false
	var idx := -1
	for i in src.get_track_count():
		if src.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		# 轨道路径形如 `character-k/root:rotation` ⇒ 先切掉属性那一段再取末节节点名。
		if String(src.track_get_path(i)).get_slice(":", 0).get_file() == "root":
			idx = i
			break
	if idx < 0:
		return false
	var a := src.duplicate() as Animation
	a.remove_track(idx)
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		if lib != null and lib.has_animation(REACT_DIE):
			lib.add_animation(REACT_DIE, a)   # 同名覆盖：本实例从此用"不倒"的那一份
			return true
	src.remove_track(idx)   # 退路（问不到库时就地改，宁可脏一份也别不生效）
	return true

## 这个 peer 坐在第几把椅子上（`-1` = 他不在座上 / 还没有角色层）。
func _slot_of_peer(peer: int) -> int:
	for i in _char_peers.size():
		if int(_char_peers[i]) == peer:
			return i
	return -1

## 第 `slot` 把椅子上那家**是不是已经破产趴下**（`react(peer, "die")` 之后一直为真）。
## 测试用它核"趴下这件事被记住了" —— 不记住的话，一次重建就把他**复活**了。
## `_apply_poses` 也用它（趴着的那家走单独一支，见那里）。
func char_dead(slot: int) -> bool:
	return slot >= 0 and slot < _char_peers.size() and _dead_peers.has(int(_char_peers[slot]))
