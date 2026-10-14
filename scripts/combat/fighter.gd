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
signal hitstop(duration: float) ## ronda 23: congelación breve de impacto
## Ronda 24: «El intercambio» — contraataque, contra de guardia, rotura de postura y crítico frontal
signal counter_landed(target: Node3D)
## Ronda 25: habilidad de jefe «Estocada de jefe» (telegrafiada, invulnerable, castigable)
signal boss_started
enum Boss { NONE, CHARGE, LUNGE, RECOVER }
const BOSS_CHARGE := 1.6 ## carga visible (pose, brillo y partículas en la hoja, sonido que sube)
const BOSS_TRACK := 1.6 ## ronda 31: sigue al objetivo TODA la carga (no se esquiva caminando)
const BOSS_DIST := 12.0 ## ronda 31: más alcance (antes 7,5)
const BOSS_SPEED := 30.0 ## m/s (0,4 s de embestida)
const BOSS_HOME_DEG := 140.0 ## ronda 31: corrección de dirección durante la embestida (°/s)
const BOSS_REACH := 1.8
const BOSS_ARC_DEG := 35.0
const BOSS_DMG_MULT := 1.6 ## x daño fuerte del arma
const BOSS_POISE := 3.0
const BOSS_RECOVER_HIT := 1.0
const BOSS_RECOVER_MISS := 1.4 ## falló: estocada al aire, recuperación más larga
const BOSS_COOLDOWN := 14.0
const BOSS_STAMINA := 25.0
var boss_phase: int = Boss.NONE
var boss_t: float = 0.0
var boss_dir: Vector3 = Vector3.FORWARD
var boss_cd: float = 0.0
var boss_travel: float = 0.0
var boss_hit: bool = false
var boss_uses: int = 0
var boss_hits: int = 0
var _boss_fx: CPUParticles3D
var _boss_snd: AudioStreamPlayer3D
signal stance_broken
signal critical_landed(target: Node3D, damage: float)
const GUARD_COUNTER_WINDOW := 0.35 ## s tras bloquear en que atacar = contra de guardia
const GC_WINDUP_MULT := 0.6 ## la contra de guardia sale más rápido que un fuerte
const GC_POISE := 2.0
const STANCE_MULT := 3.5 ## postura = equilibrio x3,5 (se rompe con presión sostenida)
const STANCE_DELAY := 2.5 ## s sin recibir golpes antes de recuperar postura
const STANCE_REGEN := 12.0
const STANCE_BREAK_TIME := 1.2 ## expuesto tras romper la postura
const CRIT_MULT := 2.2
const CRIT_RANGE := 2.6
const CRIT_TIME := 0.8 ## animación del crítico (el atacante es invulnerable)
const CRIT_HIT_AT := 0.45
const CHARGE_MAX := 0.6 ## ronda 24 (fase 2): carga extra del fuerte manteniendo
const CHARGE_BONUS := 0.4 ## +40 % de daño y equilibrio con carga completa
const BLOCK_REGEN_MULT := 0.5 ## aguante con la guardia alzada
var counter_hits: int = 0
var guard_counter_t: float = 0.0
var atk_gc: bool = false
var guard_counters: int = 0
var stance: float = POISE_MAX * STANCE_MULT
var stance_max: float = POISE_MAX * STANCE_MULT
var stance_broken_t: float = 0.0
var stance_breaks: int = 0
var crit_t: float = -1.0
var _crit_target: Fighter = null
var _crit_done: bool = false
var crits: int = 0
var want_charge: bool = false ## lo fija el controlador: botón de ataque mantenido
var charge_t: float = 0.0
var running_attacks: int = 0
## Ronda 25: paso adelante de los ataques con magnetismo hacia el objetivo
const STEP_WINDOW := 0.45 ## el paso ocupa el último 45 % de la anticipación + el golpe
const STEP_CHARGE_BONUS := 0.8 ## m extra con el fuerte cargado al máximo
const MAGNET_RANGE := 1.5 ## m más allá de paso + alcance en que el ataque se imanta
const CONTACT_GAP := 0.8 ## se detiene a esta distancia del borde del objetivo (no lo atraviesa)
var _step_left: float = 0.0
var _step_total: float = 0.0
var step_travel: float = 0.0 ## recorrido del último paso (pruebas)
var _charge_added: bool = false
const HITSTOP_HEAVY := 0.08
const HITSTOP_PARRY := 0.06
signal mount_changed(mounted: bool)
signal loadout_changed(loadout: int)
signal landed_hit(target: Node3D, result: String, target_was_open: bool)
signal status_proc(kind: String) ## ronda 20: estallido de un estado alterado

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
const AIR_CONTROL := 0.0 ## ronda 29: sin control en el aire (trayectoria fijada al despegar)
## Ataque en salto: picado. Cae rápido y golpea al aterrizar cerca.
const JUMP_ATTACK := {"windup": 0.22, "chain_windup": 0.22, "active": 0.12, "recovery": 0.45, "whiff": 0.2, "damage": 16.0, "stamina": 14.0}
## Habilidad "Golpe sísmico" (Berserker): área en el suelo con aviso.
const SLAM_RADIUS := 5.0
const SLAM_TELEGRAPH := 0.7
const SLAM_DAMAGE := 22.0
const SLAM_COOLDOWN := 8.0
const COST_SLAM := 25.0
const SLAM_ENERGY := 30.0 ## ronda 18: Energía que gasta el Golpe sísmico
const POISE_MAX := 50.0
const POISE_REGEN := 25.0
## Ronda 15: cambio arco<->cuerpo a cuerpo rápido (antes 2 s). Nunca bloquea el movimiento;
## solo atacar/disparar/bloquear quedan fuera durante el cambio.
const SWAP_TIME := 0.42
## Correr a pie fijado: hacia atrás se corre algo más lento que de frente (estilo souls).
const RUN_BACK_FACTOR := 0.8
## Ronda 16: corriendo fijado, por encima de este ángulo entre la entrada y la dirección al
## rival se deja de hacer strafe y se corre de cara hacia donde se va (atrás = hacia la cámara).
const RUN_TURN_DEG := 110.0
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
const FALLBACK_BOW := preload("res://resources/weapons/arco.tres") ## arma a distancia de quien lleva cuerpo a cuerpo
## Ronda 17: disparo con compromiso. DRAW = tensar/apuntar (a pie: quieto), RECOVER = tras soltar
## (a pie: andar lento), RELOAD = recarga de la ballesta (a pie: andar algo lento, sin disparar).
enum Shot { NONE, DRAW, RECOVER, RELOAD }
## Montado y de espaldas al rival (huida fijado), el jinete gira el torso hasta mirar al rival.
const MELEE_TWIST_MAX_DEG := 100.0 ## más girado que esto no se puede atacar cuerpo a cuerpo
var stamina_max: float = STAMINA_MAX
var poise_max: float = POISE_MAX
var heals: float = 0.0 ## vida curada por la pasiva (pruebas)
## Ronda 11: modificadores de las habilidades desbloqueadas (Progression.combine_mods).
var mods: Dictionary = Progression.combine_mods([])
var trinket_ids: Array = [] ## ronda 30: anillos + talismanes equipados
var tfx: Dictionary = Trinkets.neutral()
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
var cur_hit: ComboHit = null ## Ronda 16: golpe del combo en curso
var combo_log: Array[String] = [] ## nombres de los últimos golpes de combo (pruebas/HUD)
var attacks_started: int = 0
var _atk_landed: bool = false
var _atk_hit: Array[Node3D] = []
var _buffered: bool = false
var poise: float = POISE_MAX
var _since_hit: float = 10.0
var riposte_t: float = 0.0 ## tras sufrir un parry: recibe daño extra
var loadout: Loadout = Loadout.SWORD_SHIELD
## Ronda 16: adelanto al apuntar (0 = a la posición actual). Solo la IA difícil lo sube (0,5).
var aim_lead: float = 0.0
var swap_t: float = 0.0
var swap_from: int = Loadout.SWORD_SHIELD ## arma que se enfunda durante el cambio
var bow_cd: float = 0.0
var shot_state: Shot = Shot.NONE
var shot_t: float = 0.0
var shot_dur: float = 0.0
var shots_fired: int = 0
var shot_cut_sprint: bool = false ## el disparo cortó la carrera (el control apaga «Correr»)
var incoming_arrow_stun: float = 0.0 ## lo fija el proyectil justo antes de impactar
var incoming_stun_force: float = -1.0 ## ronda 31: fuerza de aturdimiento fijada por quien golpea (-1 = calcular)
var last_hitstun: float = 0.0
var rider_yaw: float = 0.0 ## giro del jinete sobre la silla respecto a la montura (rad)
var run_away: bool = false
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
## Ronda 18: atributos y estadísticas derivadas; Energía (habilidades).
var attrs: Dictionary = {}
var ad: Dictionary = Attributes.derived("caballero", {})
var energy_max: float = 50.0
var level: int = 1
var armor_ids: Dictionary = {}
var armor_set: bool = false
var secondary: WeaponDef = null
var eq: Dictionary = {}
var eq_ref: Dictionary = {}
var energy: float = 50.0
## Ronda 20: estados alterados y audio
var status_fx: StatusFx = StatusFx.new()
const LOBO_FROST := 30.0 ## acumulación de congelación por golpe del Lobo de Hielo
var _step_d: float = 0.0
var _status_flash: float = 0.0
var _status_flash_c: Color = Color.WHITE
var _aura: CPUParticles3D
signal energy_changed(value: float, max_value: float)
## Ronda 21: magia de eikon (ranuras) y artes de arma
signal spell_changed(idx: int, id: String)
var spells: Array = [] ## ids de EikonSpells equipados ("" = ranura vacía)
var spell_idx: int = 0
var spell_cd: Dictionary = {}
var cast_t: float = 0.0
var _cast_id: String = ""
var spells_cast: int = 0
var stoneskin_t: float = 0.0
var _stoneskin: Dictionary = {}
var weapon_art_id: String = ""
var art_cd: float = 0.0
var arts_used: int = 0
var _art_mult: float = 1.0
var incoming_element: String = "" ## lo fija el proyectil/hechizo justo antes de impactar
var incoming_status: Dictionary = {}
var _hit_element: String = ""
var _hit_status: Dictionary = {}
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

## Ronda 26: lista de luchadores en el árbol (misma pertenencia que el grupo "fighter",
## sin crear un Array por fotograma en la separación).
static var all: Array[Fighter] = []

func _enter_tree() -> void:
	if is_node_ready() and not all.has(self):
		all.append(self)

func _exit_tree() -> void:
	all.erase(self)

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("fighter")
	if not all.has(self):
		all.append(self)
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

## Ronda 18: atributos (vacío = reparto inicial del rol: sin bonos). Antes de añadir al árbol
## o seguido de _apply_character().
func set_attributes(a: Dictionary) -> void:
	attrs = a.duplicate()

## Ronda 19: nivel, armadura ({slot: id}; sin llamar = equipo inicial del rol) y arma secundaria.
## Ronda 30: anillos y talismanes (antes de entrar en escena).
func set_trinkets(ids: Array) -> void:
	trinket_ids = ids.duplicate()
	tfx = Trinkets.combine(ids)
	if is_inside_tree():
		_apply_character()

func set_equipment(lv: int, armor: Dictionary, w2: WeaponDef = null) -> void:
	level = maxi(lv, 1)
	armor_ids = armor.duplicate()
	armor_set = true
	secondary = w2 if w2 and character.allows(w2.id) and w2.ranged != weapon.ranged else null

func armor_pieces() -> Dictionary:
	return EquipStats.armor_defs(armor_ids if armor_set else Catalog.starter_armor(character.id))

func _refresh_equipment() -> void:
	eq = EquipStats.sheet(character, level, attributes(), weapon, secondary, armor_pieces())
	eq_ref = EquipStats.role_reference(character)

func roll_mod() -> Dictionary:
	return eq["roll"] if not eq.is_empty() else EquipStats.ROLL_BY_LOAD["medio"]

## Duración total de la voltereta (la recuperación se alarga con carga pesada).
func roll_total() -> float:
	return roll_iframe_end() + ROLL_RECOVERY_FRAMES * float(roll_mod()["rec"]) / ROLL_FPS

