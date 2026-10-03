# AGENTS.md — 项目级代理说明

> 面向在此仓库工作的 AI 编码代理（Claude Code / opencode 等）；**人类开发者也先读本文件**
> ——文档导航、工程约定、提交规范都在这里，本文件是这些约定的**单一来源**。
> `CLAUDE.md` 通过 `@AGENTS.md` 引入本文件，不复制内容。
> 更新：2026-10-03。

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
| 要手动验证某件道具效果 | `doc/development/道具试验场.md`（原型 `doc/game-design/道具试验场-原型.html`） |
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
| `开局设置.md` | 房主开局配置项（经济/节奏/胜利/道具/特殊）+ 预设方案 |
| `开局科技.md` | 开局三选一科技机制 + 图鉴 |
| `畸变.md` | 全场畸变机制 + 图鉴 + 候选草案 |
| `设计决策留痕.md` | 讨论过程、拍板理由、当时的备选方案与日期（**不是当前事实**） |

**原型文件**（同目录，`.html`/`.drawio`）：`布局原型-玩家区与选项菜单.html`、
`布局原型-四人围桌.drawio` 是**定稿存档（2026-10-01），不随实现更新**——原型记录的是
当时谈定的交互，**可能与现状不一致**（例如原型里的「☰ 选项」按钮后来已改名「⏸ 暂停」）。
要写代码请以 `game-design/*` 与现有实现为准，不要把原型当成活的规范逐条对照。
`道具试验场-原型.html`、`对局UI改版-原型.html`（牌垫阶段按钮 + 道具点选交互）、
`赌场改造-原型.html` 是可交互原型。

### 工程与协作（`doc/development/`）

| 文档 | 内容 |
|---|---|
| `架构总览.md` | 场景流、房主权威模型、RPC 约定、目录地图、表现层约定 |
| `联机协议.md` | s_*/c_* 全表、状态快照字段、等待状态机、超时/托管/断线 |
| `上手指南.md` | 环境、跑通、自动化开关、新增内容 checklist |
| `开发台账.md` | 系统状态总表、批次进度、跨文档待办（分工用） |
| `道具试验场.md` | 道具效果的独立沙盒（已实现）：入口、界面、状态注入 |
| `plans/` | 实施计划：**随版本开发，合并进 `main` 后连同文件一起删除**（不留档） |

### 仓库根（不在 `doc/` 里，但属于文档体系）

| 文件 | 内容 |
|---|---|
| `README.md` | 项目门面：玩法规则、界面说明、项目结构、测试、构建打包 |
| `AGENTS.md` | **本文件**：文档导航、工程约定、提交规范的单一来源 |
| `CHANGELOG.md` | 版本变更（Keep a Changelog 风格 + 语义化版本） |
| `LICENSE` | MIT 授权 + 第三方素材来源与授权（原 `assets/CREDITS.md` 已并入本节）；**分发时必须一并保留** |

