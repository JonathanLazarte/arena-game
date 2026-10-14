class_name ResCache
## Ronda 26: caché de escenas pesadas (modelos de eikon/montura). Se piden en hilo al
## empezar la arena y se calienta una instancia oculta para que invocar no dé tirón.

static var _scenes: Dictionary = {} ## ruta -> PackedScene
static var _pending: Dictionary = {} ## ruta -> true (petición en hilo)

## Escena por ruta: de la caché, del hilo (espera si aún carga) o carga síncrona.
static func scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var ps: PackedScene = null
	if _pending.has(path):
		_pending.erase(path)
		ps = ResourceLoader.load_threaded_get(path) as PackedScene
	if ps == null:
		ps = load(path) as PackedScene
	_scenes[path] = ps
	return ps

static func request(path: String) -> void:
	if path == "" or _scenes.has(path) or _pending.has(path):
		return
	if ResourceLoader.has_cached(path):
		_scenes[path] = load(path)
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_pending[path] = true

## Recoge las que ya terminaron (llamar cada cierto tiempo; no bloquea).
static func poll() -> bool:
	for path: String in _pending.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			scene(path)
	return _pending.is_empty()

## Rutas de modelo que necesita la invocación de un eikon.
static func eikon_paths(e: EikonData) -> Array[String]:
	var out: Array[String] = []
	if e == null:
		return out
	if e.rideable and e.ride:
		out.append(e.ride.model_path)
	else:
		var cfg: Array = Eikon.MODELS.get(e.attack_kind, Eikon.GOLEM)
		out.append(cfg[0])
		if not Eikon.MODELS.has(e.attack_kind):
			out.append(Eikon.ROCK)
	return out
