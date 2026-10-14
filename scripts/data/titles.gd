class_name Titles
## Ronda 30: títulos/emblemas que se ganan con la ficha del personaje (victorias, partidas, nivel,
## tiempo jugado). Se muestran junto al nombre y dan una bonificación pequeña (mismo formato de
## efectos que Trinkets). Uno equipado por personaje.

const TITLES := {
	"recien_llegado": {"name": "Recién Llegado", "desc": "Sin bonificación.", "cond": ["matches", 0], "fx": {}},
	"vencedor": {"name": "Vencedor", "desc": "5 victorias · −2 % de gasto de aguante.", "cond": ["wins", 5], "fx": {"stamina_cost": 0.98}},
	"curtido": {"name": "Curtido", "desc": "Nivel 5 · +2 % de daño cuerpo a cuerpo.", "cond": ["level", 5], "fx": {"dmg_todo": 1.02}},
	"veterano": {"name": "Veterano de la Arena", "desc": "20 partidas · +5 de equilibrio.", "cond": ["matches", 20], "fx": {"poise": 5.0}},
	"incansable": {"name": "Incansable", "desc": "1 h jugada · medidor de eikon +5 %.", "cond": ["hours", 1], "fx": {"eikon_rate": 1.05}},
	"campeon": {"name": "Campeón del Círculo", "desc": "25 victorias · +3 % de daño y +5 de equilibrio.", "cond": ["wins", 25], "fx": {"dmg_todo": 1.03, "poise": 5.0}},
}
const ORDER := ["recien_llegado", "vencedor", "curtido", "veterano", "incansable", "campeon"]

static func def(id: String) -> Dictionary:
	return TITLES.get(id, {})

## ¿Cumple la ficha (stats = GameState.char_stat() + "level") la condición del título?
static func earned(id: String, stats: Dictionary) -> bool:
	var t := def(id)
	if t.is_empty():
		return false
	var c: Array = t["cond"]
	match String(c[0]):
		"wins": return int(stats.get("wins", 0)) >= int(c[1])
		"matches": return int(stats.get("matches", 0)) >= int(c[1])
		"level": return int(stats.get("level", 1)) >= int(c[1])
		"hours": return float(stats.get("secs", 0.0)) >= float(c[1]) * 3600.0
	return false
