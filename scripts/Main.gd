extends Node2D
## Main scene: arena + wave spawner + platform generator + camera + HUD.

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

const PLATFORM_SCENE: PackedScene = preload("res://scenes/Platform.tscn")

@export var spawn_interval: float = 1.0

# Arena geometry.
const EDGE_MARGIN: float = 20.0          # keep spawns this far from screen left/right edges
const SPAWN_ABOVE_SCREEN: float = 40.0   # spawn enemies this far above the camera top edge

# Enemy difficulty scaling.
const MIN_SPAWN_INTERVAL: float = 0.3
const MAX_ENEMIES: int = 20

# Platform generator.
## Vertical gap between consecutive platform centers.
## 60–84 px is reachable with a base jump (450²/2/1200 ≈ 84 px); 85–110 px needs recoil assist.
const MIN_PLATFORM_GAP: float = 100.0
const MAX_PLATFORM_GAP: float = 150.0
const MIN_PLATFORM_WIDTH: float = 700.0
const MAX_PLATFORM_WIDTH: float = 940.0
## Max horizontal distance between consecutive platform centers.
## Rough reach in a 0.75 s jump arc ≈ move_speed × 0.75 = 187 px.
const MAX_HORIZONTAL_JUMP_DELTA: float = 150.0
## Generate new platforms until this many px above the camera's top edge.
const GENERATE_AHEAD_MARGIN: float = 400.0
## Free platforms and enemies when they drift this far below the camera's bottom edge.
const CLEANUP_MARGIN_BELOW: float = 300.0

# Camera ratchet.
## Distance above the player that the camera center sits.
## At 200 px: player appears at screen y = 360 + 200 = 560 (78% from top), showing
## 560 px of level ahead (above) and 160 px behind (below).
const VERTICAL_LEAD: float = 200.0

# Fall death (camera-relative; checked in Main, not Player).
const FALL_DEATH_MARGIN: float = 300.0

const HP_BAR_WIDTH: float = 200.0
const XP_BAR_WIDTH: float = 200.0

@onready var spawn_timer: Timer = $SpawnTimer
@onready var camera: Camera2D = $Camera2D
@onready var hp_bar_fill: ColorRect = $HUD/HPBarFill
@onready var xp_bar_fill: ColorRect = $HUD/XPBarFill

var _elapsed_time: float = 0.0
## Y coordinate of the camera center in world space. Ratchet: only ever decreases.
var _camera_y: float = 0.0
## World Y of the topmost platform spawned so far (lower number = higher up).
var _highest_platform_y: float = 0.0
## X of the most recently spawned platform, for horizontal continuity.
var _last_platform_x: float = 640.0


func _ready() -> void:
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	var player: Player = GameManager.player
	# Start the ratchet camera so the player appears at 78% screen height.
	_camera_y = player.global_position.y - VERTICAL_LEAD
	camera.global_position = Vector2(640.0, _camera_y)

	# First platform center goes directly under the player's feet.
	# player_center_y + player_half_height (32) + platform_half_height (10) = +42.
	_highest_platform_y = player.global_position.y + 42.0

	_prefill_platforms()


func _process(delta: float) -> void:
	_elapsed_time += delta
	_update_camera()
	_generate_platforms()
	_cleanup_nodes()
	_check_fall_death()
	_update_hud()


func _difficulty() -> float:
	return _elapsed_time / 30.0


func _update_camera() -> void:
	var player: Player = GameManager.player
	if not is_instance_valid(player):
		return
	# Ratchet: camera only scrolls up (Y decreases), never back down.
	var target_y := player.global_position.y - VERTICAL_LEAD
	_camera_y = minf(_camera_y, target_y)
	camera.global_position = Vector2(640.0, _camera_y)


func _on_spawn_timer_timeout() -> void:
	_spawn_enemy()
	spawn_timer.wait_time = maxf(MIN_SPAWN_INTERVAL, spawn_interval / (1.0 + _difficulty() * 0.25))


