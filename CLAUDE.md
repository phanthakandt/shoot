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
Every gameplay scene under `scenes/` is a thin `.tscn` wrapper around a same-named script in `scripts/` (e.g. `scenes/Player.tscn` + `scripts/Player.gd`). `Player.gd` and `Bullet.gd` declare `class_name` (`Player`, `Bullet`) so other scripts can type-hint against them directly (e.g. `GameManager.player: Player`) without preloading.

### Player controls & shooting (`scripts/Player.gd`)
- Movement: `A`/`D` (`Input.is_physical_key_pressed`) for left/right; `W` or `Space` to jump, edge-triggered via `_jump_was_pressed` and gated on `is_on_floor()`.
- Aiming is 360-degree and follows the mouse: `_shoot()` computes `aim_direction = (get_global_mouse_position() - global_position).normalized()`.
- Firing is full-auto: holding the left mouse button (`Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)`) fires repeatedly at `fire_rate`-second intervals via `_fire_cooldown`.
- `Bullet.direction` is a normalized `Vector2` (set to `aim_direction`), and `Bullet._physics_process` moves it by `direction * speed * delta` — bullets travel in any direction, not just left/right.

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
  `Player.add_xp()` -> `check_level_up()` -> `_trigger_level_up()` (sets `Engine.time_scale = 0`, picks 3 random cards, shows `LevelUpUI`) -> `select_card()` (applies the chosen effect, multiplies `xp_to_next_level` by `XP_SCALING`, sets `Engine.time_scale = 1`).

Pausing uses `Engine.time_scale = 0` (not `SceneTree.paused`), so every `_physics_process` in `Player.gd` / `Enemy.gd` / `Bullet.gd` starts with `if Engine.time_scale == 0.0: return`. UI button presses still work while "paused" because input handling is unaffected by `time_scale`.

### Physics collision layers
A 4-layer scheme is shared across `Player.tscn`, `Bullet.tscn`, `Enemy.tscn`, and the `StaticBody2D` arena pieces in `Main.tscn`. If you change a layer/mask on one node, update its counterpart too or hit detection silently breaks:

| Layer (bit) | Value | Used by |
|---|---|---|
| 1 World  | 1 | Ground/platforms (`StaticBody2D`); Player & Enemy `collision_mask` (floor collision) |
| 2 Player | 2 | Player body |
| 3 Enemy  | 4 | Enemy body; Player's `HurtBox` mask; Bullet mask |
| 4 Bullet | 8 | Bullet area |

- Player and Enemy bodies only physically collide with World (layer 1) — they pass through each other physically.
- Player's `HurtBox` (Area2D, mask 4) detects Enemy bodies for contact damage, polled every tick by `ContactDamageTimer`.
- Bullet (layer 8, mask 5 = World|Enemy) frees itself via `body_entered` on hitting a `StaticBody2D` or a node in the `"enemies"` group.

### Groups
`Enemy._ready()` adds itself to the `"enemies"` group. `Bullet` and `Player`'s `HurtBox` use `is_in_group("enemies")` / `has_method("take_damage")` to identify enemies generically rather than type-checking.

### Enemy spawning & arena boundaries
`Main.gd`'s `_spawn_enemy()` picks a random X across the viewport width (inset by `EDGE_MARGIN`) and spawns the enemy `SPAWN_ABOVE_SCREEN` pixels above the top of the screen. Enemies then fall under gravity (`Enemy._physics_process`) and land on whichever platform or the `Ground` is below their spawn X.

`Main.tscn` has invisible `LeftWall`/`RightWall` `StaticBody2D` nodes just outside x=0 and x=1280 (full viewport height, layer 1/World) that block the Player and any Enemy from walking off the left/right edges of the arena.
