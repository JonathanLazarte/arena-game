class_name FighterMount
extends RefCounted
## Controlador de montura. Fighter conserva el estado público como fachada.

static func update_stance(f: Fighter, delta: float) -> void:
	if not f.mounted:
		return
	f.mount_stance_regen_t = maxf(f.mount_stance_regen_t - delta, 0.0)
	if f.mount_stance_regen_t <= 0.0:
		f.mount_stance = minf(f.mount_stance + 12.0 * delta, Fighter.MOUNT_STANCE_MAX)

static func damage_stance(f: Fighter, amount: float) -> void:
	if not f.mounted or amount <= 0.0:
		return
	f.mount_stance = maxf(f.mount_stance - amount, 0.0)
	f.mount_stance_regen_t = 4.0
	if f.mount_stance <= 0.0:
		f.mount_stance = Fighter.MOUNT_STANCE_MAX
		dismount(f, true)

static func mount_on(f: Fighter, m: Mount) -> bool:
	if m == null or not m.can_ride(f) or f.mounted:
		return false
	f.mounted = true
	f.mount_stance = Fighter.MOUNT_STANCE_MAX
	f.mount_stance_regen_t = 0.0
	f.mount_node = m
	m.set_rider(f)
	f.global_position = Vector3(m.global_position.x, f.global_position.y, m.global_position.z)
	f._apply_mount_visuals()
	f.mount_changed.emit(true)
	return true

static func dismount(f: Fighter, forced: bool = false) -> void:
	if not f.mounted:
		return
	var m: Mount = f.mount_node
	f.mounted = false
	f.mount_node = null
	var side := f.facing.cross(Vector3.UP)
	m.global_position = f.global_position
	m.set_rider(null)
	f.global_position += side * -1.6 + Vector3(0, 0.1, 0)
	f.planar_vel = Vector3.ZERO
	f.dash_time = 0.0
	f._apply_mount_visuals()
	if forced:
		f.apply_stun(0.6)
	f.mount_changed.emit(false)

static func nearest_free_mount(f: Fighter) -> Mount:
	var best: Mount = null
	var bd: float = INF
	for n in f.get_tree().get_nodes_in_group("mount"):
		var m := n as Mount
		if m and m.can_ride(f):
			var d := f.global_position.distance_to(m.global_position)
			if d < bd:
				bd = d
				best = m
	if is_instance_valid(f.owned_mount) and f.owned_mount.can_ride(f) and f.global_position.distance_to(f.owned_mount.global_position) <= bd + 1.0:
		return f.owned_mount
	return best

static func can_remount(f: Fighter) -> bool:
	var m := nearest_free_mount(f)
	return m != null and f.global_position.distance_to(m.global_position) <= Fighter.MOUNT_REACH

static func toggle_mount(f: Fighter) -> bool:
	if not f.alive:
		return false
	if not f.mounted and is_instance_valid(f.owned_mount) and f.owned_mount.owner_fighter == f and f.owned_mount.can_ride(f):
		if f.owned_mount.called:
			f.owned_mount.called = false
			return false
		if f.can_mount_now() and f.global_position.distance_to(f.owned_mount.global_position) <= Fighter.MOUNT_REACH:
			return mount_on(f, f.owned_mount)
		f.owned_mount.called = true
		return false
	if not f.can_mount_now():
		return false
	if f.mounted:
		dismount(f, false)
		return true
	if can_remount(f):
		return mount_on(f, nearest_free_mount(f))
	return false

static func can_mount_now(f: Fighter) -> bool:
	return f.alive and f.stun <= 0.0 and f.atk_state == Fighter.Atk.NONE and f.swap_t <= 0.0 and not f.airborne and f.special_t <= 0.0 and f.roll_t < 0.0 and f.backstep_t <= 0.0 and f.flask_t <= 0.0 and not f.is_shooting()
