class_name Fighter
extends CharacterBody3D
## Jinete / personaje. Puede ir montado (usa los MountData de su Mount) o a pie
## (usa on_foot.tres). Los controladores (jugador/IA) rellenan move_input,
## want_block y want_sprint y llaman a sword()/shoot()/summon()/dash()/toggle_mount().
## Cualquier nodo en el grupo "damageable" con team, alive, hit_radius, take_hit()
## y get_hit_center() puede ser objetivo (eikons ahora, mobs en el futuro).

signal health_changed(value: float, max_value: float)
signal meter_changed(value: float)
signal stamina_changed(value: float, exhausted: bool)
signal died(fighter: Fighter)
signal summoned(eikon: Node3D)
## Se pulsó invocar sin poder hacerlo: "meter" (medidor sin llenar), "active" (ya hay uno) o "stun".
signal summon_failed(reason: String)
signal impact(strength: float)
signal mount_changed(mounted: bool)
signal loadout_changed(loadout: int)
signal landed_hit(target: Node3D, result: String, target_was_open: bool)

const METER_MAX := 100.0
const METER_PASSIVE := 1.2 ## por segundo en combate (sin eikon activo); con golpes se llena en ~35-45 s
var meter_passive: bool = true
const GRAVITY := 20.0
const SWORD_DAMAGE := 12.0
const SWORD_RANGE_MOUNTED := 3.4
const SWORD_RANGE_FOOT := 2.2
const SWORD_HALF_ARC_MOUNTED := deg_to_rad(100.0) ## frente y lados
const SWORD_HALF_ARC_FOOT := deg_to_rad(70.0)
## Ataques estilo souls: anticipación (telegrafiada) -> frames activos -> recuperación vulnerable.
const LIGHT := {"windup": 0.45, "chain_windup": 0.45, "active": 0.12, "recovery": 0.6, "whiff": 0.3, "damage": 12.0, "stamina": 14.0}
const HEAVY := {"windup": 0.8, "chain_windup": 0.8, "active": 0.15, "recovery": 0.75, "whiff": 0.35, "damage": 26.0, "stamina": 28.0}
const MAX_COMBO := 3
const FINISHER_EXTRA_RECOVERY := 0.3 ## el último golpe del combo deja más expuesto
const CHAIN_MIN_RECOVERY := 0.3 ## un encadenado no se salta toda la recuperación
const ROLL_CANCEL_FRACTION := 0.5 ## voltereta/dash permitido en la 2.ª mitad de la recuperación
## Voltereta a pie estilo Dark Souls (frames a 30 fps; ver README "Ronda 9" para las fuentes).
## DS1 fast roll (25 % de carga): 24 frames en total; 11-13 de invulnerabilidad.
const ROLL_FPS := 30.0
const ROLL_STARTUP_FRAMES := 2 ## vulnerable: el cuerpo aún no ha bajado
const ROLL_IFRAMES := 12 ## invulnerable (DS1 fast 11-13, DS3 12-13)
const ROLL_RECOVERY_FRAMES := 10 ## vulnerable: levantarse; no se puede atacar, bloquear ni volver a rodar
const ROLL_STARTUP := ROLL_STARTUP_FRAMES / ROLL_FPS
const ROLL_IFRAME_END := (ROLL_STARTUP_FRAMES + ROLL_IFRAMES) / ROLL_FPS
const ROLL_TOTAL := (ROLL_STARTUP_FRAMES + ROLL_IFRAMES + ROLL_RECOVERY_FRAMES) / ROLL_FPS
const ROLL_DISTANCE := 4.5 ## m (casi todo durante el arranque y los i-frames)
const ROLL_RECOVERY_DRIFT := 0.4 ## m extra que se desliza al levantarse
## Dash montado + ataque: la anticipación sigue durante el dash y el golpe sale al acabarlo.
const DASH_STRIKE_MIN_TIME := 0.12 ## anticipación mínima (s) de un ataque ligado al dash antes de golpear
const HEAVY_HOLD := 0.4 ## mantener ataque este tiempo = ataque fuerte
## Ronda 14: GOLPE CON DASH a pie (estocada en carrera). Sale de 2 maneras, con búfer generoso:
##  - atacar en cualquier momento del arranque o de los i-frames de la voltereta: al acabar los
##    i-frames la voltereta se convierte en la estocada (se salta la recuperación de la voltereta);
##  - hacer dash durante la anticipación de un ligero: el ligero se convierte en la estocada.
## Durante la anticipación y los frames activos avanza (lunge) hacia el rival.
const DASH_STRIKE := {"windup": 0.16, "chain_windup": 0.16, "active": 0.14, "recovery": 0.5, "whiff": 0.25, "damage": 15.0, "stamina": 10.0}
const LUNGE_SPEED := 12.0 ## m/s durante la estocada (≈2,5 m)
## Salto (Espacio / botón "Saltar"): a pie salto completo; montado en lobo o grifo, un brinco
## de la montura; en el fénix no hace falta (ya vuela). En el aire los golpes de área en el
## suelo (GroundAoE) no alcanzan. Al caer hay una breve recuperación.
const JUMP_VELOCITY := 8.0 ## ≈0,8 s en el aire, 1,6 m de altura
const MOUNT_HOP_MULT := 0.85
const COST_JUMP := 12.0
const LAND_RECOVERY := 0.18
const AIR_CONTROL := 0.35
## Ataque en salto: picado. Cae rápido y golpea al aterrizar cerca.
const JUMP_ATTACK := {"windup": 0.22, "chain_windup": 0.22, "active": 0.12, "recovery": 0.45, "whiff": 0.2, "damage": 16.0, "stamina": 14.0}
## Habilidad "Golpe sísmico" (Berserker): área en el suelo con aviso.
const SLAM_RADIUS := 5.0
const SLAM_TELEGRAPH := 0.7
const SLAM_DAMAGE := 22.0
const SLAM_COOLDOWN := 8.0
const COST_SLAM := 25.0
const POISE_MAX := 50.0
const POISE_REGEN := 25.0
## Ronda 15: cambio arco<->cuerpo a cuerpo rápido (antes 2 s). Nunca bloquea el movimiento;
## solo atacar/disparar/bloquear quedan fuera durante el cambio.
const SWAP_TIME := 0.42
## Correr a pie fijado: hacia atrás se corre algo más lento que de frente (estilo souls).
const RUN_BACK_FACTOR := 0.8
const PARRY_STAGGER := 1.6
const RIPOSTE_MULT := 1.8
enum Atk { NONE, WINDUP, ACTIVE, RECOVERY }
enum Loadout { SWORD_SHIELD, BOW }
const BOW_COOLDOWN := 1.0
## Parry = acción propia (no depende del escudo): ventana activa corta y luego recuperación vulnerable.
const PARRY_WINDOW := 0.3
const PARRY_RECOVERY := 0.8
const PARRY_EXPOSED_MULT := 1.25 ## daño extra recibido durante la recuperación del parry
const COST_PARRY := 15.0
enum Parry { NONE, ACTIVE, RECOVERY }
const BLOCK_REDUCTION := 0.12 ## bloqueo de cuerpo a cuerpo: solo pasa un 12 % (chip)
const EXHAUSTED_BLOCK_REDUCTION := 0.6
const REVERSE_FACTOR := 0.5
const DASH_DAMAGE := 6.0
const DASH_KNOCKBACK := 16.0
const SEPARATION := 3.0
const SEPARATION_FOOT := 1.6
const MOUNT_REACH := 3.5
const HEAVY_HIT := 14.0 ## golpes de este daño o más pueden derribar
# Aguante (stamina)
const STAMINA_MAX := 100.0
const COST_DASH := 25.0
const COST_ROLL := 20.0
const COST_SWORD := 12.0
const COST_BOW := 6.0
const COST_BLOCKED_HIT := 22.0 ## por golpe ligero bloqueado: ~4-5 golpes con la barra llena
const COST_BLOCKED_HEAVY_MULT := 2.0
const COST_BLOCKED_ARROW := 3.0 ## las flechas bloqueadas no hacen daño
const GUARD_BREAK_STAGGER := 1.0
const EIKON_BLOCK_PASS := 0.5 ## ataque de eikon bloqueado: pasa el 50 % del daño
const COST_BLOCKED_EIKON := 30.0 ## y cuesta más aguante que un golpe ligero
const DRAIN_BLOCK := 3.0 ## por segundo (mantener el escudo; poco para no romper el objetivo de 4-5 golpes)
const DRAIN_SPRINT := 20.0 ## por segundo
const REGEN := 18.0
const REGEN_IDLE := 32.0
const REGEN_DELAY := 0.6
const EXHAUST_TIME := 1.5

