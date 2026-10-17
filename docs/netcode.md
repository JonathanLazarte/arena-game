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

## 10. Phase 2: online transport, lobby, relay

**Files:** `net/online/net_link.gd` (UDP link: relay room, NAT punch, relay fallback, LAN), `net/online/net_match.gd` (handshake, rollback session, sync, checksums, logs), `net/online/online_panel.gd` (lobby menu), `net/sim/sim_match.gd` (local device input + online stepping), `server/` (Node.js + TypeScript relay, Dockerfile, `fly.toml` example).

**Transport:** plain UDP (`PacketPeerUDP`), one socket per client, IPv4. ENet was not used: it would add its own reliability and ordering on top of the rollback input redundancy, and a third-party relay can't forward ENet without speaking it. WebRTC was not used: it needs a signalling + STUN/TURN stack and a native extension on Android/desktop. The relay already gives rendezvous plus a TURN-like fallback. Byte 0 of each datagram is the type:
- relay: `C` create {code?} → `W` {code, slot 0}; `J` join {code} → `M` {slot, peer "ip:port", code} to both, or `E` {err: no_room / room_full / code_taken}; `R`+payload is forwarded verbatim as `D`+payload; `K`/`k` keepalive every 2 s; `X` leave → `x` to the other member. Rooms expire after 120 s without traffic. Codes are 5 chars from an alphabet with no 0/O/1/I.
- peer: `P`/`Q` punch request/answer (for 2 s after `M`; a `Q` reply means the direct path works both ways, and from then on data goes direct). `L`/`l` LAN hello (host binds UDP 47801). `D`+`var_to_bytes(Dictionary)` game messages (decoded without objects).
- Control messages are retransmitted every 300 ms until answered. The guest's join is retried for `join_wait_ms` when the room doesn't exist yet.

**Handshake (`NetMatch.prelude_step`):** `hi` {protocol version} → 12 `ping`/`pong` 40 ms apart → the host takes the median RTT, picks the input delay and RNG seed, and repeats `start` {delay, seed} until it gets `go`. The guest only reports ready once its `go` has actually left the socket, and it answers any late `start` during play.

**Adaptive input delay:** `delay = clamp(round(RTT / 2 / 16.7 ms) − 1, 1, 4)` ticks, fixed for the match (host decides): LAN ~1, 100 ms → 2, 150 ms → 3, ≥ 170 ms → 4. Rollback covers the rest (window 8).

**Session packet** (`t: "in"`, every physics tick): redundant local inputs since the peer's ack (`PackedInt32Array`), `ack`, `ph` (params checksum), `f` (sender frame), `s`/`e`/`ed` (send time, echoed time, echo hold → RTT, EMA 0.1), and every 4th tick the last 12 confirmed `[frame, checksum]` pairs (`PackedInt64Array`). Measured ≈ 16–19 kB/s each way.

**Time sync (frame advantage):** `adv = my_frame − (peer_frame + RTT/2 in ticks)`, EMA 0.1. When `adv > 1.5` the peer that is ahead skips one tick (no local input, no step), at most once every 12 ticks. RbSession's window stall (frame − last confirmed > 8) is the hard limit.

**Checksums + desync report:** each peer compares the received checksums with its own confirmed ones. On the first mismatch, status becomes `desync` and `user://net/desync_<time>_p<slot>_f<frame>.json` is written: the replay up to that point, both checksums, and the full state int array after the frame.

**Params handshake:** see section 9. A peer that detects a mismatch sends `bad_params` 3× (the other side would otherwise just stall), and both end with `params_mismatch`.

**Replays / input logs:** `NetMatch.replay_dict()` = {proto, params (var_to_str), seed, delay, slot, spawn, in0[], in1[] confirmed, checksum every 10th tick}. It's saved to `user://net/replay_<time>_p<slot>.json` at the end of every online match. `NetMatch.verify_replay(d)` re-simulates without the network and returns the ticks whose checksum differs.

**Rounds in the sim (online):** globals `G_WINS0/1`, `G_ROUND`, `G_END_T`. A KO sets `G_END_T` and adds the win. `FightEngine` (rounds = true) resets the fighters from `spawn` 150 ticks later, keeping wins, round, frame and RNG, so the reset rolls back like everything else. A match is first to 2. The arena only reads the *confirmed* state (`NetMatch.confirmed_state()`) for the round label and the match end. There's no round timer online; the HUD timer shows the RTT.

