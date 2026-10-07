class_name LabCase
extends RefCounted
## 道具试验场（Item Lab）的**可复现用例**：把「复现一件道具效果所需的状态」序列化成 JSON，
## 存进 `user://lab_cases/`（**不进仓库**），回放时清空重注入。
##
## **范围照 `doc/development/道具试验场.md` §七 注入表**：各家 钱 / 体力 / 位置 / 背包、
## 地块 owner / level / soil、货架与刷新数、全局回合；外加 `items_consumed`（它影响后续铺货）。
## **纯数据搬运、不碰玩法** —— 写/读都是字典，注入只走 `apply()`（先 `lab_reset()` 清场再写回）。
##
## 为什么独立成类而不是塞进 `item_lab.gd`：序列化 / 注入**不需要 UI 或联机**，独立后
## `tests/lab_case_test.gd` 能拿一个 `lab_mode` 的 `game` 直接跑，不必拉起整个试验场场景。

const DIR := "user://lab_cases"
const VERSION := 1

## 文件名消毒：只挡路径穿越与非法字符（允许中文），空名回落 `case`。
static func safe_name(name: String) -> String:
	var s := name.strip_edges()
	for bad in ["/", "\\", "..", ":", "*", "?", "\"", "<", ">", "|"]:
		s = s.replace(bad, "_")
	return "case" if s == "" else s

static func path_for(name: String) -> String:
	return "%s/%s.json" % [DIR, safe_name(name)]

## 抓一份可复现状态（JSON 安全：全是 int / bool / String / Array / Dictionary）。
static func snapshot(g) -> Dictionary:
	var players := []
	for p in g.hp:
		players.append({
			"money": int(p.get("money", 0)),
			"stamina": int(p.get("stamina", 0)),
			"pos": int(p.get("pos", 0)),
			"items": (p.get("items", []) as Array).duplicate(true),
		})
	var tiles := []
	for t in g.htiles:
		tiles.append({
			"owner": int(t.get("owner", GameData.NO_OWNER)),
			"level": int(t.get("level", 0)),
			"soil": bool(t.get("soil", false)),
		})
	var shops := {}
	for k in g.shops:
		shops[str(k)] = (g.shops[k].slots as Array).duplicate()
	return {
		"version": VERSION,
		"players": players,
		"tiles": tiles,
		"shops": shops,
		"refresh": int(g.refresh_count),
		"round": int(g.round_no),
		"items_consumed": (g.items_consumed as Dictionary).duplicate(),
	}

## 注入：**先 `lab_reset()` 清空**（免得上一次用例的残留混进来），再逐项写回。
static func apply(g, data: Dictionary) -> void:
	g.lab_reset()
	var ps: Array = data.get("players", [])
	for i in mini(ps.size(), g.hp.size()):
		var b: Dictionary = ps[i]
		g.hp[i].money = int(b.get("money", 0))
		g.hp[i].stamina = int(b.get("stamina", 0))
		g.hp[i].pos = int(b.get("pos", 0))
		var its: Array = []
		for it in b.get("items", []):
			its.append((it as Dictionary).duplicate(true))
		g.hp[i].items = its
	var ts: Array = data.get("tiles", [])
	for i in mini(ts.size(), g.htiles.size()):
		var bt: Dictionary = ts[i]
		g.htiles[i].owner = int(bt.get("owner", GameData.NO_OWNER))
		g.htiles[i].level = int(bt.get("level", 0))
		g.htiles[i].soil = bool(bt.get("soil", false))
	g.shops = {}
	var sh: Dictionary = data.get("shops", {})
	for k in sh:
		g.shops[int(k)] = {"slots": (sh[k] as Array).duplicate()}
	g.refresh_count = int(data.get("refresh", 0))
	g.round_no = int(data.get("round", 1))
	g.items_consumed = (data.get("items_consumed", {}) as Dictionary).duplicate()
	g._broadcast_state()

## 写用例；返回实际写入路径（失败给 ""）。
static func save(name: String, g) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_for(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(snapshot(g), "  "))
	f.close()
	return path

## 读用例；解析失败 / 文件不存在都给空字典。
static func load_data(name: String) -> Dictionary:
	var path := path_for(name)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

## 现有用例名（排序；目录不存在给空数组）。
static func list_cases() -> Array:
	var out := []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for fn in dir.get_files():
		if fn.ends_with(".json"):
			out.append(fn.get_basename())
	out.sort()
	return out
