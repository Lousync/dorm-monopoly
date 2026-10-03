extends SceneTree
## 2.5D 桌面几何单测：平面求交 + 世界↔UV↔SubViewport 往返一致性
## godot --headless --path . --script tests/layout_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _run() -> void:
	print("== 射线与水平地面求交 ==")
	var hit = TableGeometry.hit_floor(Vector3(0, 5, 0), Vector3(0, -1, 0))
	_check(hit != null and (hit as Vector3).is_equal_approx(Vector3.ZERO), "垂直下射打中地面原点")
	_check(TableGeometry.hit_floor(Vector3(0, 5, 0), Vector3(0, 1, 0)) == null,
		"向上的射线打不到地面（返回 null）")

	print("== 世界 ↔ UV 往返 ==")
	var side := 8.0
	for uv in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75),
			Vector2(0.75, 0.75), Vector2(0.5, 0.5), Vector2(0.0, 1.0)]:
		var w := TableGeometry.uv_to_world(uv, side)
		var back := TableGeometry.world_to_uv(w, side)
		_check(back.distance_to(uv) < 0.0001, "UV %s → 世界 %s → UV %s" % [uv, w, back])
	_check(TableGeometry.uv_to_world(Vector2(0.25, 0.25), side).is_equal_approx(Vector3(-2, 0, -2)),
		"UV(0.25,0.25) 落在远左（z 负）")

	print("== UV ↔ SubViewport 像素往返 ==")
	var vp := Vector2i(2048, 2048)
	for uv in [Vector2(0.0, 0.0), Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(1.0, 1.0)]:
		var px := TableGeometry.uv_to_viewport(uv, vp)
		var back := TableGeometry.viewport_to_uv(px, vp)
		_check(back.distance_to(uv) < 0.0001, "UV %s → px %s → UV %s" % [uv, px, back])
	_check(TableGeometry.uv_to_viewport(Vector2(0.5, 0.5), vp) == Vector2(1024, 1024), "中心映射到像素中心")

	print("== TableView3D 容器结构 ==")
	# 用运行时 load() 取 TableView3D，而不是写类名：--script 入口脚本的静态依赖链在
	# autoload 全局标识符注册之前就编译，而 TableView3D 依赖的 BoardView 内部用了 Fx
	#（autoload）→ 静态引用会以「Identifier not found: Fx」整链编译失败。
	# 本仓库既有约定同此：需要 game/BoardView 的测试都在运行时 load（见 hud_test.gd）。
	var t3 = load("res://scripts/table_3d.gd").new()
	root.add_child(t3)
	_check(t3.board != null, "容器内有 BoardView")
	_check(t3.viewport != null and t3.board.get_parent() == t3.viewport,
		"BoardView 挂在容器自己的 SubViewport 下")
	_check(t3.camera != null and t3.camera.current, "3D 相机已就位并 current")
	_check(t3.camera.global_position.y > 0.0, "相机在桌面之上（实得 y=%.2f）" % t3.camera.global_position.y)
	# 俯角 = 相机位置矢量（相对注视点）与竖直方向的夹角余角。
	# 必须用 Vector3.UP：angle_to 是无符号夹角，位置矢量与 DOWN 的夹角 = 180° − 俯角
	# （50° 配置实测得 140°，`90 - 140` 是 −50°，永远过不了）；与 UP 的夹角才是 90° − 俯角。
	var tilt := 90.0 - rad_to_deg(t3.camera.global_position.angle_to(Vector3.UP))
	_check(absf(tilt - t3.CAM_TILT_DEG) < 8.0,
		"俯角接近配置值 %.0f°（实得 %.1f°）" % [t3.CAM_TILT_DEG, tilt])
	t3.queue_free()

	if fails == 0:
		print("LAYOUT TEST: ALL PASS")
		quit(0)
	else:
		print("LAYOUT TEST: %d FAILURES" % fails)
		quit(1)