## Ronda 20: efecto de sonido posicional (no hace nada sin el autoload Audio).
func _snd(n: String, db: float = 0.0) -> void:
	var a := get_node_or_null("/root/Audio")
	if a and is_inside_tree():
		a.sfx3d(n, global_position + Vector3(0, 1.0, 0), 0.08, db)

## Umbral de un estado (10 + resistencia de la ficha: Robustez o Inmunidad).
func status_threshold(k: String) -> float:
	var r := 60.0
	if not eq.is_empty():
		r = float(eq["resist"].get(StatusFx.RESIST[k], 60.0))
	return StatusFx.threshold_for(r)

func status_fraction(k: String) -> float:
	return status_fx.fraction(k, status_threshold(k))

## Suma acumulación de un estado; si se llena, estallido (sangrado/congelación) o veneno.
func add_status(k: String, amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	if not status_fx.add(k, amount, status_threshold(k)):
		return false
	match k:
		"sangrado": _damage(max_health * StatusFx.BLEED_PCT + StatusFx.BLEED_FLAT)
		"congelacion": _damage(max_health * StatusFx.FROST_PCT + StatusFx.FROST_FLAT)
	_status_flash = 0.5
	_status_flash_c = StatusFx.COLORS[k]
	_snd("status_" + k, 2.0)
	_burst_particles(StatusFx.COLORS[k])
	status_proc.emit(k)
	return true

## Acumulación que trae un golpe recibido.
func _status_from(from: Node3D, kind: String) -> Dictionary:
	if from is Fighter and is_instance_valid(from):
		var f := from as Fighter
		if kind == "melee":
			return f.melee().status
		if kind == "arrow":
			return f.ranged().status
		if kind == "eikon" and f.eikon and f.eikon.id == "lobo":
			return {"congelacion": LOBO_FROST}
	if from is Mount and (from as Mount).eikon and (from as Mount).eikon.id == "lobo":
		return {"congelacion": LOBO_FROST}
	if from is Eikon and (from as Eikon).data and (from as Eikon).data.id == "lobo":
		return {"congelacion": LOBO_FROST}
	return {}

func _burst_particles(c: Color) -> void:
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.6
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	add_child(p)
	p.position = Vector3(0, 1.2, 0)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## Aura continua mientras dura el veneno o la congelación.
func _update_aura() -> void:
	var c := Color.TRANSPARENT
	if status_fx.poison_t > 0.0:
		c = StatusFx.COLORS["veneno"]
	elif status_fx.frost_t > 0.0:
		c = StatusFx.COLORS["congelacion"]
	if c.a == 0.0:
		if _aura:
			_aura.emitting = false
		return
	if _aura == null:
		_aura = CPUParticles3D.new()
		_aura.amount = 10
		_aura.lifetime = 1.0
		_aura.direction = Vector3.UP
		_aura.spread = 25.0
		_aura.initial_velocity_min = 0.5
		_aura.initial_velocity_max = 1.2
		_aura.gravity = Vector3.ZERO
		_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_aura.emission_sphere_radius = 0.5
		var m := SphereMesh.new()
		m.radius = 0.05
		m.height = 0.1
		m.material = StandardMaterial3D.new()
		(m.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aura.mesh = m
		add_child(_aura)
		_aura.position = Vector3(0, 1.0, 0)
	((_aura.mesh as SphereMesh).material as StandardMaterial3D).albedo_color = c
	_aura.emitting = true

## Tipo de daño de un golpe recibido.
func _damage_type(from: Node3D, kind: String) -> String:
	if _hit_element != "":
		return _hit_element
	if kind == "melee" or kind == "arrow":
		return "fisico"
	var eid := ""
	if from is Mount and (from as Mount).eikon:
		eid = (from as Mount).eikon.id
	elif from is Eikon and (from as Eikon).data:
		eid = (from as Eikon).data.id
	elif from is Fighter and kind == "eikon" and (from as Fighter).eikon:
		eid = (from as Fighter).eikon.id
	return EquipStats.EIKON_ELEMENT.get(eid, "fisico")

func attributes() -> Dictionary:
	return attrs if not attrs.is_empty() else Attributes.start_for(character.id)

func _refresh_derived() -> void:
	ad = Attributes.derived(character.id, attributes())

## Multiplicador de daño por atributos del arma (las de recambio no aplican requisitos).
func weapon_attr_mult(w: WeaponDef) -> float:
	return Attributes.weapon_mult(w, character.id, attributes(), w == weapon)

## Velocidad de ataque/disparo por Destreza.
func attr_speed() -> float:
	return float(ad.get("vel", 1.0))

## Potencia de la pasiva (1.0 = base; las habilidades la suben).
func passive_k() -> float:
	return 1.0 + float(mods["passive"])

func _apply_character() -> void:
	_refresh_derived()
	_refresh_equipment()
	max_health = character.vida + float(mods["vida"]) + float(ad["vida"]) + (mount.health_bonus if mount else 0.0)
	health = max_health
	stamina_max = character.estamina + float(mods["estamina"]) + float(ad["estamina"])
	stamina = stamina_max
	poise_max = character.poise + float(mods["poise"]) + float(ad["poise"]) + float(eq["armor_poise"]) - float(eq_ref["armor_poise"]) + float(tfx["poise"])
	energy_max = float(ad["energia_max"])
	energy = energy_max
	parry_window = PARRY_WINDOW + float(mods["parry_window"])
	poise = poise_max
	stance_max = poise_max * STANCE_MULT
	stance = stance_max
	if weapon.ranged:
		loadout = Loadout.BOW

## Arma cuerpo a cuerpo efectiva (el arquero usa dagas al cambiar de arma).
func melee() -> WeaponDef:
	if weapon.ranged:
		return secondary if secondary and not secondary.ranged else FALLBACK_MELEE
	return weapon

## Arma a distancia efectiva (con arma cuerpo a cuerpo, el arco de recambio).
func ranged() -> WeaponDef:
	if weapon.ranged:
		return weapon
	return secondary if secondary and secondary.ranged else FALLBACK_BOW

func is_shooting() -> bool:
	return shot_state == Shot.DRAW or shot_state == Shot.RECOVER

## Dirección hacia la que mira el jinete/arquero (montado puede girarse sobre la silla).
func aim_facing() -> Vector3:
	return facing.rotated(Vector3.UP, rider_yaw) if mounted else facing

## Ronda 17: aturdimiento que causa el golpe actual de este luchador.
func current_hitstun() -> float:
	if atk_dash or atk_jump:
		return 0.45
	if atk_heavy:
		return melee().heavy_hitstun
	if cur_hit:
		return cur_hit.hitstun
	return 0.3

func has_shield() -> bool:
	return melee().allows_shield and character.shield_mesh != ""

func stats() -> MountData:
	return mount_node.data if mounted and mount_node else foot_stats

func speed_mult() -> float:
	return character.velocidad * float(mods["velocidad"]) * float(roll_mod()["move"])

func sword_range() -> float:
	if cur_hit and atk_state != Atk.NONE:
		return cur_hit.reach * (melee().reach_mounted / maxf(melee().reach_foot, 0.1) if mounted else 1.0)
	return melee().reach_mounted if mounted else melee().reach_foot

func sword_half_arc() -> float:
	if cur_hit and atk_state != Atk.NONE:
		return deg_to_rad(minf(cur_hit.arc_deg * (1.3 if mounted else 1.0), 180.0))
	return deg_to_rad(melee().half_arc_mounted_deg if mounted else melee().half_arc_foot_deg)

func max_combo() -> int:
	return melee().combo.size() if not melee().combo.is_empty() else melee().max_combo

## Ronda 16: golpe de la cadena n (1..3) para este personaje y arma (null = ligero genérico).
func combo_hit_for(n: int) -> ComboHit:
	return melee().combo_hit(n - 1, character)

## Multiplicador de daño de poise del golpe actual (remates > 1).
func poise_mult_now() -> float:
	var k := melee().poise_damage_mult
	if cur_hit and atk_state != Atk.NONE:
		k *= cur_hit.poise_mult
	if atk_gc and atk_state != Atk.NONE:
		k *= GC_POISE
	k *= 1.0 + CHARGE_BONUS * charge_t / CHARGE_MAX
	return k * float(PhysTypes.POISE_MOD.get(phys_now(), 1.0))

## Ronda 24: subtipo físico del golpe en curso.
func phys_now() -> String:
	if atk_heavy or atk_dash or atk_jump:
		return melee().phys_type
	return PhysTypes.of_hit(melee(), cur_hit)

## ¿Toca el suelo? (para los golpes de área en el suelo). En el fénix se vuela.
func is_grounded() -> bool:
	if mounted and mount_node and mount_node.is_flying():
		return false
	return not airborne and not ab_air and global_position.y < GroundAoE.GROUND_HEIGHT

func is_dash_striking() -> bool:
	return atk_state != Atk.NONE and (_ds_visual or atk_dash)

func roll_iframe_end() -> float:
	return maxf(ROLL_IFRAME_END + (character.roll_iframe_bonus + int(mods["roll_iframes"]) + int(ad["iframes"]) + int(roll_mod()["iframes"]) + int(tfx["roll_iframes"])) / ROLL_FPS, ROLL_STARTUP)

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
	_kv.set_base_glow(Smithing.engraving_glow(melee().upgrade_level)) # ronda 30: grabado +5
	_kv.set_armor(armor_pieces())
	_body = MeshUtil.box(_prim, Vector3(0.6, 1.0, 0.45), Vector3(0, 1.0, 0.1), color)
	MeshUtil.own(_body) # se tiñe con los estados
	MeshUtil.sphere(_prim, 0.25, Vector3(0, 1.75, 0.1), Color(0.95, 0.8, 0.65))
	for x: float in [-0.15, 0.15]:
		_legs.append(MeshUtil.box(_prim, Vector3(0.2, 0.55, 0.25), Vector3(x, 0.27, 0.1), color.darkened(0.4)))
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.45, 1.1, 0.0)
	_prim.add_child(_sword_pivot)
	_blade = MeshUtil.box(_sword_pivot, Vector3(0.1, 0.1, 1.0), Vector3(0, 0, -0.5), Color(0.85, 0.85, 0.95))
	MeshUtil.box(_sword_pivot, Vector3(0.4, 0.08, 0.08), Vector3(0, 0, 0), Color(0.6, 0.5, 0.2)) # guarda
	_blade_mat = MeshUtil.own(_blade)
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
	if not alive:
		return false
	# Ronda 17: tu eikon sin jinete: «Montar» lo llama (viene corriendo desde cualquier distancia y
	# te monta solo al llegar, aunque estés atacando o aturdido: monta en cuanto quedes libre).
	# Pulsar otra vez cancela la llamada.
	if not mounted and is_instance_valid(owned_mount) and owned_mount.owner_fighter == self and owned_mount.can_ride(self):
		if owned_mount.called:
			owned_mount.called = false
			return false
		if can_mount_now() and global_position.distance_to(owned_mount.global_position) <= MOUNT_REACH:
			return mount_on(owned_mount)
		owned_mount.called = true
		return false
	if not can_mount_now():
		return false
	if mounted:
		dismount(false)
		return true
	if can_remount():
		return mount_on(nearest_free_mount())
	return false

## ¿Libre para subir/bajar de la montura ahora mismo?
func can_mount_now() -> bool:
	return alive and stun <= 0.0 and atk_state == Atk.NONE and swap_t <= 0.0 and not airborne and special_t <= 0.0 and roll_t < 0.0 and not is_shooting()

# ---------------- Aguante ----------------

func spend_stamina(v: float) -> void:
	if v > 0.0:
		v *= float(tfx["stamina_cost"]) # ronda 30: talismanes
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
		stamina = minf(stamina + (REGEN_IDLE if idle else REGEN) * float(roll_mod()["regen"]) * status_fx.regen_mult() * (BLOCK_REGEN_MULT if blocking else 1.0) * delta, stamina_max)
		stamina_changed.emit(stamina, exhausted > 0.0)

# ---------------- Bucle principal ----------------

func _physics_process(delta: float) -> void:
	riposte_t = maxf(riposte_t - delta, 0.0)
	if alive:
		var pd := status_fx.tick(delta)
		if pd > 0.0:
			health = maxf(health - pd, 0.0)
			health_changed.emit(health, max_health)
			if health <= 0.0:
				alive = false
				died.emit(self)
	_status_flash = maxf(_status_flash - delta, 0.0)
	_since_hit += delta
	_update_stun_meter(delta) # ronda 31: ventana de acumulación (sustituye a la regeneración de poise)
	# Pasiva "Luz sanadora": se cura si lleva 3 s sin recibir golpes
	if character.passive_id == "luz_sanadora" and alive and _since_hit > 3.0 and health < max_health:
		var hv := minf(2.0 * passive_k() * float(ad["curacion"]) * delta, max_health - health)
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
	_update_shot(delta)
	dash_cd = maxf(dash_cd - delta, 0.0)
	special_cd = maxf(special_cd - delta, 0.0)
	if energy < energy_max:
		energy = minf(energy + float(ad["energia_regen"]) * delta, energy_max)
		energy_changed.emit(energy, energy_max)
	land_t = maxf(land_t - delta, 0.0)
	if special_t > 0.0:
		special_t = maxf(special_t - delta, 0.0)
	_update_magic(delta)
	_update_exchange(delta)
	_update_boss(delta)
	_update_ability(delta)
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
		elif roll_t >= roll_total() or not alive:
			roll_t = -1.0
			_roll_atk_buffer = false
	if was_dashing and dash_time <= 0.0:
		_on_dash_end()
	stun = maxf(stun - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	var st := stats()
	var inp := move_input
	if not alive or stun > 0.0 or special_t > 0.0 or cast_t > 0.0 or crit_t >= 0.0 or boss_phase != Boss.NONE or (ab_id != "" and ab_id != "escudo_mana"):
		inp = Vector3.ZERO
	elif ab_id == "escudo_mana":
		inp *= 0.5 # ronda 31: con el escudo de maná te mueves despacio
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
	# Ronda 30: a pie se gira con velocidad angular fija (~800°/s), no a saltos
	var turn := (deg_to_rad(TURN_RATE_DEG) if fluid and not mounted else st.turn_speed) * delta
	# Ronda 29 (regla soulslike): el seguimiento solo existe en la anticipación; en frames activos y
	# recuperación la dirección del golpe queda comprometida. En el aire tampoco se gira.
	if turning_locked():
		turn = 0.0
	reversing = false
	var run_req := want_sprint and amount > 0.3 and exhausted <= 0.0 and not blocking and stamina > 0.0
	if shot_state != Shot.NONE and not mounted:
		run_req = false # disparar a pie corta la carrera (vuelve a andar)
	run_away = false
	if _lock_valid() and run_req and amount > 0.05:
		# Ronda 16: corriendo fijado, si la entrada se aleja más de RUN_TURN_DEG del rival el
		# personaje se gira y corre hacia allí (hacia la cámara), sin correr de espaldas.
		var d0 := MeshUtil.flat(face_target.global_position - global_position)
		if d0.length() > 0.1 and rad_to_deg(d0.normalized().angle_to(inp.normalized())) > RUN_TURN_DEG:
			run_away = true
	if run_away:
		var dirn := inp.normalized()
		facing = _turn_toward(facing, dirn, turn * (1.0 if fluid and not mounted else 2.2))
		target_vel = facing * st.speed * speed_mult() * amount
	elif _lock_valid():
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
		# Ronda 25: sin fijar, solo se retrocede (montado, sin galopar) si la entrada es casi
		# exactamente hacia atrás; en diagonal atrás (S+A / S+D) se gira y anda/corre hacia allí.
		if mounted and not run_req and dirn.dot(facing) < -0.92:
			reversing = true
			target_vel = -facing * st.speed * speed_mult() * REVERSE_FACTOR * amount
		else:
			# Sin fijar, correr gira al personaje con normalidad.
			facing = _turn_toward(facing, dirn, turn * (1.4 if run_req and not mounted and not fluid else 1.0))
			target_vel = facing * st.speed * speed_mult() * amount
	# Galope (montado, igual que antes) / correr a pie (también de espaldas si va fijado)
	sprinting = run_req and (not reversing or (not mounted and _lock_valid()) or run_away)
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
	# Ronda 17: compromiso del disparo a pie (montado se dispara sin penalizar a la montura)
	if not mounted:
		match shot_state:
			Shot.DRAW:
				target_vel = Vector3.ZERO
				planar_vel = Vector3.ZERO # raíz inmediata al tensar
			Shot.RECOVER: target_vel *= ranged().fire_slow
			Shot.RELOAD: target_vel *= ranged().reload_slow
	# Jinete girado sobre la silla: mira al rival mientras la montura huye
	var want_yaw := 0.0
	if mounted and _lock_valid():
		var dt := MeshUtil.flat(face_target.global_position - global_position)
		if dt.length() > 0.1:
			want_yaw = facing.signed_angle_to(dt.normalized(), Vector3.UP)
	rider_yaw = lerp_angle(rider_yaw, want_yaw, clampf(delta * 10.0, 0.0, 1.0)) if mounted else 0.0
	_rider_root.rotation.y = rider_yaw
	_update_stamina(delta, amount < 0.3 or reversing)
	# Ronda 29: salto comprometido. La trayectoria queda fijada al despegar (sin control aéreo).
	if not airborne:
		planar_vel = _steer_velocity(planar_vel, target_vel, st.acceleration * delta, deg_to_rad(TURN_RATE_DEG) * 1.15 * delta) if fluid and not mounted else planar_vel.move_toward(target_vel, st.acceleration * delta)
	var v := planar_vel
	if atk_dash and not mounted and (atk_state == Atk.WINDUP or atk_state == Atk.ACTIVE):
		v = _lunge_velocity()
		planar_vel = v * 0.5
	elif cur_hit and cur_hit.lunge > 0.0 and not mounted and _combo_lunging():
		v = facing * cur_hit.lunge * speed_mult()
		planar_vel = v * 0.5
	elif (_step_left > 0.0 or (atk_heavy and charge_t > 0.0 and not _charge_added)) and not mounted and not atk_dash and not atk_jump and (atk_state == Atk.WINDUP or atk_state == Atk.ACTIVE):
		v = _step_velocity(delta)
		if v != Vector3.ZERO:
			planar_vel = Vector3.ZERO
	elif ab_id != "" and ab_id != "escudo_mana":
		v = ab_vel
		planar_vel = Vector3.ZERO
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
	for other: Fighter in all:
		if other != self:
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
	_clamp_world()
	if not mounted and not airborne and alive and roll_t < 0.0:
		_step_d += MeshUtil.flat(velocity).length() * delta
		if _step_d >= (2.2 if sprinting else 1.5):
			_step_d = 0.0
			_snd("step")
	if airborne:
		_air_t += delta
		if _air_t > 0.08 and (is_on_floor() or global_position.y < 0.02) and velocity.y <= 0.0:
			_land()
	rotation.y = atan2(-facing.x, -facing.z)
	# Ronda 30: inclinación del cuerpo hacia el giro (según velocidad angular y rapidez)
	var yr := wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = rotation.y
	var spd_k := clampf(MeshUtil.flat(velocity).length() / maxf(stats().speed, 0.1), 0.0, 1.5)
	var lean_t := clampf(yr * LEAN_K * spd_k, -LEAN_MAX, LEAN_MAX) if not mounted and not airborne else 0.0
	lean = lerpf(lean, lean_t, clampf(delta * 10.0, 0.0, 1.0))
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	# Visuales
	var sy := _rider_root.position.y
	if _flash > 0.0:
		_flash -= delta
	var bc := color
	if _flash > 0.0:
		bc = Color.WHITE
	elif _status_flash > 0.0:
		bc = color.lerp(_status_flash_c, 0.75)
	elif status_fx.frost_t > 0.0:
		bc = color.lerp(StatusFx.COLORS["congelacion"], 0.45)
	elif status_fx.poison_t > 0.0:
		bc = color.lerp(StatusFx.COLORS["veneno"], 0.4)
	elif exhausted > 0.0:
		bc = color.lerp(Color(0.5, 0.5, 0.5), 0.6)
	(_body.material_override as StandardMaterial3D).albedo_color = bc
	var ec := Color.WHITE
	if _flash <= 0.0:
		if _status_flash > 0.0:
			ec = _status_flash_c
		elif status_fx.frost_t > 0.0:
			ec = StatusFx.COLORS["congelacion"] * 0.35
		elif status_fx.poison_t > 0.0:
			ec = StatusFx.COLORS["veneno"] * 0.3
	_kv.set_tint(bc, _flash > 0.0 or _status_flash > 0.0 or status_fx.frost_t > 0.0 or status_fx.poison_t > 0.0, ec)
	_update_aura()
	_kv.update(self, delta)
	_rider_root.rotation.x = 0.0 # la voltereta la hace la animación Dodge_*
	_rider_root.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2 if stun > 0.0 else lean
	_rider_root.position.y = sy
	if mounted and mount_node:
		# Sentado en la silla: la cadera sigue el punto de silla del caballo
		_rider_root.position = to_local(mount_node.saddle_position())

## Arremetida del golpe de combo: final de la anticipación y frames activos, sin meterse en el rival.
func _combo_lunging() -> bool:
	if not (atk_state == Atk.ACTIVE or (atk_state == Atk.WINDUP and atk_t > atk_dur * 0.55)):
		return false
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	return tgt == null or MeshUtil.flat(tgt.global_position - global_position).length() > 1.3

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
	return atk_state == Atk.RECOVERY or boss_phase == Boss.RECOVER

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.6 if mounted else 1.0, 0)

func add_meter(v: float) -> void:
	if v > 0.0:
		v *= float(ad["medidor"]) * float(tfx["eikon_rate"])
	meter = clampf(meter + v, 0.0, METER_MAX)
	meter_changed.emit(meter)

func _can_act() -> bool:
	return alive and stun <= 0.0 and exhausted <= 0.0 and land_t <= 0.0 and special_t <= 0.0 and cast_t <= 0.0 and crit_t < 0.0 and boss_phase == Boss.NONE and ab_id == ""

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
	if cur_hit and not atk_dash and not atk_jump and not atk_heavy:
		d = cur_hit.attack_dict()
	d["damage"] = d["damage"] * damage_mult() * (1.0 + CHARGE_BONUS * charge_t / CHARGE_MAX)
	var sp := attr_speed()
	for k: String in ["windup", "chain_windup", "recovery", "whiff"]:
		d[k] = d[k] / sp
	return d

## Multiplicador de daño cuerpo a cuerpo: personaje, lanza a caballo y pasiva "Furia".
func damage_mult() -> float:
	var k := character.dano * float(mods["dano"]) * weapon_attr_mult(melee()) * melee().upgrade_dmg_mult * _art_mult
	if mounted:
		k *= melee().mounted_damage_mult
	if character.passive_id == "furia" and health < max_health * 0.4:
		k *= 1.0 + 0.25 * passive_k()
	return k * Trinkets.dmg_mult(tfx, melee().phys_type)

func _request_attack(heavy: bool) -> bool:
	if roll_t >= 0.0 and not mounted and loadout == Loadout.SWORD_SHIELD and alive and roll_t < roll_iframe_end():
		_roll_atk_buffer = true # búfer: la estocada sale al acabar los i-frames
		return false
	if loadout != Loadout.SWORD_SHIELD or not _can_act() or swap_t > 0.0 or parry_state != Parry.NONE or roll_t >= 0.0:
		return false
	if not mounted and not airborne and atk_state == Atk.NONE and stamina > 0.0:
		var ct := crit_candidate()
		if ct:
			_start_crit(ct)
			return true
		if guard_counter_t > 0.0:
			# Contra de guardia: fuerte rápido, súper-armadura y mucho daño de equilibrio
			guard_counter_t = 0.0
			blocking = false
			combo = max_combo()
			_start_attack(true, false)
			atk_gc = true
			atk_dur *= GC_WINDUP_MULT
			guard_counters += 1
			return true
		if sprinting and not heavy and move_input.length() > 0.5:
			# Fase 2: ataque corriendo = embestida con la inercia
			dash_dir = MeshUtil.flat(move_input).normalized()
			running_attacks += 1
			_start_dash_strike()
			return true
	if mounted and absf(rad_to_deg(rider_yaw)) > MELEE_TWIST_MAX_DEG:
		return false # girado en la silla (huyendo): solo se puede disparar
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
		var in_window := atk_state != Atk.RECOVERY or cur_hit == null or atk_t <= cur_hit.window
		if not heavy and not atk_heavy and combo < max_combo() and in_window and (atk_state != Atk.WINDUP or atk_t > atk_dur * 0.5):
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
	_art_mult = 1.0
	atk_gc = false
	charge_t = 0.0
	_step_total = 0.0
	step_travel = 0.0
	if not mounted:
		var w := melee()
		if heavy:
			_step_total = w.step_heavy
		elif not w.step_light.is_empty():
			_step_total = w.step_light[clampi(combo - 1, 0, w.step_light.size() - 1)]
	_step_left = _step_total
	_charge_added = false
	atk_heavy = heavy
	cur_hit = null
	if not heavy and not atk_dash and not atk_jump:
		cur_hit = combo_hit_for(combo)
		if cur_hit:
			combo_log.append(cur_hit.name)
			if combo_log.size() > 12:
				combo_log.pop_front()
	var d := _atk_data()
	atk_state = Atk.WINDUP
	atk_t = 0.0
	atk_dur = d["chain_windup"] if chained else d["windup"]
	_atk_landed = false
	_atk_hit.clear()
	_buffered = false
	attacks_started += 1
	spend_stamina(d["stamina"])
	_snd("swing_heavy" if heavy or EquipStats.weapon_weight(melee()) >= 8.0 else "swing_light")
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt and global_position.distance_to(tgt.global_position) < sword_range() + 1.5:
		var dd := MeshUtil.flat(tgt.global_position - global_position)
		# Ronda 23: con objetivo fijado se encara siempre; sin fijar, solo si está delante
		if dd.length() > 0.1 and (_lock_valid() or facing.dot(dd.normalized()) > 0.0):
			facing = dd.normalized()
	# Telegrafía: hoja alzada y brillante
	_sword_pivot.rotation = Vector3(1.4 if heavy else 1.0, sword_half_arc(), 0)
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1.0, 0.45, 0.1) if heavy else Color(1.0, 0.9, 0.4)
	_blade_mat.emission_energy_multiplier = 3.0
	_kv.set_glow(true, _blade_mat.emission)

