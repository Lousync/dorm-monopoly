# AGENTS.md — 项目级代理说明

> 面向在此仓库工作的 AI 编码代理（Claude Code / opencode 等）；人类开发者请先读 `docs/README.md`。
> 本文件是项目约定的**单一来源**；`CLAUDE.md` 通过 `@AGENTS.md` 引入本文件。
> 更新：2026-10-02。

## 一、项目

**《宿舍大富翁》**：Godot **4.6** / **GDScript** 的 2D 桌游。56 格外圈棋盘，1~4 人联机（**房主即权威服务器**），亦可纯单机（房主 + 机器人，同一套代码）。无存档、不支持中途加入/观战。

## 二、先读文档（不要凭空猜功能）

- `docs/README.md` —— 文档总索引（按角色导航）。
- `docs/dev/` —— `架构总览.md`（权威模型/目录地图）、`联机协议.md`（RPC/状态快照）、`上手指南.md`、`开发台账.md`（进度+待办）。
- `docs/gameplay/` —— `README.md`（术语表）、`回合与行动.md`、`棋盘与地产.md`、`事件卡.md`、`经济与胜负.md`、`小卖部.md`、`黑市.md`、`赌场-炸弹猫.md`、`道具系统.md`、`道具图鉴.md`、`开局科技.md`、`畸变.md`。

## 三、常用命令（PowerShell）

```powershell
$G = "D:\develp\Godot\Godot_v4.6.2-stable_win64_console.exe"
& $G --path .                                             # 运行（或双击 start.bat）
& $G --headless --path . --script tests/load_all.gd       # 脚本静态加载检查（改完先跑）
& $G --headless --path . --script tests/rules_test.gd     # 规则单测
& $G --headless --path . --script tests/item_test.gd      # 道具单测
& $G --headless --path . --script tests/blackshop_test.gd # 黑市单测
& $G --headless --path . --script tests/shop_test.gd      # 小卖部单测
& $G --headless --path . -- --autotest=host --rounds=5    # 联机回归（另开 client）
```

## 四、硬性约定

- **房主权威**：玩法逻辑只在房主（`scripts/game.gd` 的 host 侧）计算；客户端只发 `c_*` 请求 + 渲染，绝不直接改 `hp/htiles`。
- **RPC 命名**：`s_*` = 房主→全员（`authority`,`call_local`）；`c_*` = 客户端→房主（`any_peer`）。私密信息走 `rpc_id`。
- **状态同步**：任何「全员可见」的状态必须进 `_broadcast_state`（曾漏发 `shop_peer` 导致小卖部操作条永不显示）。
- **哨兵值**：`GameData.NO_OWNER = -100`，不要用 -1（机器人 peer 从 -1 开始编号）。
- **动画**：持续动画手写 `_process` 相位，Tween 仅用于一次性过渡。
- **Godot 生成文件已忽略**（`*.import` / `*.uid` / `shots/`）：新克隆后先用编辑器打开项目一次重建，否则可能报资源缺失。
- **风格**：GDScript、**Tab 缩进**、中文注释；数据/工具类用 `class_name`。

## 五、改文档

- 机制/数值改动 → 同步 `docs/gameplay/*`；协议/架构改动 → 同步 `docs/dev/*`。
- **逐件道具的唯一来源是 `docs/gameplay/道具图鉴.md`**；`道具系统.md` 只讲机制与进度。
- 新想法（未排期）→ `docs/想法备忘.md`。
- 本项目的实施计划放 `.claude/plans/`。

## 六、提交 / 分支

- **不主动 commit / push / 合并**，除非用户明确要求。
- 分支：`main` 为集成分支，功能开发开个人分支（如 `xuzhiyan`）。
- 提交信息用中文、聚焦单一改动；不提交 `shots/`、`_patch_*.py`、`*.import`、`*.uid`（已忽略）。

## 七、当前状态

见 `docs/dev/开发台账.md`。主要待办：破产未清道具回唯一池、数值专场回填、开局科技/畸变/开局设置面板、发现三选一大卡、赌场弹层迁桌面、对局布局返工。
