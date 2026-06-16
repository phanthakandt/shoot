extends Node2D
## Main scene: arena + wave spawner + HUD.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

@export var spawn_interval: float = 1.0

# Arena geometry constants.
const EDGE_MARGIN: float = 20.0     # keep spawns this far from the screen's left/right edges
const SPAWN_ABOVE_SCREEN: float = 40.0  # spawn this far above the top of the viewport

# Difficulty scaling constants.
const MIN_SPAWN_INTERVAL: float = 0.3   # fastest spawn rate cap
const MAX_ENEMIES: int = 20             # max simultaneous live enemies

const HP_BAR_WIDTH: float = 200.0
const XP_BAR_WIDTH: float = 200.0

@onready var spawn_timer: Timer = $SpawnTimer
@onready var hp_bar_fill: ColorRect = $HUD/HPBarFill
@onready var xp_bar_fill: ColorRect = $HUD/XPBarFill

var _elapsed_time: float = 0.0


func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)


func _process(delta: float) -> void:
	_elapsed_time += delta
	_update_hud()


func _difficulty() -> float:
	# Increases by 1 per 30 seconds; drives spawn speed and enemy stats.
	return _elapsed_time / 30.0


func _on_spawn_timer_timeout() -> void:
	_spawn_enemy()
	# Tighten the spawn interval after each wave, clamped to the minimum cap.
	spawn_timer.wait_time = maxf(MIN_SPAWN_INTERVAL, spawn_interval / (1.0 + _difficulty() * 0.25))


## Spawns an enemy at a random horizontal position above the screen; it then
## falls under gravity (see Enemy._physics_process) onto the ground or a platform.
func _spawn_enemy() -> void:
	if get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES:
		return

	var diff := _difficulty()
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
	enemy.max_hp = 30.0 * (1.0 + diff * 0.3)
	enemy.move_speed = 80.0 + diff * 8.0
	var viewport_width: float = get_viewport_rect().size.x
	var spawn_x: float = randf_range(EDGE_MARGIN, viewport_width - EDGE_MARGIN)
	enemy.global_position = Vector2(spawn_x, -SPAWN_ABOVE_SCREEN)
	add_child(enemy)


func _update_hud() -> void:
	var player: Player = GameManager.player
	if not is_instance_valid(player):
		return
	var hp_ratio := clampf(player.current_hp / player.max_hp, 0.0, 1.0)
	var xp_ratio := clampf(player.current_xp / GameManager.xp_to_next_level, 0.0, 1.0)
	hp_bar_fill.size.x = HP_BAR_WIDTH * hp_ratio
	hp_bar_fill.color = Color(1.0 - hp_ratio, hp_ratio, 0.0, 1.0)
	xp_bar_fill.size.x = XP_BAR_WIDTH * xp_ratio
