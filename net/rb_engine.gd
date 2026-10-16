class_name RbEngine
extends RefCounted
## Interfaz de simulación para RbSession. Por defecto: el prototipo mínimo RbSim.
func initial() -> PackedInt64Array:
	return RbSim.initial()
func step(s: PackedInt64Array, a: int, b: int) -> void:
	RbSim.step(s, a, b)
func checksum(s: PackedInt64Array) -> int:
	return RbSim.checksum(s)
## Ganchos de presentación (no afectan al estado): inicio de una re-simulación y fin de tick.
func on_rollback(_from_frame: int) -> void:
	pass
func after_tick(_confirmed: int, _frame: int) -> void:
	pass