## Sigue existiendo por compatibilidad: montura inicial.
@export var mount: MountData
@export var eikon: EikonData
var foot_stats: MountData = preload("res://resources/mounts/on_foot.tres")
## Ronda 10: personaje (rol) y arma. Sin asignar = luchador neutro (stats del Caballero sin
## pasiva) con espada y escudo: el comportamiento clásico en el que se basan las pruebas antiguas.
var character: CharacterDef = _neutral()
var weapon: WeaponDef = preload("res://resources/weapons/espada_escudo.tres")
const FALLBACK_MELEE := preload("res://resources/weapons/dagas.tres") ## cuerpo a cuerpo del que lleva arco
var stamina_max: float = STAMINA_MAX
var poise_max: float = POISE_MAX
var heals: float = 0.0 ## vida curada por la pasiva (pruebas)
## Ronda 11: modificadores de las habilidades desbloqueadas (Progression.combine_mods).
var mods: Dictionary = Progression.combine_mods([])
var parry_window: float = PARRY_WINDOW
var hits_landed: int = 0 ## golpes conectados en la partida (XP)
var team: int = 0
var color: Color = Color(0.2, 0.4, 1.0)
var display_name: String = "Jugador"
var opponent: Fighter

var max_health: float = 100.0
var health: float = 100.0
var meter: float = 0.0
var stamina: float = STAMINA_MAX
var exhausted: float = 0.0
var alive: bool = true
var hit_radius: float = 1.3
## Probabilidad de derribo al recibir un dash / golpe fuerte estando montado.
var knockoff_chance_dash: float = 0.5
var knockoff_chance_heavy: float = 0.6

# Entrada de los controladores
var move_input: Vector3 = Vector3.ZERO
var want_block: bool = false
var want_sprint: bool = false

var facing: Vector3 = Vector3.FORWARD
var face_target: Node3D = null ## lock-on
var planar_vel: Vector3 = Vector3.ZERO
var dash_dir: Vector3 = Vector3.FORWARD
var invuln: float = 0.0
var knock: Vector3 = Vector3.ZERO
var reversing: bool = false
var sprinting: bool = false
var blocking: bool = false
var block_time: float = 0.0
var parry_state: Parry = Parry.NONE
var parry_t: float = 0.0
var parries_landed: int = 0
var guard_breaks: int = 0
var stun: float = 0.0
var atk_state: Atk = Atk.NONE
var atk_heavy: bool = false
var atk_t: float = 0.0
var atk_dur: float = 0.0
var combo: int = 0
var attacks_started: int = 0
var _atk_landed: bool = false
var _atk_hit: Array[Node3D] = []
var _buffered: bool = false
var poise: float = POISE_MAX
var _since_hit: float = 10.0
var riposte_t: float = 0.0 ## tras sufrir un parry: recibe daño extra
var loadout: Loadout = Loadout.SWORD_SHIELD
var swap_t: float = 0.0
var swap_from: int = Loadout.SWORD_SHIELD ## arma que se enfunda durante el cambio
var bow_cd: float = 0.0
var dash_time: float = 0.0
var dash_cd: float = 0.0
var roll_t: float = -1.0 ## tiempo dentro de la voltereta a pie (-1 = sin voltereta)
var rolls_dodged: int = 0 ## golpes evitados con i-frames de voltereta (pruebas)
var dash_strikes: int = 0 ## ataques que salieron al final de un dash montado (pruebas)
var _dash_atk: bool = false ## hay un ataque en anticipación ligado al dash actual
var active_eikon: Node3D = null
# --- Ronda 14 ---
var atk_dash: bool = false ## el ataque actual es la estocada con dash (a pie)
var _ds_visual: bool = false ## el ataque actual va ligado a un dash (a pie o montado): animación Dash_Strike
var _roll_atk_buffer: bool = false ## se pulsó atacar durante la voltereta
var atk_jump: bool = false ## ataque en salto
var airborne: bool = false
var _air_t: float = 0.0
var _jump_v: float = 0.0
var land_t: float = 0.0
var jumps: int = 0
var aoe_jumped: int = 0 ## golpes de área esquivados en el aire (pruebas / IA)
var special_cd: float = 0.0
var special_t: float = 0.0 ## anticipación del golpe sísmico
var specials_used: int = 0
var eikon_specials: int = 0

var mounted: bool = false
var mount_node: Mount = null ## montura actual (si está montado)
var owned_mount: Mount = null ## su montura (para volver a montar)

var _since_spend: float = 10.0
var _dash_hit: bool = false
var _rider_root: Node3D
var _sword_pivot: Node3D
var _blade: MeshInstance3D
var _bow: MeshInstance3D
var _blade_mat: StandardMaterial3D
var _shield: MeshInstance3D
var _body: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _kv: KnightVisual ## modelo animado (solo visual)
var _prim: Node3D ## primitivas antiguas (ocultas; pivote de espada)
var _col_shape: BoxShape3D
var _col: CollisionShape3D
var _flash: float = 0.0

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("fighter")
	_apply_character()
	_build_visuals()
	_apply_mount_visuals()

## Asigna personaje y arma (antes de añadir el luchador al árbol).
func set_loadout_defs(c: CharacterDef, w: WeaponDef) -> void:
	character = c if c else character
	weapon = w if w and character.allows(w.id) else Catalog.weapon(character.default_weapon)

static func _neutral() -> CharacterDef:
	var c := CharacterDef.new()
	c.passive_id = ""
	c.weapons = PackedStringArray(["espada_escudo", "espada_larga", "hacha_2m", "dagas", "lanza", "arco"])
	return c

