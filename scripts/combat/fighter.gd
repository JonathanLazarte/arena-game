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
signal guard_broken
signal execution_cinematic(attacker: Fighter, target: Fighter, duration: float)
## Ronda 25: habilidad de jefe «Estocada de jefe» (telegrafiada, invulnerable, castigable)
signal boss_started
enum Boss { NONE, CHARGE, LUNGE, RECOVER }
const BOSS_CHARGE := 1.6 ## carga visible (pose, brillo y partículas en la hoja, sonido que sube)
const BOSS_TRACK := 1.6 ## ronda 31: sigue al objetivo TODA la carga (no se esquiva caminando)
const BOSS_DIST := 12.0 ## ronda 31: más alcance (antes 7,5)
const BOSS_SPEED := 30.0 ## m/s (0,4 s de embestida)
const BOSS_LUNGE_HOME_T := 0.15 ## ronda 33: la embestida solo se corrige durante 0,15 s
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
## Ronda 33: recarga global entre habilidades de jefe y recargas por habilidad (opcionales).
const BOSS_GLOBAL_CD := 1.4
static var per_ability_cd_enabled: bool = false
var ab_cds: Dictionary = {}
var _last_boss_id: String = ""
## Ronda 33: búfer de voltereta (una pulsación durante una acción se ejecuta al quedar libre).
const ROLL_BUFFER := 0.18
var roll_buf_t: float = 0.0
## Ronda 33: rendimiento — datos del ataque una vez por ataque.
var _atk_cache: Dictionary = {}
var _atk_cache_key: Array = []
## Ronda 33: máximo de ráfagas de partículas simultáneas (todas las instancias).
const MAX_BURSTS := 6
static var bursts_live: int = 0
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
const BACKSTEP_TIME := 0.35
const BACKSTEP_DISTANCE := 2.0
const BACKSTEP_STAMINA := 6.0
const FLASK_TIME := 1.1
const FLASK_HEAL_FRACTION := 0.35
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
## Fase 7 (sensación de acción): a pie se alcanza la velocidad de andar en ~0,09 s y se frena en
## ~0,07 s (corriendo ~0,11 s, ≤0,75 m de inercia). La carrera entra/sale en rampa lineal corta.
## Ver docs/design.md («Movimiento»). La sim online usa los mismos valores (SimParams).
const FOOT_MOVE_ACCEL := 90.0
const FOOT_SPRINT_ACCEL := 75.0
const FOOT_BRAKE_ACCEL := 120.0
const SPRINT_RAMP_UP := 0.06 ## s de andar a correr (rampa lineal)
const SPRINT_RAMP_DOWN := 0.08 ## s de correr a andar
const STEER_TURN_MULT := 2.0 ## la velocidad gira a TURN_RATE_DEG × esto (sin derrapes en giros)
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
const MOUNT_STANCE_MAX := 100.0
var mount_stance: float = MOUNT_STANCE_MAX
var mount_stance_regen_t: float = 0.0
## Compatibilidad con pruebas antiguas; el derribo ya no usa probabilidades.
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
var _sprint_blend: float = 0.0
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
var backstep_t: float = 0.0
var backstep_attack_queued: bool = false
var flask_t: float = 0.0
var flask_charges: int = 1
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
var left_hand_id: String = ""
var tertiary_shield: bool = false
var offhand: WeaponDef = null
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
var eikon_seal_id: String = ""
var arts_used: int = 0
var _art_mult: float = 1.0
var incoming_element: String = "" ## lo fija el proyectil/hechizo justo antes de impactar
var incoming_status: Dictionary = {}
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

func set_equipment(lv: int, armor: Dictionary, w2: WeaponDef = null, lh: String = "", offhand_weapon: WeaponDef = null, shield_equipped: bool = false) -> void:
	level = maxi(lv, 1)
	armor_ids = armor.duplicate()
	armor_set = true
	secondary = w2 if w2 and w2.ranged and character.allows(w2.id) else null
	left_hand_id = lh
	tertiary_shield = shield_equipped
	offhand = offhand_weapon if offhand_weapon and character.allows(offhand_weapon.id) and not offhand_weapon.ranged and not offhand_weapon.two_handed else null

func armor_pieces() -> Dictionary:
	return EquipStats.armor_defs(armor_ids if armor_set else Catalog.starter_armor(character.id))

func _refresh_equipment() -> void:
	eq = EquipStats.sheet(character, level, attributes(), weapon, secondary, armor_pieces(), offhand)
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
		"sangrado", "congelacion": pass # el daño del estallido lo aplica la sim
	_status_flash = 0.5
	_status_flash_c = StatusFx.COLORS[k]
	_snd("status_" + k, 2.0)
	_burst_particles(StatusFx.COLORS[k])
	status_proc.emit(k)
	return true


