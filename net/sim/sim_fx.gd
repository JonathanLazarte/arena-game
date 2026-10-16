class_name SimFx
extends RefCounted
## Dispara efectos una sola vez por clave (tick, tipo, jugador) aunque el rollback re-simule.
## Online (hold_ticks > 0): los eventos se retienen hasta que su tick está confirmado o han pasado
## hold_ticks; si una re-simulación ya no los produce se cancelan sin mostrarse. Las acciones propias
## del jugador local (golpe, voltereta, disparo) salen al instante para no perder respuesta.
## Un evento ya mostrado que luego no se confirma se cuenta en `spurious` (confirm(), pruebas).
var fired: Dictionary = {}   # clave -> frame
var pending: Dictionary = {} # clave -> evento retenido
var callback: Callable       # func(ev: Dictionary)
var keep_frames := 240
var hold_ticks := 0
var local_slot := -1
const INSTANT := ["swing", "roll", "shot"]
var spurious := 0
var duplicates_blocked := 0
var cancelled := 0
var _resim_from := -1
var _seen: Dictionary = {}

func feed(events: Array) -> void:
	for ev: Dictionary in events:
		var k: String = ev["key"]
		_seen[k] = true
		if fired.has(k):
			duplicates_blocked += 1
			continue
		if hold_ticks <= 0 or (int(ev["player"]) == local_slot and String(ev["kind"]) in INSTANT):
			_fire(ev)
		elif not pending.has(k):
			pending[k] = ev

func _fire(ev: Dictionary) -> void:
	fired[ev["key"]] = ev["frame"]
	pending.erase(ev["key"])
	if callback.is_valid():
		callback.call(ev)

func begin_resim(from_frame: int) -> void:
	_resim_from = from_frame if _resim_from < 0 else mini(_resim_from, from_frame)
	_seen = {}

## Tras cada tick: cancela lo que la re-simulación ya no produjo y dispara lo confirmado o maduro.
func flush(confirmed: int, frame: int) -> void:
	if _resim_from >= 0:
		for k: String in pending.keys():
			if int(pending[k]["frame"]) >= _resim_from and not _seen.has(k):
				pending.erase(k)
				cancelled += 1
		_resim_from = -1
	_seen = {}
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
