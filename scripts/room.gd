class_name GameRoom
extends Node3D
## 3D 房间（一期）：天花板 / 地板 / 四面墙 / 家具 / 四把椅子与名牌 / 吊灯可见几何 / 补光。
##
## **只摆位与长相，不碰玩法** —— 与 `table_props.gd` 同一条纪律。
## **一律不投影**：那盏吊灯是全场唯一投影源（见 `table_3d.LAMP_LIGHT_POS`），
## 房间多一个投影物件就多一张阴影图，性能与氛围两头不讨好。
##
## 总开关 `ROOM_ENABLED`：置 false 就整层不建，回到"只有桌子"的样子。
## 这是本期的保命开关 —— 房间出任何问题都可以先关掉它，不影响对局。

const ROOM_ENABLED := true

## 房间尺寸。以桌心为原点；桌面在 y = 0。
## 天花板必须高于吊灯的光（`LAMP_LIGHT_POS.y = 10.0`），否则灯吊到了屋顶外。
const ROOM_W := 22.0          # 房间宽（x）
const ROOM_D := 18.0          # 房间深（z）
const ROOM_CEIL_Y := 13.0     # 天花板高

## `lamp_light_pos` = `table_3d.LAMP_LIGHT_POS`（吊灯的光在世界的哪一点）。
## **由调用方传进来**，不让 `room.gd` 去 import `table_3d` 的常量 —— 房间不该反向依赖桌子。
static func build(parent: Node3D, lamp_light_pos: Vector3) -> GameRoom:
	if not ROOM_ENABLED:
		return null
	var r := GameRoom.new()
	r.name = "Room"
	parent.add_child(r)
	r._lamp_light_pos = lamp_light_pos
	r._build_shell()
	return r

var _lamp_light_pos := Vector3.ZERO

func _build_shell() -> void:
	# Task 3/4/5 在这里继续加家具 / 椅子 / 吊灯。
	pass
