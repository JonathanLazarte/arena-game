# Netcode (online 1v1) — design

Status: phase 0 (feasibility + rollback prototype in `net/`). The offline game does not use `net/`.

## 1. Architecture

- **Model:** deterministic peer-to-peer rollback (GGPO-style). Each peer runs the full simulation; only inputs travel.
- **Sim tick:** fixed 60 Hz (`physics_ticks_per_second = 60`), integer tick counter. The gameplay sim never reads variable delta, wall clock, `Engine.time_scale`, or scene-tree physics.
- **Sim/view split:** gameplay state lives in a pure data object (`SimState`, ints in fixed point, PackedInt64Array or typed arrays). Nodes (`Fighter`, `KnightVisual`, mount, eikon, projectiles, VFX, audio, camera) read the state each rendered frame and are never rolled back. Effects (sound, particles, hit-stop, shake) fire from state *events* tagged with a tick and are de-duplicated when a resim regenerates them.
- **Fixed point:** 1 unit = 1 mm, time in ticks, angles as integer facings or a 4096-step table, sin/cos/sqrt from lookup tables / integer sqrt. Needed because PC (x86) and mobile (ARM) builds must agree bit for bit; GDScript floats are doubles and mostly portable, but engine helpers (`Vector3.normalized`, `move_and_slide`, `lerp` on Transform, `look_at`) are not guaranteed identical across CPUs/builds.
- **Input struct (per player, per tick):** bitfield int — 8-direction move (or stick quantized to 16 directions × 3 magnitudes = 6 bits), light, heavy (held), block (held), parry, roll, bow/aim, swap, special, summon, mount, interact. ~16 bits; camera-relative movement must be converted to world space *before* packing (camera is local only). Lock-on target is part of the input (1 bit in 1v1).
- **State save/load:** `saved[tick] = state.duplicate()` before each simulated tick; ring buffer of `window + 2` entries. Prototype state: 23 ints. Full game estimate: 300–600 ints (2 fighters × ~150 fields incl. status effects, cooldown dictionaries → fixed arrays, plus projectiles/AoE/ground waves/mounts/eikons in fixed-size pools, RNG state).
- **Rollback window:** 8 ticks (133 ms) default; peer stalls (frame advantage pause) when it is more than `window` ticks ahead of the last confirmed remote input.
- **Input delay:** 2 ticks default (33 ms), adaptive 1–3 by measured RTT (see §6).
- **Prediction:** repeat last confirmed remote input (held buttons stay held, edges are derived inside the sim from `prev_input`, so a predicted "repeat" never re-triggers an attack).
- **Desync detection:** FNV-1a 32-bit checksum over the state ints for each confirmed tick; peers exchange checksums every 30 ticks (in the input packet). On mismatch: log both states (debug builds dump the full state and last 120 inputs), end the match as "connection error". The prototype detects a 1 mm corruption immediately.
- **Time sync:** peers estimate frame advantage from acks; the one ahead skips/slows a tick (≤1 tick per 1 s) to keep both near the same tick and minimise one-sided rollbacks.
- **RNG:** one seeded xorshift/PCG inside `SimState` (seed agreed at match start). Cosmetic randomness (camera shake, particles) keeps engine `randf`.

## 2. Transport

