# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A minimal 2D action-platformer roguelike prototype built in Godot 4.6 (GL Compatibility renderer, Windows/D3D12). All visuals are placeholder `ColorRect` shapes with `CollisionShape2D` physics — no sprite assets.

## Running the project

This is a Godot project, not an npm/CLI project — there is no build step, linter, or test suite.

- Open `project.godot` in the Godot 4.6 editor and press F5 (Play). The main scene is `res://scenes/Main.tscn` (set via `run/main_scene` in `project.godot`).
- Headless sanity check (if a `godot`/`godot4` binary is available): `godot4 --headless --path . --quit` loads the project and prints any script/scene parse errors without opening a window.

## Architecture

### Scene <-> script pairing
Every gameplay scene under `scenes/` is a thin `.tscn` wrapper around a same-named script in `scripts/` (e.g. `scenes/Player.tscn` + `scripts/Player.gd`). `Player.gd`, `Bullet.gd`, and `ExplosiveBullet.gd` declare `class_name` (`Player`, `Bullet`, `ExplosiveBullet`) so other scripts can type-hint against them without preloading.

### Player controls & shooting (`scripts/Player.gd`)
- Movement: `A`/`D` (`Input.is_physical_key_pressed`) for left/right; `W` or `Space` to jump, edge-triggered via `_jump_was_pressed` and gated on `is_on_floor()`.
- Aiming is 360-degree and follows the mouse: `_shoot()` computes `aim_direction = (get_global_mouse_position() - global_position).normalized()`.
- **Normal attack** (left mouse button, hold to auto-fire): fires `bullet_count` bullets at `fire_rate`-second intervals. Extra bullets are spread perpendicular to the aim direction with 12 px spacing.
- **Heavy attack** (right mouse button, `heavy_cooldown_max` = 10 s cooldown): fires a single `ExplosiveBullet`. A `HeavyBarFill` `ColorRect` above the player head shows cooldown progress (orange while charging, green when ready).
- **Recoil system**: every normal shot applies `recoil_force` impulse opposite to aim direction (horizontal always; vertical only when aiming downward). Heavy attack multiplies force by 2× on floor, 4× in air. Recoil is tracked in `_recoil: Vector2` and applied to `velocity` each physics frame after decaying.
  - Horizontal recoil is clamped to `±RECOIL_HORIZONTAL_CAP` (540) each frame so rapid fire can't stack it indefinitely.
  - When the player holds a direction key that opposes `_recoil.x`, horizontal decay is multiplied by `RECOIL_COUNTER_DECAY_MULT` (3×), so input can always fight back against recoil at any fire rate.
  - Vertical (upward) recoil is capped at `RECOIL_UPWARD_CAP` (540) applied to `velocity.y`.
- **Rise-height cap**: once the player is `MAX_RISE_HEIGHT` (130 px) above their last floor, all upward velocity and upward recoil are zeroed so they don't rocket off screen.
- **Forced-fall timer**: `_airborne_timer` increments every frame the player is off the floor and resets on landing. Once it exceeds `MAX_AIRBORNE_TIME` (2 s), all upward recoil and upward velocity are zeroed each frame until the player lands, preventing indefinite hover via rapid downward-shot recoil.

#### Roguelike stat modifiers (changed by level-up cards)
| Field | Default | Effect |
|---|---|---|
| `bullet_count` | 1 | Bullets fired per shot |
| `bullet_size_mult` | 1.0 | Scales bullet `ColorRect` + damage multiplier |

### Bullet (`scripts/Bullet.gd`)
Travels in a straight line (`direction * speed * delta`). On `_ready()` scales `self.scale` by `size_mult` so child `ColorRect` and `CollisionShape2D` both scale uniformly. Frees itself after a 2-second lifetime or on hitting an enemy/`StaticBody2D`.

### ExplosiveBullet (`scripts/ExplosiveBullet.gd`)
Heavy-attack projectile (`speed` 500, lifetime 3 s). On impact (enemy or `StaticBody2D`) calls `_explode()`:
- Runs a `PhysicsShapeQueryParameters2D` circle query (`radius` = 100 px, mask = 4 / Enemy layer) and calls `take_damage(explosion_damage)` on every collider in range.
- Spawns a temporary orange `ColorRect` flash node (size = 2× radius, 0.15 s lifetime) as a visual.
- A `_exploded` guard prevents double-detonation if multiple bodies trigger `body_entered` in the same frame.

### Enemy AI (`scripts/Enemy.gd`)
- Chases the player's X position: `dir_x = sign(player.global_position.x - global_position.x)`.
- If the enemy is on a platform above the player (`is_on_floor()` and `global_position.y <= player.global_position.y - ABOVE_PLAYER_Y_OFFSET`), it ignores the player's X and keeps walking its current direction (`sign(velocity.x)`) so it walks off the platform edge instead of stalling directly overhead.
- If `dir_x` would still be `0` (e.g. exact X alignment or zero velocity), it falls back to `_fallback_direction`, a `-1`/`1` chosen once per enemy in `_ready()`.
- Each enemy has a health bar above its head (`HealthBarBg` + `HealthBarFill` `ColorRect`s in `Enemy.tscn`); `take_damage()` shrinks `health_bar_fill.size.x` proportionally to `current_hp / max_hp`.

