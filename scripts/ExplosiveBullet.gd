extends Area2D
class_name ExplosiveBullet
## Heavy-attack projectile: larger bullet that explodes on impact.
## Deals area damage to every enemy within explosion_radius via a shape query.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 500.0
var explosion_damage: float = 80.0
var explosion_radius: float = 100.0

var _lifetime: float = 3.0
var _exploded: bool = false  # guard against double-detonation

const FLASH_DURATION: float = 0.15


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return

	position += direction * speed * delta

	_lifetime -= delta
	if _lifetime <= 0.0:
		_explode()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body is StaticBody2D:
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	# Query every enemy inside the explosion radius at the moment of impact.
	var space_state := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = explosion_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 4  # Enemy layer
	for result in space_state.intersect_shape(query, 64):
		var collider: Node2D = result["collider"]
		if collider.has_method("take_damage"):
			collider.take_damage(explosion_damage)

	_spawn_flash()
	queue_free()


func _spawn_flash() -> void:
	var flash_node := Node2D.new()
	flash_node.global_position = global_position
	get_tree().current_scene.add_child(flash_node)

	var rect := ColorRect.new()
	rect.offset_left = -explosion_radius
	rect.offset_top = -explosion_radius
	rect.offset_right = explosion_radius
	rect.offset_bottom = explosion_radius
	rect.color = Color(1.0, 0.55, 0.0, 0.75)
	flash_node.add_child(rect)

	var timer := Timer.new()
	timer.wait_time = FLASH_DURATION
	timer.one_shot = true
	timer.timeout.connect(flash_node.queue_free)
	flash_node.add_child(timer)
	timer.start()
