# AGENTS.md — 项目级代理说明

> 面向在此仓库工作的 AI 编码代理（Claude Code / opencode 等）；**人类开发者也先读本文件**
> ——文档导航、工程约定、提交规范都在这里，本文件是这些约定的**单一来源**。
> `CLAUDE.md` 通过 `@AGENTS.md` 引入本文件，不复制内容。
> 更新：2026-10-08。

## 一、项目

**《宿舍大富翁》**：Godot **4.6** / **GDScript** 的 2D 桌游。56 格外圈棋盘，1~4 人联机（**房主即权威服务器**），亦可纯单机（房主 + 机器人，同一套代码）。无存档、不支持中途加入/观战。

## 二、文档导航（不要凭空猜功能）

### 我该看哪篇？

| 我是… | 先看 |
|---|---|
| 新加入的开发者 | `doc/development/上手指南.md` → `架构总览.md` → `联机协议.md` |
| 要改某个玩法 | `doc/game-design/` 下找对应系统（清单见下一节） |
| 要接美术/表现 | `doc/game-design/道具系统.md` §12（卡面规格）、`设计决策留痕.md` §一/§二 |
| 要排期/分工 | `doc/development/开发台账.md` |
| 要手动验证某件道具效果 | `doc/development/道具试验场.md`（原型 `doc/game-design/prototype/道具试验场-原型.html`） |
| 想知道这版改了什么 | `CHANGELOG.md` |

### 玩法设计（`doc/game-design/`）

| 文档 | 内容 |
|---|---|
| `术语表.md` | **全局共用语义**：发现 / 休眠 / 跳过回合 / 冷却 / 唯一性 / 标签 / 科技 / 畸变 |
| `回合与行动.md` | 回合顺序、两阶段、转轮规则、休眠 vs 跳过、决策托管 |
| `棋盘与地产.md` | 棋盘几何、格型、30 块独立地产、租金/装修/焦土 |
| `事件卡.md` | 机会/命运卡池、卡字段、`only` 过滤、免疫点 |
| `经济与胜负.md` | 资金、罚款/奖励、破产、反省、30 轮身家结算 |
| `小卖部.md` | 4 家独立货架、品质权重、刷新曲线、点击购买 |
| `黑市.md` | 机会卡进入、地皮计价、挨打小黑屋（休眠） |
| `赌场.md` | 全屏演出场景、抽游戏、投骰子、同步 |
| `道具系统.md` | 体力/冷却/唯一性/焚毁/免疫标签、橙货子系统、卡面规格 |
| `道具图鉴.md` | **逐件道具唯一来源**：品质/能量/类型/效果/联动/卡面文案（61 件） |
| `开局设置.md` | 房主开局配置项（经济/节奏/胜利/道具/特殊）；**每局从默认值起、无预设方案** |
| `开局科技.md` | 开局三选一科技机制 + 图鉴 |
| `畸变.md` | 全场畸变机制 + 图鉴 + 候选草案 |
| `设计决策留痕.md` | 讨论过程、拍板理由、当时的备选方案与日期（**不是当前事实**） |
| `图鉴.html` | **生成产物，勿手改**（唯一的非 `.md` 活文件）：事件卡 / 道具 / 科技 / 畸变 的检索页。由 `tools/gen_gallery.gd` 从数据表 + `道具图鉴.md` 生成，浏览器直接打开 |