### GameManager autoload (`scripts/GameManager.gd`)
Registered as a global singleton in `project.godot` (`[autoload]`). It's the hub connecting otherwise-decoupled nodes:
- `GameManager.player` — set by `Player._ready()`; read by `Enemy` (AI targeting, XP grants) and `Main` (HUD).
- `GameManager.level_up_ui` — set by `LevelUpUI._ready()`.
- Owns the **card database** (`Array[Dictionary]`, each `{id, name, description, effect}`, where `effect` is a `Callable` that mutates a `Player`'s stats) and the level-up flow:
  `Player.add_xp()` -> `check_level_up()` -> `_trigger_level_up()` (sets `Engine.time_scale = 0`, picks 3 random cards, shows `LevelUpUI`) -> `select_card()` (applies the chosen effect, multiplies `xp_to_next_level` by `XP_SCALING` = 1.5, sets `Engine.time_scale = 1`).

#### Card database (5 cards)
| id | Name | Effect |
|---|---|---|
| `move_speed_up` | Swift Boots | `move_speed *= 1.2` |
| `extra_bullet` | Twin Shot | `bullet_count += 1` |
| `heavy_rounds` | Heavy Rounds | `damage *= 1.5`, `bullet_size_mult *= 1.5` |
| `fire_rate_up` | Quick Trigger | `fire_rate *= 0.75` (smaller = faster) |
| `max_hp_up` | Vitality | `max_hp += 25`, `current_hp += 25` |

Pausing uses `Engine.time_scale = 0` (not `SceneTree.paused`), so every `_physics_process` in `Player.gd` / `Enemy.gd` / `Bullet.gd` / `ExplosiveBullet.gd` starts with `if Engine.time_scale == 0.0: return`. UI button presses still work while "paused" because input handling is unaffected by `time_scale`.

### HUD (`scenes/Main.tscn` + `scripts/Main.gd`)
The HUD lives in a `CanvasLayer` node named `HUD` inside `Main.tscn`. It uses the same `ColorRect` bar pattern as enemy health bars (background + fill pair), not Godot's `ProgressBar` control, so it matches the placeholder art style.

- **HP bar**: `HPBarBg` (dark gray, 200×16 px) + `HPBarFill` on top; fill width = `200 * clamp(current_hp / max_hp, 0, 1)`. Color lerps green→yellow→red via `Color(1-ratio, ratio, 0, 1)`. A small `HPLabel` ("HP") sits to the left.
- **XP bar**: `XPBarBg` (dark gray, 200×12 px) + `XPBarFill` (blue `Color(0.2, 0.5, 1, 1)`) below the HP bar; fill width = `200 * clamp(current_xp / xp_to_next_level, 0, 1)`. A small `XPLabel` ("XP") sits to the left.
- `Main.gd` holds `@onready` refs to `HPBarFill` and `XPBarFill` and updates both via `size.x` in `_update_hud()`, called every `_process` frame.

### Physics collision layers
A 4-layer scheme is shared across `Player.tscn`, `Bullet.tscn`, `ExplosiveBullet.tscn`, `Enemy.tscn`, and the `StaticBody2D` arena pieces in `Main.tscn`. If you change a layer/mask on one node, update its counterpart too or hit detection silently breaks:

| Layer (bit) | Value | Used by |
|---|---|---|
| 1 World  | 1 | Ground/platforms (`StaticBody2D`); Player & Enemy `collision_mask` (floor collision) |
| 2 Player | 2 | Player body |
| 3 Enemy  | 4 | Enemy body; Player's `HurtBox` mask; Bullet mask; ExplosiveBullet shape query mask |
| 4 Bullet | 8 | Bullet area; ExplosiveBullet area |

- Player and Enemy bodies only physically collide with World (layer 1) — they pass through each other physically.
- Player's `HurtBox` (Area2D, mask 4) detects Enemy bodies for contact damage, polled every tick by `ContactDamageTimer`.
- Bullet and ExplosiveBullet (layer 8, mask 5 = World|Enemy) free themselves via `body_entered` on hitting a `StaticBody2D` or an enemy.

### Groups
`Enemy._ready()` adds itself to the `"enemies"` group. `Bullet`, `ExplosiveBullet`, and Player's `HurtBox` use `is_in_group("enemies")` / `has_method("take_damage")` to identify enemies generically rather than type-checking.

### Enemy spawning & arena boundaries
`Main.gd`'s `_spawn_enemy()` picks a random X across the viewport width (inset by `EDGE_MARGIN`) and spawns the enemy `SPAWN_ABOVE_SCREEN` pixels above the top of the screen. Enemies then fall under gravity (`Enemy._physics_process`) and land on whichever platform or the `Ground` is below their spawn X.

`Main.tscn` has invisible `LeftWall`/`RightWall` `StaticBody2D` nodes just outside x=0 and x=1280 (full viewport height, layer 1/World) that block the Player and any Enemy from walking off the left/right edges of the arena.
