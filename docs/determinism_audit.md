# Determinism audit (online phase 0)

Effort: S < 1 day, M 1–3 days, L 1–2 weeks, XL > 2 weeks (one developer + agent).

| # | Blocker | Where | Effort |
|---|---|---|---|
| 1 | Gameplay coupled to nodes: ~150 mutable fields on `Fighter` (CharacterBody3D) + components, no snapshot | `fighter.gd` (2979 lines), `fighter_combat/_mount/_magic/_boss_ext`, `status_fx` | **XL** (extract `SimState` + pure `step()`; the core of the port) |
| 2 | Variable `delta` timers (float seconds) everywhere: atk_t, roll_t, stun, cooldowns, `ab_cds` Dictionary, status ticks, regen | all `_physics_process` (fighter, AI, projectile, ground_wave, ground_aoe, mount, eikon) | L (convert to integer ticks; mechanical but wide) |
| 3 | `move_and_slide` (fighter ×2, mount ×3, eikon ×1) for movement/collision | fighter.gd:1098/2264, mount.gd, eikon.gd | M (arena is open: integer kinematics + circle push + wall clamp) |
| 4 | `Engine.time_scale` hit-stop with real-time timer (global, wall-clock) | arena.gd:169–186, `hitstop` signal | S–M (per-sim freeze counter; visual-only slowdown) |
| 5 | Unseeded `randf/randi`: AI (~40 uses), boss random AoE circles, mount wander, arena rival pick/music, game_state random loadout | ai_controller.gd, fighter_boss_ext.gd:167, mount.gd:181–186, arena.gd, game_state.gd:980 | S for sim (seeded PCG in state); AI not needed online (human vs human) |
| 6 | Wall clock `Time.get_ticks_msec()` | fighter.gd:568/579/609/1146, eikon.gd:192 (eikon hover *affects position*), arena.gd | S (only eikon.gd:192 is gameplay; rest visual) |
| 7 | Float math / engine vector helpers (normalized, distance_to, look_at, lerp/slerp ×16 in fighter) for gameplay decisions | fighter.gd, projectile.gd:65, fighter_mount distance checks | L (fixed point + LUT trig, part of #1) |
| 8 | Signals driving gameplay (≈60 emits in fighter: died, hitstop, counter_landed, guard_broken, execution_cinematic, summoned…) and arena reacting | fighter.gd, arena.gd, fighter_combat.gd | M (keep signals for view only; gameplay effects inside step(), event list per tick) |
| 9 | Node spawning/freeing during play (projectiles, ground waves, AoE, eikons, mounts): ~100 add_child/queue_free | projectile, ground_wave, ground_aoe, eikon, fighter_magic, mesh_util | L (fixed-size entity pools in state; nodes become views) |
| 10 | Tweens and SceneTree timers with gameplay effect (fighter.gd:556 `create_timer(1.2)`, arena round restart 2.5 s, tweens in mount/eikon/fighter_combat) | fighter.gd, arena.gd, mount.gd, eikon.gd, fighter_combat.gd:119 | S–M (tick counters; tweens visual only) |
| 11 | AnimationPlayer for eikon/mount behaviour (eikon.gd plays anims; mount anim) | eikon.gd, mount.gd | M (state machine in ticks drives anim, never reverse) |
| 12 | Group queries / iteration order (`get_nodes_in_group` in AI, mount picking) | ai_controller.gd, fighter_mount.gd | S (explicit ordered arrays in state) |
| 13 | Input read from `Input` singleton inside controller and camera-relative stick | player_controller.gd | M (pack world-space input struct per tick) |

Good news: melee hit detection is already **timer-based + distance/angle checks** (no Area3D, no raycasts, no animation-driven hitboxes): `atk_t` vs `atk_dur` windows (fighter.gd:1154, 2319). Animations follow state rather than drive it. So the combat rules translate 1:1 to a tick sim.

Total estimate for a deterministic sim of the full game (all weapons, magic, 13 boss abilities, mounts, eikons): **6–10 weeks**; a reduced online ruleset (sword/shield + bow, no mounts/eikons) first: **3–4 weeks**.
