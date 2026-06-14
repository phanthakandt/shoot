extends CharacterBody2D
class_name Player
## Player character: blue 32x64 ColorRect.
## Controls: A/D = move, W or Space = jump, hold Left Mouse Button = fire.
## Aiming follows the mouse cursor in 360 degrees.

# --- Core stats (shown in the Inspector, tweak to taste) -------------------
@export var max_hp: float = 100.0
@export var move_speed: float = 250.0
@export var fire_rate: float = 0.3      # seconds between shots (lower = faster)
@export var damage: float = 10.0
@export var contact_damage: float = 10.0  # damage taken per tick while touching an enemy

# --- Runtime state (also visible to the card system) -----------------------
var current_hp: float = max_hp
var current_xp: float = 0.0

# --- Roguelike modifiers, changed by level-up cards -------------------------
var bullet_count: int = 1          # bullets fired per shot ("Twin Shot")
var bullet_size_mult: float = 1.0  # scales bullet size + is applied to damage

# --- Movement constants ------------------------------------------------------
const GRAVITY: float = 1200.0
const JUMP_VELOCITY: float = -450.0

# --- Internal state -----------------------------------------------------------
var _fire_cooldown: float = 0.0
var _jump_was_pressed: bool = false

const BULLET_SCENE: PackedScene = preload("res://scenes/Bullet.tscn")

@onready var hurt_box: Area2D = $HurtBox
@onready var contact_damage_timer: Timer = $ContactDamageTimer


func _ready() -> void:
	current_hp = max_hp
	GameManager.player = self
	contact_damage_timer.timeout.connect(_on_contact_damage_timer_timeout)


func _physics_process(delta: float) -> void:
	# Don't move/shoot while the level-up screen is open.
	if Engine.time_scale == 0.0:
		return

	# --- Gravity ---
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# --- Horizontal movement ---
	var direction := 0
	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1

	if direction != 0:
		velocity.x = direction * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)

	# --- Jump (W or Space, edge-triggered) ---
	var jump_pressed := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE)
	if jump_pressed and not _jump_was_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_was_pressed = jump_pressed

	move_and_slide()

	# --- Shooting (360-degree aim, hold left mouse button to auto-fire) ---
	_fire_cooldown -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = fire_rate


## Spawns one or more bullets traveling from the player towards the mouse cursor.
func _shoot() -> void:
	var aim_direction := (get_global_mouse_position() - global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	var perpendicular := Vector2(-aim_direction.y, aim_direction.x)
	var spacing := 12.0
	for i in range(bullet_count):
		var bullet: Bullet = BULLET_SCENE.instantiate()
		# Stack extra bullets side-by-side, perpendicular to the aim direction.
		var offset := (i - (bullet_count - 1) / 2.0) * spacing
		bullet.global_position = global_position + aim_direction * 24.0 + perpendicular * offset
		bullet.direction = aim_direction
		bullet.damage = damage
		bullet.size_mult = bullet_size_mult
		get_tree().current_scene.add_child(bullet)


## Called by enemies (via the contact damage timer below).
func take_damage(amount: float) -> void:
	current_hp = max(current_hp - amount, 0.0)
	if current_hp <= 0.0:
		_die()


## Called by Enemy when it dies.
func add_xp(amount: float) -> void:
	current_xp += amount
	GameManager.check_level_up()


func _die() -> void:
	print("Player died! Pausing game.")
	Engine.time_scale = 0.0


## Periodically checks the HurtBox for overlapping enemies and applies damage.
func _on_contact_damage_timer_timeout() -> void:
	for body in hurt_box.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			take_damage(contact_damage)
			break
