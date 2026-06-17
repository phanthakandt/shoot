extends Enemy
class_name FlyingEnemy
## Flying enemy. Ignores gravity and flies straight toward the player on both axes.
## Visually distinct: smaller purple rectangle (24x24) vs. the walker's red 32x32.

func _apply_gravity(_delta: float) -> void:
	pass  # no gravity — this enemy flies freely


func _update_ai(_delta: float) -> void:
	var player: Player = GameManager.player
	if is_instance_valid(player):
		var dir: Vector2 = (player.global_position - global_position).normalized()
		velocity = dir * move_speed
	else:
		velocity = Vector2.ZERO
