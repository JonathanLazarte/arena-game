extends SceneTree
## Cliente online sin escena para la prueba de extremo a extremo (server/test/e2e.test.ts).
## godot --headless --path . -s res://tests/net_client.gd -- mode=relay role=host relay=127.0.0.1:47800 code=AB12 ticks=900 out=/tmp/a.json delay_ms=50
var cfg := {}
var link := NetLink.new()
var m: NetMatch
var bot := RandomNumberGenerator.new()
var cur := 0
var started_ms := 0
var params: Array

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2: cfg[kv[0]] = kv[1]
	link.sim_delay_ms = float(cfg.get("delay_ms", "0"))
	link.sim_jitter_ms = float(cfg.get("jitter_ms", "0"))
	link.sim_loss = float(cfg.get("loss", "0"))
	link.join_wait_ms = 10000
	link.force_relay = cfg.get("force_relay", "0") == "1"
	var role := String(cfg.get("role", "host"))
	var mode := String(cfg.get("mode", "relay"))
	if mode == "relay":
		var r := String(cfg.get("relay", "127.0.0.1:47800")).split(":")
		if role == "host": link.create_room(r[0], int(r[1]), String(cfg.get("code", "")))
		else: link.join_room(r[0], int(r[1]), String(cfg.get("code", "")))
	else:
		var port := int(cfg.get("port", str(NetLink.LAN_PORT)))
		if role == "host": link.host_lan(port)
		else: link.join_lan(String(cfg.get("ip", "127.0.0.1")), port)
	bot.seed = 11 if role == "host" else 23
	params = SimParams.defaults()
	started_ms = Time.get_ticks_msec()

func _physics_process(_d: float) -> bool:
	var t := Time.get_ticks_msec() - started_ms
	if t > int(cfg.get("timeout_ms", "60000")):
		_finish("timeout"); return true
	if m == null:
		link.poll()
		if link.state == NetLink.St.FAILED:
			_finish("link_failed:" + link.error); return true
		if link.ready_to_play():
			m = NetMatch.new(link)
		return false
	if m.phase != NetMatch.Ph.PLAY and m.phase != NetMatch.Ph.OVER:
		if m.prelude_step():
			m.start_play(params)
		elif m.status != "":
			_finish(m.status); return true
		return false
	if bot.randf() < 0.25:
		cur = (bot.randi() & 0x1FFF) | FightSim.IN_LOCK
	m.play_step(cur)
	if m.phase == NetMatch.Ph.OVER or m.session.frame >= int(cfg.get("ticks", "900")):
		_finish(m.status); return true
	return false

func _finish(st: String) -> void:
	var out := {"status": st, "link_state": link.state, "direct": link.direct, "slot": link.slot, "code": link.code}
	if m != null and m.session != null:
		var s := m.session
		var ck := {}
		for f: int in s.checksums: ck[str(f)] = s.checksums[f]
		var rep := m.replay_dict()
		out.merge({"frame": s.frame, "confirmed": m.confirmed_frame(), "rollbacks": s.rollbacks, "max_resim": s.max_resim,
			"stalls": s.stalls, "sync_skips": m.sync_skips, "rtt": m.rtt_ms, "delay": m.input_delay, "desync": m.desync_frame,
			"checked_to": m.checked_to, "ck": ck, "replay_bad": NetMatch.verify_replay(rep).size(), "replay_frames": rep["in0"].size(),
			"bytes_out": link.bytes_out})
		m.link.close()
	var f := FileAccess.open(String(cfg.get("out", "/tmp/net_client.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("net_client done: ", st)
	quit(0)