## Picks a random eligible enemy type (weighted by difficulty) and spawns it
## just above the camera's current top edge.
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
	var camera_top := _camera_y - get_viewport_rect().size.y / 2.0
	enemy.global_position = Vector2(spawn_x, camera_top - SPAWN_ABOVE_SCREEN)
	add_child(enemy)


## Fills the initial view with platforms from under the player's feet upward.
## The very first platform is forced to x=640 for a guaranteed safe landing.
func _prefill_platforms() -> void:
	var camera_top := _camera_y - get_viewport_rect().size.y / 2.0
	_spawn_platform_at(_highest_platform_y, 640.0)  # safe-start platform under player
	while _highest_platform_y > camera_top - GENERATE_AHEAD_MARGIN:
		_spawn_platform_at(_highest_platform_y - randf_range(MIN_PLATFORM_GAP, MAX_PLATFORM_GAP))


## Lazily generates new platforms whenever the camera scrolls close enough to
## the topmost generated platform. Called every _process frame.
func _generate_platforms() -> void:
	var camera_top := _camera_y - get_viewport_rect().size.y / 2.0
	while _highest_platform_y > camera_top - GENERATE_AHEAD_MARGIN:
		_spawn_platform_at(_highest_platform_y - randf_range(MIN_PLATFORM_GAP, MAX_PLATFORM_GAP))


## Spawns one static Platform at spawn_y. forced_x overrides random horizontal
## placement when ≥ 0 (used for the safe-start platform).
func _spawn_platform_at(spawn_y: float, forced_x: float = -1.0) -> void:
	var platform := PLATFORM_SCENE.instantiate()
	platform.width = randf_range(MIN_PLATFORM_WIDTH, MAX_PLATFORM_WIDTH)
	var half_w = platform.width / 2.0
	var viewport_width := get_viewport_rect().size.x
	var new_x: float
	if forced_x >= 0.0:
		new_x = forced_x
	else:
		new_x = clampf(
			_last_platform_x + randf_range(-MAX_HORIZONTAL_JUMP_DELTA, MAX_HORIZONTAL_JUMP_DELTA),
			EDGE_MARGIN + half_w,
			viewport_width - EDGE_MARGIN - half_w
		)
	_last_platform_x = new_x
	_highest_platform_y = spawn_y
	platform.global_position = Vector2(new_x, spawn_y)
	add_child(platform)
	platform.add_to_group("platforms")


## Frees platforms and enemies that have drifted far below the camera bottom.
## In a climbing game both accumulate downward as the player ascends.
func _cleanup_nodes() -> void:
	var camera_bottom := _camera_y + get_viewport_rect().size.y / 2.0
	var cull_y := camera_bottom + CLEANUP_MARGIN_BELOW
	for node in get_tree().get_nodes_in_group("platforms"):
		if node.global_position.y > cull_y:
			node.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.global_position.y > cull_y:
			node.queue_free()


## Camera-relative fall-death: if the player drops FALL_DEATH_MARGIN px below the
## camera's current bottom edge they die. Checked here (not Player.gd) because
## Main has direct access to _camera_y.
func _check_fall_death() -> void:
	var player: Player = GameManager.player
	if not is_instance_valid(player):
		return
	var camera_bottom := _camera_y + get_viewport_rect().size.y / 2.0
	if player.global_position.y > camera_bottom + FALL_DEATH_MARGIN:
		player._die()


func _update_hud() -> void:
	var player: Player = GameManager.player
	if not is_instance_valid(player):
		return
	var hp_ratio := clampf(player.current_hp / player.max_hp, 0.0, 1.0)
	var xp_ratio := clampf(player.current_xp / GameManager.xp_to_next_level, 0.0, 1.0)
	hp_bar_fill.size.x = HP_BAR_WIDTH * hp_ratio
	hp_bar_fill.color = Color(1.0 - hp_ratio, hp_ratio, 0.0, 1.0)
	xp_bar_fill.size.x = XP_BAR_WIDTH * xp_ratio
