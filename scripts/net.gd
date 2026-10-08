extends Node
## 自动加载单例：网络传输、房间大厅数据、局域网房间搜索。
##
## 联机方案：ENet 服务器绑定通配地址（IPv4 + IPv6 双栈），
## 客户端用 create_client(ip, port) 可填 IPv4 / IPv6 / 域名；
## 局域网内用 UDP 广播（全网广播 + 各网卡子网定向广播 + 本机回环）自动搜索房间，
## IPv6 无广播概念，走「直连地址」手动输入。

signal lobby_joined            # 客户端：收到第一份大厅数据
signal lobby_changed
signal join_failed(reason: String)
signal kicked(reason: String)
signal connection_lost(reason: String)
signal chat_received

const PORT := 7777
const DISCO_PORT := 7778
const MAX_PLAYERS := 4
const DISCO_REQ := "DMONO:DISCO?"
const DISCO_PROTO := "DMONO3"   # v3：INFO 增加房主端口字段（v2 客户端会忽略本房）
const HELLO_RETRIES := 20

var my_name := "玩家"
var is_host := false
var in_game := false           # 对局已开始（用于拒绝中途加入）
var room_name := "宿舍房间"
var host_port := 0             # 房主实际使用的端口
var last_error := ""           # 返回主菜单时展示给玩家看

# ---------------- 直连探测与超时（fix/0.14.1） ----------------
## 连 ENet 的同时并行向目标发发现协议探针（UDP DISCO_REQ）：有合法回复 = 对方在线，
## 局域网 / 公网都能秒判；迟迟无响应就自动断开，不再让玩家对着「正在连接…」无限转圈。
var _probe_socket: PacketPeerUDP
var _probe_host := ""
var _probe_enabled := false    # 探针 socket 是否建起（建失败则只靠硬超时兜底）
var _probe_seen := false       # 收到过合法 INFO 回复
var _connecting := false       # 正在尝试加入（join_game → 进大厅 / 失败）
var _net_connected := false    # ENet 握手已成功（connected_to_server 置位）
var _probe_last := 0           # 上次发探针的 tick（毫秒）
var _connect_start := 0        # 本次 join 开始的 tick（毫秒）

const PROBE_INTERVAL_MS := 400     # 探针发送间隔
const PROBE_TIMEOUT_MS := 3000     # 无任何回复 → 判定地址不可达
const CONNECT_TIMEOUT_MS := 12000  # 整体硬超时（连上了但大厅不来也走这条）

# ---------------- 延迟 / 信号质量（fix/0.14.1） ----------------
## 非房主每 1s `c_ping` 一发，房主 `s_pong` 原样回；客户端用**同一时钟**算 RTT。
## `latency_ms = -1` 表示未知 / 超时未更新（UI 显示「延迟 --」）。
signal latency_changed(ms: int)
var latency_ms := -1
var _ping_timer := 0.0
var _ping_last_ms := 0

const PING_INTERVAL := 1.0
const PING_STALE_MS := 3000        # 这么久没更新过 pong → 视为未知

# ---------------- 掉线重连（协议 §六） ----------------
## 重连凭证：开局时房主私发（s_assign_token）；掉线后随 c_hello 带回认领座位。
## 整局有效、可重复使用；认领成功 token 不变、座位表换绑新 peer。
## **2026-10-07 起持久化**：原先只在内存 ⇒ 退出程序 / 回主菜单再重开就丢，「退出游戏后重连」失效；
## 现写进 `user://rejoin.cfg`，启动时读回（房主进程重启 = 对局没了，token 会因认领失败被清）。
var rejoin_token := 0
var rejoined := false          # 本次连接已认领成功（s_reclaim 置位；停掉 hello 重试）
var last_join_addr := ""       # 上次加入的地址（主菜单回填，方便断线后一键重连）

const REJOIN_CFG := "user://rejoin.cfg"

func _persist_rejoin() -> void:
	var cfg := ConfigFile.new()
	cfg.load(REJOIN_CFG)   # 先读旧文件（保留其它段），再覆盖 rejoin 段
	cfg.set_value("rejoin", "token", rejoin_token)
	cfg.set_value("rejoin", "addr", last_join_addr)
	cfg.save(REJOIN_CFG)