## Habilidades del árbol del personaje (antes de añadir al árbol o seguido de _apply_character()).
func set_skills(skills: Array) -> void:
	mods = Progression.combine_mods(skills)

## Potencia de la pasiva (1.0 = base; las habilidades la suben).
func passive_k() -> float:
	return 1.0 + float(mods["passive"])

func _apply_character() -> void:
	max_health = character.vida + float(mods["vida"]) + (mount.health_bonus if mount else 0.0)
	health = max_health
	stamina_max = character.estamina + float(mods["estamina"])
	stamina = stamina_max
	poise_max = character.poise + float(mods["poise"])
	parry_window = PARRY_WINDOW + float(mods["parry_window"])
	poise = poise_max
	if weapon.ranged:
		loadout = Loadout.BOW

## Arma cuerpo a cuerpo efectiva (el arquero usa dagas al cambiar de arma).
func melee() -> WeaponDef:
	return FALLBACK_MELEE if weapon.ranged else weapon

func has_shield() -> bool:
	return melee().allows_shield and character.shield_mesh != ""

func stats() -> MountData:
	return mount_node.data if mounted and mount_node else foot_stats

func speed_mult() -> float:
	return character.velocidad * float(mods["velocidad"])

func sword_range() -> float:
	return melee().reach_mounted if mounted else melee().reach_foot

func sword_half_arc() -> float:
	return deg_to_rad(melee().half_arc_mounted_deg if mounted else melee().half_arc_foot_deg)

func max_combo() -> int:
	return melee().max_combo

## ¿Toca el suelo? (para los golpes de área en el suelo). En el fénix se vuela.
func is_grounded() -> bool:
	if mounted and mount_node and mount_node.is_flying():
		return false
	return not airborne and global_position.y < GroundAoE.GROUND_HEIGHT

func is_dash_striking() -> bool:
	return atk_state != Atk.NONE and (_ds_visual or atk_dash)

func roll_iframe_end() -> float:
	return ROLL_IFRAME_END + (character.roll_iframe_bonus + int(mods["roll_iframes"])) / ROLL_FPS

## "none", "startup", "iframes" o "recovery".
func roll_phase() -> String:
	if roll_t < 0.0:
		return "none"
	if roll_t < ROLL_STARTUP:
		return "startup"
	if roll_t < roll_iframe_end():
		return "iframes"
	return "recovery"

func is_rolling() -> bool:
	return roll_t >= 0.0

func is_exhausted() -> bool:
	return exhausted > 0.0

func _build_visuals() -> void:
	_col = CollisionShape3D.new()
	_col_shape = BoxShape3D.new()
	_col.shape = _col_shape
	add_child(_col)
	_rider_root = Node3D.new()
	add_child(_rider_root)
	_prim = Node3D.new()
	_prim.visible = false
	_rider_root.add_child(_prim)
	_kv = KnightVisual.new()
	_rider_root.add_child(_kv)
	_kv.setup(color, character, weapon)
	_body = MeshUtil.box(_prim, Vector3(0.6, 1.0, 0.45), Vector3(0, 1.0, 0.1), color)
	MeshUtil.sphere(_prim, 0.25, Vector3(0, 1.75, 0.1), Color(0.95, 0.8, 0.65))
	for x: float in [-0.15, 0.15]:
		_legs.append(MeshUtil.box(_prim, Vector3(0.2, 0.55, 0.25), Vector3(x, 0.27, 0.1), color.darkened(0.4)))
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.45, 1.1, 0.0)
	_prim.add_child(_sword_pivot)
	_blade = MeshUtil.box(_sword_pivot, Vector3(0.1, 0.1, 1.0), Vector3(0, 0, -0.5), Color(0.85, 0.85, 0.95))
	MeshUtil.box(_sword_pivot, Vector3(0.4, 0.08, 0.08), Vector3(0, 0, 0), Color(0.6, 0.5, 0.2)) # guarda
	_blade_mat = _blade.material_override as StandardMaterial3D
	# Armas visibles: espada y escudo del KayKit (BoneAttachment3D handslot.r / handslot.l) y arco propio
	_bow = _kv.bow
	_shield = _kv.shield

func _apply_mount_visuals() -> void:
	_rider_root.position.y = 1.3 if mounted else 0.0
	for l in _legs:
		l.visible = not mounted
	# Espada más larga montado (alcance real)
	var blade_len := 2.2 if mounted else 1.4
	(_blade.mesh as BoxMesh).size = Vector3(0.1, 0.1, blade_len)
	_blade.position = Vector3(0, 0, -blade_len * 0.5)
	_kv.set_mounted(mounted, 1.5 if mounted else 1.0)
	if mounted:
		_col_shape.size = Vector3(1.2, 2.4, 2.4)
		_col.position = Vector3(0, 1.2, 0)
		hit_radius = 1.3
	else:
		_col_shape.size = Vector3(0.7, 1.9, 0.7)
		_col.position = Vector3(0, 0.95, 0)
		hit_radius = 0.75

# ---------------- Montar / desmontar ----------------

func mount_on(m: Mount) -> bool:
	if m == null or not m.can_ride(self) or mounted:
		return false
	mounted = true
	mount_node = m
	m.set_rider(self)
	global_position = Vector3(m.global_position.x, global_position.y, m.global_position.z)
	_apply_mount_visuals()
	mount_changed.emit(true)
	return true

func dismount(forced: bool = false) -> void:
	if not mounted:
		return
	var m := mount_node
	mounted = false
	mount_node = null
	var side := facing.cross(Vector3.UP)
	m.global_position = global_position
	m.set_rider(null)
	global_position += side * -1.6 + Vector3(0, 0.1, 0)
	planar_vel = Vector3.ZERO
	dash_time = 0.0
	_apply_mount_visuals()
	if forced:
		apply_stun(0.6)
	mount_changed.emit(false)

func nearest_free_mount() -> Mount:
	var best: Mount = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("mount"):
		var m := n as Mount
		if m and m.can_ride(self):
			var d := global_position.distance_to(m.global_position)
			if d < bd:
				bd = d
				best = m
	# Preferir la propia si está a la misma distancia aproximada
	if is_instance_valid(owned_mount) and owned_mount.can_ride(self) and global_position.distance_to(owned_mount.global_position) <= bd + 1.0:
		return owned_mount
	return best

func can_remount() -> bool:
	var m := nearest_free_mount()
	return m != null and global_position.distance_to(m.global_position) <= MOUNT_REACH

## Acción "Montar": monta si hay montura libre cerca, desmonta si va montado.
func toggle_mount() -> bool:
	if not alive or stun > 0.0 or atk_state != Atk.NONE or swap_t > 0.0 or airborne or special_t > 0.0:
		return false
	if mounted:
		dismount(false)
		return true
	if can_remount():
		return mount_on(nearest_free_mount())
	return false

# ---------------- Aguante ----------------

func spend_stamina(v: float) -> void:
	stamina = maxf(stamina - v, 0.0)
	_since_spend = 0.0
	if stamina <= 0.0 and exhausted <= 0.0:
		exhausted = EXHAUST_TIME
		sprinting = false
	stamina_changed.emit(stamina, exhausted > 0.0)

