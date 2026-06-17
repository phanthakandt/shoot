extends StaticBody2D
class_name Platform
## A stationary platform the player and enemies can land on.
## Width is set by the spawner immediately after instantiate(); _ready()
## resizes both the ColorRect and CollisionShape2D to match, allocating a
## fresh RectangleShape2D so the shared scene sub-resource is never mutated.

## Width in px. Set by the spawner before add_child().
@export var width: float = 270.0

const HEIGHT: float = 20.0

@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var half_w := width / 2.0
	color_rect.offset_left = -half_w
	color_rect.offset_right = half_w
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, HEIGHT)
	collision_shape.shape = shape