**原型文件**收在 `doc/game-design/prototype/` 子目录（`.html`/`.drawio`）——**该子目录只放定稿存档、
不随实现更新**，与 `game-design/` 顶层的活文档 `.md` 分开放。
（顶层另有一份 `图鉴.html`，是**生成产物**、不是手写原型，别混进 `prototype/`，也别手改它。）`布局原型-玩家区与选项菜单.html`、
`布局原型-四人围桌.drawio` 是**定稿存档（2026-10-01）**——原型记录的是当时谈定的交互，
**可能与现状不一致**（例如原型里的「☰ 选项」按钮后来已改名「⏸ 暂停」）。
要写代码请以 `game-design/*` 与现有实现为准，不要把原型当成活的规范逐条对照。
`道具试验场-原型.html`、`对局UI改版-原型.html`（牌垫阶段按钮 + 道具点选交互）、
`赌场改造-原型.html`、`倒计时位置-原型.html`（倒计时落点五方案对比）、
`道具使用引导-原型.html`（拖动指向 + 引导）、`卡面角标与放大-原型.html`、
`小卖部开关-原型.html` 是可交互原型。
其中后四个原型**专供 `开发台账.md` §六「实机问题」**（#22 卡面角标 / #23 放大 / #24 拖动指向 /
#25 小卖部开关 / 倒计时落点）当时拍板用，除 `倒计时位置-原型.html` 外均**未被活文档引用**，
属"用了但没登记"——保留作定稿存档，**不要**当成活规范对照。

### 工程与协作（`doc/development/`）

| 文档 | 内容 |
|---|---|
| `架构总览.md` | 场景流、房主权威模型、RPC 约定、目录地图、表现层约定 |
| `联机协议.md` | s_*/c_* 全表、状态快照字段、等待状态机、超时/托管/断线 |
| `上手指南.md` | 环境、跑通、自动化开关、新增内容 checklist |
| `开发台账.md` | 系统状态总表、批次进度与**批次记录**（分工用）；**「还剩什么」不在这里** |
| `未完成项-交接.md` | **「还剩什么」的唯一权威**：可直接开工的清单 + 验收口径（交接用） |
| `道具试验场.md` | 道具效果的独立沙盒（已实现）：入口、界面、状态注入 |
| `3D房间-一期设计.md` | 3D 房间一期设计稿（**已完成，随 [0.10.0] 发布**）：房间层 / 推拉 / 材质与光照 |
| `3D房间-二期设计.md` | 3D 房间二期设计稿（**已完成，随 [0.10.0] 发布**）：人物层 / 坐姿 / 事件反应 |
| `chars-导入与动画普查.md` | Kenney「Blocky Characters」包的导入与动画普查（二期成果，零骨骼结论在此） |
| `plans/` | 实施计划：**随版本开发，合并进 `main` 后连同文件一起删除**（不留档） |

### 仓库根（不在 `doc/` 里，但属于文档体系）

| 文件 | 内容 |
|---|---|
| `README.md` | 项目门面：玩法规则、界面说明、项目结构、测试、构建打包 |
| `AGENTS.md` | **本文件**：文档导航、工程约定、提交规范的单一来源 |
| `CHANGELOG.md` | 版本变更（Keep a Changelog 风格 + 语义化版本） |
| `LICENSE` | MIT 授权 + 第三方素材来源与授权（原 `assets/CREDITS.md` 已并入本节）；**分发时必须一并保留** |

## 三、常用命令（PowerShell）

> **改完只跑「相关的那几套」测试，不要每次都跑全套**（用户 2026-10-09 定）：
> 全套十几套跑一轮要好几分钟，开发期间是纯浪费。按改动面挑：改玩法逻辑跑对应系统那套
> （`item_test` / `shop_test` / …）、改 `game.gd` 或公共代码跑 `regression_test`、
> 改界面 / 输入链路跑对应的 GUI 回归（`settings_ui_test` / `pause_menu_test` / `hud_test` …）。
> **`load_all` 例外 —— 它很便宜（几秒），改完任何 `.gd` 都先跑一遍**（它只做静态加载检查）。
> **全套留给 CI 与发版前**（`.github/workflows/ci.yml` 里那份清单就是全套）。

