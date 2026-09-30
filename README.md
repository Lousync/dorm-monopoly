# 宿舍大富翁

宿舍主题的大富翁棋牌游戏，用 **Godot 4.6** 制作。
**56 格宿舍地图铺在木纹桌面上，四人各坐一边**（滚轮缩放 / 拖拽平移 / 镜头自动跟随 /
点座位转到 TA 视角），
支持 **同一局域网 4 人联机**（自动搜索房间）与 **IPv6 / IPv4 直连**（跨校园网也能玩）。
界面全部程序化绘制，另引用少量开源素材（棋子 / 图标 / 木纹），授权见 `assets/CREDITS.md`；
8-bit 音效同样为运行时程序合成。

![玩法：房主开局，室友加入，掷骰子买地收租，30 轮结算或活到最后](#)

## 怎么运行

1. 安装 [Godot 4.3 及以上版本](https://godotengine.org/download)（本项目用 4.6.2 开发）。
2. 双击仓库根目录的 `start.bat` 启动（会自动找 Godot；也可 `start.bat "Godot.exe路径"` 指定）；
   或者用 Godot 编辑器打开本目录的 `project.godot` 按 **F5** 运行；
   或者用命令行：`Godot.exe --path "本目录"`。
3. 想给室友发独立程序：用 Godot 编辑器「项目 → 导出」导出 Windows 可执行文件即可。

> 第一次联机时 Windows 防火墙可能弹窗，请选择「允许访问」（专用网络即可）。

## 怎么联机

### 同一宿舍 / 同一局域网（推荐）

1. 房主点「**创建房间**」。
2. 其他人在主菜单的「局域网房间」列表里就能看到房间，点「加入」；
   搜不到时（路由器开了 AP 隔离等）在「地址」框里填房主大厅里的
   **局域网 IPv4**（大厅里可一键复制），例如 `10.11.28.88`。
   搜索同时会发全网广播、各网段定向广播和本机回环，同机双开也能互相搜到。
3. 人齐（2~4 人）或补上机器人，全部点「准备」，房主点「开始游戏！」。
   房间列表会标注「已满 / 游戏中」，这类房间不可再加入。

### IPv6 / IPv4 直连（跨网络）

1. 房主在大厅里点「复制地址」，把 **全球 IPv6 地址**（形如 `2001:da8:…`，教育网基本都有）发给朋友。
2. 朋友在「地址」框直接粘贴，点「加入」。支持这些写法：
   - `2001:da8::1234`
   - `[2001:da8::1234]:7800`（自定义端口）
   - `10.11.28.88:7800`（IPv4 加端口）
   - 域名
3. 服务端是 **IPv4 + IPv6 双栈**：一个房间里可以同时有局域网玩家和 IPv6 直连玩家。

直连要求：双方都有公网 IPv6（测试：浏览器打开 test-ipv6.com 能通），
且防火墙放行了游戏端口（默认 **7777/TCP**）。

### 机器人

房主可以在大厅「＋机器人」补位到 4 人，掉线的玩家会自动被机器人接管
（包括他正弹着的购买/装修询问，立刻按机器人策略替他决定，不会全场干等）。
真人发呆 35 秒没掷骰，系统会代掷一步，避免整局卡住。
机器人策略很朴实：钱多就买房装修，穷就苟着。

## 玩法规则（宿舍魔改版）

- **56 格环形棋盘**（18×12 外圈、10 大产业组各 3 块），每人初始 **¥20,000**，
  每次踏上「起点」领工资 **¥4,500**。
- **棋盘中央的赌场风转盘决定步数（0~12）**：转到 **12 满值**奖励再动一次；
  **连续三次转到 10+** 会被「查寝」押进「宿委会」反省一回合；转到 **0** 原地待命一回合。
- 落在无主地产可购买；落在自己的地产可花钱**装修**（Lv1~Lv3，费用为地价一半）。
- 租金 = 基础租金 × (1 + 装修等级)；**集齐同色一组再 ×2**。路过别人的地自动扣款。
- 「机会 / 命运」格抽宿舍事件卡：奖学金、查寝、请客奶茶、过生日收红包、共享单车快进……
  仿实体桌游，两副牌堆就摆在棋盘中央，抽卡时镜头对准牌堆、卡片从堆中滑出展示再收回。
- **「宿舍赌场」格（2 个）**：踩到后全员各掏 ¥800 入局玩小游戏，赢家通吃奖池。
  内置小游戏「**炸弹猫**」：12 张牌堆（炸弹×3 / 拆除×2 / 小鱼×7）轮抽，
  摸到炸弹没【拆除】直接出局；每人一次「透视牌堆顶」，看完可选抽顶或抽底；
  最后幸存者（或牌堆耗尽后小鱼最多者）赢下全部奖金，破产者观战、机器人自动玩。
- 「校医院 / 缴电费」等 10 个格强制缴费；「勤工俭学 / 奖学金」等 12 个格直接进账；
  「空教室 / 卧谈会」免费休息。
- 付不起钱即破产，名下地产充公；**活到最后**，或 **30 轮后总资产最高**者获胜。

## 操作与表现

- **四人围桌**：整屏是一张木纹桌面，棋盘铺在中央，四家座位分坐下/左/上/右边，
  座位上摆着各自的头像、现金、体力槽和 **5 个道具牌位**；对手的信息与牌位按**他们的视角**
  摆放——上家的牌你看着是倒的、左右两家是横的，跟真围一张桌子一样。
- 视角：**点谁的座位就转到谁的视角**（TA 的区域转到屏幕下方变正），点自己座位或按
  **空格**回自己视角，「全桌」一键看全景；转到别人视角时对局镜头不会把你拽回来。
- 棋盘：**滚轮缩放**、**拖拽平移**（拖一下就解除跟随）、「跟随」按钮回到镜头跟随，
  轮到谁行动镜头自动跟到谁（仅在自己视角时），行动棋子带脉冲光环。
- 战报 / 聊天收进右上角折叠面板，点「战报」展开；底部行动条集中状态与「转动转盘」。
- 转盘：减速旋转 + 指针滴答声 + 落点格高亮，转到 12 满值有音效奖励。
- 金额变动：玩家面板数字滚动、涨绿跌红闪烁，棋盘上同步飘字。
- 事件/缴费/查寝：游戏内风格弹卡（不同颜色），查寝、破产伴随震屏与音效。
- 购买/装修询问：游戏内弹窗 + 倒计时条，超时自动放弃。
- 全部音效为运行时程序合成（`fx.gd`），无外部素材。

## 项目结构

```
project.godot          引擎配置（GL Compatibility 渲染，窗口 1280×800）
theme.tres             全局主题（SystemFont 中文字体：雅黑/苹方/思源黑）
start.bat              Windows 双击启动（自动查找 Godot）
export_presets.cfg     Windows 导出预设（模板指向 D:\develp\Godot\export_templates）
build/                 打包产物（DormMonopoly.exe 单文件 + zip 分发包）
scenes/                main_menu / lobby / game 三个场景（根节点，UI 代码构建）
scripts/
  net.gd               自动加载：ENet 联机、大厅数据、UDP 广播搜索房间
  net_addr.gd          纯函数地址工具（可单测）
  game_data.gd         56 格棋盘生成、事件卡、租金/路径/几何等纯规则（可单测）
  game.gd              对局场景：房主权威回合状态机 + 全员状态同步 + HUD
  board_view.gd        大棋盘渲染、缩放/平移/跟随镜头、棋子动画
  wheel_view.gd        棋盘中央 13 格转轮（0~12 点数来源）
  fx.gd                自动加载：程序合成音效、场景淡入淡出、震屏、飘字、彩带
  main_menu.gd         主菜单（昵称、创建/加入、房间搜索）
  lobby.gd             大厅（准备、机器人、直连地址一键复制、聊天）
  ui_kit.gd            控件样式小工具（程序化九宫格渐变纹理 / 氛围背景 / 素材加载）
assets/                开源素材（授权与来源见 assets/CREDITS.md）
  pieces/              Kenney 桌游棋子（CC0）：玩家棋子与头像
  icons/               Twemoji 主题图标（CC-BY 4.0）：格子水印图标
  textures/            ambientCG 木纹（CC0）：棋盘桌面
tests/
  rules_test.gd        规则单元测试：godot --headless --script tests/rules_test.gd
  net_probe.gd 等      ENet 双栈连通性探针
```

## 素材与授权

界面主体（按钮、卡片、背景、转盘、骰面）为运行时程序化绘制，无外部素材。
引用的开源素材均在 `assets/CREDITS.md` 中声明来源与授权：
**Kenney** 桌游棋子（CC0）、**Twemoji** 图标（CC-BY 4.0，需保留署名）、
**ambientCG** 木纹（CC0）。分发时请一并保留该文件。

## 打包（导出独立 exe）

前提：`D:\develp\Godot\export_templates\4.6.2.stable\` 里有对应版本的导出模板
（从 godotengine.org 下载 `Godot_v4.6.2-stable_export_templates.tpz`，把里面
`templates/` 的内容解压到该目录）。然后：

```bash
Godot_console.exe --headless --path . --export-release "Windows Desktop"
# 产物：build/DormMonopoly.exe（pck 已内嵌的单文件，约 70MB）
```

联机架构：房主即服务器（权威状态机），客户端只上报「掷骰 / 买卖决定 / 聊天」，
状态快照通过可靠 RPC 全量广播；踢人先送达原因再延迟断开；掉线玩家自动转机器人；
不支持中途加入与观战；房主退出即对局结束；无存档。

## 自动化测试

```bash
# 规则单测（56 格棋盘 / 租金公式 / 路径 / 地址解析 / 坐标闭合）
Godot_console.exe --headless --path . --script tests/rules_test.gd
# 脚本静态加载检查
Godot_console.exe --headless --path . --script tests/load_all.gd
# 双实例联机回归（房主+客户端自动打 3 轮，含机器人、购买决策、断线接管）
Godot_console.exe --headless --path . -- --autotest=host --rounds=3 &
Godot_console.exe --headless --path . -- --autotest=client --rounds=3
# 快速打完结算（2 轮后按身家结算，覆盖游戏结束排名界面）
Godot_console.exe --headless --path . -- --autotest=host --rounds=3 --max-rounds=2 &
Godot_console.exe --headless --path . -- --autotest=client --rounds=3 --max-rounds=2
# 无干扰布局截图（单人开局即拍；--shot= 也可配 autotest 在第 2 轮拍对局）
Godot_console.exe --path . -- --shot-game=x --shot=shots/layout.png
# 围桌摆拍：路径含 table 停在全景、含 plain 关闭摆拍道具；--shot-rot=1/2/3 转到对应座位视角
Godot_console.exe --path . -- --autotest=host --rounds=3 --shot=shots/table_4p_home_plain.png
Godot_console.exe --path . -- --autotest=host --rounds=3 --shot=shots/table_4p_rot1_plain.png --shot-rot=1
# IPv6 回环验证（验证双栈服务端接受 ::1）
Godot_console.exe --headless --path . --script tests/net_probe.gd -- --mode=host &
Godot_console.exe --headless --path . --script tests/net_probe.gd -- --mode=client6
```
