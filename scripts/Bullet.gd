extends Area2D
class_name Bullet
## Bullet: small yellow 8x8 ColorRect.
## Travels in a straight horizontal line and frees itself on impact
## or after a short lifetime (so stray bullets don't pile up forever).

var direction: int = 1      # 1 = right, -1 = left (set by Player before adding to tree)
var speed: float = 700.0
var damage: float = 10.0
var size_mult: float = 1.0  # scales the bullet's visuals + collision shape

var _lifetime: float = 2.0


func _ready() -> void:
	# Uniformly scale the bullet (ColorRect + CollisionShape2D are children,
	# so they scale along with this node).
	scale = Vector2(size_mult, size_mult)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return

	position.x += direction * speed * delta

	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body is StaticBody2D:
		# Hit a wall/platform.
		queue_free()