```powershell
# Godot 路径因机器而异：start.bat 会按已知目录自动查找；下面这行改成你机器上的实际路径。
# 注意要用 _console.exe（带控制台，才有 stdout；不带的那个看不到 print 输出）。
$G = "D:\Godot\Godot_v4.6.2-stable_win64_console.exe"
& $G --version                                            # 先确认路径可用
& $G --path .                                             # 运行（或双击 start.bat）
& $G --headless --path . --script tests/load_all.gd       # 脚本静态加载检查（改完先跑）
& $G --headless --path . --script tests/rules_test.gd     # 规则单测
& $G --headless --path . --script tests/item_test.gd      # 道具单测
& $G --headless --path . --script tests/blackshop_test.gd # 黑市单测
& $G --headless --path . --script tests/shop_test.gd      # 小卖部单测
& $G --headless --path . --script tests/casino_test.gd    # 赌场单测
& $G --headless --path . --script tests/regression_test.gd # 回归单测（审查发现的问题逐条钉住）
& $G --headless --path . --script tests/aberration_test.gd # 畸变单测（两道闸门 + 逐条效果）
& $G --headless --path . --script tests/tech_test.gd    # 开局科技单测（定档抽卡 + 逐条效果）
& $G --headless --path . --script tests/pause_menu_test.gd # 暂停菜单回归（真实 GUI 输入链路）
& $G --headless --path . --script tests/rules_panel_test.gd # 规则说明面板回归
& $G --headless --path . --script tests/hud_test.gd      # HUD 回归（身家条/底栏/客户端视角）
& $G --headless --path . --script tests/placard_test.gd  # 桌面立牌回归（落点/朝向/命中/烘图）
& $G --headless --path . --script tests/layout_test.gd  # 3D 房间+桌面布局与取景（格宽/房间带/光照契约/家具/吊灯）
& $G --headless --path . --script tests/chars_test.gd   # 3D 人物（坐姿/静止/事件反应/不穿模/不投影）
& $G --headless --path . --script tests/lab_case_test.gd # 道具试验场用例（保存/回放逐项还原）
& $G --headless --path . --script tests/settings_test.gd    # 开局设置单测（操作限时挡位）
& $G --headless --path . --script tests/settings_ui_test.gd # 大厅游戏设置弹窗回归
& $G --headless --path . --script tools/gen_gallery.gd  # 图鉴页生成（改了数据表 / 道具图鉴.md 后**必须重跑**）
& $G --headless --path . -- --autotest=host --rounds=5    # 联机回归（另开 client）
```

**自动化开关**（用法与更多细节见 `doc/development/上手指南.md`）：
`--autotest=host|client`、`--rounds=N`、`--max-rounds=N`、`--shot=`（截图）、
`--fps=N`（帧率实测：采 N 秒后打印平均 / 分位 / 最差帧并退出；加 `--fps-houses=1` 先灌满盘装修再采）、
`--card-gallery`（卡片图鉴）、`--menu-probe`（菜单探针）、`--dev`（开发者模式）、`--lab`（道具试验场）。

**摆拍截图（改界面时自检用）**：`--shot=<路径>` 存 PNG。四个非显然的坑：

- **不能加 `--headless`** —— 无头模式下 `get_viewport().get_texture()` 拿到的是**空帧**，
  截图必须开真实窗口跑。