## Parry dedicado (tecla Q / botón Parry). Solo con espada+escudo.
func parry() -> bool:
	if mounted: # ronda 21: sin parry montado
		return false
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
	cur_hit = null
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
			# Fase 2: fuerte cargado — mantener el botón retiene el golpe al final de la anticipación
			if atk_heavy and not atk_gc and not mounted and want_charge and atk_t >= atk_dur and charge_t < CHARGE_MAX and stamina > 0.0:
				charge_t = minf(charge_t + delta, CHARGE_MAX)
				atk_t = atk_dur - 0.001
				return
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
				if not _atk_landed:
					_snd("whiff")
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
			if atk_heavy or was_open:
				hitstop.emit(HITSTOP_HEAVY) # ronda 23: fuertes y castigos «pesan»
				impact.emit(0.9)
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
	if loadout != Loadout.BOW or swap_t > 0.0 or atk_state != Atk.NONE or shot_state != Shot.NONE:
		return false
	if not _can_act() or bow_cd > 0.0 or stamina <= 0.0 or roll_t >= 0.0:
		return false
	var r := ranged()
	spend_stamina(COST_BOW)
	shot_state = Shot.DRAW
	shot_t = 0.0
	shot_dur = r.fire_draw / attr_speed()
	if r.reload_time <= 0.0:
		_snd("bow_draw")
	if not mounted:
		shot_cut_sprint = want_sprint or sprinting
		sprinting = false
	return true