func _load_rejoin() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(REJOIN_CFG) != OK:
		return
	rejoin_token = int(cfg.get_value("rejoin", "token", 0))
	last_join_addr = String(cfg.get_value("rejoin", "addr", ""))

## 房主侧：token -> 座位 peer（开局发牌时建；认领后换绑新 peer）
var _seat_tokens := {}
## 房主侧：已连上但还没完成 hello / 认领的连接（peer_connected 不再立即踢，防误杀重连握手）
var _pending_hello := {}

var game_settings: GameSettings = GameSettings.new()   # 房主配置，大厅写、对局读（见 开局设置.md §三之一）
var players: Array = []        # [{peer:int, name:String, color:int, bot:bool, ready:bool}]
var chat_history: Array = []   # ["名字：文本", ...]

var found_rooms := {}          # ip -> {name, count, state, time}

var _disco_host: PacketPeerUDP
var _disco_client: PacketPeerUDP
var _disco_clock := 99.0
var _disco_targets: PackedStringArray = []

func _ready() -> void:
	_load_rejoin()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	_poll_disco(delta)
	_poll_probe()
	_poll_ping(delta)

# ---------------- 创建 / 加入 / 离开 ----------------

func host_game(port: int) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	in_game = false
	# 开房 = 不再需要旧的重连凭证（那是别人局里的座位）
	rejoin_token = 0
	_persist_rejoin()
	host_port = port
	players = []
	chat_history = []
	last_error = ""
	room_name = "%s 的房间" % my_name
	_add_player(1, my_name, false, true)
	_start_disco_host()
	lobby_changed.emit()
	return OK

func join_game(address: String, port: int) -> Error:
	_reset_peer()
	rejoined = false   # 本次连接是否认领成功，由 s_reclaim 置位
	if not address.is_empty():
		last_join_addr = address
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "地址无法解析：" + address
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	_start_probe(address)
	return OK

## 用户主动取消「正在连接」：立刻断开并回到可操作状态（fix/0.14.1）。
func cancel_join() -> void:
	if not _connecting:
		return
	_fail_join("已取消连接")

func leave(keep_seat := false) -> void:
	_reset_peer()
	players = []
	in_game = false
	# 主动退出 = 放弃座位，凭证作废；`keep_seat=true`（游戏内「返回主菜单」）= 软离开，保留凭证可重连。
	if not keep_seat:
		rejoin_token = 0
		last_join_addr = ""
	_persist_rejoin()

func _reset_peer() -> void:
	_connecting = false
	_net_connected = false
	_stop_probe()
	latency_ms = -1
	stop_disco()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	# 残留清理：players 不清空会让 s_lobby 的「首次进房」判定
	#（had := players.size() > 0）永久失效——被踢或连接失败后再加入任何房间，
	# lobby_joined 都不再触发，界面永久卡在「正在连接…」，_hello_retry 也会
	# 因 players 非空提前返回而不报错。只能重启程序（见 fix/v0.0.2）。
	players = []
	chat_history = []

# ---------------- 大厅（房主权威） ----------------

func _add_player(peer: int, pname: String, bot: bool, ready_now := false) -> void:
	var used := {}
	for p in players:
		used[int(p.color)] = true
	var slot := 0
	for i in MAX_PLAYERS:
		if not used.has(i):
			slot = i
			break
	players.append({"peer": peer, "name": pname, "color": slot, "bot": bot, "ready": ready_now or bot})

func toggle_ready() -> void:
	if is_host:
		for p in players:
			if int(p.peer) == 1:
				p.ready = not p.ready
		broadcast_lobby()
	else:
		c_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func c_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for p in players:
		if int(p.peer) == sender:
			p.ready = not p.ready
	broadcast_lobby()

func host_add_bot() -> void:
	if not is_host or players.size() >= MAX_PLAYERS:
		return
	_add_player(_free_bot_id(), "机器人%s" % char(65 + _bot_count()), true)
	broadcast_lobby()

func host_remove_bot() -> void:
	if not is_host:
		return
	for i in range(players.size() - 1, -1, -1):
		if bool(players[i].bot):
			players.remove_at(i)
			break
	broadcast_lobby()

func _bot_count() -> int:
	var n := 0
	for p in players:
		if bool(p.bot):
			n += 1
	return n

func _free_bot_id() -> int:
	var id := -1
	while true:
		var clash := false
		for p in players:
			if int(p.peer) == id:
				clash = true
				break
		if not clash:
			return id
		id -= 1
	return -1