- **文件名同时决定摆拍内容**（`dev_tools.take_shot` 里按 `path.contains(...)` 分支）：
  `plain` → 不弹赌场、不翻卡；`table` → 停在 3D 端全景（**不拉近、不弹格详情卡**）；不写
  `table` 时会调 `focus_grid(27, 2.0)` 想拉近到 27 号格、并弹格详情卡 —— **但 `cam_locked`
  默认锁着，`focus_grid` 直接 no-op**（摆拍默认锁镜头那条的副作用，见下 `freecam`）⇒ 不带
  `table` 的图**实际也是全景**，只是多一张格详情卡；真要看近景**必须配 `freecam`**；
  `rules` → 展开规则说明；`pause` → 打开暂停菜单（文件名再带 `setpanel` ⇒ 顺手切到「设置」那一片，
  用来核对**对局内设置面板**的分节边框盒 / 开关组件 / 与大厅弹窗的一致性，如
  `xx_pause_setpanel_table_plain.png`）；`card` → 跳过赌局；
  `deckout` → **抽卡「抽出」瞬间**：在 **0.06s / 0.16s 各补一张**（常规三帧的第一帧落在翻面之后，
  拍不到"卡刚亮出来的那一刻"）—— 批次 8 起**抽卡演出已在屏幕层、相机不动**，那个"先让推近
  生效"的旧前提没了：**不再需要 `freecam`**。**出图门是 `not path.contains("plain") or
  path.contains("card")`**（名字里带 `plain` 就跳过演出）⇒ 文件名要么不含 `plain`、要么带
  `card`，**有其一即可**（`card` 顺带跳过会盖住演出的赌局浮层），
  如 `--shot-game=1 --shot=shots/xx_deckout_card.png`；这个分支**不转轮**
  （转轮会把镜头焦点抢到转盘）。因为不带 `freecam`，这张图的背景**就是全景**，
  可直接与 `xx_table_plain.png`（及批次 7 的同名图）逐格比对"桌面没被放大 / 滑动"；
  `tilt` → 走**真接口** `table3d.snap_view(0.5)` 把视角推到轨道中点（俯角 50°→**69°**、
  距离一并插值），配 `table` 用出纯视角对比图（如 `xx_tilt_table_plain.png`）；
  `view2d` → 走 `table3d.snap_view(1.0)` 推到 **2D 端**（近正俯视、只看桌上地图）出图，
  用来拍 2D 那张（如 `xx_view2d_table_plain.png`）；
  `freecam` → **不锁自动镜头**（默认摆拍会锁住，避免对局推进拽走视角）；解锁后随后的
  `focus_grid` 拉近才生效，用来复现「玩家自己看到的近景」；
  `hand` → 给房主**发几张不同品质的道具**（只在房主侧注入状态，不动玩法代码），
  用来拍「手里握着牌」——开局背包是空的；
  `level` → 给前几块地**注入装修等级 1..4**（房主名下，用来核对房子图标与等级配色）；
  `target` → 进**选目标态**（给房主发一张「强拆令」、只给最后一家两块地）核对"可选中的**名册格**
  亮着、其余不亮"（**批次 13 ② 起落点在左上角「暂停」旁的名册条**；批次 12 D 起是右上角「战报」
  之下、再此前是屏幕四角条），**必须同时带 `plain`**
  （如 `xx_target_plain.png`）—— 不带的话后面那段赌局预览会盖上整屏、什么都看不出来。
  **注意看第一帧**（`xx_target_plain.png`，不带 `_N` 后缀）：选目标态不冻结树，第 2/3 帧
  （0.6/1.2s 后）对局可能已经推进过、状态被 `_cancel_target` 收掉了。；
  `logopen` → 展开右上角**战报栏**（走真入口 `_toggle_log`），用来核对"展开的战报栏不压名册条"
  （批次 12 D；如 `xx_logopen_table_plain.png`）—— **批次 13 ② 起名册条搬到左上角，两者天然分居
  左右、不再打架**；**批次 13 辛 ② 起战报栏顶边已收到 52**（贴在两枚按钮之下），这张图用来核那一条；
  `abshow` → 把房主的 `_ab_active` 写一条畸变再 `_broadcast_state()`，让**顶部居中的畸变横幅**
  亮起来核对落位与不重叠（批次 12 D；如 `xx_abshow_table_plain.png`）；
  `techroll` → 播**开局科技定档演出**（屏幕层，`_show_tech_tier`），停在「等级横幅」那一刻
  （如 `xx_techroll_table_plain.png`）——核对等级配色 / 落位。**2026-10-09 起演出无骰面**
  （骰子绘制已删），随机与房主指定是同一种演出 ⇒ 文件名带不带 `fixed` 已无区别
  （分支名 `techroll` 保留，多处文档按它引用，别顺手改名）。
  注：`tilt` / `view2d` 只动 3D 视角；SubViewport 里的 2D 相机（`focus_grid` 那一套）不受影响。
  **两条都会顺带推动手牌淡出**（`view2d` 端手里牌本就看不见）：想拍"手里有牌"，文件名别带
  `tilt` / `view2d` —— 否则会拿到一张空手牌，并当成 bug 去查。
  常拼的几个：**干净全景 `xx_table_plain.png`**、**全景＋格详情卡 `xx_plain.png`**
  （单带 `plain` 拍出来的**仍是全景**，要近景请再加 `freecam`，见上）、
  **看房子 `xx_level_plain.png`**、**看手里握着牌 `xx_table_hand_plain.png`**、
  **看选目标态 `xx_target_plain.png`**（看**第一帧**）、**看展开的战报栏 `xx_logopen_table_plain.png`**、
  **看畸变横幅 `xx_abshow_table_plain.png`**、**看科技定档演出 `xx_techroll_table_plain.png`**。
- **一次连拍三帧**（间隔 0.6s），文件名依次 `x.png` / `x_1.png` / `x_2.png`，挑一张看即可。
- **`--` 分隔符不能漏** —— 这些开关都读 `OS.get_cmdline_user_args()`（`--` **之后**的那一段）：
  写成 `--path . --shot=x.png` 会被 Godot 自己吃掉（不报错、也不生效），必须是
  `--path . -- --shot=x.png`。**漏了的表现是"跑完了但什么都没拍"、日志里一个字都不提**，
  第一次出图最容易踩。

配套：`--shot-game=1 --shot=<路径>` 单人直达对局 —— 注意**不补机器人**，牌桌上只有你一家，
**要拍四家的名册条请改用 `--autotest=host --rounds=N --shot=...`**；
`--shot=<路径>`（**不带** `-game` / `-lobby`）= 拍**主菜单**本身，会往列表里注入两个假房间；
**页签落点由 `user://rejoin.cfg` 决定** —— 里面存着上次的加入地址时，主菜单会自动切到
「加入房间」并回填地址；要拍默认的「我是房主」页就先那份 cfg 挪走再跑，别当成 bug 查；
`--shot-lobby=<路径>` 直达大厅；
`--shot-round=N` 指定**第几轮**摆拍（默认 2）——
想看中后期才有的状态（满盘归属、各家装修）就把它调大，例如
`--autotest=host --rounds=20 --shot-round=15 --shot=xx_table_plain.png`
让机器人真的打到第 15 轮再拍。**注意自动对局里的机器人要很久才会主动装修**，
所以「房子图标」一律用文件名带 `level` 注入来看，别指望机器人。

