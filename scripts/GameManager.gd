extends Node
## Autoload singleton (see project.godot -> [autoload]).
## Holds the card database, tracks the player's level-up threshold,
## and drives the pause / card-selection flow.

# Set by Player._ready(). Lets enemies and the HUD reach the player easily.
var player: Player = null

# Set by LevelUpUI._ready(). Lets us push card choices to the UI.
var level_up_ui: CanvasLayer = null

# XP required to trigger the next level-up.
var xp_to_next_level: float = 100.0

# How much harder the next level-up gets after each card is picked.
const XP_SCALING: float = 1.5

# ---------------------------------------------------------------------------
# CARD DATABASE
# Each entry is a Dictionary: { id, name, description, effect }
# "effect" is a Callable that takes the player node and mutates its stats.
# ---------------------------------------------------------------------------
var card_database: Array[Dictionary] = []


func _ready() -> void:
	_build_card_database()


func _build_card_database() -> void:
	card_database = [
		{
			"id": "move_speed_up",
			"name": "Swift Boots",
			"description": "+20% Move Speed",
			"effect": _apply_move_speed,
		},
		{
			"id": "extra_bullet",
			"name": "Twin Shot",
			"description": "+1 Bullet per shot",
			"effect": _apply_extra_bullet,
		},
		{
			"id": "heavy_rounds",
			"name": "Heavy Rounds",
			"description": "+50% Bullet Size & Damage",
			"effect": _apply_bullet_size_and_damage,
		},
		{
			"id": "fire_rate_up",
			"name": "Quick Trigger",
			"description": "+25% Fire Rate",
			"effect": _apply_fire_rate,
		},
		{
			"id": "max_hp_up",
			"name": "Vitality",
			"description": "+25 Max HP (and heal)",
			"effect": _apply_max_hp,
		},
	]


# --- Card effects -----------------------------------------------------------
# Each effect receives the Player node and mutates its stats directly.

func _apply_move_speed(p: Player) -> void:
	p.move_speed *= 1.2


func _apply_extra_bullet(p: Player) -> void:
	p.bullet_count += 1


func _apply_bullet_size_and_damage(p: Player) -> void:
	p.damage *= 1.5
	p.bullet_size_mult *= 1.5


func _apply_fire_rate(p: Player) -> void:
	# fire_rate is the cooldown in seconds, so "faster" means a smaller value.
	p.fire_rate *= 0.75


func _apply_max_hp(p: Player) -> void:
	p.max_hp += 25.0
	p.current_hp += 25.0


# ---------------------------------------------------------------------------
# LEVEL-UP FLOW
# ---------------------------------------------------------------------------

## Called by the player whenever it gains XP.
func check_level_up() -> void:
	if player == null:
		return
	if player.current_xp >= xp_to_next_level:
		_trigger_level_up()


func _trigger_level_up() -> void:
	# Freeze gameplay. _physics_process/_process still run with delta == 0,
	# but UI input (button presses) is unaffected by time_scale.
	Engine.time_scale = 0.0

	var choices: Array[Dictionary] = _pick_random_cards(3)

	if level_up_ui != null:
		level_up_ui.show_cards(choices)
	else:
		# Fallback if no UI is present: print choices and auto-pick the first.
		print("=== LEVEL UP! Choose a card ===")
		for c in choices:
			print("- %s: %s" % [c["name"], c["description"]])
		select_card(choices[0])


func _pick_random_cards(count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = card_database.duplicate()
	pool.shuffle()
	var result: Array[Dictionary] = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result


## Called by LevelUpUI when the player clicks a card button.
func select_card(card: Dictionary) -> void:
	if player != null:
		var effect: Callable = card["effect"]
		effect.call(player)
		player.current_xp -= xp_to_next_level

	xp_to_next_level *= XP_SCALING

	if level_up_ui != null:
		level_up_ui.hide_cards()

	# Unpause.
	Engine.time_scale = 1.0