func can_start() -> bool:
	if not is_host or players.size() < 2:
		return false
	for p in players:
		if not bool(p.bot) and not bool(p.ready):
			return false
	return true

func broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	s_lobby.rpc(room_name, players)

@rpc("authority", "call_local", "reliable")
func s_lobby(rname: String, plist: Array) -> void:
	_connecting = false
	_net_connected = false
	_stop_probe()
	room_name = rname
	var had := players.size() > 0
	players = plist
	lobby_changed.emit()
	if not is_host and not had and plist.size() > 0:
		lobby_joined.emit()

func start_game() -> void:
	if not can_start():
		return
	in_game = true
	# 重连凭证（协议 §六）：开局给每位真人客户端私发一枚 token；掉线后凭它认领座位。
	# 房主自己（peer 1）不发——房主掉线 = 服务器没了，无重连可言。
	_seat_tokens.clear()
	for p in players:
		if not bool(p.bot) and int(p.peer) != 1:
			var t := randi()
			_seat_tokens[int(p.peer)] = t
			s_assign_token.rpc_id(int(p.peer), t)
	s_start.rpc()

@rpc("authority", "call_remote", "reliable")
func s_assign_token(token: int) -> void:
	rejoin_token = token
	_persist_rejoin()   # 持久化：退出程序 / 回主菜单再重开也能凭它重连
	print("NET: rejoin token assigned")

## 客户端：认领成功。直进对局场景——状态快照是全量的，对局内各界面都由快照驱动。
@rpc("authority", "call_remote", "reliable")
func s_reclaim() -> void:
	rejoined = true
	_connecting = false
	_net_connected = false
	_stop_probe()
	print("AUTOTEST RECLAIM client ok")
	Fx.go_to("res://scenes/game.tscn")

## 自动化用：模拟「网络波动」断开（客户端主动掐断连接，本端表现 = server_disconnected）。
## **不清 rejoin_token**——它正是重连认领要带的凭证。真机上的断线走 server_disconnected，
## 本函数只让联机回归不用真拔网线（协议 §六）。
func simulate_drop() -> void:
	print("NET: simulate drop (autotest)")
	_reset_peer()
	players = []
	in_game = false
	connection_lost.emit("与房主的连接已断开")

@rpc("authority", "call_local", "reliable")
func s_start() -> void:
	Fx.go_to("res://scenes/game.tscn")

# ---------------- 聊天 ----------------

func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 120)
	if text.is_empty():
		return
	if multiplayer.is_server():
		_add_chat_line("%s：%s" % [my_name, text])
	else:
		c_chat.rpc_id(1, text)

@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	text = String(text).strip_edges().substr(0, 120)
	if text.is_empty():
		return
	_add_chat_line("%s：%s" % [_name_of(sender), text])

func _add_chat_line(line: String) -> void:
	s_chat.rpc(line)

@rpc("authority", "call_local", "reliable")
func s_chat(line: String) -> void:
	chat_history.append(line)
	if chat_history.size() > 60:
		chat_history.pop_front()
	chat_received.emit()

func _name_of(peer: int) -> String:
	for p in players:
		if int(p.peer) == peer:
			return p.name
	return "玩家"

# ---------------- 连接事件 ----------------

func _on_peer_connected(id: int) -> void:
	print("NET: peer_connected id=", id, " is_server=", multiplayer.is_server())
	if not multiplayer.is_server():
		return
	# 不再立即踢（对局中连接可能是掉线玩家的重连握手，先给 1.5 秒完成 hello / 认领）；
	# 到点还没完成才按陌生人清走（协议 §六.4）。
	_pending_hello[id] = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if multiplayer.is_server() and _pending_hello.has(id) \
				and multiplayer.get_peers().has(id):
			_pending_hello.erase(id)
			_kick_peer(id, "对局已开始，无法中途加入"))

## 先把踢人原因可靠送达，稍等一拍再断开连接（避免对端来不及收到就掉线）
func _kick_peer(id: int, reason: String) -> void:
	s_kick.rpc_id(id, reason)
	await get_tree().create_timer(0.35).timeout
	# `ENetMultiplayerPeer` 在 4.x **没有** `get_peer_address(id)`（那是 3.x 的写法）。
	# 原来那句有两重坏：① 抛 `SCRIPT ERROR: Nonexistent function`；② 表达式求值为 null ⇒
	# `not "".is_empty()` = false ⇒ **`disconnect_peer` 永远不执行** ⇒ 踢人静默失效
	# （只发了个 `s_kick` 通知，对端照样留在房里）。改用 `multiplayer.get_peers()` 判在不在：
	# 仍连着才断（对端也可能已经自己走了）。实测复现与修后对照见提交说明。
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer and multiplayer.get_peers().has(id):
		mp.disconnect_peer(id)