> **联机回归必须放在同一条命令里跑**（`host ... &` → 等它就绪 → `client ...`），
> 不要分两次工具调用：代理沙箱会把不同调用隔离到各自的网络命名空间，两个进程
> 谁也看不见谁。表现是 client 报 `NET: connection_failed`、host 那边
> `AUTOTEST LOBBY humans=1` 直接补机器人开打——**看着像联机坏了，其实是调用方式的问题**。
> CI（`.github/workflows/ci.yml`）在同一个 `run:` 块里跑，不受影响 —— 它那段的等待是
> **`sleep 4`**（2026-10-04 核对 `ci.yml` 现状）。本机 `sleep 3` 与 `sleep 4` 都通
> （均 `humans=2` / 两侧 `OK round=3`）；**别拖到 6 秒**：房主会先带机器人开局，把迟到的
> client 当外人 `_kick_peer` 踢掉 ⇒ client `TIMEOUT`（看着像联机坏了，其实是等太久）。
> 本机实测：同一次调用内 host 报 `humans=2`、两侧 `OK round=3`，全程无 SCRIPT ERROR。
>
> **但也别把"十几套件的循环"与联机回归塞进同一条命令**（2026-10-04 实测）：先跑完 13 套件、
> ≈4 分钟后才起 host，client 仍报 `NET: connection_failed`、host 只有 `humans=1`；**拆成
> 独立一条命令（间隔 4 秒）即通**。⇒ 两条约定**不冲突**：上面那条讲的是 **host 与 client 这两个
> 进程**要待在一起，这条讲的是**别把它们跟在长循环后面** —— 套件与联机回归分开跑。
> 表现与上面那条一模一样，先按"调用方式"排查，别急着怀疑联机代码。
>
> **第三条（2026-10-05 实测，最容易误判成"联机坏了"的一条）：机器上有别的 Godot 在跑时就别跑联机回归。**
> 表现和上面两条**又**一模一样（client 只停在 `READY`、host 只有 `humans=2` 却到不了 `HOST OK`），
> 但根因是**争抢**：同机并发几个 Godot（子代理在跑测试/`--import`、另开 worktree 导入）时，
> 联机回归那一对进程会被拖到 200 s 都不出结果 —— 一旦机器空下来，**连跑 4 次全部 24~39 s 双端 OK**。
> **判据**：先看是不是有并发 Godot；**别拿"这次挂了"当回归依据**，先空机复跑两次再下结论。
> 另注：**`--rounds=N` 的单人 host 跑不满 N 轮不是 bug** —— 房主是"真人"，它每一轮的决定都要
> 等满 25 s 询问超时（`Engine.time_scale` 3 倍速下 ≈8.3 s），`--rounds=30` 得跑好几分钟；
> 想快速自检就配一个 client 一起跑，或把 `--rounds` 调小。
> 排查这类"卡住"时，**在 `_process` 里打一行心跳**（`paused` / `Engine.time_scale` / `running` /
> 各 `_awaiting_*`）比猜快得多 —— 2026-10-05 就是靠它一次定位到"树没暂停、时间倍率正常、
> 只是房主在等自己的决定超时"。