func _update_shot(delta: float) -> void:
	if shot_state == Shot.NONE:
		return
	if stun > 0.0 and shot_state == Shot.DRAW:
		shot_state = Shot.NONE # interrumpido: no sale el tiro
		bow_cd = 0.2
		return
	shot_t += delta
	if shot_t < shot_dur:
		_hold_t = 0.0
		return
	# Ronda 32: con el botón mantenido se queda tensado y apuntando (sin límite) y dispara al soltar;
	# pasado CHARGE_HOLD el tiro sale cargado (brillo en el arco + sonido al alcanzarlo).
	if shot_state == Shot.DRAW and want_shot_hold:
		var was := _hold_t
		_hold_t += delta
		if was < CHARGE_HOLD and _hold_t >= CHARGE_HOLD:
			charge_ready_events += 1
			_snd("bow_draw", 6.0)
			if _kv:
				_kv.set_bow_charged(true)
		return
	var r := ranged()
	shot_t = 0.0
	match shot_state:
		Shot.DRAW:
			# Ronda 31: mantener = espera CHARGE_HOLD s más y sale cargado; soltar antes = normal.
			shot_charged = _hold_t >= CHARGE_HOLD - 0.001
			_hold_t = 0.0
			if _kv:
				_kv.set_bow_charged(false)
			_release_shot(shot_charged)
			shot_state = Shot.RECOVER
			shot_dur = r.fire_recovery * (1.2 if shot_charged else 1.0)
		Shot.RECOVER:
			if r.reload_time > 0.0:
				shot_state = Shot.RELOAD
				shot_dur = r.reload_time
				_snd("xbow_reload")
			else:
				shot_state = Shot.NONE
				bow_cd = r.fire_cooldown
		Shot.RELOAD:
			shot_state = Shot.NONE
			bow_cd = r.fire_cooldown

func _release_shot(charged: bool = false) -> void:
	var r := ranged()
	var af := aim_facing()
	var origin := get_hit_center() + Vector3(0, 0.8, 0) + af * 1.4
	var dir := af
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var d: Vector3 = tgt.get_hit_center() - origin
		if MeshUtil.flat(d).normalized().dot(af) > -0.2:
			dir = Projectile.aim_dir(origin, tgt, r.projectile_speed, aim_lead)
	var kind := charged_shot_kind() if charged else ""
	var dmg_k := 1.0
	var spd_k := 1.0
	var stun_k := 1.0
	var n := 1
	if charged:
		charged_shots += 1
		if kind == "potente":
			dmg_k = 2.4 if character.passive_id == "ojo_de_halcon" else 2.2
			spd_k = 1.4
			stun_k = 2.5
		else: # triple (ballesta): abanico de 3
			n = 3
			dmg_k = 0.7
			stun_k = 1.2
	for i in n:
		var p := Projectile.new()
		p.team = team
		p.shooter = self
		p.direction = dir.rotated(Vector3.UP, (i - 1) * 0.18 if n > 1 else 0.0).normalized()
		p.aimed_at = tgt if (n == 1 or i == 1) else null
		p.speed = r.projectile_speed * spd_k
		p.hitstun = r.ranged_hitstun * stun_k
		if charged:
			p.stun_force = arrow_stun_force(p.hitstun)
		p.damage = r.arrow_damage * dmg_k * (1.0 + 0.3 * passive_k() if character.passive_id == "ojo_de_halcon" else 1.0) * weapon_attr_mult(r) * r.upgrade_dmg_mult
		p.color = Color(1.0, 0.55, 0.2) if charged else (Color(0.9, 0.8, 0.5) if r.reload_time <= 0.0 else Color(0.75, 0.85, 1.0))
		get_parent().add_child(p)
		p.global_position = origin
	shots_fired += n
	_snd("xbow_fire" if r.reload_time > 0.0 else "bow_release")
	_kv.event("shoot")

## Dash montado / voltereta a pie.
## Ronda 33: el botón de esquiva es la voltereta; la estocada con dash (dash en la anticipación
## del ligero) queda desactivada pero conservada para el futuro.
static var dash_strike_enabled: bool = false

func dash() -> bool:
	_stagger_roll_cancel() # ronda 31
	if not _can_act() or dash_cd > 0.0 or stamina <= 0.0 or parry_state != Parry.NONE or roll_t >= 0.0:
		return false
	if airborne or special_t > 0.0:
		return false
	if atk_state != Atk.NONE:
		if mounted and atk_state == Atk.WINDUP:
			_ds_visual = true # montado: el ataque sigue cargándose durante el dash y golpea al final
		elif dash_strike_enabled and not mounted and atk_state == Atk.WINDUP and not atk_heavy and not atk_dash and not atk_jump:
			# A pie: dash durante la anticipación del ligero = estocada con dash
			var mi0 := MeshUtil.flat(move_input)
			dash_dir = mi0.normalized() if mi0.length() > 0.2 else facing
			spend_stamina(COST_ROLL * character.roll_cost_mult * float(mods["roll_cost"]) * float(ad["roll_cost"]))
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
	dash_time = roll_total() # solo para la animación Dodge_* y la IA (no da i-frames)
	dash_cd = maxf(st.dash_cooldown, roll_total())
	invuln = 0.0
	_dash_hit = true # la voltereta no embiste
	_snd("roll")
	spend_stamina(COST_ROLL * character.roll_cost_mult * float(mods["roll_cost"]) * float(ad["roll_cost"]))
	return true

func _roll_velocity() -> Vector3:
	var fast := ROLL_IFRAME_END # la distancia no cambia con la pasiva "Sombra" (solo los i-frames)
	if roll_t < fast:
		return dash_dir * (ROLL_DISTANCE * float(roll_mod()["dist"]) / fast)
	# Recuperación: frena linealmente (área = ROLL_RECOVERY_DRIFT)
	var rec := roll_total() - fast
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
	_snd("jump", -4.0)
	return true

func _land() -> void:
	airborne = false
	_air_t = 0.0
	velocity.y = 0.0
	land_t = LAND_RECOVERY
	_snd("land", -4.0)
	if atk_jump and atk_state == Atk.WINDUP:
		atk_t = atk_dur # el picado golpea al tocar el suelo

func has_special() -> bool:
	return character.special_id != ""

## Habilidad del personaje (G / botón "Habilidad"). Berserker: golpe sísmico.
## Ronda 21: sin habilidad propia, el botón usa el arte del arma equipada.
func special() -> bool:
	if not has_special():
		return use_weapon_art()
	if not _can_act() or special_cd > 0.0 or airborne or mounted or roll_t >= 0.0:
		return false
	if atk_state != Atk.NONE or parry_state != Parry.NONE or swap_t > 0.0 or stamina <= 0.0:
		return false
	if energy < SLAM_ENERGY:
		return false
	match character.special_id:
		"golpe_sismico":
			energy -= SLAM_ENERGY
			energy_changed.emit(energy, energy_max)
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
	_snd({"llamarada": "eikon_fire", "colmillo": "eikon_ice", "vendaval": "eikon_wind"}.get(ed.special_id, "eikon_fire"))
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	match ed.special_id:
		"llamarada":
			var p := Projectile.new()
			p.team = team
			p.shooter = self
			p.kind = "eikon"
			p.damage = ed.special_damage * float(ad["eikon"])
			p.speed = 24.0
			p.radius = 0.7
			p.color = ed.color
			p.aimed_at = tgt
			var origin := global_position + Vector3(0, 1.6 + m.data.hover, 0) + facing * 1.8
			p.direction = (Projectile.aim_dir(origin, tgt, p.speed, aim_lead) if tgt else facing)
			get_parent().add_child(p)
			p.global_position = origin
		"colmillo":
			knock = facing * 10.0
			for t in MeshUtil.enemies_of(get_tree(), team):
				var d := MeshUtil.flat(t.global_position - global_position)
				if d.length() < 4.5 and (d.length() < 0.5 or absf(facing.signed_angle_to(d.normalized(), Vector3.UP)) < deg_to_rad(60)):
					if t.take_hit(ed.special_damage * float(ad["eikon"]), self, "eikon") == "hit" and t is Fighter:
						(t as Fighter).apply_stun(0.5) # congelado un instante
		"vendaval":
			for t in MeshUtil.enemies_of(get_tree(), team):
				var d := MeshUtil.flat(t.global_position - global_position)
				if d.length() < 5.5:
					var r: String = t.take_hit(ed.special_damage * float(ad["eikon"]), self, "eikon")
					if (r == "hit" or r == "block") and t.has_method("apply_knockback"):
						t.apply_knockback((d.normalized() if d.length() > 0.1 else facing) * 14.0, r == "hit")
	impact.emit(0.6)
	return true