func _update_stamina(delta: float, idle: bool) -> void:
	_since_spend += delta
	if exhausted > 0.0:
		exhausted = maxf(exhausted - delta, 0.0)
	if _since_spend >= REGEN_DELAY and stamina < stamina_max:
		stamina = minf(stamina + (REGEN_IDLE if idle else REGEN) * delta, stamina_max)
		stamina_changed.emit(stamina, exhausted > 0.0)

# ---------------- Bucle principal ----------------

func _physics_process(delta: float) -> void:
	riposte_t = maxf(riposte_t - delta, 0.0)
	_since_hit += delta
	if _since_hit > 1.5:
		poise = minf(poise + POISE_REGEN * delta, poise_max)
	# Pasiva "Luz sanadora": se cura si lleva 3 s sin recibir golpes
	if character.passive_id == "luz_sanadora" and alive and _since_hit > 3.0 and health < max_health:
		var hv := minf(2.0 * passive_k() * delta, max_health - health)
		health += hv
		heals += hv
		health_changed.emit(health, max_health)
	if swap_t > 0.0:
		swap_t -= delta
		if swap_t <= 0.0:
			swap_t = 0.0
			loadout = Loadout.BOW if loadout == Loadout.SWORD_SHIELD else Loadout.SWORD_SHIELD
			_apply_loadout_visuals()
			loadout_changed.emit(loadout)
	_update_attack(delta)
	_update_parry(delta)
	if meter_passive and alive and meter < METER_MAX and not is_instance_valid(active_eikon):
		add_meter(METER_PASSIVE * delta)
	bow_cd = maxf(bow_cd - delta, 0.0)
	dash_cd = maxf(dash_cd - delta, 0.0)
	special_cd = maxf(special_cd - delta, 0.0)
	land_t = maxf(land_t - delta, 0.0)
	if special_t > 0.0:
		special_t = maxf(special_t - delta, 0.0)
	var was_dashing := dash_time > 0.0
	dash_time = maxf(dash_time - delta, 0.0)
	if roll_t >= 0.0:
		roll_t += delta
		if _roll_atk_buffer and roll_t >= roll_iframe_end() and alive and stun <= 0.0:
			# Búfer: la voltereta enlaza con la estocada (sin recuperación de voltereta)
			roll_t = -1.0
			dash_time = 0.0
			_roll_atk_buffer = false
			_start_dash_strike()
		elif roll_t >= ROLL_TOTAL or not alive:
			roll_t = -1.0
			_roll_atk_buffer = false
	if was_dashing and dash_time <= 0.0:
		_on_dash_end()
	stun = maxf(stun - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	var st := stats()
	var inp := move_input
	if not alive or stun > 0.0 or special_t > 0.0:
		inp = Vector3.ZERO
	var wb := want_block and alive and stun <= 0.0 and roll_t < 0.0 and loadout == Loadout.SWORD_SHIELD and swap_t <= 0.0 and atk_state == Atk.NONE and parry_state == Parry.NONE
	if wb and not blocking:
		block_time = 0.0
	blocking = wb
	if blocking:
		block_time += delta
		spend_stamina(DRAIN_BLOCK * delta)
	inp.y = 0.0
	var amount := minf(inp.length(), 1.0)
	var target_vel := Vector3.ZERO
	var turn := st.turn_speed * delta
	reversing = false
	var run_req := want_sprint and amount > 0.3 and exhausted <= 0.0 and not blocking and stamina > 0.0
	if _lock_valid():
		var d := MeshUtil.flat(face_target.global_position - global_position)
		if d.length() > 0.1:
			facing = _turn_toward(facing, d.normalized(), turn * 1.8)
		if amount > 0.05:
			var dirn := inp.normalized()
			var fdot := dirn.dot(facing)
			var k := lerpf(0.8, 1.0, fdot) if fdot >= 0.0 else lerpf(0.8, REVERSE_FACTOR, -fdot)
			reversing = fdot < -0.6
			if run_req and not mounted:
				# Ronda 15: corriendo fijado NO se da la vuelta: sigue mirando al rival y
				# corre de espaldas o en diagonal/lateral (strafe).
				k = lerpf(0.9, 1.0, fdot) if fdot >= 0.0 else lerpf(0.9, RUN_BACK_FACTOR, -fdot)
			target_vel = dirn * st.speed * speed_mult() * amount * k
	elif amount > 0.05:
		var dirn := inp.normalized()
		if dirn.dot(facing) < -0.6 and not (run_req and not mounted):
			reversing = true
			target_vel = -facing * st.speed * speed_mult() * REVERSE_FACTOR * amount
		else:
			# Sin fijar, correr gira al personaje con normalidad.
			facing = _turn_toward(facing, dirn, turn * (1.4 if run_req and not mounted else 1.0))
			target_vel = facing * st.speed * speed_mult() * amount
	# Galope (montado, igual que antes) / correr a pie (también de espaldas si va fijado)
	sprinting = run_req and (not reversing or (not mounted and _lock_valid()))
	if sprinting:
		target_vel *= st.sprint_multiplier
		spend_stamina(DRAIN_SPRINT * delta)
	if blocking:
		target_vel *= 0.45
	if exhausted > 0.0:
		target_vel *= 0.6
	if atk_state != Atk.NONE:
		target_vel *= 0.55 if mounted else 0.3 # compromiso: casi no te mueves al atacar
	if land_t > 0.0:
		target_vel *= 0.4
	_update_stamina(delta, amount < 0.3 or reversing)
	planar_vel = planar_vel.move_toward(target_vel, st.acceleration * delta * (AIR_CONTROL if airborne else 1.0))
	var v := planar_vel
	if atk_dash and not mounted and (atk_state == Atk.WINDUP or atk_state == Atk.ACTIVE):
		v = _lunge_velocity()
		planar_vel = v * 0.5
	elif roll_t >= 0.0:
		v = _roll_velocity()
		planar_vel = v
	elif dash_time > 0.0:
		v = dash_dir * st.dash_speed
		if mounted:
			_check_dash_hit()
	v += knock
	knock = knock.move_toward(Vector3.ZERO, 40.0 * delta)
	var my_sep := SEPARATION if mounted else SEPARATION_FOOT
	for n in get_tree().get_nodes_in_group("fighter"):
		if n != self:
			var other := n as Fighter
			var min_sep := maxf(my_sep, SEPARATION if other.mounted else SEPARATION_FOOT)
			var sep := MeshUtil.flat(global_position - other.global_position)
			var sl := sep.length()
			if sl < min_sep:
				v += (sep.normalized() if sl > 0.01 else facing.cross(Vector3.UP)) * (min_sep - sl) * 8.0
	velocity.x = v.x
	velocity.z = v.z
	if _jump_v > 0.0:
		velocity.y = _jump_v
		_jump_v = 0.0
	elif is_on_floor() and not airborne:
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta * (1.8 if atk_jump else 1.0)
	move_and_slide()
	if airborne:
		_air_t += delta
		if _air_t > 0.08 and (is_on_floor() or global_position.y < 0.02) and velocity.y <= 0.0:
			_land()
	rotation.y = atan2(-facing.x, -facing.z)
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	# Visuales
	var sy := _rider_root.position.y
	if _flash > 0.0:
		_flash -= delta
	var bc := color
	if _flash > 0.0:
		bc = Color.WHITE
	elif exhausted > 0.0:
		bc = color.lerp(Color(0.5, 0.5, 0.5), 0.6)
	(_body.material_override as StandardMaterial3D).albedo_color = bc
	_kv.set_tint(bc, _flash > 0.0)
	_kv.update(self, delta)
	_rider_root.rotation.x = 0.0 # la voltereta la hace la animación Dodge_*
	_rider_root.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2 if stun > 0.0 else 0.0
	_rider_root.position.y = sy
	if mounted and mount_node:
		# Sentado en la silla: la cadera sigue el punto de silla del caballo
		_rider_root.position = to_local(mount_node.saddle_position())

func _lock_valid() -> bool:
	return is_instance_valid(face_target) and bool(face_target.get("alive"))

static func _turn_toward(from: Vector3, to: Vector3, max_step: float) -> Vector3:
	var ang := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(ang, -max_step, max_step)).normalized()