## 四、硬性约定

- **房主权威**：玩法逻辑只在房主（`scripts/game.gd` 的 host 侧）计算；客户端只发 `c_*` 请求 + 渲染，绝不直接改 `hp/htiles`。
- **RPC 命名**：`s_*` = 房主→全员（`authority`,`call_local`）；`c_*` = 客户端→房主（`any_peer`）。私密信息走 `rpc_id`。全表见 `doc/development/联机协议.md`。
- **状态同步**：任何「全员可见」的状态必须进 `_broadcast_state`（曾漏发 `shop_peer` 导致小卖部界面永不显示）。
- **哨兵值**：`GameData.NO_OWNER = -100`（地产无主）、`GameData.NO_PEER = -9999`（无玩家 /
  没命中），不要用 -1（机器人 peer 从 -1 开始编号 —— 批次 13 ④ 那次「调休」哨兵撞车就是踩了它）。
- **动画**：持续动画手写 `_process` 相位，Tween 仅用于一次性过渡。
- **素材优先开源**：新增美术 / 音效素材**一律优先选开源且许可兼容的**（CC0 / CC-BY / MIT / OFL 等），
  并在根目录 `LICENSE` 的**第三方素材登记**里逐个写明**来源与授权**（原 `assets/CREDITS.md` 已并入那里）；
  来源不明或许可不兼容的素材不要引入。**能用程序化手段画出来的就别加素材**（转盘、房子贴图、
  卡面、棋子与房子的等级纹理等都是这么做的）。
  **已批准的例外：`Quaternius Asset License (QAL) v1.0`**（2026-10-05 用户拍板；理由、证据与两条
  约束见 `doc/game-design/设计决策留痕.md` §十四）。它**不是标准开源许可证、不在上面的白名单里**，
  但实质兼容：商用 / 免署名 / 永久不可撤销，唯一额外限制是**不能把素材本身当素材包再分发**。
  登记时**必须写 QAL 及其版本、不能写 CC0**（Quaternius 官网三处说法互相矛盾，§7 定"以取得素材时
  生效的版本为准"；若下载包内自带 `LICENSE` 文本，以**包内那份**为准）。

- **Godot 生成文件已忽略**（`*.import` / `*.uid` / `shots/`）：新克隆后先用编辑器打开项目一次重建，否则可能报资源缺失。
- **整数除法**：GDScript 的 `total / n` 返回 int（向零截断），注意取整预期。
- **风格**：GDScript、**Tab 缩进**、中文注释；数据/工具类用 `class_name`；业务逻辑尽量静态类型（`var x := ...` / `: int`）。

## 五、改文档

