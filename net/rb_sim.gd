class_name RbSim
extends RefCounted
## Simulación determinista reducida para el prototipo de rollback (fase online 0).
## Todo en enteros (punto fijo: 1 unidad = 1 mm, 1 tick = 1/60 s). Sin física de Godot,
## sin delta variable, sin RNG, sin nodos: el estado es un PackedInt64Array copiable.

const TICK_HZ := 60
const WALK := 83            # mm/tick (~5 m/s)
const ROLL_SPEED := 150     # mm/tick (~9 m/s)
const ROLL_FRAMES := 24
const IFRAME_FROM := 3
const IFRAME_TO := 15
const ATK_WINDUP := 12
const ATK_ACTIVE := 4
const ATK_RECOVERY := 14
const ATK_RANGE := 1800     # mm
const ATK_DAMAGE := 10
const HITSTUN := 18
const ROLL_BUFFER := 11     # ticks (~0.18 s) como el búfer de voltereta del juego
const ARENA := 10000
const RADIUS := 450
const HP_MAX := 100

# Bits de entrada (un int por jugador y tick)
const IN_LEFT := 1
const IN_RIGHT := 2
const IN_UP := 4
const IN_DOWN := 8
const IN_ROLL := 16
const IN_ATK := 32

# Disposición del estado por luchador
enum { X, Z, FX, FZ, HP, ROLL_T, ATK_T, ATK_HIT, STUN, RBUF, PREV_IN, FIELDS }
const FRAME := FIELDS * 2  # índice del contador de tick
const SIZE := FIELDS * 2 + 1

static func initial() -> PackedInt64Array:
	var s := PackedInt64Array()
	s.resize(SIZE)
	s[X] = -3000; s[FX] = 1; s[HP] = HP_MAX; s[ROLL_T] = -1; s[ATK_T] = -1
	var o := FIELDS
	s[o + X] = 3000; s[o + FX] = -1; s[o + HP] = HP_MAX; s[o + ROLL_T] = -1; s[o + ATK_T] = -1
	return s

static func _dir(inp: int) -> Vector2i:
	return Vector2i(int((inp & IN_RIGHT) != 0) - int((inp & IN_LEFT) != 0), int((inp & IN_DOWN) != 0) - int((inp & IN_UP) != 0))

## Avanza un tick. Modifica s en el sitio. Orden fijo: P0 y luego P1 para movimiento;
## los golpes se resuelven después para ambos con el estado ya movido (simétrico).
static func step(s: PackedInt64Array, in0: int, in1: int) -> void:
	_move(s, 0, in0)
	_move(s, FIELDS, in1)
	_separate(s)
	var h0 := _hits(s, 0, FIELDS)
	var h1 := _hits(s, FIELDS, 0)
	if h0: _apply_hit(s, FIELDS)
	if h1: _apply_hit(s, 0)
	s[FRAME] += 1

static func _move(s: PackedInt64Array, o: int, inp: int) -> void:
	var pressed := inp & ~s[o + PREV_IN]
	s[o + PREV_IN] = inp
	if s[o + HP] <= 0:
		return
	var d := _dir(inp)
	if pressed & IN_ROLL:
		s[o + RBUF] = ROLL_BUFFER
	elif s[o + RBUF] > 0:
		s[o + RBUF] -= 1
	if s[o + STUN] > 0:
		s[o + STUN] -= 1
		return
	if s[o + ROLL_T] >= 0:
		s[o + X] += s[o + FX] * ROLL_SPEED
		s[o + Z] += s[o + FZ] * ROLL_SPEED
		s[o + ROLL_T] += 1
		if s[o + ROLL_T] >= ROLL_FRAMES:
			s[o + ROLL_T] = -1
	elif s[o + ATK_T] >= 0:
		s[o + ATK_T] += 1
		if s[o + ATK_T] >= ATK_WINDUP + ATK_ACTIVE + ATK_RECOVERY:
			s[o + ATK_T] = -1
	else:
		if s[o + RBUF] > 0:
			s[o + RBUF] = 0
			if d != Vector2i.ZERO:
				s[o + FX] = d.x; s[o + FZ] = d.y
			s[o + ROLL_T] = 0
		elif pressed & IN_ATK:
			s[o + ATK_T] = 0
			s[o + ATK_HIT] = 0
		elif d != Vector2i.ZERO:
			s[o + FX] = d.x; s[o + FZ] = d.y
			s[o + X] += d.x * WALK
			s[o + Z] += d.y * WALK
	s[o + X] = clampi(s[o + X], -ARENA, ARENA)
	s[o + Z] = clampi(s[o + Z], -ARENA, ARENA)

static func _separate(s: PackedInt64Array) -> void:
	var dx := s[FIELDS + X] - s[X]
	var dz := s[FIELDS + Z] - s[Z]
	var min_d := RADIUS * 2
	if absi(dx) < min_d and absi(dz) < min_d:
		# empuje en el eje de mayor solape (entero, simétrico)
		if absi(dx) >= absi(dz):
			var p := (min_d - absi(dx)) / 2 + 1
			var sg := 1 if dx >= 0 else -1
			s[X] -= sg * p; s[FIELDS + X] += sg * p
		else:
			var p2 := (min_d - absi(dz)) / 2 + 1
			var sg2 := 1 if dz >= 0 else -1
			s[Z] -= sg2 * p2; s[FIELDS + Z] += sg2 * p2

static func _hits(s: PackedInt64Array, a: int, b: int) -> bool:
	var t := s[a + ATK_T]
	if t < ATK_WINDUP or t >= ATK_WINDUP + ATK_ACTIVE or s[a + ATK_HIT] != 0 or s[b + HP] <= 0:
		return false
	var rt := s[b + ROLL_T]
	if rt >= IFRAME_FROM and rt <= IFRAME_TO:
		return false
	var dx := s[b + X] - s[a + X]
	var dz := s[b + Z] - s[a + Z]
	if dx * dx + dz * dz > ATK_RANGE * ATK_RANGE:
		return false
	if dx * s[a + FX] + dz * s[a + FZ] <= 0: # delante del atacante
		return false
	s[a + ATK_HIT] = 1
	return true

static func _apply_hit(s: PackedInt64Array, b: int) -> void:
	s[b + HP] = maxi(s[b + HP] - ATK_DAMAGE, 0)
	s[b + STUN] = HITSTUN
	s[b + ATK_T] = -1
	s[b + ROLL_T] = -1

## Suma de comprobación portable (FNV-1a de 32 bits sobre los enteros), no depende de hash() del motor.
static func checksum(s: PackedInt64Array) -> int:
	var h := 2166136261
	for v in s:
		var x: int = v & 0xFFFFFFFF
		for k in 4:
			h = ((h ^ ((x >> (k * 8)) & 0xFF)) * 16777619) & 0xFFFFFFFF
	return h