func _check_dash_hit() -> void:
	if _dash_hit:
		return
	for t in MeshUtil.enemies_of(get_tree(), team):
		var d := MeshUtil.flat(t.global_position - global_position)
		if atk_state == Atk.WINDUP and d.length() < sword_range() - 0.4 and (d.length() < 0.5 or dash_dir.dot(d.normalized()) > 0.3):
			# Dash + ataque: se frena justo delante del rival y golpea la espada (sin embestida)
			_dash_hit = true
			dash_time = 0.0
			_on_dash_end()
			return
		if d.length() < 2.9 and (d.length() < 0.5 or dash_dir.dot(d.normalized()) > 0.3):
			_dash_hit = true
			var res: String = t.take_hit(DASH_DAMAGE, self, "dash")
			if res == "hit" or res == "block":
				if t.has_method("apply_knockback"):
					t.apply_knockback(dash_dir * DASH_KNOCKBACK * (0.5 if res == "block" else 1.0), res == "hit")
				if res == "hit":
					add_meter(6.0)
					if t is Fighter and (t as Fighter).mounted and randf() < (t as Fighter).knockoff_chance_dash:
						(t as Fighter).dismount(true)
				impact.emit(1.0)
				dash_time = minf(dash_time, 0.05)
			return

func apply_knockback(v: Vector3, stagger: bool = true) -> void:
	knock = MeshUtil.flat(v)
	if stagger:
		apply_stun(0.25)
	impact.emit(0.8)

## Telegrafía: true durante la anticipación de un ataque.
func is_attacking() -> bool:
	return atk_state == Atk.WINDUP

func is_swapping() -> bool:
	return swap_t > 0.0

func swap_progress() -> float:
	return 1.0 - swap_t / SWAP_TIME if swap_t > 0.0 else 0.0

func in_recovery() -> bool:
	return atk_state == Atk.RECOVERY

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.6 if mounted else 1.0, 0)

func add_meter(v: float) -> void:
	meter = clampf(meter + v, 0.0, METER_MAX)
	meter_changed.emit(meter)

func _can_act() -> bool:
	return alive and stun <= 0.0 and exhausted <= 0.0 and land_t <= 0.0 and special_t <= 0.0

## ¿Está t dentro del arco de la espada?
func in_sword_arc(t: Node3D) -> bool:
	var d := MeshUtil.flat(t.global_position - global_position)
	var hr: float = t.get("hit_radius")
	if d.length() - hr * 0.5 > sword_range():
		return false
	if d.length() < 0.5:
		return true
	return absf(facing.signed_angle_to(d.normalized(), Vector3.UP)) <= sword_half_arc()

## Compatibilidad: sword() = ataque ligero.
func sword() -> bool:
	return attack_light()

func attack_light() -> bool:
	return _request_attack(false)

func attack_heavy() -> bool:
	return _request_attack(true)

func _atk_data() -> Dictionary:
	var d: Dictionary = DASH_STRIKE.duplicate() if atk_dash else (JUMP_ATTACK.duplicate() if atk_jump else melee().attack(atk_heavy))
	d["damage"] = d["damage"] * damage_mult()
	return d

## Multiplicador de daño cuerpo a cuerpo: personaje, lanza a caballo y pasiva "Furia".
func damage_mult() -> float:
	var k := character.dano * float(mods["dano"])
	if mounted:
		k *= melee().mounted_damage_mult
	if character.passive_id == "furia" and health < max_health * 0.4:
		k *= 1.0 + 0.25 * passive_k()
	return k

func _request_attack(heavy: bool) -> bool:
	if roll_t >= 0.0 and not mounted and loadout == Loadout.SWORD_SHIELD and alive and roll_t < roll_iframe_end():
		_roll_atk_buffer = true # búfer: la estocada sale al acabar los i-frames
		return false
	if loadout != Loadout.SWORD_SHIELD or not _can_act() or swap_t > 0.0 or parry_state != Parry.NONE or roll_t >= 0.0:
		return false
	if airborne and not mounted:
		if atk_state != Atk.NONE or stamina <= 0.0:
			return false
		atk_jump = true # ataque en salto (picado)
		combo = max_combo()
		_start_attack(false, false)
		velocity.y = minf(velocity.y, -2.0)
		return true
	if atk_state != Atk.NONE:
		# Búfer de entrada para encadenar ligeros
		if not heavy and not atk_heavy and combo < max_combo() and (atk_state != Atk.WINDUP or atk_t > atk_dur * 0.5):
			_buffered = true
		return false
	if blocking or stamina <= 0.0:
		return false
	combo = 1
	_start_attack(heavy, false)
	if mounted and dash_time > 0.0:
		_ds_visual = true # ataque empezado durante el dash montado
	return true

func _start_attack(heavy: bool, chained: bool) -> void:
	atk_heavy = heavy
	var d := _atk_data()
	atk_state = Atk.WINDUP
	atk_t = 0.0
	atk_dur = d["chain_windup"] if chained else d["windup"]
	_atk_landed = false
	_atk_hit.clear()
	_buffered = false
	attacks_started += 1
	spend_stamina(d["stamina"])
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt and global_position.distance_to(tgt.global_position) < sword_range() + 1.5:
		var dd := MeshUtil.flat(tgt.global_position - global_position)
		if dd.length() > 0.1 and facing.dot(dd.normalized()) > 0.0:
			facing = dd.normalized()
	# Telegrafía: hoja alzada y brillante
	_sword_pivot.rotation = Vector3(1.4 if heavy else 1.0, sword_half_arc(), 0)
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1.0, 0.45, 0.1) if heavy else Color(1.0, 0.9, 0.4)
	_blade_mat.emission_energy_multiplier = 3.0
	_kv.set_glow(true, _blade_mat.emission)

## Parry dedicado (tecla Q / botón Parry). Solo con espada+escudo.
func parry() -> bool:
	if loadout != Loadout.SWORD_SHIELD or not _can_act() or swap_t > 0.0 or roll_t >= 0.0:
		return false
	if atk_state != Atk.NONE or parry_state != Parry.NONE or stamina <= 0.0:
		return false
	parry_state = Parry.ACTIVE
	parry_t = 0.0
	blocking = false
	spend_stamina(COST_PARRY)
	return true