func _burst_particles(c: Color) -> void:
	if not is_inside_tree() or bursts_live >= MAX_BURSTS:
		return
	bursts_live += 1
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
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		bursts_live = maxi(bursts_live - 1, 0)
		if is_instance_valid(p):
			p.queue_free())

## Ronda 33: aura dorada pulsante con invulnerabilidad (incl. inmunidad al aturdimiento) o súper-armadura.
func golden_aura_active() -> bool:
	if not alive:
		return false
	return invuln > 0.0 or stun_immune_t > 0.0 or current_stun_resist() >= 1.0


## Aura continua mientras dura el veneno o la congelación.
func _update_aura() -> void:
	var c := Color.TRANSPARENT
	var gold := golden_aura_active()
	if gold:
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012) # ronda 33: pulso dorado
		c = Color(1.0, 0.82, 0.25).lerp(Color(1.0, 0.95, 0.6), k)
	elif status_fx.poison_t > 0.0:
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
	_aura.scale = Vector3.ONE * ((1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.012)) if gold else 1.0)
	_aura.emitting = true


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
	return loadout == Loadout.SWORD_SHIELD and tertiary_shield and character.shield_mesh != ""

func stats() -> MountData:
	return mount_node.data if mounted and mount_node else foot_stats

func speed_mult() -> float:
	return character.velocidad * float(mods["velocidad"]) * float(roll_mod()["move"]) * (1.15 if rage_t > 0.0 else 1.0)

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
	_kv.setup(color, character, weapon, offhand, secondary)
	_kv.set_loadout(0 if loadout == Loadout.SWORD_SHIELD else 1, has_shield())
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

# ---------------- Aguante ----------------

# ---------------- Bucle principal ----------------

var local_hitstop_t: float = 0.0

## Online (fase 1): con sim_driven la simulación determinista (net/sim, SimView) manda y este nodo
## solo se dibuja. Por defecto false: el juego offline no cambia.
var sim_driven: bool = false

## Fase 8: la jugabilidad vive solo en net/sim; este nodo es la vista (SimView escribe su estado).
func _physics_process(delta: float) -> void:
	rotation.y = atan2(-facing.x, -facing.z)
	if _kv:
		_kv.update(self, delta)


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

func _can_act() -> bool:
	return alive and stun <= 0.0 and exhausted <= 0.0 and land_t <= 0.0 and special_t <= 0.0 and cast_t <= 0.0 and crit_t < 0.0 and boss_phase == Boss.NONE and ab_id == "" and flask_t <= 0.0 and backstep_t <= 0.0


func _atk_data() -> Dictionary:
	var key := [attacks_started, atk_heavy, atk_dash, atk_jump, cur_hit, charge_t, combo, melee(), mounted]
	if key == _atk_cache_key and not _atk_cache.is_empty():
		return _atk_cache
	_atk_cache_key = key
	_atk_cache = _atk_data_build()
	return _atk_cache

func _atk_data_build() -> Dictionary:
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
	return k * Trinkets.dmg_mult(tfx, melee().phys_type) * (1.3 if rage_t > 0.0 else 1.0)

func is_parrying() -> bool:
	return parry_state == Parry.ACTIVE

# ---------------- Armas: espada+escudo O arco ----------------

func _apply_loadout_visuals() -> void:
	var sw := loadout == Loadout.SWORD_SHIELD
	_kv.set_loadout(0 if sw else 1, has_shield())

## Dash montado / voltereta a pie.
## Ronda 33: el botón de esquiva es la voltereta; la estocada con dash (dash en la anticipación
## del ligero) queda desactivada pero conservada para el futuro.
static var dash_strike_enabled: bool = false

func has_special() -> bool:
	return character.special_id != ""

## Ronda 21: se puede invocar ya (medidor lleno, sin eikon activo, sin aturdir).
func can_summon() -> bool:
	return alive and eikon != null and not is_instance_valid(active_eikon) and meter >= METER_MAX and stun <= 0.0

## Hay un eikon activo en la arena (el botón Montar solo tiene sentido entonces).
func has_active_eikon() -> bool:
	return is_instance_valid(active_eikon) or (mounted and mount_node != null and mount_node.eikon != null)