- **Packets:** unreliable, unordered UDP. Each packet: all unacked local inputs (redundancy, covers loss without resend timers), ack of last contiguous remote tick, optional checksum. ~20–60 bytes at 60 Hz (~3 KB/s).
- **Godot:** `ENetMultiplayerPeer` (UDP, PC + Android/iOS) with raw `put_packet` on an unreliable channel, not RPC node paths. `WebRTCMultiplayerPeer` (+ webrtc-native GDExtension on desktop/mobile) gives built-in ICE/STUN/TURN NAT traversal and is required for a web build.
- **NAT:** ~70–85 % of home/mobile pairs connect directly via STUN hole punching; the rest (symmetric NAT, CGNAT on mobile carriers) need a relay (TURN/coturn or a custom UDP relay, ~10–30 ms extra).
- **Lobby/matchmaking options:**
  1. *Simple:* room codes + tiny relay/signalling server (Node/Go, 1 cheap VPS), always relay. Easiest, adds latency, ~1–2 weeks.
  2. *Nakama* (open source, self-host or Heroic Cloud): auth, matchmaker, friends, leaderboards, realtime relay, Godot 4 client. Best fit for a full online mode, ~2–3 weeks to integrate.
  3. *Steam* (GodotSteam, P2P with Valve relay fallback): PC only, free relay, cross-play with mobile not possible.
  Recommendation: WebRTC or ENet P2P with Nakama for matchmaking/signalling and coturn/relay fallback.

## 3. Mobile + PC constraints

- Budget per rendered frame on mid mobile ≈ 16.6 ms total; rollback must stay ≤ ~3–4 ms worst case (resim of 7–8 ticks + save/restore).
- Current offline game: ~2.6 ms of physics/process per tick on the dev Xeon (headless, includes AI, nodes, move_and_slide). Resimulating 7 ticks of *that* would cost ~18 ms desktop / 60+ ms mobile → **impossible**; the pure-data sim is mandatory.
- Prototype pure sim: 2–3 µs per tick (GDScript). A full fighter sim in GDScript is estimated at 50–150 µs/tick (both fighters + projectiles) → 7-tick resim ≈ 0.4–1 ms desktop, ≈ 2–5 ms on a mid Android (4–5× slower). Acceptable; if not, move `SimState.step` to C++ GDExtension (10–30× faster).
- Mobile radio: Wi-Fi jitter 5–30 ms, 4G/5G RTT 40–120 ms with spikes; input redundancy handles loss; adaptive input delay handles jitter. Backgrounding the app must pause/forfeit (timeout 5 s).
- Cross-play PC↔mobile works only with fixed-point sim (see §1).

## 4. Mechanics to tune under latency

