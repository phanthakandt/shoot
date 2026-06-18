extends Node2D
## Main scene: arena + wave spawner + HUD.

## Registry of all spawnable enemy types.
## Each entry: { scene: PackedScene, weight: float, min_difficulty: float }
## Add a new enemy type here — no other file needs to change.
const ENEMY_TYPES: Array[Dictionary] = [
	{
		"scene": preload("res://scenes/enemies/WalkerEnemy.tscn"),
		"weight": 3.0,
		"min_difficulty": 0.0,
	},
	{
		"scene": preload("res://scenes/enemies/FlyingEnemy.tscn"),
		"weight": 1.0,
		"min_difficulty": 1.0,
	},
]

@export var spawn_interval: float = 1.0

# Arena geometry constants.
const EDGE_MARGIN: float = 20.0          # keep spawns this far from screen left/right edges
const SPAWN_ABOVE_SCREEN: float = 40.0   # spawn enemies this far above the top of the viewport

# Enemy difficulty scaling.
const MIN_SPAWN_INTERVAL: float = 0.3
const MAX_ENEMIES: int = 20

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
	return _elapsed_time / 30.0


func _on_spawn_timer_timeout() -> void:
	_spawn_enemy()
	spawn_timer.wait_time = maxf(MIN_SPAWN_INTERVAL, spawn_interval / (1.0 + _difficulty() * 0.25))


## Picks a random eligible enemy type (weighted by difficulty) and spawns it
## just above the top of the fixed viewport.
func _spawn_enemy() -> void:
	if get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES:
		return

	var diff := _difficulty()

	var eligible: Array[Dictionary] = []
	for entry: Dictionary in ENEMY_TYPES:
		if diff >= entry.min_difficulty:
			eligible.append(entry)
	if eligible.is_empty():
		return

	var total_weight: float = 0.0
	for entry: Dictionary in eligible:
		total_weight += entry.weight
	var roll: float = randf() * total_weight
	var chosen: Dictionary = eligible[eligible.size() - 1]
	for entry: Dictionary in eligible:
		roll -= entry.weight
		if roll <= 0.0:
			chosen = entry
			break

	var enemy: Enemy = chosen.scene.instantiate()
	enemy.apply_difficulty(diff)
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
