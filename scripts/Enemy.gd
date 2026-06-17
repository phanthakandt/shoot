extends CharacterBody2D
class_name Enemy
## Base class for all enemies.
## Owns health, death, XP grant, health-bar update, and the physics loop
## structure. Subclasses override the virtual hooks below to implement their
## specific movement, AI, and on-death behaviour.

## Maximum hit points. Set on the scene root or via apply_difficulty().
@export var max_hp: float = 30.0
## Movement speed in pixels/sec; used by subclass AI.
@export var move_speed: float = 80.0
## XP awarded to the player on death.
@export var xp_value: float = 20.0

const GRAVITY: float = 1200.0

var current_hp: float = max_hp
var _is_dead: bool = false
var _health_bar_max_width: float = 0.0

@onready var health_bar_fill: ColorRect = $HealthBarFill


func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")
	_health_bar_max_width = health_bar_fill.size.x
	_enemy_ready()


func _physics_process(delta: float) -> void:
	if Engine.time_scale == 0.0:
		return
	_apply_gravity(delta)
	_update_ai(delta)
	move_and_slide()


# ---------------------------------------------------------------------------
# Virtual hooks — override in subclasses as needed.
# ---------------------------------------------------------------------------

## Called from _ready() for per-instance setup (e.g. randomising direction).
func _enemy_ready() -> void:
	pass


## Override to implement custom gravity or none (e.g. flying enemies).
## Default: standard downward gravity, zeroed on floor contact.
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0


## Override to implement movement / attack AI. Called every physics frame.
func _update_ai(_delta: float) -> void:
	pass


## Called right before queue_free() in _die(). Override for on-death effects.
func _on_death() -> void:
	pass


# ---------------------------------------------------------------------------
# Public API (called by spawner, bullets, and player).
# ---------------------------------------------------------------------------

## Called by the spawner immediately after instantiation to apply wave scaling.
## Override to customise difficulty scaling per enemy type.
func apply_difficulty(difficulty: float) -> void:
	max_hp *= 1.0 + difficulty * 0.3
	move_speed += difficulty * 8.0


## Called by Bullet / ExplosiveBullet on hit (duck-typed, signature must not change).
func take_damage(amount: float) -> void:
	current_hp -= amount
	health_bar_fill.size.x = _health_bar_max_width * clampf(current_hp / max_hp, 0.0, 1.0)
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	var player: Player = GameManager.player
	if is_instance_valid(player):
		player.add_xp(xp_value)
	_on_death()
	queue_free()
