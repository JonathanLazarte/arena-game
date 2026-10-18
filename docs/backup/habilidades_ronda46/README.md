# Respaldo de habilidades — ronda 46

Copia de las 45 habilidades de jefe tal como estaban antes del catálogo por pasos.
No están migradas. El juego sigue usando los originales.

La carpeta tiene `.gdignore` y las copias no declaran `class_name`. Si lo declararan,
Godot registraría el respaldo en lugar de los scripts vivos.

- `scripts/data/boss_abilities.gd` (6 base)
- `scripts/combat/boss_abilities_ext.gd` (39 ampliadas)

Las habilidades nuevas (Hoja Escarlata) viven en `data/abilities/hoja_escarlata_catalog.json`
y se ejecutan aparte (`AbilityCatalog` / `SimCatalog`). Estas 45 no se reescribieron.
