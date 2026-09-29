extends SceneTree
## 加载所有脚本做静态检查：godot --headless --script tests/load_all.gd

func _initialize() -> void:
	var scripts := [
		"res://scripts/net.gd", "res://scripts/fx.gd", "res://scripts/net_addr.gd",
		"res://scripts/game_data.gd", "res://scripts/game.gd", "res://scripts/board_view.gd",
		"res://scripts/dice_view.gd", "res://scripts/main_menu.gd", "res://scripts/lobby.gd",
		"res://scripts/ui_kit.gd",
	]
	var fails := 0
	for s in scripts:
		var res := ResourceLoader.load(s, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null:
			printerr("LOAD FAIL - ", s)
			fails += 1
		elif not (res as GDScript).can_instantiate() and s.ends_with("net.gd") == false:
			# autoload 脚本在 --script 模式下引用单例可能限制实例化，能 load 过即可
			print("  loaded (no-instantiate) - ", s)
		else:
			print("  ok - ", s)
	if fails == 0:
		print("LOAD ALL: PASS")
		quit(0)
	else:
		print("LOAD ALL: %d FAILURES" % fails)
		quit(1)