## Ronda 21: se puede invocar ya (medidor lleno, sin eikon activo, sin aturdir).
func can_summon() -> bool:
	return alive and eikon != null and not is_instance_valid(active_eikon) and meter >= METER_MAX and stun <= 0.0

## Hay un eikon activo en la arena (el botón Montar solo tiene sentido entonces).
func has_active_eikon() -> bool:
	return is_instance_valid(active_eikon) or (mounted and mount_node != null and mount_node.eikon != null)

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
	_snd("eikon_summon")
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
	_snd("eikon_summon")
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
	if boss_phase == Boss.CHARGE or boss_phase == Boss.LUNGE:
		return # ronda 25: la habilidad de jefe no se interrumpe
	if stun_immune_t > 0.0 or ab_immune():
		return # ronda 31: levantándose de un derribo / escudo de maná
	if ab_id != "":
		_end_ability(true) # interrumpida
	stun = maxf(stun, t)
	if atk_state != Atk.NONE:
		_cancel_attack()

## Devuelve "hit", "block", "parry", "dodge" o "none".
func take_hit(amount: float, from: Node3D, _kind: String) -> String:
	_hit_element = incoming_element
	_hit_status = incoming_status
	incoming_element = ""
	incoming_status = {}
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
	if parry_state == Parry.ACTIVE and frontal and _kind != "eikon" and _kind != "aoe" and _kind != "jefe":
		if from is Fighter and _kind == "melee":
			(from as Fighter).apply_stun(PARRY_STAGGER)
			(from as Fighter).riposte_t = PARRY_STAGGER
		add_meter(15.0)
		parries_landed += 1
		if float(tfx["parry_stamina"]) > 0.0:
			stamina = minf(stamina + float(tfx["parry_stamina"]), stamina_max)
			stamina_changed.emit(stamina, exhausted > 0.0)
		parry_state = Parry.NONE # éxito: sin recuperación
		hitstop.emit(HITSTOP_PARRY)
		impact.emit(0.7)
		_snd("parry")
		return "parry"
	if parry_state == Parry.RECOVERY:
		amount *= PARRY_EXPOSED_MULT
	if blocking and frontal:
		if _kind == "arrow":
			spend_stamina(COST_BLOCKED_ARROW) # flecha anulada por completo
			_kv.event("block_hit")
			_snd("block")
			if stamina <= 0.0:
				_guard_break()
			return "block"
		if _kind == "eikon" or _kind == "aoe":
			_damage(amount * maxf(EIKON_BLOCK_PASS, EXHAUSTED_BLOCK_REDUCTION if exhausted > 0.0 else 0.0))
			spend_stamina(COST_BLOCKED_EIKON)
			add_meter(3.0)
			_kv.event("block_hit")
			_snd("block")
			if stamina <= 0.0:
				_guard_break()
			return "block"
		guard_counter_t = GUARD_COUNTER_WINDOW # ronda 24: ventana de contra de guardia
		var chip := BLOCK_REDUCTION if has_shield() else melee().no_shield_block_chip
		_damage(amount * (EXHAUSTED_BLOCK_REDUCTION if exhausted > 0.0 else chip))
		spend_stamina(blocked_hit_cost(amount, from))
		add_meter(3.0)
		_kv.event("block_hit")
		_snd("block")
		if stamina <= 0.0:
			_guard_break()
		return "block"
	if riposte_t > 0.0 and _kind == "melee":
		amount *= RIPOSTE_MULT # riposte tras parry
		riposte_t = 0.0
	# Ronda 18: Vitalidad = defensa física; Devoción = resistencia sagrada (eikon/área)
	# Ronda 19: Defensa (plana, nivel y atributos) y Absorción % de la armadura por tipo de daño
	# Ronda 24: contraataque — te golpean mientras atacas (anticipación o golpe)
	var counter := false
	var sub := ""
	if from is Fighter and is_instance_valid(from) and (_kind == "melee" or _kind == "critico"):
		sub = (from as Fighter).phys_now()
	elif _kind == "jefe":
		sub = "perforante"
	if from is Fighter and (_kind == "melee" or _kind == "arrow") and (atk_state == Atk.WINDUP or atk_state == Atk.ACTIVE or cast_t > 0.0):
		counter = true
		amount *= float(PhysTypes.COUNTER_DMG.get(sub if sub != "" else "estandar", 1.15))
		(from as Fighter).counter_hits += 1
		(from as Fighter).counter_landed.emit(self)
	amount = EquipStats.incoming(amount, _damage_type(from, _kind), eq, eq_ref, sub)
	if _kind == "eikon" or _kind == "aoe":
		amount *= 1.0 - float(ad["sagrado"])
	if _kind == "aoe":
		amount *= EquipStats.resist_mult("inmunidad", eq, eq_ref) # Inmunidad: daño de área
	amount *= status_fx.damage_taken_mult() # congelación: más daño recibido
	if stun_immune_t > 0.0 and knockdowns > 0:
		amount *= StunRules.GETUP_DMG_MULT # ronda 31: levantándose de un derribo
	if stoneskin_t > 0.0:
		amount *= 1.0 - float(_stoneskin.get("reduction", 0.0)) # Piel de piedra
	_damage(amount)
	add_meter(5.0)
	_kv.event("hit")
	if _kind == "arrow":
		_snd("arrow_hit")
	_snd("hit_armor" if not eq.is_empty() and float(eq["absorcion"].get("fisico", 0.0)) >= 0.3 else "hit_flesh")
	var stx := _hit_status if not _hit_status.is_empty() else _status_from(from, _kind)
	for sk: String in stx:
		add_status(sk, float(stx[sk]))
	if _kind == "melee":
		impact.emit(0.5)
	# Ronda 31: la postura (stance) se sigue gastando con el daño; el aturdimiento es ACUMULADO
	# (StunRules): fuerza del golpe contra la robustez en una ventana de unos segundos.
	_since_hit = 0.0
	var pd := amount * 2.0 / (float(_stoneskin.get("poise", 1.0)) if stoneskin_t > 0.0 else 1.0) * ((from as Fighter).poise_mult_now() * float((from as Fighter).ad["impacto"]) if from is Fighter and _kind == "melee" else 1.0)
	if counter:
		pd *= PhysTypes.COUNTER_POISE
	if _kind == "jefe":
		pd *= BOSS_POISE
	if _kind != "critico":
		stance -= pd
	var sforce := _incoming_force(from, _kind, amount)
	incoming_arrow_stun = 0.0
	if counter:
		sforce *= StunRules.COUNTER_K
	if stance <= 0.0 and alive and not mounted:
		# Rotura de postura: expuesto ~1,2 s a un crítico frontal
		stance = stance_max
		stance_broken_t = STANCE_BREAK_TIME
		stance_breaks += 1
		blocking = false
		_cancel_attack()
		_reset_stun_meter()
		apply_stun(STANCE_BREAK_TIME)
		stance_broken.emit()
		_snd("guard_break")
		return "hit"
	if _kind != "critico":
		add_stun_force(sforce)
	if mounted and alive and amount >= HEAVY_HIT and randf() < knockoff_chance_heavy:
		dismount(true)
	return "hit"

## Sin aguante bajo el escudo: guardia rota, tambaleo y expuesto.
func _guard_break() -> void:
	guard_breaks += 1
	blocking = false
	_snd("guard_break")
	apply_stun(GUARD_BREAK_STAGGER * (EquipStats.resist_mult("concentracion", eq, eq_ref) if not eq.is_empty() else 1.0))
	impact.emit(0.8)

## Aguante que cuesta bloquear un golpe: ligero/fuerte, rompeguardias del atacante,
## guardia del personaje, pasiva "Guardia firme" y bloqueo sin escudo (x1.5).
func blocked_hit_cost(amount: float, from: Node3D) -> float:
	var c := COST_BLOCKED_HIT * (COST_BLOCKED_HEAVY_MULT if amount >= HEAVY_HIT else 1.0)
	if from is Fighter:
		c *= (from as Fighter).melee().guard_break_mult * float((from as Fighter).ad["impacto"])
	c *= float(ad["guard_k"])
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
	cast_t = 0.0
	_cast_id = ""
	crit_t = -1.0
	_crit_target = null
	_end_boss()
	_end_ability(true)
	_reset_stun_meter()
	down_t = 0.0
	stagger_t = 0.0
	stun_immune_t = 0.0
	want_shot_hold = false
	shot_charged = false
	charged_shots = 0
	boss_cd = 0.0
	stance = stance_max
	stance_broken_t = 0.0
	guard_counter_t = 0.0
	charge_t = 0.0
	spell_cd = {}
	stoneskin_t = 0.0
	art_cd = 0.0
	_art_mult = 1.0
	energy = energy_max
	energy_changed.emit(energy, energy_max)
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
	status_fx.reset()
	var start_l := Loadout.BOW if weapon.ranged else Loadout.SWORD_SHIELD
	if swap_t > 0.0 or loadout != start_l:
		swap_t = 0.0
		loadout = start_l
		_apply_loadout_visuals()
		loadout_changed.emit(loadout)
	bow_cd = 0.0
	shot_state = Shot.NONE
	rider_yaw = 0.0
	dash_cd = 0.0
	health_changed.emit(health, max_health)
	meter_changed.emit(meter)
	stamina_changed.emit(stamina, false)


# ---------------- Ronda 21: magia de eikon y artes de arma ----------------

func set_magic(sp: Array, art: String) -> void:
	spells = sp.duplicate()
	spell_idx = 0
	for i in spells.size():
		if String(spells[i]) != "":
			spell_idx = i
			break
	weapon_art_id = art

func has_spells() -> bool:
	for s in spells:
		if String(s) != "":
			return true
	return false

func current_spell() -> String:
	return String(spells[spell_idx]) if spell_idx < spells.size() else ""

## Siguiente ranura con hechizo (T / botón «↻»).
func cycle_spell() -> String:
	if not has_spells():
		return ""
	for k in range(1, spells.size() + 1):
		var i := (spell_idx + k) % spells.size()
		if String(spells[i]) != "":
			spell_idx = i
			break
	spell_changed.emit(spell_idx, current_spell())
	return current_spell()

func spell_cd_left(id: String = "") -> float:
	return float(spell_cd.get(current_spell() if id == "" else id, 0.0))

func can_cast() -> bool:
	var id := current_spell()
	if id == "" or mounted or airborne or not _can_act() or roll_t >= 0.0 or swap_t > 0.0 or is_shooting():
		return false
	if atk_state != Atk.NONE or parry_state != Parry.NONE:
		return false
	return spell_cd_left(id) <= 0.0 and energy >= float(EikonSpells.spell(id)["cost"])

## Lanza el hechizo de la ranura activa (X / botón «Hechizo»). Solo a pie.
func cast_spell() -> bool:
	if not can_cast():
		return false
	var id := current_spell()
	var d := EikonSpells.spell(id)
	energy -= float(d["cost"])
	energy_changed.emit(energy, energy_max)
	spell_cd[id] = float(d["cooldown"])
	cast_t = float(d["cast"])
	_cast_id = id
	blocking = false
	spells_cast += 1
	_snd("eikon_summon", -6.0)
	_kv.event("shoot")
	return true

func _update_magic(delta: float) -> void:
	for k: String in spell_cd.keys():
		spell_cd[k] = maxf(float(spell_cd[k]) - delta, 0.0)
	art_cd = maxf(art_cd - delta, 0.0)
	stoneskin_t = maxf(stoneskin_t - delta, 0.0)
	if cast_t > 0.0:
		if not alive or stun > 0.0: # interrumpido: se pierde la Energía
			cast_t = 0.0
			_cast_id = ""
			return
		cast_t -= delta
		if cast_t <= 0.0:
			cast_t = 0.0
			var id := _cast_id
			_cast_id = ""
			_fire_spell(id)

