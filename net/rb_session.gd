class_name RbSession
extends RefCounted
## Sesión de rollback para un par (estilo GGPO): retardo de entrada local, predicción
## (repite la última entrada remota conocida), guardado de estado por tick, rollback y
## re-simulación al llegar entradas remotas que contradicen la predicción.

var me: int                 # 0 o 1
var input_delay: int = 2    # ticks
var max_rollback: int = 8   # ventana de predicción máxima (ticks)
var frame: int = 0          # siguiente tick a simular
var state: PackedInt64Array
var local_in: Dictionary = {}    # tick -> int
var remote_in: Dictionary = {}   # tick -> int (confirmadas)
var predicted: Dictionary = {}   # tick -> int usada al simular
var saved: Dictionary = {}       # tick -> estado ANTES de simular ese tick
var checksums: Dictionary = {}   # tick -> checksum del estado tras ese tick (solo confirmados)
var last_remote: int = -1        # último tick remoto contiguo recibido
var last_local: int = -1         # último tick con entrada local registrada
var _earliest_wrong: int = -1
# métricas
var rollbacks: int = 0
var resim_frames: int = 0
var max_resim: int = 0
var stalls: int = 0
var resim_usec: Array[int] = []

var params_hash: int = 0    ## params_checksum local (0 = sin comprobación)
var peer_hash: int = -1     ## recibido del rival; hasta que coincida no se avanza
var params_mismatch := false
var engine: RbEngine ## simulación enchufable (RbSim por defecto; FightEngine para las reglas de combate)

func _init(player: int, delay: int = 2, window: int = 8, eng: RbEngine = null) -> void:
	me = player
	input_delay = delay
	max_rollback = window
	engine = eng if eng != null else RbEngine.new()
	state = engine.initial()
	for t in delay: # los primeros ticks no tienen entrada: neutros y confirmados
		local_in[t] = 0
		remote_in[t] = 0
	last_remote = delay - 1
	last_local = delay - 1

## Registra la entrada local muestreada ahora; se aplicará en frame + input_delay.
## Si el par está detenido (stall) el tick ya tiene entrada enviada: no se sobrescribe nunca.
func add_local_input(inp: int) -> void:
	if local_in.has(frame + input_delay):
		return
	local_in[frame + input_delay] = inp
	last_local = maxi(last_local, frame + input_delay)

## Paquete a enviar: entradas locales redundantes desde ack+1 (cubre pérdidas).
func make_packet(peer_ack: int) -> Dictionary:
	var from := maxi(peer_ack + 1, last_local - 30)
	var arr: Array[int] = []
	for t in range(from, last_local + 1):
		arr.append(int(local_in.get(t, 0)))
	return {"from": from, "inputs": arr, "ack": last_remote, "ph": params_hash}

func receive_packet(p: Dictionary) -> void:
	peer_hash = int(p.get("ph", 0))
	if params_hash != 0 and peer_hash != params_hash:
		params_mismatch = true # reglas distintas: la partida no puede ser determinista
		return
	var from: int = int(p["from"])
	var arr: Variant = p["inputs"]
	for i in arr.size():
		var t: int = from + i
		if remote_in.has(t):
			continue
		remote_in[t] = arr[i]
		if t < frame and predicted.get(t, -999) != arr[i]:
			if _earliest_wrong < 0 or t < _earliest_wrong:
				_earliest_wrong = t
	while remote_in.has(last_remote + 1):
		last_remote += 1

func _inputs_for(t: int) -> Array:
	var r: int
	if remote_in.has(t):
		r = remote_in[t]
	else:
		r = int(remote_in.get(last_remote, 0)) # predicción: repetir la última
	predicted[t] = r
	var l: int = local_in.get(t, 0)
	return [l, r] if me == 0 else [r, l]

func _sim_one() -> void:
	saved[frame] = state.duplicate()
	var ins: Array = _inputs_for(frame)
	engine.step(state, ins[0], ins[1])
	if frame <= last_remote:
		checksums[frame] = engine.checksum(state)
	frame += 1

## Un tick de tiempo real. Devuelve false si se detiene (demasiado por delante del rival).
func tick() -> bool:
	if params_mismatch or (params_hash != 0 and peer_hash != params_hash):
		stalls += 1
		return false
	if _earliest_wrong >= 0:
		var t0 := Time.get_ticks_usec()
		var target := frame
		var n := target - _earliest_wrong
		state = saved[_earliest_wrong].duplicate()
		frame = _earliest_wrong
		_earliest_wrong = -1
		while frame < target:
			_sim_one()
		rollbacks += 1
		resim_frames += n
		max_resim = maxi(max_resim, n)
		resim_usec.append(Time.get_ticks_usec() - t0)
	else:
		# los ticks ya confirmados que acertaron también obtienen checksum
		for t in range(maxi(0, last_remote - max_rollback - 2), mini(last_remote + 1, frame)):
			if not checksums.has(t) and saved.has(t + 1):
				checksums[t] = engine.checksum(saved[t + 1])
	if frame - last_remote > max_rollback:
		stalls += 1
		return false
	_sim_one()
	# limpieza
	var old := frame - 120
	saved.erase(old); predicted.erase(old)
	return true
