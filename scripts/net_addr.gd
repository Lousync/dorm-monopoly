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