func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	if multiplayer.is_server() and not in_game:
		for i in players.size():
			if int(players[i].peer) == id:
				players.remove_at(i)
				break
		broadcast_lobby()

func _on_connected_to_server() -> void:
	print("NET: connected_to_server, sending hello")
	_net_connected = true
	_hello_retry()

## 进房握手重试：ENet 连接建立瞬间高层握手可能未完成，
## 首个 RPC 有小概率被丢弃，这里带去重地重发直到收到大厅数据；
## 一直收不到则明确报错，不再让玩家干等。
func _hello_retry() -> void:
	for i in HELLO_RETRIES:
		if not (multiplayer.multiplayer_peer is ENetMultiplayerPeer):
			return  # 已被踢 / 已断开，静默退出
		if rejoined:
			return  # 认领成功，不用再重试 hello
		c_hello.rpc_id(1, my_name, rejoin_token)
		await get_tree().create_timer(0.5).timeout
		if not players.is_empty() or rejoined:
			return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_fail_join("已连上房间但始终无响应，请让房主重新创建房间")

## 昵称清洗：剔除 `|`（会破坏发现报文的字段分隔、让整个房间搜不到）、
## 换行/制表等控制字符（会伪造聊天与战报行），限长 12，空则回落「玩家」。
static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in String(raw).strip_edges():
		if ch == "|" or ch.unicode_at(0) < 32:
			continue
		out += ch
	out = out.substr(0, 12)
	return out if not out.is_empty() else "玩家"

## 收到 hello 时的判定：返回 "" 收下，否则返回踢人理由。
## 顺序很关键：必须先判「已在房间里」。反过来的话，满员房间里一个已入座玩家
## 重发的 hello 会被当成新人踢掉；_hello_retry 每 0.5 秒重发一次，
## 只要首轮 s_lobby 稍慢（房主卡顿/弱网）就必然触发（见 fix/v0.0.2）。
func hello_verdict(sender: int) -> String:
	for p in players:
		if int(p.peer) == sender:
			return ""          # 重发的 hello，已在房间里
	if in_game:
		return "对局已开始，无法中途加入"
	if players.size() >= MAX_PLAYERS:
		return "房间已满（最多 4 人）"
	return ""

