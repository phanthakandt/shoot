extends Node2D
## Main scene: arena + wave spawner + HUD.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

@export var spawn_interval: float = 2.0

# Arena geometry constants.
const EDGE_MARGIN: float = 20.0     # keep spawns this far from the screen's left/right edges
const SPAWN_ABOVE_SCREEN: float = 40.0  # spawn this far above the top of the viewport

@onready var spawn_timer: Timer = $SpawnTimer
@onready var stats_label: Label = $HUD/StatsLabel


func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)


func _process(_delta: float) -> void:
	_update_hud()


func _on_spawn_timer_timeout() -> void:
	_spawn_enemy()


## Spawns an enemy at a random horizontal position above the screen; it then
## falls under gravity (see Enemy._physics_process) onto the ground or a platform.
func _spawn_enemy() -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
	var viewport_width: float = get_viewport_rect().size.x
	var spawn_x: float = randf_range(EDGE_MARGIN, viewport_width - EDGE_MARGIN)
	enemy.global_position = Vector2(spawn_x, -SPAWN_ABOVE_SCREEN)
	add_child(enemy)


func _update_hud() -> void:
	var player: Player = GameManager.player
	if not is_instance_valid(player):
		return
	stats_label.text = "HP: %d / %d\nXP: %d / %d" % [
		int(player.current_hp),
		int(player.max_hp),
		int(player.current_xp),
		int(GameManager.xp_to_next_level),
	]
