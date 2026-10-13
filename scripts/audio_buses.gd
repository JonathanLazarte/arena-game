class_name AudioMgrBuses
## Crea los buses de audio si faltan (Sfx se carga antes que Audio).
static func ensure() -> void:
	for b: String in ["Música", "Efectos", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
