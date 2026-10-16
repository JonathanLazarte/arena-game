class_name RbEngine
extends RefCounted
## Interfaz de simulación para RbSession. Por defecto: el prototipo mínimo RbSim.
func initial() -> PackedInt64Array:
	return RbSim.initial()
func step(s: PackedInt64Array, a: int, b: int) -> void:
	RbSim.step(s, a, b)
func checksum(s: PackedInt64Array) -> int:
	return RbSim.checksum(s)
