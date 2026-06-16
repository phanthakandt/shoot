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
@export var recoil_force: float = 150.0   # impulse per shot, applied opposite to aim direction
@export var recoil_decay: float = 600.0   # units/sec rate at which recoil fades out
@export var heavy_damage: float = 80.0    # explosion damage of the heavy attack
@export var heavy_cooldown_max: float = 10.0  # seconds between heavy attacks

# --- Runtime state (also visible to the card system) -----------------------
var current_hp: float = max_hp
var current_xp: float = 0.0

# --- Roguelike modifiers, changed by level-up cards -------------------------
var bullet_count: int = 1          # bullets fired per shot ("Twin Shot")
var bullet_size_mult: float = 1.0  # scales bullet size + is applied to damage

# --- Movement constants ------------------------------------------------------
const GRAVITY: float = 1200.0
const JUMP_VELOCITY: float = -450.0
const RECOIL_UPWARD_CAP: float = 540.0        # max upward speed recoil can give per-frame
const RECOIL_HORIZONTAL_CAP: float = 540.0    # max horizontal speed recoil can accumulate
const RECOIL_COUNTER_DECAY_MULT: float = 3.0  # extra decay rate when holding against recoil
const MAX_RISE_HEIGHT: float = 130.0       # max px above last floor player can reach (normal jump ~84px)
const MAX_AIRBORNE_TIME: float = 2.0       # seconds before a forced fall kicks in
const HEAVY_BAR_WIDTH: float = 32.0     # matches the player body width

# --- Internal state -----------------------------------------------------------
var _fire_cooldown: float = 0.0
var _heavy_cooldown_timer: float = 0.0
var _jump_was_pressed: bool = false
var _recoil: Vector2 = Vector2.ZERO
var _last_floor_y: float = 0.0  # Y of the last surface the player stood on
var _airborne_timer: float = 0.0

const BULLET_SCENE: PackedScene = preload("res://scenes/Bullet.tscn")
const EXPLOSIVE_BULLET_SCENE: PackedScene = preload("res://scenes/ExplosiveBullet.tscn")

@onready var hurt_box: Area2D = $HurtBox
@onready var contact_damage_timer: Timer = $ContactDamageTimer
@onready var heavy_bar_fill: ColorRect = $HeavyBarFill


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
		_airborne_timer += delta
	else:
		velocity.y = 0.0
		_last_floor_y = global_position.y  # record height of current floor/platform
		_airborne_timer = 0.0

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

	# --- Recoil (decays each frame, then added to velocity before physics step) ---
	# Holding a direction that opposes _recoil.x drains it faster, guaranteeing
	# input can always fight back regardless of how fast recoil accumulates.
	var opposing_input: bool = direction != 0 and sign(float(direction)) * sign(_recoil.x) < 0.0
	var x_decay := recoil_decay * RECOIL_COUNTER_DECAY_MULT if opposing_input else recoil_decay
	_recoil.x = move_toward(_recoil.x, 0.0, x_decay * delta)
	_recoil.y = move_toward(_recoil.y, 0.0, recoil_decay * delta)
	_recoil.x = clampf(_recoil.x, -RECOIL_HORIZONTAL_CAP, RECOIL_HORIZONTAL_CAP)
	if _airborne_timer >= MAX_AIRBORNE_TIME:
		_recoil.y = maxf(_recoil.y, 0.0)  # discard upward recoil before it reaches velocity
	velocity += _recoil
	velocity.y = maxf(velocity.y, -RECOIL_UPWARD_CAP)

	# Hard height ceiling: once the player is MAX_RISE_HEIGHT above the last floor,
	# kill all upward momentum so gravity can pull them back down.
	if global_position.y <= _last_floor_y - MAX_RISE_HEIGHT and velocity.y < 0.0:
		velocity.y = 0.0
		_recoil.y = maxf(_recoil.y, 0.0)  # discard accumulated upward recoil

	# Forced fall after prolonged airtime: gravity wins, no recoil or input can sustain hover.
	if _airborne_timer >= MAX_AIRBORNE_TIME:
		velocity.y = maxf(velocity.y, 0.0)

	move_and_slide()

	# --- Shooting (360-degree aim, hold left mouse button to auto-fire) ---
	_fire_cooldown -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = fire_rate

	# --- Heavy attack (right mouse button, long cooldown) ---
	_heavy_cooldown_timer = maxf(_heavy_cooldown_timer - delta, 0.0)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _heavy_cooldown_timer <= 0.0:
		_shoot_heavy()
		_heavy_cooldown_timer = heavy_cooldown_max

	# --- Heavy attack progress bar (above player head) ---
	var fill_ratio := clampf(1.0 - _heavy_cooldown_timer / heavy_cooldown_max, 0.0, 1.0)
	heavy_bar_fill.size.x = HEAVY_BAR_WIDTH * fill_ratio
	heavy_bar_fill.color = Color(0.0, 1.0, 0.0, 1.0) if _heavy_cooldown_timer <= 0.0 \
			else Color(1.0, 0.55, 0.0, 1.0)


## Spawns one or more bullets traveling from the player towards the mouse cursor.
func _shoot() -> void:
	var aim_direction := (get_global_mouse_position() - global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	# Horizontal recoil always; vertical only when shooting downward (aim_direction.y > 0).
	_recoil.x += -aim_direction.x * recoil_force
	if aim_direction.y > 0.0:
		_recoil.y += -aim_direction.y * recoil_force

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


## Fires an explosive bullet and applies heavy recoil.
## On floor: 2× horizontal force only (ground absorbs vertical).
## In air: 4× force in both axes for massive propulsion.
func _shoot_heavy() -> void:
	var aim_direction := (get_global_mouse_position() - global_position).normalized()
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	var bullet: ExplosiveBullet = EXPLOSIVE_BULLET_SCENE.instantiate()
	bullet.global_position = global_position + aim_direction * 30.0
	bullet.direction = aim_direction
	bullet.explosion_damage = heavy_damage
	get_tree().current_scene.add_child(bullet)

	var force_mult := 2.0 if is_on_floor() else 4.0
	var heavy_force := recoil_force * force_mult
	_recoil.x += -aim_direction.x * heavy_force
	if aim_direction.y > 0.0 and not is_on_floor():
		_recoil.y += -aim_direction.y * heavy_force


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