- 机制/数值改动 → 同步 `doc/game-design/*`；协议/架构改动 → 同步 `doc/development/*`。
- **逐件道具的唯一来源是 `doc/game-design/道具图鉴.md`**；`道具系统.md` 只讲机制与进度，不重复逐件表。
- **动了任何一张玩法数据表**（`game_data.gd` 的 `EVENTS` / `item_data.gd` 的 `ITEMS` /
  `tech_data.gd` 的 `TECHS` / `aberration_data.gd` 的 `ABERRATIONS`）**或 `道具图鉴.md`**，
  都要重跑 `tools/gen_gallery.gd` 重新生成 `doc/game-design/图鉴.html` 并一并提交 ——
  CI 有一道「重新生成后 `git diff --exit-code`」的闸，过期即红（见 §三）。
  这页是给团队当参考查的，**悄悄过时比没有更糟**（有人会拿它当准）。
  生成器自己会打印「代码有文档没写 / 文档有代码没写 / 卡面文案不一致」三类缺项，别忽略它。
- 新想法（未排期）→ 登记到 `doc/development/未完成项-交接.md`（**「还剩什么」的唯一权威**，见 §七）；
  讨论过程、拍板理由与备选方案写进 `doc/game-design/设计决策留痕.md`。
  批次推进过程中的记录留在 `doc/development/开发台账.md`——它**只记「做到哪了」，不再收待办**。
- 实施计划 → `doc/development/plans/`；**该版本开发完并合入 `main` 后，连同计划文件一起删除**（这里不留档，历史看 `git log`）。
- 代码与文档里的互相引用：跨目录一律写仓库相对路径（`doc/game-design/...`、`doc/development/...`）；
  `doc/` 内部互引写相对 `doc/` 的路径（`game-design/...`、`development/...`）。
- **别写会烂的坐标**（2026-10-08 定；这一轮整理里踩到的两类腐烂）：
  - **不写行号 / 「在哪个文件」**。`game.gd:1940` 这种引用今天多半已经指错地方了（实测：
    文档里的 `_dev_force_use` 位置指向 `game.gd`，实际早在 `dev_tools.gd`）。要指就指
    **函数名 / 常量名 / 章节号**——它们重构后还能靠搜索找到，行号不能。
  - **引 `plans/*` 与 `.superpowers/*` 时必须写明它们的下场**：前者按上面那条约定
    **必然会被删**（所以「合并后删除」的计划，别在其它文档里当活引用用）；后者是 superpowers
    技能的本机临时产物（已 gitignore），**任何新克隆里都不存在**。不写说明就是一条死链。
    真要留档，写「原计划已随版本删除，历史见 `git log`」，或把结论搬进
    `doc/game-design/设计决策留痕.md` 再引用它。

## 六、提交 / 分支

- **改动完成后自动提交（commit），但不自动推送（push）**；合并（merge）仍需用户明确要求。
- **tag 只随用户明确要求的「推送 / 合并」新建或递增**：本地开发期间（含开新分支、收尾提交）
  不新建、不递增 tag；要打 tag / 叠版本号，等用户说推送或合并时一并处理。
- **动手改之前先开分支，别直接在 `main` 上改**（用户 2026-10-07 明确要求）：`main` 为集成分支。
  **分支命名规则（用户 2026-10-08 定）**：**修 bug 用 `fix/` 开头、加新功能用 `feature/` 开头，
  后面直接跟版本号**（如 `fix/0.14.1`、`feature/0.15.0`）。改完按用户要求合并回 `main`。
  只有「纯文档回填 / 极小的收尾」可例外，且仍应尽量走分支。
- 提交信息用中文、说清「做了什么 + 为什么」，一条提交尽量聚焦单一改动；风格参考 `git log --oneline` 的历史。
- 不提交 `shots/`、`_patch_*.py`、`*.import`、`*.uid`（已忽略）。

## 七、当前状态

**「还剩什么」的唯一权威是 `doc/development/未完成项-交接.md`**（可直接开工的清单，含优先级与验收口径）。
**本文件不复述待办**——复述过的必然落后：这里曾把「开局科技黄金 / 钻石池」当待办挂着，
而它早在 0.13.0 就实装了，`未完成项-交接.md` 也早已标 ✅。

- 进度总表（做到哪了）→ `doc/development/开发台账.md`
- 决策理由与当时的取舍 → `doc/game-design/设计决策留痕.md`