func _spell_dir() -> Vector3:
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var dd := MeshUtil.flat(tgt.global_position - global_position)
		if dd.length() > 0.1:
			return dd.normalized()
	return facing

func _fire_spell(id: String) -> void:
	var d := EikonSpells.spell(id)
	if d.is_empty():
		return
	var pw := EikonSpells.power(id, ad)
	facing = _spell_dir()
	match String(d["type"]):
		"proyectil":
			var p := Projectile.new()
			p.team = team
			p.shooter = self
			p.kind = "eikon"
			p.element = String(d["element"])
			p.status = d.get("status", {})
			p.direction = facing
			p.speed = float(d["speed"])
			p.damage = float(d["damage"]) * pw
			p.color = Color(1.0, 0.55, 0.2) if d["element"] == "fuego" else Color(0.75, 0.9, 1.0)
			get_parent().add_child(p)
			p.global_position = get_hit_center() + Vector3(0, 0.6, 0) + facing * 1.2
			_snd("eikon_fire" if d["element"] == "fuego" else "eikon_wind")
		"cono":
			_snd("eikon_ice")
			var half := deg_to_rad(float(d["arc"]) * 0.5)
			for t in MeshUtil.enemies_of(get_tree(), team):
				var dd := MeshUtil.flat(t.global_position - global_position)
				if dd.length() > float(d["range"]) + float(t.hit_radius):
					continue
				if dd.length() > 0.2 and facing.angle_to(dd.normalized()) > half:
					continue
				if t is Fighter:
					(t as Fighter).incoming_element = String(d["element"])
					(t as Fighter).incoming_status = d.get("status", {})
				t.take_hit(float(d["damage"]) * pw, self, "eikon")
			_burst_particles(Color(0.7, 0.9, 1.0))
		"buff":
			_stoneskin = d
			stoneskin_t = float(d["duration"]) * pw
			_burst_particles(Color(0.75, 0.65, 0.5))
			_snd("eikon_slam", -4.0)

## Arte de arma (Habilidad sin habilidad propia). Cuerpo a cuerpo, a pie.
func use_weapon_art() -> bool:
	var a := WeaponArts.art(weapon_art_id)
	if a.is_empty() or mounted or airborne or not _can_act() or art_cd > 0.0 or roll_t >= 0.0:
		return false
	if loadout != Loadout.SWORD_SHIELD or atk_state != Atk.NONE or parry_state != Parry.NONE or swap_t > 0.0 or stamina <= 0.0:
		return false
	if energy < float(a["cost"]):
		return false
	energy -= float(a["cost"])
	energy_changed.emit(energy, energy_max)
	art_cd = float(a["cooldown"])
	arts_used += 1
	blocking = false
	match weapon_art_id:
		"estocada_impulsada":
			dash_dir = _spell_dir()
			spend_stamina(melee().light_stamina)
			_start_dash_strike()
			_art_mult = float(a["mult"])
		"torbellino":
			special_t = 0.3
			spend_stamina(melee().heavy_stamina)
			GroundAoE.spawn(get_parent(), self, team, global_position, float(a["radius"]), 0.3, melee().light_damage * float(a["mult"]) * damage_mult())
			_kv.event("slam")
			_snd("swing_heavy")
	return true


# ---------------- Ronda 24: postura y crítico ----------------

func stance_fraction() -> float:
	return clampf(stance / maxf(stance_max, 1.0), 0.0, 1.0)

func _update_exchange(delta: float) -> void:
	guard_counter_t = maxf(guard_counter_t - delta, 0.0)
	stance_broken_t = maxf(stance_broken_t - delta, 0.0)
	if _since_hit > STANCE_DELAY:
		stance = minf(stance + STANCE_REGEN * delta, stance_max)
	if crit_t >= 0.0:
		crit_t += delta
		if not _crit_done and crit_t >= CRIT_HIT_AT:
			_crit_done = true
			if is_instance_valid(_crit_target) and _crit_target.alive:
				var dmg := melee().heavy_damage * damage_mult() * CRIT_MULT
				var h0 := _crit_target.health
				_crit_target.take_hit(dmg, self, "critico")
				crits += 1
				critical_landed.emit(_crit_target, h0 - _crit_target.health)
				hitstop.emit(0.12)
				impact.emit(1.2)
		if crit_t >= CRIT_TIME:
			crit_t = -1.0
			_crit_target = null

## Rival a tiro de crítico frontal: postura rota, a pie, cerca y de frente a mí.
func crit_candidate() -> Fighter:
	for t in MeshUtil.enemies_of(get_tree(), team):
		if not (t is Fighter):
			continue
		var f := t as Fighter
		if f.stance_broken_t <= 0.0 or f.mounted or not f.alive:
			continue
		var d := MeshUtil.flat(global_position - f.global_position)
		if d.length() > CRIT_RANGE:
			continue
		if d.length() > 0.1 and f.facing.dot(d.normalized()) < 0.2:
			continue # frontal: estoy delante de él
		return f
	return null

func _start_crit(t: Fighter) -> void:
	crit_t = 0.0
	_crit_done = false
	_crit_target = t
	invuln = CRIT_TIME # invulnerable durante la animación
	blocking = false
	var dd := MeshUtil.flat(t.global_position - global_position)
	if dd.length() > 0.1:
		facing = dd.normalized()
	t.stance_broken_t = 0.0
	t.stun = maxf(t.stun, CRIT_TIME + 0.3)
	t.blocking = false
	spend_stamina(COST_PARRY)
	_kv.event("slam")
	_snd("swing_heavy")

func is_criticalling() -> bool:
	return crit_t >= 0.0


# ---------------- Ronda 25: Estocada de jefe ----------------

func can_boss() -> bool:
	return can_use_boss(selected_boss())

## Ronda 31: libre para empezar una habilidad de jefe (sin recarga: solo su coste).
func can_use_boss(id: String) -> bool:
	if not id in boss_ids or BossAbilities.def(id).is_empty():
		return false
	if mounted or airborne or not _can_act() or atk_state != Atk.NONE or parry_state != Parry.NONE or roll_t >= 0.0 or swap_t > 0.0 or is_shooting():
		return false
	if id != "escudo_mana" and loadout != Loadout.SWORD_SHIELD:
		return false
	return boss_cost_ok(id)

func boss_cost_ok(id: String) -> bool:
	var d := BossAbilities.def(id)
	var c := float(d.get("cost", 0.0))
	match String(d.get("cost_type", "")):
		"stamina": return stamina > 0.0 and exhausted <= 0.0
		"mana": return energy >= c
		"health": return health - c > 0.0 # no te puede dejar a 0
	return false

func _pay_boss(id: String) -> void:
	var d := BossAbilities.def(id)
	var c := float(d["cost"])
	match String(d["cost_type"]):
		"stamina": spend_stamina(c)
		"mana":
			energy -= c
			energy_changed.emit(energy, energy_max)
		"health":
			health = maxf(health - c, 1.0)
			health_changed.emit(health, max_health)

func boss_skill(id: String = "") -> bool:
	if id == "":
		id = selected_boss()
	if not can_use_boss(id):
		return false
	_pay_boss(id)
	ab_uses[id] = int(ab_uses.get(id, 0)) + 1
	if id != "estocada":
		_start_ability(id)
		return true
	boss_phase = Boss.CHARGE
	boss_t = 0.0
	boss_travel = 0.0
	boss_hit = false
	boss_uses += 1
	blocking = false
	boss_dir = _spell_dir()
	facing = boss_dir
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1.0, 0.25, 0.1)
	_blade_mat.emission_energy_multiplier = 0.5
	_kv.set_glow(true, Color(1.0, 0.25, 0.1))
	if _boss_fx == null:
		_boss_fx = CPUParticles3D.new()
		_boss_fx.amount = 40
		_boss_fx.lifetime = 0.5
		_boss_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_boss_fx.emission_sphere_radius = 0.6
		_boss_fx.gravity = Vector3(0, 2.0, 0)
		_boss_fx.initial_velocity_min = 0.2
		_boss_fx.initial_velocity_max = 0.8
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.45, 0.15)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.1)
		var qm := QuadMesh.new()
		qm.size = Vector2(0.12, 0.12)
		qm.material = m
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_boss_fx.mesh = qm
		add_child(_boss_fx)
		_boss_fx.position = Vector3(0.5, 1.2, -0.6)
	_boss_fx.emitting = true
	_boss_fx.scale_amount_min = 0.3
	_boss_fx.scale_amount_max = 0.5
	# Sonido que sube de tono durante la carga
	var au := get_node_or_null("/root/Audio")
	if au and _boss_snd == null:
		_boss_snd = AudioStreamPlayer3D.new()
		_boss_snd.bus = "Efectos"
		_boss_snd.unit_size = 14.0
		add_child(_boss_snd)
	if _boss_snd and au:
		_boss_snd.stream = au._pick("bow_draw")
		_boss_snd.pitch_scale = 0.55
		_boss_snd.play()
	boss_started.emit()
	return true

func boss_charge_left() -> float:
	return maxf(BOSS_CHARGE - boss_t, 0.0) if boss_phase == Boss.CHARGE else 0.0

func is_boss_invulnerable() -> bool:
	return boss_phase == Boss.CHARGE or boss_phase == Boss.LUNGE

func _update_boss(delta: float) -> void:
	boss_cd = maxf(boss_cd - delta, 0.0)
	if boss_phase == Boss.NONE:
		return
	if not alive:
		_end_boss()
		return
	boss_t += delta
	if is_boss_invulnerable():
		invuln = maxf(invuln, 0.05)
	match boss_phase:
		Boss.CHARGE:
			var k := clampf(boss_t / BOSS_CHARGE, 0.0, 1.0)
			_blade_mat.emission_energy_multiplier = lerpf(0.5, 6.0, k)
			if _boss_fx:
				_boss_fx.scale_amount_min = lerpf(0.3, 1.4, k)
				_boss_fx.scale_amount_max = lerpf(0.5, 2.2, k)
				_boss_fx.amount = 40
			if _boss_snd and _boss_snd.playing:
				_boss_snd.pitch_scale = lerpf(0.55, 1.6, k)
			if boss_t <= BOSS_TRACK:
				boss_dir = _spell_dir() # sigue al objetivo...
				facing = boss_dir
			# ...y después la dirección queda fija: un paso lateral o una voltereta a tiempo la esquivan
			if boss_t >= BOSS_CHARGE:
				boss_phase = Boss.LUNGE
				boss_t = 0.0
				_snd("swing_heavy", 4.0)
				impact.emit(0.4)
		Boss.LUNGE:
			# Ronda 31: corrige la dirección hacia el objetivo mientras embiste (caminar de lado no basta)
			boss_dir = _turn_toward(boss_dir, _spell_dir(), deg_to_rad(BOSS_HOME_DEG) * delta)
			facing = boss_dir
			var step := BOSS_SPEED * delta
			boss_travel += step
			velocity = boss_dir * BOSS_SPEED
			velocity.y = 0.0
			move_and_slide()
			_clamp_world()
			velocity = Vector3.ZERO
			planar_vel = Vector3.ZERO
			for t in MeshUtil.enemies_of(get_tree(), team):
				var d := MeshUtil.flat(t.global_position - global_position)
				var rr: float = BOSS_REACH + float(t.hit_radius)
				if d.length() > rr:
					continue
				if d.length() > 0.2 and rad_to_deg(boss_dir.angle_to(d.normalized())) > BOSS_ARC_DEG:
					continue
				var res: String = t.take_hit(melee().heavy_damage * damage_mult() * BOSS_DMG_MULT, self, "jefe")
				if res == "hit" or res == "block":
					boss_hit = true
					boss_hits += 1 if res == "hit" else 0
					hitstop.emit(0.1)
					impact.emit(1.1)
					landed_hit.emit(t, res, false)
					break
			if boss_hit or boss_travel >= BOSS_DIST:
				boss_phase = Boss.RECOVER # recuperación castigable
				boss_t = 0.0
				invuln = 0.0
				_blade_mat.emission_enabled = false
				_kv.set_glow(false, Color.BLACK)
				if _boss_fx:
					_boss_fx.emitting = false
				if not boss_hit:
					_snd("whiff")
		Boss.RECOVER:
			if boss_t >= (BOSS_RECOVER_HIT if boss_hit else BOSS_RECOVER_MISS):
				_end_boss()

