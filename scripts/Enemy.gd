extends CharacterBody2D
## Enemy: red 32x32 ColorRect.
## Walks toward the player's X position. Falls to the floor with gravity.
## Dies (and grants XP) when its HP reaches 0.

@export var max_hp: float = 30.0
@export var move_speed: float = 80.0
@export var xp_value: float = 20.0

const GRAVITY: float = 1200.0

var current_hp: float = max_hp


func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return

	# Gravity, so enemies spawned mid-air land on the arena floor.
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# Simple AI: walk toward the player's horizontal position.
	var player: Player = GameManager.player
	if is_instance_valid(player):
		var dir_x: float = sign(player.global_position.x - global_position.x)
		velocity.x = dir_x * move_speed
	else:
		velocity.x = 0.0

	move_and_slide()


## Called by Bullet on hit.
func take_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	var player: Player = GameManager.player
	if is_instance_valid(player):
		player.add_xp(xp_value)
	queue_free()
