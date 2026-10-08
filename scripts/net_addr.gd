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
	return classify_addresses(IP.get_local_addresses())

## 把一串地址（一般来自 `IP.get_local_addresses()`）分类成
## 局域网/公网 × IPv4/IPv6。抽成纯函数是为了能喂固定输入做单测
##（`IP.get_local_addresses()` 每台机器都不一样，没法断言）。
##
## 两条清洗规则（fix/0.14.1）：
## - **回环必须按展开式一起过滤**：Godot 在 Windows 上给的是 `0:0:0:0:0:0:0:1`
##   而不是 `::1`，只判 `== "::1"` 会把回环漏进「全球 IPv6」展示给用户。
## - **同一 /64 前缀只留一条**：一张网卡常同时挂 EUI-64 地址 + 若干 RFC4941 隐私
##   地址，前缀相同、都能连，并列展示只会让用户犯迷糊。
static func classify_addresses(raw: Array) -> Dictionary:
	var res := {"lan4": [], "pub4": [], "lan6": [], "pub6": []}
	var seen6 := {}
	for a in raw:
		var s := String(a)
		if _is_ignored(s):
			continue
		if s.contains(":"):
			var prefix := _prefix64(s)
			if seen6.has(prefix):
				continue
			seen6[prefix] = true
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

## 不参与对外直连的地址：IPv4 回环 / 链路本地 / 通配，IPv6 回环 / 链路本地。
static func _is_ignored(s: String) -> bool:
	if s.begins_with("127.") or s.begins_with("169.254") or s == "0.0.0.0":
		return true
	if s.begins_with("fe80"):
		return true
	return _is_loopback6(s)

## IPv6 回环：`::1` 或展开式 `0:0:0:0:0:0:0:1`（每段去前导 0 后前 7 段为空、末段为 1）。
static func _is_loopback6(s: String) -> bool:
	var n := s.to_lower()
	if n == "::1":
		return true
	var parts := n.split(":")
	if parts.size() != 8:
		return false
	for i in range(7):
		if String(parts[i]).lstrip("0") != "":
			return false
	return String(parts[7]).lstrip("0") == "1"

## 取 IPv6 的前 64 位（前 4 段，去前导 0）作为去重键。
static func _prefix64(s: String) -> String:
	var parts := _expand6(s.to_lower()).split(":")
	if parts.size() < 4:
		return s.to_lower()
	var out: Array[String] = []
	for i in 4:
		out.append(String(parts[i]).lstrip("0"))
	return ":".join(out)

## 把可能含 `::` 的 IPv6 展开成 8 段（不好补的坏串原样返回）。
static func _expand6(s: String) -> String:
	if not s.contains("::"):
		return s
	var halves := s.split("::")
	var head: Array = [] if String(halves[0]) == "" else String(halves[0]).split(":")
	var tail: Array = []
	if halves.size() > 1 and String(halves[1]) != "":
		tail = String(halves[1]).split(":")
	var fill := 8 - head.size() - tail.size()
	if fill < 0:
		return s
	var out: Array = head.duplicate()
	for i in fill:
		out.append("0")
	out.append_array(tail)
	return ":".join(out)
