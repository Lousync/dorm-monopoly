class_name TableGeometry
## 2.5D 桌面的纯几何（见 doc/development/plans/v0.5.0-布局2.5D.md §6.2）。
## 刻意不依赖相机与场景：相机只负责给出射线的 origin/dir，几何全在这里，于是可无头单测。

## 射线与水平地面（y = floor_y）求交；打不到返回 null。
static func hit_floor(origin: Vector3, dir: Vector3, floor_y: float = 0.0) -> Variant:
	return Plane(Vector3.UP, floor_y).intersects_ray(origin, dir)

## 桌面局部坐标 → UV(0~1)。PlaneMesh 躺在 XZ 平面、中心在原点，边长 side。
static func world_to_uv(local: Vector3, side: float) -> Vector2:
	return Vector2(local.x / side + 0.5, local.z / side + 0.5)

## UV → 桌面局部坐标（y = 0，与 world_to_uv 互逆）。
static func uv_to_world(uv: Vector2, side: float) -> Vector3:
	return Vector3((uv.x - 0.5) * side, 0.0, (uv.y - 0.5) * side)

static func uv_to_viewport(uv: Vector2, vp_size: Vector2i) -> Vector2:
	return uv * Vector2(vp_size)

static func viewport_to_uv(pos: Vector2, vp_size: Vector2i) -> Vector2:
	return pos / Vector2(vp_size)
