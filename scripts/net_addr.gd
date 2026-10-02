class_name NetAddr
## 纯函数网络地址工具（不依赖任何单例，可被 --script 单测直接加载）。

## 把输入解析为 [地址, 端口]。
## 支持：10.11.28.88 / 10.11.28.88:7800 / ::1 / 2001:db8::1 / [2001:db8::1]:7800 / hostname
static func parse_endpoint(text: String, default_port: int) -> Array:
	var s := text.strip_edges()
	if s.is_empty():
		return []
	var host := s
	var port := default_port
	if s.begins_with("["):
		var close := s.find("]")
		if close < 0:
			return []
		host = s.substr(1, close - 1)
		var rest := s.substr(close + 1)
		if rest.begins_with(":"):
			port = int(rest.substr(1))
	elif s.count(":") == 1:
		var parts := s.split(":")
		host = parts[0]
		port = int(parts[1])
	if host.is_empty() or port <= 0:
		return []
	return [host, port]

## 拼「主机:端口」展示串。IPv6 必须带方括号，否则 parse_endpoint 无法把端口
## 与地址本身区分开（`2001:db8::1:8000` 整体会被当成主机名）——见 fix/v0.0.2。
static func format_endpoint(host: String, port: int) -> String:
	if host.contains(":"):
		return "[%s]:%d" % [host, port]
	return "%s:%d" % [host, port]

## 解析房间发现广播的 INFO 报文（房主 → 客户端）。
## 格式：<proto>|INFO|<房名>|<人数>/<上限>|<状态>|<端口>
static func parse_room_info(text: String) -> Dictionary:
	var parts := text.split("|")
	if parts.size() != 6 or parts[1] != "INFO":
		return {}
	var port := int(parts[5])
	if port <= 0 or port > 65535:
		return {}
	return {"proto": String(parts[0]), "name": String(parts[2]),
		"count": String(parts[3]), "state": String(parts[4]), "port": port}

## 本机地址分类，便于把可用的直连地址展示给朋友。
static func split_addresses() -> Dictionary:
	var res := {"lan4": [], "pub4": [], "lan6": [], "pub6": []}
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s == "::1" or s.begins_with("169.254") \
				or s.begins_with("fe80:") or s == "0.0.0.0":
			continue
		if s.contains(":"):
			if s.begins_with("fd") or s.begins_with("fc"):
				res.lan6.append(s)
			else:
				res.pub6.append(s)
		else:
			if s.begins_with("10.") or s.begins_with("192.168.") or s.begins_with("172."):
				res.lan4.append(s)
			else:
				res.pub4.append(s)
	return res