func is_parrying() -> bool:
	return parry_state == Parry.ACTIVE

func _update_parry(delta: float) -> void:
	if parry_state == Parry.NONE:
		return
	parry_t += delta
	if parry_state == Parry.ACTIVE and parry_t >= parry_window:
		parry_state = Parry.RECOVERY # parry fallido: expuesto
		parry_t = 0.0
	elif parry_state == Parry.RECOVERY and parry_t >= PARRY_RECOVERY:
		parry_state = Parry.NONE

func _cancel_attack() -> void:
	atk_state = Atk.NONE
	_dash_atk = false
	atk_dash = false
	_ds_visual = false
	atk_jump = false
	combo = 0
	_buffered = false
	_blade_mat.emission_enabled = false
	_kv.set_glow(false, Color.BLACK)
	_sword_pivot.rotation = Vector3.ZERO

func _update_attack(delta: float) -> void:
	if atk_state == Atk.NONE:
		return
	atk_t += delta
	var d := _atk_data()
	match atk_state:
		Atk.WINDUP:
			if dash_time > 0.0 and mounted:
				_dash_atk = true # la anticipación se carga durante el dash; el golpe sale al acabar
				return
			if _dash_atk and atk_t >= DASH_STRIKE_MIN_TIME and atk_t < atk_dur:
				atk_t = atk_dur # el dash hizo de anticipación: golpe ya, delante del rival
				dash_strikes += 1
			_dash_atk = _dash_atk and atk_t < atk_dur
			if atk_t >= atk_dur:
				atk_state = Atk.ACTIVE
				atk_t = 0.0
				atk_dur = d["active"]
				_blade_mat.emission_enabled = false
				_kv.set_glow(false, Color.BLACK)
				var half := sword_half_arc()
				var tw := create_tween()
				tw.tween_property(_sword_pivot, "rotation", Vector3(0, -half, 0), atk_dur)
				var arc := MeshUtil.arc(self, 0.6, sword_range(), half, _rider_root.position.y + 1.0, Color(1, 0.6, 0.3) if atk_heavy else Color(1, 1, 0.85))
				var tw2 := arc.create_tween()
				tw2.tween_property(arc, "transparency", 1.0, 0.3)
				tw2.tween_callback(arc.queue_free)
				_strike_frame(d)
		Atk.ACTIVE:
			_strike_frame(d)
			if atk_t >= atk_dur:
				atk_state = Atk.RECOVERY
				atk_t = 0.0
				atk_dur = d["recovery"] + (0.0 if _atk_landed else d["whiff"])
				if combo >= max_combo():
					atk_dur += FINISHER_EXTRA_RECOVERY
		Atk.RECOVERY:
			if _buffered and combo < max_combo() and atk_t >= CHAIN_MIN_RECOVERY and stamina > 0.0 and exhausted <= 0.0 and stun <= 0.0:
				combo += 1
				atk_dash = false
				_ds_visual = false
				_start_attack(false, true)
				return
			if atk_t >= atk_dur:
				_cancel_attack()

func _strike_frame(d: Dictionary) -> void:
	if not alive:
		return
	for t in MeshUtil.enemies_of(get_tree(), team):
		if t in _atk_hit or not in_sword_arc(t):
			continue
		_atk_hit.append(t)
		var was_open: bool = t is Fighter and ((t as Fighter).in_recovery() or (t as Fighter).stun > 0.0)
		var res: String = t.take_hit(d["damage"], self, "melee")
		if res == "hit" or res == "block" or res == "parry":
			_atk_landed = true
		if res == "hit":
			add_meter(18.0 if atk_heavy else 12.0)
		elif res == "block":
			add_meter(3.0)
		if res == "hit":
			hits_landed += 1
		landed_hit.emit(t, res, was_open)

# ---------------- Armas: espada+escudo O arco ----------------

func swap_loadout() -> bool:
	if not alive or swap_t > 0.0 or atk_state != Atk.NONE or stun > 0.0:
		return false
	swap_t = SWAP_TIME
	blocking = false
	swap_from = loadout
	return true

func _apply_loadout_visuals() -> void:
	var sw := loadout == Loadout.SWORD_SHIELD
	_kv.set_loadout(0 if sw else 1)

func shoot() -> bool:
	if loadout != Loadout.BOW or swap_t > 0.0 or atk_state != Atk.NONE:
		return false
	if not _can_act() or bow_cd > 0.0 or stamina <= 0.0:
		return false
	bow_cd = BOW_COOLDOWN
	spend_stamina(COST_BOW)
	var origin := get_hit_center() + Vector3(0, 0.8, 0) + facing * 1.4
	var dir := facing
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var d: Vector3 = tgt.get_hit_center() - origin
		if MeshUtil.flat(d).normalized().dot(facing) > -0.2:
			dir = d.normalized()
	var p := Projectile.new()
	p.team = team
	p.shooter = self
	p.direction = dir
	p.target = tgt
	p.damage = 8.0 * (1.0 + 0.3 * passive_k() if character.passive_id == "ojo_de_halcon" else 1.0)
	p.color = Color(0.9, 0.8, 0.5)
	get_parent().add_child(p)
	p.global_position = origin
	_kv.event("shoot")
	return true

## Dash montado / voltereta a pie.
func dash() -> bool:
	if not _can_act() or dash_cd > 0.0 or stamina <= 0.0 or parry_state != Parry.NONE or roll_t >= 0.0:
		return false
	if airborne or special_t > 0.0:
		return false
	if atk_state != Atk.NONE:
		if mounted and atk_state == Atk.WINDUP:
			_ds_visual = true # montado: el ataque sigue cargándose durante el dash y golpea al final
		elif not mounted and atk_state == Atk.WINDUP and not atk_heavy and not atk_dash and not atk_jump:
			# A pie: dash durante la anticipación del ligero = estocada con dash
			var mi0 := MeshUtil.flat(move_input)
			dash_dir = mi0.normalized() if mi0.length() > 0.2 else facing
			spend_stamina(COST_ROLL * character.roll_cost_mult * float(mods["roll_cost"]))
			dash_cd = stats().dash_cooldown
			_start_dash_strike()
			return true
		elif atk_state == Atk.RECOVERY and atk_t >= atk_dur * ROLL_CANCEL_FRACTION:
			_cancel_attack() # compromiso: solo se cancela al final de la recuperación
		else:
			return false
	var st := stats()
	var mi := MeshUtil.flat(move_input)
	dash_dir = mi.normalized() if mi.length() > 0.2 else facing
	if not mounted:
		return _start_roll(st)
	# Dash montado: sin cambios (embestida, empuje y derribo)
	dash_cd = st.dash_cooldown
	dash_time = st.dash_duration
	invuln = st.dash_iframes
	_dash_hit = false
	_dash_atk = atk_state == Atk.WINDUP
	spend_stamina(COST_DASH)
	return true

