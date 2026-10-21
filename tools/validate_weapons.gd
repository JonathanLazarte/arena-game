extends SceneTree
## Valida data/weapons/weapons.json (ver docs/WEAPON_GUIDE.md).
##   godot --headless --path . --script res://tools/validate_weapons.gd [-- otro.json] [--strict]
## Sale con 1 si hay errores (o avisos con --strict).

func _initialize() -> void:
	var path := WeaponAttacher.PATH
	var strict := false
	for a in OS.get_cmdline_user_args():
		if a == "--strict": strict = true
		else: path = a if a.begins_with("res://") or a.begins_with("/") else "res://" + a
	if not FileAccess.file_exists(path):
		print("FALLÓ: no existe %s" % path)
		quit(1)
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not v is Dictionary:
		print("FALLÓ %s: JSON inválido" % path)
		quit(1)
		return
	var ids: Array = []
	for w in Catalog.weapons():
		ids.append(w.id)
	var r := WeaponAttacher.validate(v, ids)
	for e: String in r["errors"]: print("ERROR  " + e)
	for w: String in r["warnings"]: print("AVISO  " + w)
	var ws: Dictionary = (v as Dictionary).get("weapons", {})
	for id: String in ids:
		if not ws.has(id):
			print("AVISO  weapons.%s: arma del catálogo sin entrada" % id)
	var ne: int = (r["errors"] as Array).size()
	var nw: int = (r["warnings"] as Array).size()
	print(("OK %s: %d armas, %d avisos" if ne == 0 else "FALLÓ %s: %d armas, %d errores") % [path, ws.size(), nw if ne == 0 else ne])
	quit(1 if ne > 0 or (strict and nw > 0) else 0)
