extends Node

var mode := ""
var done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	multiplayer.peer_connected.connect(_on_pc)
	multiplayer.connected_to_server.connect(_on_conn)
	multiplayer.connection_failed.connect(_on_fail)
	multiplayer.server_disconnected.connect(_on_sd)
	if mode == "host":
		var p := ENetMultiplayerPeer.new()
		var err := p.create_server(7910)
		multiplayer.multiplayer_peer = p
		print("HOST listen err=", err)
	elif mode == "client4" or mode == "client6":
		var p := ENetMultiplayerPeer.new()
		var addr := "::1" if mode == "client6" else "127.0.0.1"
		var err := p.create_client(addr, 7910)
		multiplayer.multiplayer_peer = p
		print("CLIENT to ", addr, " err=", err)
	else:
		get_tree().quit(2)
		return
	get_tree().create_timer(8.0).timeout.connect(_on_timeout)

func _on_timeout() -> void:
	if not done:
		print("PROBE TIMEOUT FAIL")
		get_tree().quit(3)

func _on_pc(_id: int) -> void:
	print("peer_connected")

func _on_conn() -> void:
	print("connected_to_server")
	hello.rpc_id(1, "hi")

func _on_fail() -> void:
	print("PROBE CONNECT FAIL")
	get_tree().quit(4)

func _on_sd() -> void:
	print("server_disconnected")
	get_tree().quit(5)

@rpc("any_peer", "call_remote", "reliable")
func hello(msg: String) -> void:
	print("HOST GOT RPC '", msg, "' from peer ", multiplayer.get_remote_sender_id())
	pong.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func pong() -> void:
	print("CLIENT GOT PONG -> PROBE OK")
	done = true
	get_tree().quit(0)