@rpc("any_peer", "call_remote", "reliable")
func c_hello(pname: String, token: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# 对局中：只认「凭证命中座位」的重连，其余照旧拒绝（协议 §六.3）
	if in_game and not players.any(func(p) -> bool: return int(p.peer) == sender):
		var old := _token_seat(int(token))
		if old != GameData.NO_PEER:
			var scene := get_tree().current_scene
			if scene != null and scene.has_method("reclaim_seat") \
					and scene.reclaim_seat(old, sender):
				_seat_tokens.erase(old)
				_seat_tokens[sender] = int(token)   # token 不变，座位换绑新 peer（可再掉再认领）
				for p in players:
					if int(p.peer) == old:
						p.peer = sender   # 大厅行跟着换 key（聊天名等仍用它）
						break
				_pending_hello.erase(sender)
				print("NET: seat reclaimed old_peer=", old, " new_peer=", sender)
				s_reclaim.rpc_id(sender)
				return
		_kick_peer(sender, "对局已开始，无法中途加入")
		return
	var verdict := hello_verdict(sender)
	if verdict != "":
		_kick_peer(sender, verdict)
		return
	_pending_hello.erase(sender)
	var clean := sanitize_name(String(pname))
	print("NET: host accepted hello from peer ", sender, " name=", clean)
	_add_player(sender, clean, false)
	_add_chat_line("%s 加入了房间" % clean)
	broadcast_lobby()

## 按 token 反查座位 peer；没有命中返回 NO_PEER
func _token_seat(token: int) -> int:
	if token == 0:
		return GameData.NO_PEER
	for old in _seat_tokens:
		if int(_seat_tokens[old]) == token:
			return int(old)
	return GameData.NO_PEER

func _on_connection_failed() -> void:
	print("NET: connection_failed")
	_fail_join("连接失败：请检查地址、端口和防火墙设置")

func _on_server_disconnected() -> void:
	print("NET: server_disconnected")
	_reset_peer()
	players = []
	in_game = false
	connection_lost.emit("与房主的连接已断开")

@rpc("authority", "call_remote", "reliable")
func s_kick(reason: String) -> void:
	print("NET: kicked: ", reason)
	_reset_peer()
	# 被踢 = 座位没了 / 认领被拒（如房主重开了新局）⇒ 清掉持久化凭证，别再拿它去重连
	rejoin_token = 0
	_persist_rejoin()
	kicked.emit(reason)

# ---------------- 局域网房间搜索（UDP 广播） ----------------

func start_disco_client() -> void:
	stop_disco_client()
	_disco_client = PacketPeerUDP.new()
	if _disco_client.bind(0) != OK:
		_disco_client = null
		return
	_disco_client.set_broadcast_enabled(true)
	_disco_clock = 99.0
	# 全网广播 + 各私网网段的定向广播 + 本机回环（同机双开也能搜到）
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	var addrs := split_addresses()
	for ip in addrs.lan4:
		var parts := String(ip).split(".")
		if parts.size() == 4:
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	_disco_targets = targets

## 房间列表轮询的兜底重启：_reset_peer（加入失败/被踢）会 stop_disco 把它停掉，
## 而 start_disco_client 只在主菜单 _ready 调一次，于是失败一次后房间列表永久空白。
func ensure_disco_client() -> void:
	if _disco_client != null:
		return
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		return  # 正处联机会话中（房主或已加入），不另起搜索
	start_disco_client()

func stop_disco_client() -> void:
	if _disco_client != null:
		_disco_client.close()
	_disco_client = null
	found_rooms = {}

func _start_disco_host() -> void:
	stop_disco_host()
	_disco_host = PacketPeerUDP.new()
	if _disco_host.bind(DISCO_PORT) != OK:
		_disco_host = null  # 端口被占（如本机另一个实例），不影响正常对局

func stop_disco_host() -> void:
	if _disco_host != null:
		_disco_host.close()
	_disco_host = null

func stop_disco() -> void:
	stop_disco_client()
	stop_disco_host()

func _disco_state() -> String:
	if in_game:
		return "playing"
	if players.size() >= MAX_PLAYERS:
		return "full"
	return "lobby"

func _poll_disco(delta: float) -> void:
	if _disco_host != null and multiplayer.is_server():
		while _disco_host.get_available_packet_count() > 0:
			var pkt := _disco_host.get_packet()
			var ip := _disco_host.get_packet_ip()
			var port := _disco_host.get_packet_port()
			if pkt.get_string_from_utf8() == DISCO_REQ:
				var my_port := host_port if host_port > 0 else PORT
				var info := "%s|INFO|%s|%d/%d|%s|%d" % [DISCO_PROTO, room_name,
					players.size(), MAX_PLAYERS, _disco_state(), my_port]
				_disco_host.set_dest_address(ip, port)
				_disco_host.put_packet(info.to_utf8_buffer())
	if _disco_client != null:
		_disco_clock += delta
		if _disco_clock >= 1.0:
			_disco_clock = 0.0
			for t in _disco_targets:
				_disco_client.set_dest_address(t, DISCO_PORT)
				_disco_client.put_packet(DISCO_REQ.to_utf8_buffer())
		while _disco_client.get_available_packet_count() > 0:
			var pkt2 := _disco_client.get_packet()
			var ip2 := _disco_client.get_packet_ip()
			var ri := NetAddr.parse_room_info(pkt2.get_string_from_utf8())
			if not ri.is_empty() and String(ri.proto) == DISCO_PROTO:
				found_rooms[ip2] = {
					"name": ri.name, "count": ri.count, "state": ri.state,
					"port": int(ri.port), "time": Time.get_ticks_msec(),
				}
		# 清理过期房间
		var now := Time.get_ticks_msec()
		for ip3 in found_rooms.keys():
			if now - int(found_rooms[ip3].time) > 6000:
				found_rooms.erase(ip3)

# ---------------- 直连探测 / 超时（fix/0.14.1） ----------------

## 开始一次加入：建探针 socket 并起计时。地址为空（回退）时也能工作。
func _start_probe(host: String) -> void:
	_stop_probe()
	_probe_host = host
	_probe_enabled = false
	_probe_seen = false
	_probe_last = 0
	_connect_start = Time.get_ticks_msec()
	_connecting = true
	_net_connected = false
	_probe_socket = PacketPeerUDP.new()
	if _probe_socket.bind(0) == OK:
		_probe_enabled = true
	else:
		_probe_socket = null

func _stop_probe() -> void:
	if _probe_socket != null:
		_probe_socket.close()
	_probe_socket = null

## 每帧驱动探针：发 DISCO_REQ、收 INFO；超时/无响应就自动断开。
## **用真实墙钟**（Time.get_ticks_msec）而非 delta 累加 —— 自动化 3 倍速 / 卡帧都不影响判定。
func _poll_probe() -> void:
	if not _connecting:
		return
	var now := Time.get_ticks_msec()
	if _probe_socket != null:
		while _probe_socket.get_available_packet_count() > 0:
			var info := NetAddr.parse_room_info(_probe_socket.get_packet().get_string_from_utf8())
			if not info.is_empty() and String(info.proto) == DISCO_PROTO:
				_probe_seen = true
	if _net_connected:
		_stop_probe()   # 握手成功，探针使命完成；后续交给 hello 重试自身超时
		if now - _connect_start > CONNECT_TIMEOUT_MS:
			_fail_join("已连上房间但始终无响应，请让房主重新创建房间")
		return
	if _probe_enabled and _probe_socket != null and now - _probe_last >= PROBE_INTERVAL_MS:
		_probe_last = now
		_probe_socket.set_dest_address(_probe_host, DISCO_PORT)
		_probe_socket.put_packet(DISCO_REQ.to_utf8_buffer())
	if _probe_enabled and not _probe_seen and now - _connect_start > PROBE_TIMEOUT_MS:
		_fail_join("地址 %s 无响应：房主不在、端口不对，或被防火墙拦截" % _probe_host)
		return
	if now - _connect_start > CONNECT_TIMEOUT_MS:
		_fail_join("连接超时：请检查地址、端口和防火墙设置")

## 统一失败出口：清探针 + 断连 + 通知 UI（幂等，重复调用只生效一次）。
func _fail_join(reason: String) -> void:
	if not _connecting:
		return
	_connecting = false
	_net_connected = false
	_stop_probe()
	_reset_peer()
	players = []
	join_failed.emit(reason)

# ---------------- 延迟 / 信号质量（fix/0.14.1） ----------------

## 非房主：每 PING_INTERVAL 发一枚 `c_ping`（带本机时间戳）；房主回 `s_pong` 原样带回，
## 客户端用同一时钟算 RTT（无需对时）。pong 超时未更新 → `latency_ms = -1`。
func _poll_ping(delta: float) -> void:
	if is_host:
		return
	var mp := multiplayer.multiplayer_peer
	if not (mp is ENetMultiplayerPeer):
		return
	if mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_INTERVAL
		c_ping.rpc_id(1, Time.get_ticks_msec())
	if latency_ms >= 0 and Time.get_ticks_msec() - _ping_last_ms > PING_STALE_MS:
		latency_ms = -1
		latency_changed.emit(latency_ms)

@rpc("any_peer", "call_remote", "unreliable")
func c_ping(t: int) -> void:
	if not multiplayer.is_server():
		return
	s_pong.rpc_id(multiplayer.get_remote_sender_id(), t)

@rpc("authority", "call_remote", "unreliable")
func s_pong(t: int) -> void:
	var rtt := maxi(Time.get_ticks_msec() - int(t), 0)
	# 轻平滑（0.5 权重），避免单帧抖动让数字乱跳
	latency_ms = rtt if latency_ms < 0 else int(round(float(latency_ms) * 0.5 + float(rtt) * 0.5))
	_ping_last_ms = Time.get_ticks_msec()
	latency_changed.emit(latency_ms)

# ---------------- 地址工具 ----------------
# 实现在 NetAddr（纯函数、可单测），这里保留同名入口方便旧调用点。

static func parse_endpoint(text: String, default_port: int) -> Array:
	return NetAddr.parse_endpoint(text, default_port)

static func split_addresses() -> Dictionary:
	return NetAddr.split_addresses()