## 三、常用命令（PowerShell）

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
& $G --headless --path . --script tests/pause_menu_test.gd # 暂停菜单回归（真实 GUI 输入链路）
& $G --headless --path . --script tests/rules_panel_test.gd # 规则说明面板回归
& $G --headless --path . --script tests/hud_test.gd      # HUD 回归（名册/底栏/客户端视角）
& $G --headless --path . --script tests/settings_test.gd    # 开局设置单测（操作限时挡位）
& $G --headless --path . --script tests/settings_ui_test.gd # 大厅游戏设置弹窗回归
& $G --headless --path . -- --autotest=host --rounds=5    # 联机回归（另开 client）
```

**自动化开关**（用法与更多细节见 `doc/development/上手指南.md`）：
`--autotest=host|client`、`--rounds=N`、`--max-rounds=N`、`--shot=`（截图）、
`--fps=N`（帧率实测：采 N 秒后打印平均 / 分位 / 最差帧并退出）、
`--card-gallery`（卡片图鉴）、`--menu-probe`（菜单探针）、`--dev`（开发者模式）、`--lab`（道具试验场）。

**摆拍截图（改界面时自检用）**：`--shot=<路径>` 存 PNG。四个非显然的坑：

- **不能加 `--headless`** —— 无头模式下 `get_viewport().get_texture()` 拿到的是**空帧**，
  截图必须开真实窗口跑。
- **文件名同时决定摆拍内容**（`dev_tools.take_shot` 里按 `path.contains(...)` 分支）：
  `plain` → 不弹赌场、不翻卡；`table` → 停在 3D 端全景（**不拉近、不弹格详情卡**；默认不写
  `table` 时会先 `focus_grid(27, 2.0)` 拉近到 27 号格并弹出格详情卡）；
  `rules` → 展开规则说明；`pause` → 打开暂停菜单；`card` → 跳过赌局；
  `deckout` → **抽卡「抽出」瞬间**：先把注视点挪到牌堆再抽，且在 **0.06s / 0.16s 各补一张**
  （常规三帧的第一帧落在翻面之后，拍不到"牌从实体摞上被抽起"）—— 要**同时带 `freecam` 与
  `card`**（如 `xx_freecam_deckout_card.png`：解锁镜头让推近生效 + 跳过赌局浮层），
  且这个分支**不转轮**（转轮会把镜头焦点抢到转盘）；
  `tilt` → 走**真接口** `table3d.snap_view(0.5)` 把视角推到轨道中点（俯角 50°→**69°**、
  距离一并插值），配 `table` 用出纯视角对比图（如 `xx_tilt_table_plain.png`）；
  `view2d` → 走 `table3d.snap_view(1.0)` 推到 **2D 端**（近正俯视、只看桌上地图）出图，
  用来拍 2D 那张（如 `xx_view2d_table_plain.png`）；
  `freecam` → **不锁自动镜头**（默认摆拍会锁住，避免对局推进拽走视角）；解锁后随后的
  `focus_grid` 拉近才生效，用来复现「玩家自己看到的近景」；
  `hand` → 给房主**发几张不同品质的道具**（只在房主侧注入状态，不动玩法代码），
  用来拍「手里握着牌」——开局背包是空的；
  `level` → 给前几块地**注入装修等级 1..4**（房主名下，用来核对房子图标与等级配色）；
  `target` → 进**选目标态**（给房主发一张「强拆令」、只给最后一家两块地）核对"可选中的立牌
  亮着、其余不亮"，**必须同时带 `plain`**（如 `xx_target_plain.png`）—— 不带的话后面那段
  赌局预览会盖上整屏、什么都看不出来。
  注：`tilt` / `view2d` 只动 3D 视角；SubViewport 里的 2D 相机（`focus_grid` 那一套）不受影响。
  **两条都会顺带推动手牌淡出**（`view2d` 端手里牌本就看不见）：想拍"手里有牌"，文件名别带
  `tilt` / `view2d` —— 否则会拿到一张空手牌，并当成 bug 去查。
  常拼的几个：**干净全景 `xx_table_plain.png`**、**近景＋格详情卡 `xx_plain.png`**、
  **看房子 `xx_level_plain.png`**、**看手里握着牌 `xx_table_hand_plain.png`**、
  **看选目标态 `xx_target_plain.png`**。
- **一次连拍三帧**（间隔 0.6s），文件名依次 `x.png` / `x_1.png` / `x_2.png`，挑一张看即可。
- **`--` 分隔符不能漏** —— 这些开关都读 `OS.get_cmdline_user_args()`（`--` **之后**的那一段）：
  写成 `--path . --shot=x.png` 会被 Godot 自己吃掉（不报错、也不生效），必须是
  `--path . -- --shot=x.png`。**漏了的表现是"跑完了但什么都没拍"、日志里一个字都不提**，
  第一次出图最容易踩。

配套：`--shot-game=1 --shot=<路径>` 单人直达对局 —— 注意**不补机器人**，牌桌上只有你一家，
**要拍四家立牌 / 四角身家条请改用 `--autotest=host --rounds=N --shot=...`**；
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
> CI（`.github/workflows/ci.yml`）在同一个 `run:` 块里跑，不受影响。
> 本机实测：同一次调用内 host 报 `humans=2`、两侧 `OK round=3`，全程无 SCRIPT ERROR。

## 四、硬性约定

- **房主权威**：玩法逻辑只在房主（`scripts/game.gd` 的 host 侧）计算；客户端只发 `c_*` 请求 + 渲染，绝不直接改 `hp/htiles`。
- **RPC 命名**：`s_*` = 房主→全员（`authority`,`call_local`）；`c_*` = 客户端→房主（`any_peer`）。私密信息走 `rpc_id`。全表见 `doc/development/联机协议.md`。
- **状态同步**：任何「全员可见」的状态必须进 `_broadcast_state`（曾漏发 `shop_peer` 导致小卖部界面永不显示）。
- **哨兵值**：`GameData.NO_OWNER = -100`，不要用 -1（机器人 peer 从 -1 开始编号）。
- **动画**：持续动画手写 `_process` 相位，Tween 仅用于一次性过渡。
- **Godot 生成文件已忽略**（`*.import` / `*.uid` / `shots/`）：新克隆后先用编辑器打开项目一次重建，否则可能报资源缺失。
- **整数除法**：GDScript 的 `total / n` 返回 int（向零截断），注意取整预期。
- **风格**：GDScript、**Tab 缩进**、中文注释；数据/工具类用 `class_name`；业务逻辑尽量静态类型（`var x := ...` / `: int`）。

## 五、改文档

- 机制/数值改动 → 同步 `doc/game-design/*`；协议/架构改动 → 同步 `doc/development/*`。
- **逐件道具的唯一来源是 `doc/game-design/道具图鉴.md`**；`道具系统.md` 只讲机制与进度，不重复逐件表。
- 新想法（未排期）→ 登记到 `doc/development/开发台账.md` §三「跨文档待办」；
  讨论过程、拍板理由与备选方案写进 `doc/game-design/设计决策留痕.md`。
- 实施计划 → `doc/development/plans/`；**该版本开发完并合入 `main` 后，连同计划文件一起删除**（这里不留档，历史看 `git log`）。
- 代码与文档里的互相引用：跨目录一律写仓库相对路径（`doc/game-design/...`、`doc/development/...`）；
  `doc/` 内部互引写相对 `doc/` 的路径（`game-design/...`、`development/...`）。

## 六、提交 / 分支

- **改动完成后自动提交（commit），但不自动推送（push）**；合并（merge）仍需用户明确要求。
- 分支：`main` 为集成分支，功能开发开个人分支（如 `xuzhiyan`）。
- 提交信息用中文、说清「做了什么 + 为什么」，一条提交尽量聚焦单一改动；风格参考 `git log --oneline` 的历史。
- 不提交 `shots/`、`_patch_*.py`、`*.import`、`*.uid`（已忽略）。

## 七、当前状态

见 `doc/development/开发台账.md`。主要待办：数值专场回填、开局科技/畸变/开局设置面板、发现三选一大卡。
