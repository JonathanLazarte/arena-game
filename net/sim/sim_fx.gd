class_name SimFx
extends RefCounted
## Dispara efectos una sola vez por clave (tick, tipo, jugador) aunque el rollback re-simule.
## Online (hold_ticks > 0): los eventos se retienen hasta que su tick está confirmado o han pasado
## hold_ticks; si una re-simulación ya no los produce se cancelan sin mostrarse. Las acciones propias
## del jugador local (golpe, voltereta, disparo) salen al instante para no perder respuesta.
## Un evento ya mostrado que luego no se confirma se cuenta en `spurious` (confirm(), pruebas).
var fired: Dictionary = {}   # clave -> frame
var fired_dedup: Dictionary = {} # (entity, ability, step, event_id, start_tick) -> frame
var pending: Dictionary = {} # clave -> evento retenido
var active_loops: Dictionary = {} # dedup_key -> {ev, start_frame, end_frame, player, stop_on_interrupt}
var callback: Callable       # func(ev: Dictionary)
var loop_stop_callback: Callable # func(ev: Dictionary, reason: String)
var keep_frames := 240
var hold_ticks := 0
var local_slot := -1
var fx_quality: String = "high" ## "low" | "med" | "high"
var haptics_enabled: bool = true
const INSTANT := ["swing", "roll", "shot"]
var spurious := 0
var duplicates_blocked := 0
var cancelled := 0
var loops_cancelled := 0
var _resim_from := -1
var _seen: Dictionary = {}
var _seen_dedup: Dictionary = {}

func feed(events: Array) -> void:
	for ev: Dictionary in events:
		if fx_quality == "low" and bool(ev.get("footstep", false)):
			continue
		var k: String = ev["key"]
		var dk: String = String(ev.get("dedup_key", k))
		_seen[k] = true
		_seen_dedup[dk] = true
		if String(ev.get("kind", "")) == "ability_interrupt":
			_stop_player_loops(int(ev.get("player", -1)), "interrupt")
		if fired.has(k) or fired_dedup.has(dk):
			duplicates_blocked += 1
			continue
		if hold_ticks <= 0 or (int(ev["player"]) == local_slot and String(ev["kind"]) in INSTANT):
			_fire(ev)
		elif not pending.has(k):
			pending[k] = ev

func _fire(ev: Dictionary) -> void:
	var k: String = ev["key"]
	var dk: String = String(ev.get("dedup_key", k))
	fired[k] = ev["frame"]
	fired_dedup[dk] = ev["frame"]
	pending.erase(k)
	if not haptics_enabled and ev.has("haptic"):
		ev["haptic"] = "none"
	if bool(ev.get("sfx_loop", false)) and int(ev.get("duration_ticks", 0)) > 0:
		var sf := int(ev.get("frame", 0))
		active_loops[dk] = {
			"ev": ev,
			"start_frame": sf,
			"end_frame": sf + int(ev["duration_ticks"]),
			"player": int(ev.get("player", -1)),
			"stop_on_interrupt": bool(ev.get("stop_on_interrupt", true)),
		}
	if callback.is_valid():
		callback.call(ev)

func _stop_player_loops(player: int, reason: String) -> void:
	for dk: String in active_loops.keys():
		var lp: Dictionary = active_loops[dk]
		if int(lp.get("player", -1)) == player and bool(lp.get("stop_on_interrupt", true)):
			active_loops.erase(dk)
			loops_cancelled += 1
			if loop_stop_callback.is_valid():
				loop_stop_callback.call(lp["ev"], reason)

func begin_resim(from_frame: int) -> void:
	_resim_from = from_frame if _resim_from < 0 else mini(_resim_from, from_frame)
	_seen = {}
	_seen_dedup = {}

## Tras cada tick: cancela lo que la re-simulación ya no produjo y dispara lo confirmado o maduro.
func flush(confirmed: int, frame: int) -> void:
	if _resim_from >= 0:
		for k: String in pending.keys():
			if int(pending[k]["frame"]) >= _resim_from and not _seen.has(k):
				pending.erase(k)
				cancelled += 1
		for dk: String in active_loops.keys():
			var lp: Dictionary = active_loops[dk]
			if int(lp["start_frame"]) >= _resim_from and not _seen_dedup.has(dk):
				active_loops.erase(dk)
				fired_dedup.erase(dk)
				loops_cancelled += 1
				if loop_stop_callback.is_valid():
					loop_stop_callback.call(lp["ev"], "rollback")
		_resim_from = -1
	_seen = {}
	_seen_dedup = {}
	for dk2: String in active_loops.keys():
		var lp2: Dictionary = active_loops[dk2]
		if frame >= int(lp2["end_frame"]):
			active_loops.erase(dk2)
	for k: String in pending.keys():
		var ev: Dictionary = pending[k]
		var f := int(ev["frame"])
		if f <= confirmed or frame - 1 - f >= hold_ticks:
			_fire(ev)

## Marca como definitivos los eventos hasta `upto` según la lista confirmada y poda claves viejas.
func confirm(upto: int, confirmed_keys: Dictionary) -> void:
	for k: String in fired.keys():
		var fr: int = fired[k]
		if fr <= upto and not confirmed_keys.has(k) and fr >= 0:
			spurious += 1
			fired[k] = -1 - fr # ya contado
		if (fr if fr >= 0 else -1 - fr) < upto - keep_frames:
			fired.erase(k)
	for dk: String in fired_dedup.keys():
		var fr2: int = int(fired_dedup[dk])
		if fr2 < upto - keep_frames:
			fired_dedup.erase(dk)