**End conditions:** `ko`, `forfeit_win` / `forfeit_loss` (the HUD menu's back-to-lobby or rematch sends `bye` 3×, unthrottled), `peer_left` (relay `x`), `disconnected` (no packet for 4 s), `desync`, `params_mismatch`, `version`.

**Arena online mode:** `NetMatch.current` set → the arena builds two identical standard fighters (same character/weapon/eikon, no random boss abilities/magic; lobby loadouts are not exchanged yet), disables the AI and `PlayerController`, and runs `SimMatch` with `net`. The host is sim slot 0 at +Z and the guest slot 1 at −Z. On each device the `player` node (camera, left HUD bar) is its own fighter: the guest calls `setup(enemy, player)`.

**Local input (`SimMatch.sample_device(local_slot)`):** keyboard actions; HUD touch buttons (they press the same input actions: Atacar, Parry/Escudo (hold ≥ 11 ticks = shield, tap = parry), Rodar, Correr (toggle; drops when the stick is released or when exhausted), Arma 3ª, Fijar); the HUD `TouchStick` added to the keys, through `PlayerController.shape_stick`; left mouse = attack while the camera has captured the mouse. Movement is camera-relative.

**Lobby:** the `ONLINE` button opens `OnlinePanel`. Relay address field (saved in `user://online.cfg`), `Crear sala` (shows the code), `Unirse con código`, `LAN: crear` (shows this device's private IPs, UDP 47801), `LAN: unirse` (host IP). The handshake runs in the panel, then the arena opens.

**Tests:** `tests/test_net_online.gd` (in-process, 36 checks: delay formula, LAN pair at 80 ms RTT, 600 ticks in sync, replay verify/tamper, forfeit, forced desync + report, silent disconnect, params mismatch, sim rounds, touch input, arena online as host and as guest, lobby panel LAN pairing). `server` `npm test` (relay unit tests), `npm run test:e2e` (relay + two headless Godot processes, `tests/net_client.gd`). Measured on localhost with simulated latency (900 ticks, random bots):

| scenario | RTT measured | delay | path | max resim | result |
|---|---|---|---|---|---|
| 0 ms | 13 ms | 1 | direct after punch | 1 | 0 checksum mismatches |
| 50 ms RTT, 2 % loss | 78 ms | 2 | relay-forwarded | 5 | 0 |
| 100 ms RTT, 2 % loss | 124 ms | 3 | direct | 4 | 0 |
| 200 ms RTT, 5 % loss | 224 ms | 4 | relay-forwarded | 8 | 0 |
| LAN, 60 ms RTT, 1 % loss | 84 ms | 1–2 | direct, no server | — | 0 |

(Measured RTT includes up to one physics tick of polling on each side.)

**Deploying the relay (nothing deployed):** the relay needs one public UDP port, about 20 kB/s per relayed match, and almost no CPU or RAM. Pick a region near the players (São Paulo for Uruguay):
- **Oracle Cloud Always Free** (VM.Standard.E2.1.Micro or Ampere A1, São Paulo/Vinhedo regions): free; open UDP 47800 in the VCN security list and in the VM firewall; run with Docker or `node dist/src/index.js` under systemd.
- **Google Cloud free tier e2-micro:** free only in some US regions (adds ~150 ms from South America); fine for testing.
- **Fly.io:** `server/fly.toml` example (region `gru`). UDP needs `HOST=fly-global-services` and a dedicated IPv4 (paid, a few USD/month); billed by usage, with no permanent free tier for new accounts.
- **Any small VPS** (Hetzner, DigitalOcean, Vultr ~4–6 USD/month): `docker run -d --restart=always -p 47800:47800/udp arena-relay`.
Then type `host:47800` in the game's Online panel. Players who can punch through NAT (most home routers) only use the relay for pairing; symmetric NAT / CGNAT on mobile data falls back to relaying through it.

**Known limits:** both players use the standard loadout (loadout exchange + bake is next); IPv4 only; no room listing or matchmaking; the input delay is fixed per match; the relay has no authentication or rate limiting (fine for private codes, harden before public release).

## 11. Phase 3: latency tuning

**Parry lenience (online only):** `SimParams.lenience_for_delay(start delay)` gives 0 ticks at delay 1, 1 at delay 2, and 2 at delay ≥ 3 (≤ 33 ms). `online_tuning` adds it to `parry_window` and takes it off `parry_recovery`, so a whiffed parry costs the same total time. It's applied in `NetMatch.start_play` (PROTO 3), it's part of the params checksum, and the offline/base params are untouched. The value comes from the *starting* delay so the params stay fixed for the whole match. Hit-stop is unchanged: it's the in-sim freeze (5/4/7 ticks), already rollback-safe, and the frozen ticks give rollback some slack. Not scaled.

**Render smoothing:** `SimView.smooth` (online). After a tick with a rollback (`RbSession.last_resim > 0`), the per-fighter error (previous sim position + previous velocity) − corrected position is added to a visual offset. The offset decays ×0.75 per tick (≈ 19 ticks to under 3 mm from 0.5 m) and snaps if it's over 1.5 m (round reset, real teleports). Only node positions change; the sim state and checksums never see it.

**Unconfirmed effects:** `SimFx.hold_ticks = 2` online. An event is held until its tick is confirmed or 2 ticks have passed. If a re-simulation covering its tick (`RbEngine.on_rollback` → `begin_resim`) doesn't produce it again, it's cancelled before it's shown. The local player's own swing/roll/shot fire instantly. Hook: `RbEngine.after_tick(confirmed, frame)` → `SimFx.flush`. Effects shown from a wrong guess (random bots, tests/test_net_events.gd): 50 ms 2.2 % → 0 %, 100 ms 4.8 % → 0 %, 200 ms 14.3 % → 9.5 %.

**Adaptive input delay during the match:** each peer adapts its own *local* delay (`RbSession.set_delay`). Inputs that were already sent are final; when the delay goes up, the ticks that would have no input are filled with the last input and sent like any other. So the two peers never need to agree on a switch frame, and determinism doesn't depend on it.
- Target = `delay_for_rtt(rtt EMA)`.
- Go up 1 after 90 consecutive ticks asking for more.
- Go down 1 after 300 consecutive ticks where even RTT + 15 ms asks for less.
- At most one change per 180 ticks; range 1–4.
- Test: RTT 20 → 140 → 20 ms went 1→4→2 in 5 changes over 1500 ticks, with 0 checksum mismatches and a reproducible replay.

**Net overlay:** `NetOverlay` (F3 / "Red" button, top right). Shows ping and path (direct/relay), current/start delay and number of changes, rollback (last/max/total), frame advantage, sync skips, stalls, sim step and average re-sim µs measured *on the device*, parry lenience, kB/s, tick/confirmed tick and desync status.

**Lobby loadout online:** `NetLoadout.from_game_state` → {name, char, w/w2/lh as [id, upgrade level, infusion], level, skills, attrs, armor, trinkets}, data only. It's sent in the `hi` handshake. Each peer rebuilds *both* fighters from the two loadouts (`Arena._make_online_fighter`), and bad data is cleaned up (unknown ids → defaults, levels clamped). Eikon, magic and boss abilities don't travel (not in the online ruleset). A mismatch would show up as `params_mismatch`. Tested with berserker vs archer: the bake checksum is identical on both peers.

**Mobile budget:** `FightSim.step` ≈ 44 µs on the dev Xeon in GDScript. Worst tick (8-tick rollback + new tick + copies) ≈ 0.4 ms desktop, ≈ 2 ms estimated on a mid phone (×5), against a 4 ms budget. The overlay shows the real per-device numbers ("Sim: paso … µs").

## 12. Fase 4
- LAN: el socket escucha en 0.0.0.0:47801/udp. lan_addresses() lista primero 192.168/10 y excluye docker (172.17), virbr (192.168.122) e IPv6. El botón "Buscar" hace broadcast 'S' y el host responde 's'+nombre. El invitado acepta el 'l' de otra interfaz del host. El timeout es de 8 s ("lan_timeout"); el puerto ocupado da "port_busy:N".
- Infusiones/estado en la sim: tabla de defensas elementales (códigos 5..7). El daño se reparte mitad físico, mitad elemental. Build-up de sangrado/veneno/congelación: decay tras 90 ticks, veneno de 840 ticks, congelación de 720 ticks (×1,15 al daño recibido, ×0,6 a la regeneración de stamina). Un bloqueo aplica el 30% del build-up y un crítico no aplica estado. Los eventos son PROC0..2.
- Pilares: 6 posiciones fijas en µm (radio 23,8 m). El cuerpo se empuja hasta 1,65 m y las flechas se paran a 1,5 m. Solo se activan si params.pillars = 1.
- Bits de entrada nuevos (flanco de pulsación en la sim): IN_BOSS 1<<14, IN_BOSS_NEXT 1<<15, IN_SPELL 1<<16, IN_SPELL_NEXT 1<<17, IN_EIKON 1<<18 (invocar / especial montado), IN_MOUNT 1<<19 (desmontar).
- Habilidades de jefe (SimAbilities): las 19 (13 + ext + estocada) compiladas a ticks en params["boss"]. Telegrafía ×1,12 (TELE_ONLINE, fija en ambos pares). Cooldown global 85 ticks (1,4 s). Golpe tipo 3 «jefe»: imbloqueable, sin parada, perforante, postura ×3. Un coste de vida nunca baja de 1. Hazards: 16 plazas, tipo 1 = AoE en suelo, tipo 2 = onda.
- Proyectiles: 12 plazas; kinds 0 flecha, 1 tajo de jefe, 2 hechizo, 3 eikon. Ráfaga: 20 m/s, giro 60°/s (rumbo en mili-unidades).
- Magia y eikons (SimMagic): maná, medidor (máx. 100000 mili, +20/tick), escudo de maná 100%, hechizos proyectil/cono/buff, invocación, montura, especiales llamarada/colmillo/vendaval. Una montura sin jinete no ataca online. El medidor empieza a 0 online.
- Equipo (NetLoadout): ahora también eikon, hechizos (4), arte, sello y jefe (3). Los dos pares hacen bake → params_checksum.
- Carga: start_play → fase LOAD. Cada par envía «ka» (latido) mientras calienta la escena y luego «rdy» cada 200 ms. PLAY empieza solo con ambos listos. Plazo de carga de 30 s («load_timeout»); el de juego sigue en 4 s. La arena muestra «Cargando rival...».
- Eventos: ability (con code = AB_LAST), ability_hit, ability_interrupt, grab, cast, summon, eikon_special, eikon_hit, shield_absorb, dismount.

## 13. Fase 5: emparejamiento, reconexión, relay endurecido
- Servidor: el relay Node/TS ampliado (no Nakama: sin BD ni cuentas; ver server/DEPLOY.md). Un relay por región (REGION).
- Protocolo de juego 5 desde la fase 6 (4 en la fase 5) (NetLink.GAME_PROTO = NetMatch.PROTO). C/J/Q llevan "v"; si no coincide, E {err:"version", need}.
- Mensajes nuevos: 'Q' cola rápida → 'q' {pos} y luego 'M'; 'P'/'p' ping {t, region}; 'M' incluye token (24 hex) y region. 'B' {code, token} re-asocia una dirección nueva (re:1) y el otro recibe 'b' {peer}. 'F' {slot}: el rival lleva más de GRACE_MS (20 s) sin tráfico, victoria por abandono.
- Límites: relay 200 pkt/s (ráfaga 400), control 10/s (ráfaga 20), 600 infracciones/min → bloqueo de 60 s, paquete máx. 1200 B, 5000 salas, cola de 10 s sin «K».
- Salud: HTTP HEALTH_PORT (8080) con /healthz (JSON) y /metrics (Prometheus).
- Cliente: tras TIMEOUT_MS (4 s) sin paquetes → reconnecting. La sim se congela, se envía 'B' por el relay cada 1 s y «rs» {ep} cada 0,5 s. Al volver, el anfitrión toma una instantánea del estado confirmado (deflate, trozos de 900 B, «snap» {ep, f, i, n, sz, b}) y ambos hacen RbSession.reset_to(estado, f) (época +1; «in»/«rdy» de otra época se descartan) y repiten LOAD/«rdy». Plazo local de 25 s («disconnected»); el relay decide antes con 'F'.
- Repeticiones: replay_dict guarda "resync": [[f, estado]] por cada reinicio; verify_replay sustituye el estado en esos fotogramas, así la repetición del invitado verifica tras reconectar.

## 14. Fase 6: huecos online cerrados (protocolo 5)
- Entradas nuevas: IN_ART 1<<20 (arte de arma, acción special), IN_BOSS_VAR 1<<21 (variante, acción boss_variation). Flancos detectados en la sim.
- Campos nuevos del luchador: MD_T, MD_HIT, MD_ATK, ART_CD, ART_T, ART_K, ATK_PET y contadores ARTS, PET_HITS, PET_KILLS, MDASH_HITS. Cambian SIZE → protocolo 5.
- Montado: alcance m_reach_pm y daño m_dmg_pm de la montura; voltereta = embestida (m_dash_spd/t/if/cd, contacto 2,9 m, empuje 16 m/s, la mitad si bloquea, aturdimiento 15, medidor 6); kind 6 en _take_hit (parable, sin tambaleo al atacante). Sin parry montado. Ataque montado: lentitud 550 ‰, carga 300 ‰; un ataque en preparación durante la embestida golpea a partir del tick 7.
- Mascotas/monturas: EK_HP recibe golpes cuerpo a cuerpo (si está en el arco), proyectiles y AoE; a 0 se retira. Las voladoras (fénix) ignoran las AoE.
- Artes: estocada_impulsada (tipo 1) y torbellino (tipo 2); no disponibles si el personaje tiene especial propio (como offline).
- Variante combo-falso: remate en estocada sin salto (parada a 1,4 m, distancia ×1,45, cono 65°, empuje ×1,2, fuerza +8), sin AoE de caída.
- HUD táctil online: botones de jefe/magia/eikon/montura y los de ciclo (▶ envía pulsación+suelta de 0,12 s).
- Paridad: el arnés pone fluid = true como el jugador real (arena.gd). Pendiente: la montura sin jinete no ataca online; el coste de bloqueo del ataque montado no se recalcula con m_dmg_pm.


## 15. Fase 7: salto, montura compañera, movimiento ágil (protocolo 6)
- IN_JUMP 1<<22 (acción «jump»: Espacio / botón táctil «Saltar»). Campos FY (µm), FVY (µm/tick), AIR, AIR_T, LAND_T y contador JUMPS → SIZE cambia → protocolo 6.
- Salto: JUMP_V 133333 µm/tick, gravedad 5556 µm/tick² (×1,8 en el picado A_JUMP = 5), aterriza con AIR_T ≥ 5, FY < 0,02 m y FVY ≤ 0; LAND_T 11 ticks (no actúa, 40 % de velocidad). En el aire: sin control planar ni giro, sin voltereta/hechizo/arte/jefe/invocar montura. _grounded exige FY < 0,35 m. Proyectiles apuntan y golpean a HIT_CENTER_Y + FY. Montado: m_jump (0 en el fénix).
- Montura sin jinete: ataca como Mount._companion_step (persigue a move_speed × 0,7, primer ataque a 0,8 s, mordisco o disparo).
- Ataque montado bloqueado: block_cost_m (coste calculado con el daño × mounted_damage_mult).
- Movimiento: steer (rumbos/tick a los que gira la velocidad), sprint_up/sprint_down (‰/tick); valores en docs/design.md.
- Relay: sin respuesta en relay_timeout_ms (5 s) → FAILED "relay_unreachable"; DNS fallido → "relay_dns:host". El panel lo explica y sugiere LAN o server/DEPLOY.md.

## 16. Fase 8: offline sobre la sim (protocolo 7)
- Offline y online usan el mismo bucle: `SimMatch` + `FightEngine` + `FightSim`. Offline: `FightEngine.new(params, 1, true)` sin rondas internas (la arena reinicia la ronda con `SimMatch.reset_round()`), entrada del jugador por `sample_device`, del rival por `SimAI.think(state, params)` en `input_override[1]`.
- `SimAI` vive fuera del estado (no se re-simula): memoria propia y xorshift sembrado con `randi()` al crear la partida. Misma secuencia de estados → mismas entradas (`test_sim_ai`).
- Estado nuevo: `FLASK_T`, `FLASKS` (frasco: 1 carga por ronda, 1,1 s, cura 35 %, 25 % de velocidad, sin actuar) y `PH2` (Fase II del campeón). Entrada nueva `IN_FLASK` 1<<23 (acción «flask»). → protocolo 7.
- Params nuevos: `flasks`, `flask_t`, `flask_heal_pm`; offline además `boss_n` (habilidades disponibles antes de la Fase II), `ph2` {hp_pm, rage, invuln, summon} y `buffer` (ventana del búfer del jugador, Ajustes → Controles). `art` tipo 3 = golpe sísmico del personaje (marca de suelo con aviso).
- Paso atrás + ataque: la estocada sale al terminar el paso (`ROLL_ATK_BUF` reutilizado).
- Eventos nuevos (`SimEvents`): `flask`, `phase2`. La arena traduce `crit` a la cinemática de ejecución y `phase2` al aura/mensaje del campeón.
- Vista: `SimWorld` (eikons y monturas títere, marcas, ondas, proyectiles no-flecha) y `SimView` (medidor, maná, recargas, habilidad en curso, frasco). Sin realimentación hacia la sim.
- `test_net_parity` se retiró: ya no hay reglas offline con las que comparar.

## 17. Fase 9: apuntado del arco, ciclo de habilidades, revancha y efectos (protocolo 8)
- **Apuntado con ratón**: bits 24–29 = rumbo de apuntado en 64 pasos (`FightSim.aim_bits(rumbo256)`, `aim_heading(inp)` = paso × 4) y bit 30 = `IN_AIM`. El bit 31 no se usa (el paquete `in` es `PackedInt32Array`). Con arco y `IN_AIM`, al tensar el luchador se encara al rumbo de apuntado (con desplazamiento lateral) y la flecha sale por ese rumbo; el autoapuntado al rival solo corrige si está a < ~14°. `SimMatch.aim_input()` lo genera desde el ratón (rayo al plano y = 1, o el frente de cámara con el ratón capturado); sin joystick táctil visible. Opción «Arco: apuntar con ratón» en Ajustes (`SimMatch.mouse_aim`).
- **Ciclo de habilidades de jefe (▶)**: es solo el flanco `IN_BOSS_NEXT` de la sim (AB_SEL en el estado, seguro ante rollback). `SimMatch.pulse(bit)` encola pulsos de un tick con un tick de hueco (dos toques = dos flancos); los toques más cortos que un tick (`_input`) se convierten en pulso. La vista ya no cambia `Fighter.boss_sel` (SimView lo sobrescribía al tick siguiente: ese era el «parpadeo»). El ciclo respeta `SimAbilities.boss_avail` (la 3.ª del campeón llega en Fase II); la vista lo lee en `Fighter.boss_avail` / `avail_boss_ids()`.
- **Revancha online** (`NetMatch`): tras el KO el enlace sigue abierto. Mensajes `rm {n}` (quiero revancha número n, cada 250 ms), `rmno` (vuelvo al lobby, ×3 urgente) y `rmgo {n, seed, ep}` (el anfitrión, cuando los dos quieren: semilla nueva ≠ anterior, época + 1, ×2; reenvía si recibe un `rm` de la revancha ya arrancada). `_restart(seed, ep)`: `FightEngine` nuevo con los mismos params y aparición, `RbSession` nueva con el mismo `params_hash`, fase LOAD con el saludo `rdy`. `SimMatch._on_net_rematch` crea un `SimFx` nuevo (las claves `frame:kind:player` vuelven a empezar en 0) y la arena reinicia marcador y ronda. Si el rival vuelve al lobby: «El rival volvió al lobby».
- **Efectos de habilidades** (`SimAbilityFx`, desde `SimWorld`): brillo del arma por habilidad (blanco en el parpadeo del tajo retardado), aura de partículas y filo incandescente en la estocada, burbuja del escudo de maná, desaparición/estallidos del paso espectral, rastro de espada en cada golpe de timeline, cono y chispas del aliento, aura roja de la furia, estallido del contragolpe, marcas de suelo con anillo + relleno que crece + borde + destello que se desvanece (oculta en el salto con caída, tinte por habilidad en las lluvias, columna de luz en la lanza celeste), ondas con línea de aviso y cresta, y proyectiles: media luna dorada (kind 1), orbe con estela (hechizo, kind 2; eikon, kind 3, color del eikon). Solo lee el estado (`test_ability_fx` comprueba que no lo modifica).
- Protocolo 8 en `net_link.gd`, relay (`index.ts`, `relay.ts`, tests, `DEPLOY.md`, docker-compose).
