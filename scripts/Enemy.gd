extends CharacterBody2D
## Enemy: red 32x32 ColorRect.
## Walks toward the player's X position. Falls to the floor with gravity.
## If standing on a platform above the player, walks off the edge instead
## of stalling directly overhead. Dies (and grants XP) when its HP reaches 0.

@export var max_hp: float = 30.0
@export var move_speed: float = 80.0
@export var xp_value: float = 20.0

const GRAVITY: float = 1200.0
const HEALTH_BAR_WIDTH: float = 32.0
const ABOVE_PLAYER_Y_OFFSET: float = 16.0  # how much higher than the player counts as "on a platform above"

var current_hp: float = max_hp
var _fallback_direction: float = 1.0  # used when directly above/below the player

@onready var health_bar_fill: ColorRect = $HealthBarFill


func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")
	_fallback_direction = -1.0 if randf() < 0.5 else 1.0


func _physics_process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return

	# Gravity, so enemies spawned mid-air land on the arena floor.
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	var player: Player = GameManager.player
	if is_instance_valid(player):
		var dir_x: float
		# Smaller Y = higher up. If standing on a platform above the player,
		# ignore their X and keep walking the current direction to walk off
		# the edge instead of stalling on top of them.
		if is_on_floor() and global_position.y <= player.global_position.y - ABOVE_PLAYER_Y_OFFSET:
			dir_x = sign(velocity.x)
		else:
			# Normal AI: walk toward the player's horizontal position.
			dir_x = sign(player.global_position.x - global_position.x)

		# sign() returns 0 when stationary or directly above/below the player,
		# which would stall the enemy forever, so fall back to a fixed direction.
		if dir_x == 0.0:
			dir_x = _fallback_direction
		velocity.x = dir_x * move_speed
	else:
		velocity.x = 0.0

	move_and_slide()


## Called by Bullet on hit.
func take_damage(amount: float) -> void:
	current_hp -= amount
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * clampf(current_hp / max_hp, 0.0, 1.0)
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	var player: Player = GameManager.player
	if is_instance_valid(player):
		player.add_xp(xp_value)
	queue_free()