## Segundos que le quedan a la invocación activa (0 si no hay).
func eikon_time_left() -> float:
	if active_eikon is Mount:
		return maxf((active_eikon as Mount).life, 0.0)
	if active_eikon is Eikon:
		return maxf((active_eikon as Eikon).life, 0.0)
	return 0.0

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
	boss_phase = Boss.NONE
	ab_id = ""
	down_t = 0.0
	stagger_t = 0.0
	stun_immune_t = 0.0
	want_shot_hold = false
	shot_charged = false
	charged_shots = 0
	boss_cd = 0.0
	ab_cds.clear()
	roll_buf_t = 0.0
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
	global_position = pos
	facing = face.normalized()
	rotation.y = atan2(-facing.x, -facing.z)
	if mounted and mount_node:
		mount_node.global_transform = global_transform
	velocity = Vector3.ZERO
	planar_vel = Vector3.ZERO
	_sprint_blend = 0.0
	knock = Vector3.ZERO
	invuln = 0.0
	dash_time = 0.0
	roll_t = -1.0
	backstep_t = 0.0
	backstep_attack_queued = false
	flask_t = 0.0
	flask_charges = 1
	mount_stance = MOUNT_STANCE_MAX
	mount_stance_regen_t = 0.0
	_dash_atk = false
	health = max_health
	if not keep_meter:
		meter = 0.0
	stamina = stamina_max
	exhausted = 0.0
	alive = true
	stun = 0.0
	atk_state = Atk.NONE
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

func set_magic(sp: Array, art: String, seal: String = "") -> void:
	FighterMagic.set_magic(self, sp, art, seal)

func has_spells() -> bool:
	return FighterMagic.has_spells(self)

func current_spell() -> String:
	return FighterMagic.current_spell(self)

## Siguiente ranura con hechizo (T / botón «↻»).
func cycle_spell() -> String:
	return FighterMagic.cycle_spell(self)

func spell_cd_left(id: String = "") -> float:
	return FighterMagic.spell_cd_left(self, id)

func can_cast() -> bool:
	return FighterMagic.can_cast(self)

# ---------------- Ronda 24: postura y crítico ----------------

func stance_fraction() -> float:
	return clampf(stance / maxf(stance_max, 1.0), 0.0, 1.0)

func is_criticalling() -> bool:
	return crit_t >= 0.0

# ---------------- Ronda 25: Estocada de jefe ----------------

func boss_cost_ok(id: String) -> bool:
	var d := BossAbilities.def(id)
	var c := float(d.get("cost", 0.0))
	match String(d.get("cost_type", "")):
		"stamina": return stamina >= c and exhausted <= 0.0
		"mana": return energy >= c
		"health": return health - c > 0.0 # no te puede dejar a 0
	return false

func boss_charge_left() -> float:
	return maxf(BOSS_CHARGE - boss_t, 0.0) if boss_phase == Boss.CHARGE else 0.0

func is_boss_invulnerable() -> bool:
	return boss_phase == Boss.CHARGE or boss_phase == Boss.LUNGE

# ---------------- Ronda 25: paso de ataque + magnetismo ----------------

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
const TURN_RATE_DEG := 1080.0 ## giro a pie (°/s); fase 7: antes 800
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
		return float(BossAbilities.def(ab_id).get("resist", 0.0)) + (1.0 if rage_t > 0.0 else 0.0)
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

func is_knocked_down() -> bool:
	return down_t > StunRules.GETUP_T

func is_getting_up() -> bool:
	return down_t > 0.0 and down_t <= StunRules.GETUP_T

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
var telegraph_k: float = 1.12 if OS.has_feature("mobile") else 1.0 ## ronda 33: avisos +12 % en móvil
var rage_t: float = 0.0
var incoming_unblockable: bool = false ## lo pone una marca de suelo imbloqueable antes de take_hit
var ab_ext_hit_landed: bool = false
var ab_counter_triggered: bool = false
var ab_vanished: bool = false
var ab_breath_tick: float = 0.0
var ab_combo_staggered: bool = false
var ab_combo_queued: bool = false
var ab_combo_ready: bool = false
var ab_combo_wait: float = 0.0
var ab_combo_finisher: bool = false
var ab_combo_variant: bool = false
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
var ab_aoe: Node3D
var ab_bubble: MeshInstance3D
var ab_uses: Dictionary = {}
var ab_interrupted: int = 0
var ab_hits_landed: int = 0
signal ability_started(id: String)

func set_boss_abilities(ids: Array) -> void:
	boss_ids = []
	for id in ids:
		if BossAbilities.has(String(id)) and not String(id) in boss_ids and boss_ids.size() < BossAbilities.MAX_EQUIPPED:
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
