class_name SimFx
extends RefCounted
## Dispara efectos una sola vez por clave (tick, tipo, jugador) aunque el rollback re-simule.
## Un evento visto en una predicción que luego no se confirma ya se mostró (no se puede deshacer);
## se cuenta en `spurious` cuando confirm() lo descarta.
var fired: Dictionary = {}   # clave -> frame
var callback: Callable       # func(ev: Dictionary)
var keep_frames := 240
var spurious := 0
var duplicates_blocked := 0

func feed(events: Array) -> void:
	for ev: Dictionary in events:
		if fired.has(ev["key"]):
			duplicates_blocked += 1
			continue
		fired[ev["key"]] = ev["frame"]
		if callback.is_valid():
			callback.call(ev)

## Marca como definitivos los eventos hasta `upto` según la lista confirmada y poda claves viejas.
func confirm(upto: int, confirmed_keys: Dictionary) -> void:
	for k: String in fired.keys():
		var fr: int = fired[k]
		if fr <= upto and not confirmed_keys.has(k) and fr >= 0:
			spurious += 1
			fired[k] = -1 - fr # ya contado
		if (fr if fr >= 0 else -1 - fr) < upto - keep_frames:
			fired.erase(k)
