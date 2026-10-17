class_name Projectile
extends RefCounted
## Fase 8: los proyectiles viven en la sim (FightSim PR_*) y los dibuja SimView/SimWorld.
## Aquí solo queda la geometría de la arena que comparten la cámara, la vista y SimParams.
static var obstacles: Array[Vector3] = [] ## centros de pilares (x, radio, z)
static var arena_radius: float = 42.0
