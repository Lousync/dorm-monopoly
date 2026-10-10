class_name NetProbe
extends RefCounted
## 一次性「出网」探测（fix/0.14.1）：TCP 连到 `<地址>:<端口>`，能连上 = 该协议族出网可用。
## 非阻塞：`start()` 之后逐帧 `poll()`；默认 2.5s 没连上判失败。
## 纯逻辑、无依赖，可被 `--script` 单测（用本机 TCP 服务做回环验证）。

# 注意：**别用 `OK` 当枚举名** —— 它会在类内遮蔽 `Error.OK`，导致
# `connect_to_host(...) != OK` 的 `OK` 变成这里的枚举值（2），判定永远成立。
enum { ST_IDLE, ST_CONNECTING, ST_OK, ST_FAIL }

var state := ST_IDLE
var elapsed_ms := 0
var target := ""
var port := 0
var timeout_ms := 2500
var _peer: StreamPeerTCP
var _start := 0

func start(host: String, p: int) -> void:
	target = host
	port = p
	state = ST_CONNECTING
	elapsed_ms = 0
	_start = Time.get_ticks_msec()
	_peer = StreamPeerTCP.new()
	if _peer.connect_to_host(host, p) != Error.OK:
		state = ST_FAIL

func poll() -> int:
	if state != ST_CONNECTING:
		return state
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			state = ST_OK
			elapsed_ms = Time.get_ticks_msec() - _start
			_peer.disconnect_from_host()
		StreamPeerTCP.STATUS_ERROR:
			state = ST_FAIL
			elapsed_ms = Time.get_ticks_msec() - _start
		_:
			if Time.get_ticks_msec() - _start > timeout_ms:
				state = ST_FAIL
				elapsed_ms = Time.get_ticks_msec() - _start
				_peer.disconnect_from_host()
	return state

func status_text() -> String:
	match state:
		ST_OK:
			return "✓ 通（%d ms）" % elapsed_ms
		ST_FAIL:
			return "✕ 不通 / 超时"
		ST_CONNECTING:
			return "检测中…"
	return "未检测"
