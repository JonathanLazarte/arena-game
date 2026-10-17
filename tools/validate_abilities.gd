extends SceneTree
## Valida (y hornea) un catálogo de habilidades según docs/abilities_guide.md.
##   godot --headless --path . --script res://tools/validate_abilities.gd -- data/abilities/catalog.example.json
## Opciones: --strict (los avisos también fallan), --quiet (solo resumen).
## Sale con código 1 si hay errores (o avisos con --strict), 2 si falta el argumento.
const AC := preload("res://net/sim/ability_catalog.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var strict := false
	var quiet := false
	for a in args:
		if a == "--strict": strict = true
		elif a == "--quiet": quiet = true
		elif path == "": path = a
	if path == "":
		print("uso: godot --headless --path . --script res://tools/validate_abilities.gd -- <catalogo.json> [--strict] [--quiet]")
		quit(2)
		return
	if not path.begins_with("res://") and not path.begins_with("/") and not path.begins_with("user://"):
		path = "res://" + path
	var res: Dictionary = AC.load_file(path)
	if not quiet:
		var txt: String = AC.format_issues(res)
		if txt != "": print(txt)
	var ne: int = (res["errors"] as Array).size()
	var nw: int = (res["warnings"] as Array).size()
	if res["ok"]:
		var b: Dictionary = res["baked"]
		print("OK %s: %d habilidades, %d presets, %d avisos · hash %08x" % [path, (b["abilities"] as Array).size(), (b["presets"] as Array).size(), nw, int(res["hash"])])
	else:
		print("FALLÓ %s: %d errores, %d avisos" % [path, ne, nw])
	quit(1 if ne > 0 or (strict and nw > 0) else 0)
