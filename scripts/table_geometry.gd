class_name TableGeometry
## 2.5D 桌面的纯几何（原计划文件 doc/development/plans/v0.5.0-布局2.5D.md 已按约定随版本删除，历史见 git log）。
## 刻意不依赖相机与场景：相机只负责给出射线的 origin/dir，几何全在这里，于是可无头单测。
##
## 桌面板是**矩形**（宽 × 进深），进深与「贴图窗口」同比例（见 TableView3D.TEX_WINDOW_PX）：
## 窗口宽:高 与 桌面宽:进深 不一致的话，贴图就会被拉伸。
## **宽度是常数（TABLE_W = 8），进深由窗口的宽高比派生**（`TABLE_D = TABLE_W × 窗口高/宽`）
## —— 窗口是画布上裁出来的那一块「桌垫」（批次 5 Task 2 把它从整张画布裁到桌垫；批次 10 收窄
## 桌垫留白后是 `Rect2(14, 313.72, 2020, 1420.55)`），不再是整张方画布，所以桌面**不再是正方形**
##（今天 TABLE_D ≈ 5.63）。
## 函数按通用矩形写：改窗口（或改桌面宽）时不必动这里。

## 射线与水平地面（y = floor_y）求交；打不到返回 null。
static func hit_floor(origin: Vector3, dir: Vector3, floor_y: float = 0.0) -> Variant:
	return Plane(Vector3.UP, floor_y).intersects_ray(origin, dir)

## 桌面局部坐标 → UV(0~1)。PlaneMesh 躺在 XZ 平面、中心在原点，宽 size.x / 进深 size.y。
static func world_to_uv(local: Vector3, size: Vector2) -> Vector2:
	return Vector2(local.x / size.x + 0.5, local.z / size.y + 0.5)

## UV → 桌面局部坐标（y = 0，与 world_to_uv 互逆）。
static func uv_to_world(uv: Vector2, size: Vector2) -> Vector3:
	return Vector3((uv.x - 0.5) * size.x, 0.0, (uv.y - 0.5) * size.y)

## UV → SubViewport 画布像素。window 是画布上贴到桌面的那一块矩形（px，画布坐标系）：
## 铺满整张画布就是 Rect2(0, 0, viewport.size)。
static func uv_to_viewport(uv: Vector2, window: Rect2) -> Vector2:
	return window.position + uv * window.size

static func viewport_to_uv(pos: Vector2, window: Rect2) -> Vector2:
	return (pos - window.position) / window.size
