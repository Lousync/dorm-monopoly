extends SceneTree

func _initialize() -> void:
	print("=== API PROBE ===")
	# 1) ENet create_server / create_client 参数顺序
	for m in ClassDB.class_get_method_list("ENetMultiplayerPeer", true):
		if m.name in ["create_server", "create_client"]:
			var args := []
			for a in m.args:
				args.append("%s:%s" % [a.name, a.type])
			print("ENetMultiplayerPeer.%s(%s)" % [m.name, ", ".join(args)])
	# 2) 关键类存在性
	print("SystemFont exists: ", ClassDB.class_exists("SystemFont"))
	print("PacketPeerUDP.set_broadcast_enabled: ", ClassDB.class_has_method("PacketPeerUDP", "set_broadcast_enabled"))
	print("IP.get_local_addresses: ", ClassDB.class_has_method("IP", "get_local_addresses"))
	# 3) 本机地址（看看 IPv6 情况）
	print("Local addresses: ", IP.get_local_addresses())
	print("=== PROBE DONE ===")
	quit(0)
