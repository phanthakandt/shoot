extends Enemy
class_name WalkerEnemy
## Ground-chasing enemy. Walks toward the player's X position.
## If standing on a platform above the player, walks off the edge instead
## of stalling directly overhead. Dies and grants XP like all enemies.

const ABOVE_PLAYER_Y_OFFSET: float = 16.0

var _fallback_direction: float = 1.0


func _enemy_ready() -> void:
	_fallback_direction = -1.0 if randf() < 0.5 else 1.0


func _update_ai(_delta: float) -> void:
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