func _end_boss() -> void:
	if boss_phase != Boss.NONE and boss_phase != Boss.RECOVER:
		invuln = 0.0
	boss_phase = Boss.NONE
	boss_t = 0.0
	if _boss_fx:
		_boss_fx.emitting = false
	if _boss_snd:
		_boss_snd.stop()
	if _blade_mat:
		_blade_mat.emission_enabled = false
	if _kv:
		_kv.set_glow(false, Color.BLACK)


# ---------------- Ronda 25: paso de ataque + magnetismo ----------------

## Velocidad del paso de este fotograma: reparte la distancia del arma en la ventana del paso,
## se imanta al objetivo fijado o cercano que esté delante y se detiene al contacto.
func _step_velocity(delta: float) -> Vector3:
	var in_win := atk_state == Atk.ACTIVE or (atk_state == Atk.WINDUP and atk_t >= atk_dur * (1.0 - STEP_WINDOW))
	if not in_win or delta <= 0.0:
		return Vector3.ZERO
	if atk_state == Atk.WINDUP and atk_heavy and charge_t > 0.0:
		return Vector3.ZERO # cargando: quieto; el paso (más largo) sale al soltar
	var win := maxf(atk_dur * STEP_WINDOW + float(_atk_data()["active"]), 0.05)
	var total := _step_total + (STEP_CHARGE_BONUS * charge_t / CHARGE_MAX if atk_heavy else 0.0)
	if atk_heavy and charge_t > 0.0 and not _charge_added and atk_state == Atk.ACTIVE:
		_charge_added = true
		_step_left += STEP_CHARGE_BONUS * charge_t / CHARGE_MAX # el fuerte cargado avanza más
	var mv := minf(total / win * delta, _step_left)
	var dir := facing
	var tgt: Node3D = face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))
	if tgt:
		var d := MeshUtil.flat(tgt.global_position - global_position)
		var dl := d.length()
		if dl < total + sword_range() + MAGNET_RANGE and dl > 0.1 and facing.dot(d / dl) > 0.3:
			dir = d / dl
			facing = _turn_toward(facing, dir, 0.25)
			var contact := dl - (float(tgt.get("hit_radius") if tgt.get("hit_radius") != null else 0.6) + CONTACT_GAP)
			mv = minf(mv, maxf(contact, 0.0))
	_step_left = maxf(_step_left - mv, 0.0) if mv > 0.0 else 0.0
	if mv <= 0.0:
		return Vector3.ZERO
	step_travel += mv
	return dir * (mv / delta)


## Ronda 29: garantía física de mundo tras cada movimiento (andar, voltereta, estocada, embestida,
## arremetida de combo, embestida de jefe, empujones). Nunca bajo el suelo (y=0), nunca fuera del
## muro circular de la arena ni dentro de un pilar, aunque una velocidad alta haga «túnel» en la física.
const BODY_R := 0.45
static var world_clamp := true
var clamps: int = 0 ## correcciones aplicadas (pruebas)

func _clamp_world() -> void:
	if not world_clamp:
		return
	var p := global_position
	var fixed := false
	if p.y < 0.0:
		p.y = 0.0
		velocity.y = maxf(velocity.y, 0.0)
		fixed = true
	var ar: float = Projectile.arena_radius
	if ar > 0.0:
		var flat := Vector2(p.x, p.z)
		var lim := ar - BODY_R
		if flat.length() > lim:
			flat = flat.normalized() * lim
			p.x = flat.x
			p.z = flat.y
			fixed = true
	for o: Vector3 in Projectile.obstacles:
		var d := Vector2(p.x - o.x, p.z - o.z)
		var r: float = o.y + BODY_R - 0.3 # o.y = radio del pilar (1.5 ~ colisión 1.3 + margen)
		if d.length() < r:
			d = (d.normalized() if d.length() > 0.01 else Vector2(facing.x, facing.z).normalized()) * r
			p.x = o.x + d.x
			p.z = o.z + d.y
			fixed = true
	if fixed:
		global_position = p
		clamps += 1

## Ronda 29: compromiso de orientación (frames activos/recuperación de un ataque a pie, o en el aire).
func turning_locked() -> bool:
	if mounted:
		return false
	return airborne or atk_state == Atk.ACTIVE or atk_state == Atk.RECOVERY


# ---------------- Ronda 30: movimiento fluido ----------------
const TURN_RATE_DEG := 800.0 ## giro a pie (°/s)
const LEAN_K := 0.012 ## rad de inclinación por rad/s de giro
const LEAN_MAX := 0.14
var lean: float = 0.0
## Movimiento fluido (giro angular fijo + velocidad que gira). Lo activa la arena para el jugador;
## la IA conserva su conducción clásica (con la fluida rodea al jugador por la espalda demasiado).
var fluid: bool = false
var _prev_yaw: float = 0.0

## La velocidad GIRA hacia la deseada (sin caer a cero en un cambio de dirección) y su módulo se
## acelera/frena con normalidad. Inversiones casi completas (>150°) sí frenan y arrancan.
static func _steer_velocity(cur: Vector3, target: Vector3, accel_step: float, turn_step: float) -> Vector3:
	var lc := cur.length()
	var lt := target.length()
	if lc < 0.3 or lt < 0.3:
		return cur.move_toward(target, accel_step)
	var a := cur.signed_angle_to(target, Vector3.UP)
	if absf(a) > deg_to_rad(150.0):
		return cur.move_toward(target, accel_step)
	var dir := (cur / lc).rotated(Vector3.UP, clampf(a, -turn_step, turn_step))
	return dir * move_toward(lc, lt, accel_step)


# ---------------- Ronda 31: aturdimiento acumulado (3 niveles) ----------------
var stun_acc: float = 0.0 ## fuerza acumulada en la ventana actual
var stun_window_t: float = 0.0 ## s que le quedan a la ventana (0 = cerrada)
var stun_level_reached: int = 0 ## nivel ya provocado en esta ventana
var stagger_t: float = 0.0 ## tambaleo corto en curso (se puede rodar)
var down_t: float = 0.0 ## derribo: tiempo total (suelo + levantarse) que queda
var stun_immune_t: float = 0.0 ## inmune al aturdimiento (al levantarse y un poco después)
var staggers: int = 0
var stuns: int = 0
var knockdowns: int = 0
var last_stun_level: int = 0

## Robustez: equilibrio (poise del rol + Aguante + armadura + accesorios) y resistencia de la armadura.
func robustness() -> float:
	var r := poise_max / maxf(float(ad.get("stun_taken", 1.0)), 0.1)
	if not eq.is_empty():
		r /= maxf(EquipStats.resist_mult("robustez", eq, eq_ref), 0.1)
	return maxf(r, 1.0)

## Súper-armadura de lo que está haciendo ahora (multiplica la robustez por 1 + x).
func current_stun_resist() -> float:
	if ab_id != "":
		return ab_resist()
	if atk_state == Atk.WINDUP:
		if atk_heavy:
			return melee().heavy_stun_resist + StunRules.CHARGE_RESIST * charge_t / CHARGE_MAX
		if atk_dash or atk_jump:
			return StunRules.DASH_JUMP_RESIST
		if cur_hit:
			return cur_hit.stun_resist
	if atk_state == Atk.ACTIVE and atk_heavy:
		return melee().heavy_stun_resist * 0.5
	return 0.0

func effective_robustness() -> float:
	return robustness() * (1.0 + current_stun_resist())

## Fuerza de aturdimiento del golpe cuerpo a cuerpo en curso: Fuerza + arma + golpe.
func hit_stun_force() -> float:
	var per := -1.0
	if cur_hit and not atk_heavy and not atk_dash and not atk_jump:
		per = cur_hit.stun_force
	if per < 0.0:
		per = current_hitstun() * StunRules.HITSTUN_TO_FORCE
	if atk_heavy:
		per *= 1.0 + 0.5 * charge_t / CHARGE_MAX
	return (StunRules.str_force(float(attributes().get("fuerza", 10))) + StunRules.weapon_force(melee()) + per) * float(ad.get("stun_dealt", 1.0))

## Fuerza de un proyectil del arco/ballesta (hitstun del proyectil x 40 + arma + media Fuerza).
func arrow_stun_force(hitstun: float) -> float:
	return StunRules.str_force(float(attributes().get("fuerza", 10))) * 0.5 + StunRules.weapon_force(ranged()) + hitstun * StunRules.HITSTUN_TO_FORCE

## Fuerza mágica: poder mágico + fuerza asignada a la habilidad.
func magic_stun_force(assigned: float) -> float:
	return StunRules.magic_force(float(ad.get("magia", 100.0))) + assigned

func _incoming_force(from: Node3D, kind: String, amount: float) -> float:
	if incoming_stun_force >= 0.0:
		var f := incoming_stun_force
		incoming_stun_force = -1.0
		return f
	match kind:
		"melee":
			return (from as Fighter).hit_stun_force() if from is Fighter and is_instance_valid(from) else 20.0
		"arrow":
			var hs := incoming_arrow_stun
			if from is Fighter and is_instance_valid(from):
				return (from as Fighter).arrow_stun_force(hs if hs > 0.0 else (from as Fighter).ranged().ranged_hitstun)
			return hs * StunRules.HITSTUN_TO_FORCE
		"aoe": return StunRules.AOE_FORCE
		"jefe": return StunRules.BOSS_FORCE
		"eikon": return amount * StunRules.EIKON_K
	return 0.0

## Suma fuerza de aturdimiento y reacciona si se cruza un umbral nuevo en esta ventana.
func add_stun_force(force: float) -> int:
	if force <= 0.0 or not alive or stun_immune_t > 0.0 or invuln > 0.0 or ab_immune():
		return 0
	if boss_phase == Boss.CHARGE or boss_phase == Boss.LUNGE:
		return 0
	if stun_window_t <= 0.0:
		stun_acc = 0.0
		stun_level_reached = 0
		stun_window_t = StunRules.WINDOW
	var r := effective_robustness()
	stun_acc += minf(force, r * StunRules.SINGLE_HIT_CAP) # ningún golpe aturde por sí solo
	var lv := StunRules.level_for(stun_acc / r)
	poise = maxf(robustness() - stun_acc, 0.0)
	if lv <= stun_level_reached:
		return 0
	stun_level_reached = lv
	last_stun_level = lv
	match lv:
		1:
			staggers += 1
			apply_stun(StunRules.STAGGER_T)
			stagger_t = StunRules.STAGGER_T
			last_hitstun = StunRules.STAGGER_T
		2:
			stuns += 1
			stagger_t = 0.0
			apply_stun(StunRules.STUN_T)
			last_hitstun = StunRules.STUN_T
		3:
			if mounted:
				stuns += 1
				apply_stun(StunRules.STUN_T)
				last_hitstun = StunRules.STUN_T
			else:
				knockdowns += 1
				stagger_t = 0.0
				blocking = false
				apply_stun(StunRules.DOWN_T + StunRules.GETUP_T)
				down_t = StunRules.DOWN_T + StunRules.GETUP_T
				stun_immune_t = down_t + StunRules.IMMUNE_AFTER
				last_hitstun = down_t
				_snd("guard_break")
			_reset_stun_meter()
	return lv

func _reset_stun_meter() -> void:
	stun_acc = 0.0
	stun_window_t = 0.0
	stun_level_reached = 0
	poise = robustness()

func _update_stun_meter(delta: float) -> void:
	stagger_t = maxf(stagger_t - delta, 0.0)
	down_t = maxf(down_t - delta, 0.0)
	stun_immune_t = maxf(stun_immune_t - delta, 0.0)
	if stun_window_t > 0.0:
		stun_window_t -= delta
		if stun_window_t <= 0.0:
			_reset_stun_meter() # se recupera del todo al instante

func is_knocked_down() -> bool:
	return down_t > StunRules.GETUP_T

func is_getting_up() -> bool:
	return down_t > 0.0 and down_t <= StunRules.GETUP_T

