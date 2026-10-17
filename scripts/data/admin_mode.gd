class_name AdminMode
extends RefCounted
## Modo admin / depuración para pruebas:
## - Jugador: vida, aguante y maná infinitos, frascos llenos, medidor de eikon listo.
## - Rival: inmortal (recibe daño y muestra cifras, pero se regenera al bajar del 30 % y nunca muere).
## - Habilidades: acceso simultáneo y ciclado a las 58 habilidades del catálogo de jefes.
## - Conmutación en cualquier momento mediante F1, botón en el HUD o menú de pausa.

static var enabled: bool = false:
	set(v):
		if enabled != v:
			enabled = v
			if on_toggled.is_valid():
				on_toggled.call(enabled)

static var on_toggled: Callable

static func toggle() -> bool:
	enabled = not enabled
	return enabled
