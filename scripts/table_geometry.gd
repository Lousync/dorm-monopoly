class_name TableGeometry
## 2.5D 桌面的纯几何（见 doc/development/plans/v0.5.0-布局2.5D.md §6.2）。
## 刻意不依赖相机与场景：相机只负责给出射线的 origin/dir，几何全在这里，于是可无头单测。
##
## 桌面板是**矩形**（宽 × 进深），进深与「贴图窗口」同比例（见 TableView3D.TEX_WINDOW_PX）：
## 窗口宽:高 与 桌面宽:进深 不一致的话，贴图就会被拉伸。
## 本批次窗口 = **整张方画布**（2048²），于是 TABLE_D == TABLE_W == 8.0，桌面是**正方形**
## （与 board_view.gd 的「桌面恒为正方形」一致）。函数按通用矩形写，
## 「棋盘铺满桌面」的比例目标推迟到批次 3（窗口若再裁，进深会跟着变）。

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