## Tambaleo corto: rodar lo cancela (si se reacciona antes del siguiente golpe).
func _stagger_roll_cancel() -> void:
	if stagger_t > 0.0 and stun <= stagger_t + 0.001 and down_t <= 0.0:
		stun = 0.0
		stagger_t = 0.0


# ---------------- Ronda 31: disparo cargado (arcos) ----------------
var want_shot_hold: bool = false ## mantener el botón: disparo cargado
var shot_charged: bool = false
var charged_shots: int = 0
var _hold_t: float = 0.0
var charge_ready_events: int = 0 ## ronda 32: veces que el arco llegó a carga completa
## Ronda 32: el controlador indica cuánto lleva mantenido el ataque (pose de carga del fuerte desde el inicio)
var hold_pose_t: float = 0.0

func bow_charged_ready() -> bool:
	return shot_state == Shot.DRAW and _hold_t >= CHARGE_HOLD
const CHARGE_HOLD := 0.9 ## s extra tras tensar para el disparo cargado

func charged_shot_kind() -> String:
	var r := ranged()
	if r.charged_shot != "":
		return r.charged_shot
	return "triple" if r.reload_time > 0.0 else "potente"

# ---------------- Ronda 31: habilidades de jefe (BossAbilities) ----------------
var boss_ids: Array = BossAbilities.DEFAULT.duplicate() ## equipadas (máx. 3)
var boss_sel: int = 0
var ab_id: String = "" ## habilidad en curso (la estocada usa boss_phase)
var ab_t: float = 0.0
var ab_vel: Vector3 = Vector3.ZERO
var ab_air: bool = false
var ab_hop: float = 0.0 ## altura visual del salto con caída
var ab_lock_pos: Vector3 = Vector3.ZERO
var ab_locked: bool = false
var ab_from: Vector3 = Vector3.ZERO
var ab_fired: int = 0 ## tajos lanzados / golpes dados
var ab_marker: Node3D
var ab_aoe: GroundAoE
var ab_bubble: MeshInstance3D
var ab_uses: Dictionary = {}
var ab_interrupted: int = 0
var ab_hits_landed: int = 0
signal ability_started(id: String)

func set_boss_abilities(ids: Array) -> void:
	boss_ids = []
	for id in ids:
		if BossAbilities.DEFS.has(String(id)) and not String(id) in boss_ids and boss_ids.size() < BossAbilities.MAX_EQUIPPED:
			boss_ids.append(String(id))
	boss_sel = 0

func selected_boss() -> String:
	if boss_ids.is_empty():
		return ""
	return String(boss_ids[clampi(boss_sel, 0, boss_ids.size() - 1)])

func cycle_boss() -> String:
	if boss_ids.size() > 1:
		boss_sel = (boss_sel + 1) % boss_ids.size()
	return selected_boss()

func ab_def() -> Dictionary:
	return BossAbilities.def(ab_id)

func ab_immune() -> bool:
	return (ab_id == "escudo_mana" and ab_t >= float(ab_def()["windup"])) or (ab_id == "salto_caida" and ab_air)

func ab_resist() -> float:
	var d := ab_def()
	if ab_id == "combo_falso":
		var hits: Array = d["hits"]
		var last := hits.size() - 1
		if ab_fired == last and ab_t < float(hits[last][0]):
			return 1.0 # anticipación alzada del golpe final
	return float(d.get("resist", 0.0))

## Daño: fuerte (o ligero) del arma x multiplicador; las mágicas escalan con la magia.
func ab_damage(id: String, k: float = 1.0) -> float:
	var d := BossAbilities.def(id)
	var base := (melee().light_damage if d.get("light", false) else melee().heavy_damage) * damage_mult() * float(d["dmg"]) * k
	if d.get("magic", false):
		base *= float(ad.get("magia", 100.0)) / 100.0
	return base

func ab_force(assigned: float, magic: bool) -> float:
	if magic:
		return magic_stun_force(assigned)
	return (StunRules.str_force(float(attributes().get("fuerza", 10))) + StunRules.weapon_force(melee()) + assigned) * float(ad.get("stun_dealt", 1.0))

func _ab_target() -> Node3D:
	return face_target if _lock_valid() else MeshUtil.nearest(global_position, MeshUtil.enemies_of(get_tree(), team))

func _start_ability(id: String) -> void:
	ab_id = id
	ab_t = 0.0
	ab_vel = Vector3.ZERO
	ab_air = false
	ab_hop = 0.0
	ab_locked = false
	ab_fired = 0
	ab_from = global_position
	blocking = false
	var d := ab_def()
	var col: Color = {"carga_area": Color(0.3, 0.6, 1.0), "rafaga": Color(1.0, 0.82, 0.3), "escudo_mana": Color(0.3, 1.0, 1.0),
		"combo_falso": Color(1.0, 0.8, 0.25), "salto_caida": Color(1.0, 0.25, 0.15)}.get(id, Color.WHITE)
	if _kv:
		_kv.set_glow(true, col)
	facing = _spell_dir()
	match id:
		"carga_area":
			ab_aoe = GroundAoE.spawn(get_parent(), self, team, global_position, float(d["radius"]), float(d["windup"]), ab_damage(id))
			ab_aoe.stun_force = ab_force(float(d["force"]), true)
		"escudo_mana":
			ab_bubble = MeshUtil.sphere(self, 1.3, Vector3(0, 1.0, 0), Color(0.3, 1.0, 1.0, 0.25), true)
			ab_bubble.transparency = 0.7
		"salto_caida":
			var tg := _ab_target()
			ab_lock_pos = tg.global_position if tg else global_position + facing * 6.0
			ab_marker = null # ronda 32: sin marca en el suelo; la única pista es verle en el aire
	_snd("swing_heavy", 2.0)
	ability_started.emit(id)

func _end_ability(interrupted: bool = false) -> void:
	if ab_id == "":
		return
	if interrupted:
		ab_interrupted += 1
		if is_instance_valid(ab_aoe) and not ab_aoe.detonated:
			ab_aoe.queue_free() # la carga cortada no estalla
	ab_aoe = null
	if is_instance_valid(ab_marker):
		ab_marker.queue_free()
	ab_marker = null
	if is_instance_valid(ab_bubble):
		ab_bubble.queue_free()
	ab_bubble = null
	if ab_air:
		global_position.y = 0.0
	ab_id = ""
	ab_t = 0.0
	ab_vel = Vector3.ZERO
	ab_air = false
	ab_hop = 0.0
	if _kv:
		_kv.set_glow(false, Color.BLACK)

func _update_ability(delta: float) -> void:
	if ab_id == "":
		return
	if not alive:
		_end_ability(true)
		return
	var d := ab_def()
	var prev := ab_t
	ab_t += delta
	ab_vel = Vector3.ZERO
	var tg := _ab_target()
	match ab_id:
		"carga_area":
			if ab_t >= float(d["windup"]) + float(d["recovery"]):
				_end_ability()
		"rafaga":
			var w := float(d["windup"])
			if ab_t < w and tg:
				facing = _turn_toward(facing, _spell_dir(), deg_to_rad(360.0) * delta)
			while ab_fired < int(d["count"]) and ab_t >= w + ab_fired * float(d["interval"]):
				_fire_magic_slash(d, tg)
				ab_fired += 1
			if ab_t >= w + (int(d["count"]) - 1) * float(d["interval"]) + float(d["recovery"]):
				_end_ability()
		"escudo_mana":
			if ab_t >= float(d["windup"]):
				invuln = maxf(invuln, 0.05)
			if ab_t >= float(d["windup"]) + float(d["active"]):
				invuln = 0.0
				_end_ability()
		"combo_falso":
			var hits: Array = d["hits"]
			# Ronda 32: golpes lentos; cada uno gira hacia el objetivo y avanza ~3 m (menos que la Estocada)
			if tg and ab_fired < hits.size() and ab_t < float(hits[ab_fired][0]) - 0.1:
				facing = _turn_toward(facing, _spell_dir(), deg_to_rad(float(d["turn_deg"])) * delta)
			if ab_fired < hits.size():
				var th := float(hits[ab_fired][0])
				var lt := float(d["lunge_time"])
				if ab_t > th - lt and ab_t < th + 0.05:
					var gap := MeshUtil.flat(tg.global_position - global_position).length() if tg else 99.0
					if gap > float(d["reach"]) * 0.6:
						ab_vel = facing * float(d["lunge_speed"])
				if prev < th and ab_t >= th:
					_combo_strike(d, hits[ab_fired])
					ab_fired += 1
			if ab_t >= float(hits[-1][0]) + float(d["recovery"]):
				_end_ability()
		"salto_caida":
			var rise := float(d["rise"])
			var lock := float(d["lock"])
			var land := float(d["land"])
			var hgt := float(d["height"])
			if ab_t < land:
				ab_air = ab_t > 0.05
				if not ab_locked and tg:
					ab_lock_pos = tg.global_position # la marca sigue al objetivo...
				if is_instance_valid(ab_marker):
					ab_marker.global_position = Vector3(ab_lock_pos.x, 0.0, ab_lock_pos.z)
				if ab_t >= lock and not ab_locked:
					ab_locked = true # ...hasta aquí: luego queda fija
					ab_from = global_position
					if is_instance_valid(ab_marker):
						ab_marker.queue_free()
					ab_marker = null
					ab_aoe = GroundAoE.spawn(get_parent(), self, team, ab_lock_pos, float(d["radius"]), land - lock, ab_damage(ab_id), true)
					ab_aoe.stun_force = ab_force(float(d["force"]), false)
				if ab_t < rise:
					ab_hop = hgt * sin(ab_t / rise * PI * 0.5)
				elif ab_t < lock:
					ab_hop = hgt
				else:
					var k := clampf((ab_t - lock) / (land - lock), 0.0, 1.0)
					ab_hop = hgt * (1.0 - k * k)
					var pp := ab_from.lerp(Vector3(ab_lock_pos.x, 0.0, ab_lock_pos.z), k)
					global_position = Vector3(pp.x, 0.0, pp.z)
					_clamp_world()
				var dd := MeshUtil.flat(ab_lock_pos - global_position)
				if dd.length() > 0.1:
					facing = dd.normalized()
			else:
				if ab_air:
					ab_air = false
					ab_hop = 0.0
					impact.emit(1.0)
				if ab_t >= land + float(d["recovery"]):
					_end_ability()

func _combo_strike(d: Dictionary, h: Array) -> void:
	_snd("swing", 0.0)
	for t in MeshUtil.enemies_of(get_tree(), team):
		var dv := MeshUtil.flat(t.global_position - global_position)
		if dv.length() > float(d["reach"]) + float(t.hit_radius):
			continue
		if dv.length() > 0.2 and rad_to_deg(facing.angle_to(dv.normalized())) > float(d["arc"]):
			continue
		if t is Fighter:
			(t as Fighter).incoming_stun_force = ab_force(float(h[2]), false)
		var res: String = t.take_hit(ab_damage("combo_falso", float(h[1])), self, "melee")
		if t is Fighter:
			(t as Fighter).incoming_stun_force = -1.0
		if res == "hit" or res == "block":
			ab_hits_landed += 1
			landed_hit.emit(t, res, false)
			hitstop.emit(0.05)

func _fire_magic_slash(d: Dictionary, tg: Node3D) -> void:
	var p := Projectile.new()
	p.team = team
	p.shooter = self
	p.kind = "eikon"
	var origin := get_hit_center() + Vector3(0, 0.3, 0) + facing * 1.0
	p.direction = (Projectile.aim_dir(origin, tg, float(d["speed"])) if tg else facing)
	p.aimed_at = tg
	p.speed = float(d["speed"])
	p.life = float(d["life"])
	p.radius = float(d.get("radius", 0.7))
	p.slash = true
	p.slash_tilt = 45.0 if ab_fired % 2 == 0 else -45.0
	p.damage = ab_damage("rafaga")
	p.color = Color(1.0, 0.82, 0.3)
	p.stun_force = ab_force(float(d["force"]), true)
	p.home_target = tg
	p.home_rate = deg_to_rad(float(d["home_deg"]))
	p.home_time = float(d["home_time"])
	get_parent().add_child(p)
	p.global_position = origin
	_snd("swing_heavy", -2.0)
