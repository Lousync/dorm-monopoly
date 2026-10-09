extends SceneTree
## 加载所有脚本做静态检查：godot --headless --script tests/load_all.gd
## 自动扫描 `scripts/` 与 `tools/`（都是**扫目录**、不硬列清单——此前漏了 item_data.gd /
## item_card.gd，一个「加载检查」静默跳过最新代码比没有更糟）。
## `tools/` 是构建期工具、不进游戏，但同样是仓库里的 GDScript：图鉴生成器语法错了
## 也该在本地这一步就红，而不是等 CI 跑生成时才发现。
## 判解析失败用「方法表为空」：实测 ResourceLoader.load 在编译失败时仍返回非 null
## 资源（只判 null 会把语法错误报成 PASS），而 GDScript.reload() 对活着的 autoload
## 一律返回 22（net.gd/fx.gd 被误报）。编译失败的脚本方法表为 0，正常脚本都非空。

const DIRS := ["res://scripts", "res://tools"]

func _initialize() -> void:
	var scripts: Array[String] = []
	for d in DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			printerr("LOAD FAIL - 打不开 ", d)
			quit(1)
			return
		for f in dir.get_files():
			if f.ends_with(".gd"):
				scripts.append(d + "/" + f)
	scripts.sort()

	var fails := 0
	for s in scripts:
		var res := ResourceLoader.load(s, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null:
			printerr("LOAD FAIL - ", s)
			fails += 1
			continue
		var gd := res as GDScript
		if gd.get_script_method_list().is_empty():
			printerr("PARSE FAIL - ", s)
			fails += 1
		else:
			print("  ok - ", s)

	if fails == 0:
		print("LOAD ALL: PASS（%d 个脚本）" % scripts.size())
		quit(0)
	else:
		print("LOAD ALL: %d FAILURES" % fails)
		quit(1)
