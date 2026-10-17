class_name BossAbilitiesExt
extends RefCounted
## Fachada de las 39 ampliadas. Los números viven en data/abilities/catalog.json (`source`).
## BossAbilities.def las lee. Esta clase queda para los menús que piden la lista.

static func has(id: String) -> bool:
	return id in BossAbilities.EXT_ORDER or id in BossAbilities.ORDER

static func def(id: String) -> Dictionary:
	return BossAbilities.def(id)

static func ids() -> Array:
	return BossAbilities.EXT_ORDER.duplicate()