## Voltereta a pie: arranque vulnerable -> i-frames -> recuperación vulnerable.
func _start_roll(st: MountData) -> bool:
	roll_t = 0.0
	dash_time = ROLL_TOTAL # solo para la animación Dodge_* y la IA (no da i-frames)
	dash_cd = maxf(st.dash_cooldown, ROLL_TOTAL)
	invuln = 0.0
	_dash_hit = true # la voltereta no embiste
	spend_stamina(COST_ROLL * character.roll_cost_mult * float(mods["roll_cost"]))
	return true

func _roll_velocity() -> Vector3:
	var fast := ROLL_IFRAME_END # la distancia no cambia con la pasiva "Sombra" (solo los i-frames)
	if roll_t < fast:
		return dash_dir * (ROLL_DISTANCE / fast)
	# Recuperación: frena linealmente (área = ROLL_RECOVERY_DRIFT)
	var rec := ROLL_TOTAL - fast
	var k := 1.0 - (roll_t - fast) / rec
	return dash_dir * (2.0 * ROLL_RECOVERY_DRIFT / rec) * maxf(k, 0.0)

## Al acabar un dash montado: si hay un ataque ligado en anticipación, golpea en el
## siguiente frame (o en cuanto lleve DASH_STRIKE_MIN_TIME de anticipación).
func _on_dash_end() -> void:
	if atk_state != Atk.WINDUP:
		_dash_atk = false

## Estocada con dash (a pie): anticipación corta avanzando hacia el rival y golpe.
func _start_dash_strike() -> void:
	if atk_state != Atk.NONE:
		_cancel_attack()
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt and global_position.distance_to(tgt.global_position) < 9.0:
		var dd := MeshUtil.flat(tgt.global_position - global_position)
		if dd.length() > 0.1 and dd.normalized().dot(dash_dir) > -0.2:
			dash_dir = dd.normalized()
	facing = dash_dir
	atk_dash = true
	_ds_visual = true
	combo = max_combo() # no se encadena: es un golpe único
	dash_strikes += 1
	_start_attack(false, false)
	atk_dash = true
	_ds_visual = true

func _lunge_velocity() -> Vector3:
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var d := MeshUtil.flat(tgt.global_position - global_position)
		if d.length() < sword_range() - 0.5:
			return Vector3.ZERO # ya está delante: no lo atraviesa
	var k := 1.0 if atk_state == Atk.WINDUP else 0.6
	return dash_dir * LUNGE_SPEED * k

## Salto (a pie) o brinco de la montura (lobo/grifo). En el fénix no se salta.
func jump() -> bool:
	if not _can_act() or airborne or roll_t >= 0.0 or atk_state != Atk.NONE or parry_state != Parry.NONE or swap_t > 0.0:
		return false
	if stamina <= 0.0 or not (is_on_floor() or global_position.y < 0.05):
		return false
	var v := JUMP_VELOCITY
	if mounted:
		if mount_node == null or mount_node.is_flying():
			return false
		v = mount_node.data.jump_velocity * MOUNT_HOP_MULT
	blocking = false
	spend_stamina(COST_JUMP)
	_jump_v = v
	airborne = true
	_air_t = 0.0
	jumps += 1
	return true

func _land() -> void:
	airborne = false
	_air_t = 0.0
	velocity.y = 0.0
	land_t = LAND_RECOVERY
	if atk_jump and atk_state == Atk.WINDUP:
		atk_t = atk_dur # el picado golpea al tocar el suelo

func has_special() -> bool:
	return character.special_id != ""

## Habilidad del personaje (G / botón "Habilidad"). Berserker: golpe sísmico.
func special() -> bool:
	if not has_special() or not _can_act() or special_cd > 0.0 or airborne or mounted or roll_t >= 0.0:
		return false
	if atk_state != Atk.NONE or parry_state != Parry.NONE or swap_t > 0.0 or stamina <= 0.0:
		return false
	match character.special_id:
		"golpe_sismico":
			special_cd = SLAM_COOLDOWN
			special_t = SLAM_TELEGRAPH
			blocking = false
			spend_stamina(COST_SLAM)
			specials_used += 1
			GroundAoE.spawn(get_parent(), self, team, global_position, SLAM_RADIUS, SLAM_TELEGRAPH, SLAM_DAMAGE * damage_mult())
			_kv.event("slam")
			return true
	return false

## Especial del eikon montado (E mientras lo montas).
func eikon_special() -> bool:
	if not mounted or mount_node == null or mount_node.eikon == null or mount_node.owner_fighter != self:
		return false
	var m := mount_node
	if m.special_cd > 0.0 or not alive or stun > 0.0:
		return false
	var ed := m.eikon
	m.special_cd = ed.special_cooldown
	eikon_specials += 1
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	match ed.special_id:
		"llamarada":
			var p := Projectile.new()
			p.team = team
			p.shooter = self
			p.kind = "eikon"
			p.damage = ed.special_damage
			p.speed = 24.0
			p.radius = 0.7
			p.color = ed.color
			p.target = tgt
			p.turn_rate = 1.4
			var origin := global_position + Vector3(0, 1.6 + m.data.hover, 0) + facing * 1.8
			p.direction = ((tgt.get_hit_center() - origin).normalized() if tgt else facing)
			get_parent().add_child(p)
			p.global_position = origin
		"colmillo":
			knock = facing * 10.0
			for t in MeshUtil.enemies_of(get_tree(), team):
				var d := MeshUtil.flat(t.global_position - global_position)
				if d.length() < 4.5 and (d.length() < 0.5 or absf(facing.signed_angle_to(d.normalized(), Vector3.UP)) < deg_to_rad(60)):
					if t.take_hit(ed.special_damage, self, "eikon") == "hit" and t is Fighter:
						(t as Fighter).apply_stun(0.5) # congelado un instante
		"vendaval":
			for t in MeshUtil.enemies_of(get_tree(), team):
				var d := MeshUtil.flat(t.global_position - global_position)
				if d.length() < 5.5:
					var r: String = t.take_hit(ed.special_damage, self, "eikon")
					if (r == "hit" or r == "block") and t.has_method("apply_knockback"):
						t.apply_knockback((d.normalized() if d.length() > 0.1 else facing) * 14.0, r == "hit")
	impact.emit(0.6)
	return true

func summon() -> bool:
	if not alive or eikon == null:
		return false
	if is_instance_valid(active_eikon):
		if eikon.rideable and mounted and mount_node == active_eikon:
			return eikon_special() # montado en tu eikon: E = su ataque especial
		summon_failed.emit("active")
		return false
	if meter < METER_MAX:
		summon_failed.emit("meter")
		return false
	if stun > 0.0:
		summon_failed.emit("stun")
		return false
	if eikon.rideable:
		return _summon_mount()
	var e := Eikon.new()
	e.data = eikon
	e.team = team
	e.owner_fighter = self
	get_parent().add_child(e)
	e.global_position = global_position + facing.cross(Vector3.UP) * 3.0 + Vector3(0, 0.2, 0)
	active_eikon = e
	meter = 0.0
	meter_changed.emit(meter)
	summoned.emit(e)
	return true