| Mechanic | Current | Risk under rollback | Proposal |
|---|---|---|---|
| Parry window | short (~0.12–0.2 s) | remote's attack appears up to 3–5 ticks late; parries get "stolen" by rollback | widen by input delay (+2 ticks) online; judge parry on the defender's confirmed input tick |
| Roll buffer 0.18 s (11 ticks) | buffer | fine; buffer is sim state | keep, store in ticks |
| Roll i-frames | ~12 ticks | dodge "teleports" visually when corrected | keep; smooth visuals (render interpolation toward corrected pose over 4–6 frames) |
| Hit-stop | `Engine.time_scale` | global time scaling breaks fixed tick | make hit-stop a per-fighter sim counter (freeze both fighters' timers N ticks), purely in sim |
| Homing projectiles / Lanza Celeste | float steering + `look_at` | must be in sim, fixed point; long-lived entities magnify state size | integer steering with turn-rate cap; projectile pool in state |
| Grabs / executions / cinematics | animation + signals | rollback across a cinematic start is ugly | 3–4 tick startup minimum, confirm only on confirmed inputs or allow rollback but delay cinematic camera until confirmed |
| Boss abilities (AoE, ground waves, random circles) | `randf`, timers, nodes | non-deterministic placement | sim RNG + entity pools; telegraphs already long → latency-tolerant |
| Mounts / eikons | `move_and_slide`, AnimationPlayer | physics not rollbackable | integer kinematic movement vs arena circle/walls |
| Light attack startup (0.15 s thrust) | ~9 ticks | at 150 ms RTT, ~4–5 of 9 startup ticks are already gone when the defender sees it | accept (genre norm) or +2 ticks startup online |

## 5. Expected feel (input delay 2, rollback window 8)

Measured with the prototype (`tests/bench_net_rollback.gd`, adversarial bots changing input every ~4 ticks, jitter ±15 ms, 2 % loss):

| RTT | one-way ticks | avg rollback length | max | resim frames/tick | stalls | feel |
|---|---|---|---|---|---|---|
| 50 ms | 1.5 | 1.0 | 3 | 0.05 | 0 % | indistinguishable from offline |
| 100 ms | 3 | 1.6 | 4 | 0.34 | 0 % | very good; occasional small corrections |
| 150 ms | 4.5 | 3.0 | 6 | 0.66 | 0 % | playable; visible teleports on fast actions, parry harder |
| 200 ms | 6 | 4.6 | 7 | 1.01 | 0 % | playable but noisy; consider delay 3 (avg rb 3.6) |
| 250+ ms | 7.5+ | — | 8 | — | rising | needs window 10–12 or input delay 4; regional matchmaking should avoid it |

Rule of thumb: rollback frames ≈ ceil(RTT/2 / 16.7) − input_delay. Real players change input less often than the bots, so real rollback rates should be lower.

## 6. Adaptive input delay

`delay = clamp(round(RTT_ms / 2 / 16.7) - 3, 1, 3)` → 50 ms: 1, 100 ms: 1–2, 150 ms: 2, 200 ms: 3. Fixed at match start (changing mid-match causes a hitch).

## 7. Prototype (phase 0)

- `net/rb_sim.gd` — integer sim: 2 fighters, 8-dir move, roll (24 ticks, i-frames 3–15, 11-tick buffer), one melee attack (12 windup / 4 active / 14 recovery, 1.8 m range, frontal), damage, hitstun, push-apart, FNV checksum.
- `net/rb_session.gd` — per-peer rollback session: input delay, input history, prediction, save per tick, rollback+resim, stall, confirmed-tick checksums.
- `net/rb_harness.gd` — two peers in one process, simulated RTT/jitter/loss (seeded), redundant input packets.
- Tests: `tests/test_net_rollback.gd` (determinism, save/restore, mechanics, convergence at 0–200 ms × 3 seeds with 5 % loss, 25 % loss + 60 ms jitter, stall path, injected desync detected). Bench: `tests/bench_net_rollback.gd [-- delay window]`.

## 8. Addon vs custom

- *Snopek godot-rollback-netcode* (v1.0.0, Godot 4.2+, MIT; GDScript): node-centric (`network_sync` group, `_save_state()` dictionaries per node, `SyncManager` autoload, NetworkTimer/AnimationPlayer/RNG helpers, good debug tools). Its Dictionary-per-node snapshots are slow in GDScript (the reason the Delta fork exists) and it still requires the same deterministic rewrite of fighter logic.
- *Delta Rollback* (fork, C++ GDExtension, needs Godot 4.7+, delta snapshots, optional Rapier deterministic physics): faster, but ships per-platform native binaries (Android/iOS builds to maintain) and couples us to a single-maintainer extension.
- **Chosen: custom layer** (~300 lines now). The hard part is the deterministic data sim, which no addon does for us; our sim is already a flat int array, so save/load is one `duplicate()` (no per-node dictionaries), and it runs headless in tests. Reuse ideas from Snopek (log/replay tooling, frame-advantage sync) and keep Delta as a fallback if GDScript resim cost becomes a problem.

## 9. Phase 1: deterministic core (reduced ruleset)

Ruleset: sword/shield + bow on foot. Out: mounts, eikons, magic, boss abilities, jump, flask, backstep follow-up strike, dash-strike via dash-in-windup (disabled offline too).

**Files** (`net/sim/`): `fx_math.gd` (256-step sin/cos table ×4096 as constants, integer sqrt, integer atan2 → heading index), `sim_params.gd` (bake), `fight_sim.gd` (state + step), `fight_engine.gd` (RbEngine adapter for `RbSession`), `sim_view.gd` (state → Fighter nodes, input packing), `sim_events.gd` + `sim_fx.gd` (presentation events), `sim_match.gd` (local two-player match loop).

**Units:** position µm, velocity µm/tick, HP/stamina/stun force in thousandths, multipliers in ‰, all timers in ticks (60 Hz), heading 0..255.

**State:** one `PackedInt64Array` of 262 ints = 2 × 81 fighter fields + 4 globals (frame, hit-stop freeze counter, xorshift RNG, hit-stop flag) + 8-slot projectile pool × 12 (3D position/velocity). Save/load = `duplicate()` (~0.06 µs). Checksum = FNV-1a over both 32-bit halves of every int.

**Params (baked, read-only):** computed once per match from the real `Fighter` pair (`SimParams.bake(a, b)`), so character, weapon, attributes, armour and charms feed the same numbers as offline. Matchup-dependent values are pre-resolved per attacker→defender: raw damage + physical subtype, the defender's armour curve as a table (incoming(a)/a in ppm for a = 0..400 per subtype, applied in the sim *after* counter/riposte/charge/rage multipliers, same order as offline), blocked stamina cost (`blocked_hit_cost`), stun force, poise damage factor. Durations go through `tk()`, which replays the offline float accumulation (`t += 1/60` until `t >= d`), e.g. 0.4 s = 25 ticks. Summed timers (recovery + whiff + finisher, guard-counter windup) are baked as one value for the same reason. `params_checksum()` is FNV-1a 32 over the UTF-8 `var_to_str` of the params (platform-stable). Conditional runtime factors (rage) are divided out of the baked damage multiplier and applied live.

**Input (int per player per tick):** bits 0–4 world heading (32 steps), 5 move, 6 half stick, 7 attack held, 8 block held, 9 parry, 10 roll, 11 sprint, 12 swap, 13 lock-on. Edges are derived in the sim from the previous input (stored in state), so predicted repeats never re-trigger. The controller layer (tap = light on release, hold 24 ticks = heavy then charge, 24-tick action queue of up to 4 actions, cleared when hit) lives inside the sim, so it rolls back with the rest. Shield-less fighters must not send bit 8 (local controller rule).

**Rules ported (same order as Fighter/FighterCombat):** movement (fixed turn rate, lock-on strafe factors, sprint ramp, accel/brake, soft separation, arena circle), roll (startup/i-frames/recovery, distance + drift, 0.18 s roll buffer, cancel in 2nd half of recovery, roll→thrust buffer), backstep, light combo chain with windows, heavy + charge (+40 % damage, +50 % force, super-armour), dash/run thrust, attack step with magnet + contact stop, block (chip, stamina, guard-counter window), guard break, parry (window/recovery/exposed ×1.25, attacker stagger, riposte ×1.8), counter-hit multipliers, accumulated 3-level stun (stagger 0.35 s roll-cancellable / stun 0.9 s / knockdown 1.1+0.8 s with immunity, 3 s window, single-hit cap), stance break + critical, hit-stop as global freeze counter (heavy/open hit 5 ticks, parry 4, crit 7), stamina (regen delay, idle regen, block drain, exhaustion), bow (draw, hold to charge 0.9 s, recovery, cooldown, crossbow reload), arrows in a fixed pool (block cost, parry reflect, i-frame pass-through).

**Online/sim mode:** `Fighter.sim_driven` (default false). When true, `_physics_process` only orients the node and updates `KnightVisual`; `SimView.apply(state)` writes the fields the animation/HUD read and emits `health_changed`/`stamina_changed`/`died`. The view never feeds back into the sim, so rollback just re-applies a state.

**Parity (tests/test_net_parity.gd, real Fighter vs FightSim, same scripted actions, 22 scenarios incl. sprint attack, crit, crossbow, armour (light/heavy/counter/parry), aim lead, rage, heal passive, parry-stamina charm):** all compared values equal; first-hit tick within ±1, stun durations within ±2 ticks (0 differences beyond the exact tolerance). Remaining sub-tick drift: charged heavy damage < 0.05 (charge time quantised to ticks).