## Eikon montable: aparece ensillado y su dueño monta al instante.
func _summon_mount() -> bool:
	if atk_state != Atk.NONE or roll_t >= 0.0 or airborne or special_t > 0.0 or swap_t > 0.0:
		summon_failed.emit("busy")
		return false
	if mounted:
		dismount(false) # (solo con monturas neutrales de las pruebas antiguas)
	var m := Mount.new()
	m.data = eikon.ride
	m.eikon = eikon
	m.owner_fighter = self
	m.life = eikon.duration
	get_parent().add_child(m)
	m.global_position = Vector3(global_position.x, 0.0, global_position.z)
	m.rotation.y = rotation.y
	owned_mount = m
	active_eikon = m
	mount_on(m)
	meter = 0.0
	meter_changed.emit(meter)
	summoned.emit(m)
	return true

## Segundos que le quedan a la invocación activa (0 si no hay).
func eikon_time_left() -> float:
	if active_eikon is Mount:
		return maxf((active_eikon as Mount).life, 0.0)
	if active_eikon is Eikon:
		return maxf((active_eikon as Eikon).life, 0.0)
	return 0.0

func apply_stun(t: float) -> void:
	stun = maxf(stun, t)
	if atk_state != Atk.NONE:
		_cancel_attack()

## Devuelve "hit", "block", "parry", "dodge" o "none".
func take_hit(amount: float, from: Node3D, _kind: String) -> String:
	if not alive:
		return "none"
	if invuln > 0.0:
		return "dodge"
	if roll_phase() == "iframes":
		rolls_dodged += 1
		return "dodge"
	var frontal := true
	if is_instance_valid(from):
		var d := MeshUtil.flat(from.global_position - global_position)
		if d.length() > 0.1:
			frontal = facing.dot(d.normalized()) > 0.0
	if parry_state == Parry.ACTIVE and frontal and _kind != "eikon" and _kind != "aoe":
		if from is Fighter and _kind == "melee":
			(from as Fighter).apply_stun(PARRY_STAGGER)
			(from as Fighter).riposte_t = PARRY_STAGGER
		add_meter(15.0)
		parries_landed += 1
		parry_state = Parry.NONE # éxito: sin recuperación
		return "parry"
	if parry_state == Parry.RECOVERY:
		amount *= PARRY_EXPOSED_MULT
	if blocking and frontal:
		if _kind == "arrow":
			spend_stamina(COST_BLOCKED_ARROW) # flecha anulada por completo
			_kv.event("block_hit")
			if stamina <= 0.0:
				_guard_break()
			return "block"
		if _kind == "eikon" or _kind == "aoe":
			_damage(amount * maxf(EIKON_BLOCK_PASS, EXHAUSTED_BLOCK_REDUCTION if exhausted > 0.0 else 0.0))
			spend_stamina(COST_BLOCKED_EIKON)
			add_meter(3.0)
			_kv.event("block_hit")
			if stamina <= 0.0:
				_guard_break()
			return "block"
		var chip := BLOCK_REDUCTION if has_shield() else melee().no_shield_block_chip
		_damage(amount * (EXHAUSTED_BLOCK_REDUCTION if exhausted > 0.0 else chip))
		spend_stamina(blocked_hit_cost(amount, from))
		add_meter(3.0)
		_kv.event("block_hit")
		if stamina <= 0.0:
			_guard_break()
		return "block"
	if riposte_t > 0.0 and _kind == "melee":
		amount *= RIPOSTE_MULT # riposte tras parry
		riposte_t = 0.0
	_damage(amount)
	add_meter(5.0)
	_kv.event("hit")
	if _kind == "melee":
		impact.emit(0.5)
	# Poise / hit-stun: intercambiar golpes no sale gratis
	_since_hit = 0.0
	poise -= amount * 2.0 * ((from as Fighter).melee().poise_damage_mult if from is Fighter and _kind == "melee" else 1.0)
	if poise <= 0.0:
		poise = poise_max
		apply_stun(0.6 + (0.3 if amount >= HEAVY_HIT else 0.0))
	elif atk_state == Atk.WINDUP and not atk_heavy:
		apply_stun(0.2) # los ligeros se interrumpen; el fuerte tiene súper-armadura
	if mounted and alive and amount >= HEAVY_HIT and randf() < knockoff_chance_heavy:
		dismount(true)
	return "hit"

## Sin aguante bajo el escudo: guardia rota, tambaleo y expuesto.
func _guard_break() -> void:
	guard_breaks += 1
	blocking = false
	apply_stun(GUARD_BREAK_STAGGER)
	impact.emit(0.8)

## Aguante que cuesta bloquear un golpe: ligero/fuerte, rompeguardias del atacante,
## guardia del personaje, pasiva "Guardia firme" y bloqueo sin escudo (x1.5).
func blocked_hit_cost(amount: float, from: Node3D) -> float:
	var c := COST_BLOCKED_HIT * (COST_BLOCKED_HEAVY_MULT if amount >= HEAVY_HIT else 1.0)
	if from is Fighter:
		c *= (from as Fighter).melee().guard_break_mult
	c *= character.guardia
	if character.passive_id == "guardia_firme":
		c *= 1.0 - 0.2 * passive_k()
	c *= float(mods["block_cost"])
	if not has_shield():
		c *= 1.5
	return c

func _damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	_flash = 0.12
	health_changed.emit(health, max_health)
	if health <= 0.0 and alive:
		alive = false
		died.emit(self)

func dismiss_eikon() -> void:
	if active_eikon is Mount and is_instance_valid(active_eikon):
		(active_eikon as Mount).expire()
	elif is_instance_valid(active_eikon):
		active_eikon.queue_free()
	active_eikon = null

## keep_meter: el medidor de eikon se conserva entre rondas (antes se perdía y casi nunca se llenaba).
func reset_for_round(pos: Vector3, face: Vector3, keep_meter: bool = true) -> void:
	dismiss_eikon()
	airborne = false
	_jump_v = 0.0
	land_t = 0.0
	special_t = 0.0
	special_cd = 0.0
	_roll_atk_buffer = false
	if not mounted and is_instance_valid(owned_mount) and owned_mount.owner_fighter == null:
		if not owned_mount.is_free() and owned_mount.rider:
			owned_mount.rider.dismount(false)
		owned_mount.global_position = pos
		mount_on(owned_mount)
	global_position = pos
	facing = face.normalized()
	rotation.y = atan2(-facing.x, -facing.z)
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	velocity = Vector3.ZERO
	planar_vel = Vector3.ZERO
	knock = Vector3.ZERO
	invuln = 0.0
	dash_time = 0.0
	roll_t = -1.0
	_dash_atk = false
	health = max_health
	if not keep_meter:
		meter = 0.0
	stamina = stamina_max
	exhausted = 0.0
	alive = true
	stun = 0.0
	_cancel_attack()
	parry_state = Parry.NONE
	poise = poise_max
	riposte_t = 0.0
	var start_l := Loadout.BOW if weapon.ranged else Loadout.SWORD_SHIELD
	if swap_t > 0.0 or loadout != start_l:
		swap_t = 0.0
		loadout = start_l
		_apply_loadout_visuals()
		loadout_changed.emit(loadout)
	bow_cd = 0.0
	dash_cd = 0.0
	health_changed.emit(health, max_health)
	meter_changed.emit(meter)
	stamina_changed.emit(stamina, false)
