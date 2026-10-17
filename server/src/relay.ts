// UDP rendezvous + relay + matchmaking. Wire format: byte 0 = message type (ASCII), rest = payload.
//  client -> server (control payloads are JSON; every C/J/Q carries the game protocol "v")
//   'C' {v, code?}       create room, reply 'W' {code, slot: 0, region}
//   'J' {v, code}        join room, reply 'M' {slot, peer, code, token, region} to both, or 'E' {err}
//   'Q' {v}              quick match in this server's region: reply 'q' {pos}; when paired both get 'M'
//   'B' {code, token}    reconnect (new address / NAT rebinding) within the grace window:
//                        reply 'M' {..., re: 1}; the other member gets 'b' {peer}
//   'P' {t}              ping: reply 'p' {t, region, rooms, queue}
//   'R' <bytes>          relay: forwarded verbatim to the other member as 'D' <bytes>
//   'K'                  keepalive (refreshes room + NAT mapping), reply 'k'
//   'X'                  leave room / queue; the other member gets 'x'
//  server -> client extras: 'F' {slot} the other member abandoned (silent past the grace window).
//  Errors 'E' {err}: version (+need), no_room, room_full, code_taken, bad_token, busy, bad_request.
//  Hardening: per-address token buckets (relay and control), packet size cap, temporary bans
//  after repeated violations, room cap, random per-member session tokens.
import dgram from "node:dgram";
import { randomBytes } from "node:crypto";

export interface RelayOptions {
  port?: number; host?: string; roomTtlMs?: number; codeLength?: number; log?: (s: string) => void;
  region?: string; proto?: number; graceMs?: number; maxPacket?: number; maxRooms?: number;
  relayRate?: number; relayBurst?: number; ctlRate?: number; ctlBurst?: number;
  banViolations?: number; banMs?: number; queueTtlMs?: number;
}
interface Member { addr: string; port: number; seen: number; token: string; }
interface Room { code: string; members: Member[]; created: number; seen: number; relayed: number; matched: boolean; }
interface Bucket { relay: number; ctl: number; t: number; viol: number; violT: number; banUntil: number; }
interface Waiter { addr: string; port: number; seen: number; }

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const key = (a: string, p: number) => `${a}:${p}`;
const CTL = new Set(["C", "J", "Q", "B", "P"]);

export class RelayServer {
  readonly sock: dgram.Socket;
  readonly rooms = new Map<string, Room>();
  readonly byAddr = new Map<string, Room>();
  readonly buckets = new Map<string, Bucket>();
  queue: Waiter[] = [];
  private timer?: NodeJS.Timeout;
  readonly opts: Required<RelayOptions>;
  readonly started = Date.now();
  stats = { packets: 0, relayed: 0, rooms_created: 0, matches: 0, quick: 0, reconnects: 0, abandons: 0,
    dropped_rate: 0, dropped_size: 0, dropped_banned: 0, bans: 0, version_rejects: 0, bytes_in: 0, bytes_out: 0 };

  constructor(opts: RelayOptions = {}) {
    this.opts = {
      port: 47800, host: "0.0.0.0", roomTtlMs: 120_000, codeLength: 5, log: () => {},
      region: "local", proto: 6, graceMs: 20_000, maxPacket: 1200, maxRooms: 5000,
      relayRate: 200, relayBurst: 400, ctlRate: 10, ctlBurst: 20, banViolations: 600, banMs: 60_000,
      queueTtlMs: 10_000, ...opts,
    };
    this.sock = dgram.createSocket("udp4");
    this.sock.on("message", (m, r) => this.onMessage(m, r.address, r.port));
  }

  start(): Promise<number> {
    return new Promise((res) => {
      this.sock.bind(this.opts.port, this.opts.host, () => {
        this.timer = setInterval(() => this.sweep(), 1_000);
        this.timer.unref();
        res(this.sock.address().port);
      });
    });
  }

  stop(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    return new Promise((res) => this.sock.close(() => res()));
  }

  private raw(b: Buffer, addr: string, port: number) {
    this.stats.bytes_out += b.length;
    this.sock.send(b, port, addr);
  }

  private send(type: string, body: Buffer | object | null, addr: string, port: number) {
    const head = Buffer.from(type, "ascii");
    const payload = body == null ? Buffer.alloc(0) : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
    this.raw(Buffer.concat([head, payload]), addr, port);
  }

  newCode(): string {
    for (;;) {
      let c = "";
      for (let i = 0; i < this.opts.codeLength; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!this.rooms.has(c)) return c;
    }
  }

  private json(m: Buffer): any {
    try { const v = m.length > 1 ? JSON.parse(m.subarray(1).toString("utf8")) : {}; return v && typeof v === "object" ? v : null; } catch { return null; }
  }

  /** Token buckets per address; false = drop. Repeated violations ban the address for banMs. */
  allow(k: string, ctl: boolean, now: number): boolean {
    let b = this.buckets.get(k);
    if (!b) { b = { relay: this.opts.relayBurst, ctl: this.opts.ctlBurst, t: now, viol: 0, violT: now, banUntil: 0 }; this.buckets.set(k, b); }
    if (now < b.banUntil) { this.stats.dropped_banned++; return false; }
    const dt = (now - b.t) / 1000; b.t = now;
    b.relay = Math.min(this.opts.relayBurst, b.relay + dt * this.opts.relayRate);
    b.ctl = Math.min(this.opts.ctlBurst, b.ctl + dt * this.opts.ctlRate);
    const field = ctl ? "ctl" : "relay";
    if (b[field] >= 1) { b[field] -= 1; return true; }
    this.stats.dropped_rate++;
    if (now - b.violT > 60_000) { b.viol = 0; b.violT = now; }
    if (++b.viol >= this.opts.banViolations) {
      b.banUntil = now + this.opts.banMs; b.viol = 0; this.stats.bans++;
      this.opts.log(`ban ${k} for ${this.opts.banMs} ms`);
    }
    return false;
  }

  private leave(k: string) {
    this.queue = this.queue.filter((w) => key(w.addr, w.port) !== k);
    const room = this.byAddr.get(k);
    if (!room) return;
    this.byAddr.delete(k);
    room.members = room.members.filter((m) => key(m.addr, m.port) !== k);
    for (const m of room.members) this.send("x", null, m.addr, m.port);
    if (room.members.length === 0) this.rooms.delete(room.code);
  }

  private versionOk(j: any, addr: string, port: number): boolean {
    if (Number(j?.v) === this.opts.proto) return true;
    this.stats.version_rejects++;
    this.send("E", { err: "version", need: this.opts.proto }, addr, port);
    return false;
  }

  private match(r: Room, now: number) {
    const [h, g] = r.members;
    r.matched = true; r.seen = now; h.seen = now; g.seen = now;
    this.stats.matches++;
    this.opts.log(`room ${r.code} matched ${key(h.addr, h.port)} <-> ${key(g.addr, g.port)}`);
    this.send("M", { slot: 0, peer: key(g.addr, g.port), code: r.code, token: h.token, region: this.opts.region }, h.addr, h.port);
    this.send("M", { slot: 1, peer: key(h.addr, h.port), code: r.code, token: g.token, region: this.opts.region }, g.addr, g.port);
  }

  private newRoom(code: string, addr: string, port: number, now: number): Room | null {
    if (this.rooms.size >= this.opts.maxRooms) { this.send("E", { err: "busy" }, addr, port); return null; }
    const r: Room = { code, members: [{ addr, port, seen: now, token: randomBytes(12).toString("hex") }], created: now, seen: now, relayed: 0, matched: false };
    this.rooms.set(code, r); this.byAddr.set(key(addr, port), r); this.stats.rooms_created++;
    return r;
  }

  onMessage(m: Buffer, addr: string, port: number) {
    if (m.length === 0) return;
    this.stats.bytes_in += m.length;
    const now = Date.now();
    const k = key(addr, port);
    if (m.length > this.opts.maxPacket) { this.stats.dropped_size++; this.allow(k, true, now); return; }
    const t = String.fromCharCode(m[0]);
    if (!this.allow(k, CTL.has(t), now)) return;
    this.stats.packets++;
    const room = this.byAddr.get(k);
    if (room) { room.seen = now; const me = room.members.find((x) => key(x.addr, x.port) === k); if (me) me.seen = now; }
    switch (t) {
      case "R": {
        if (!room) return;
        for (const o of room.members) if (key(o.addr, o.port) !== k) {
          const out = Buffer.from(m); out[0] = 0x44; // 'D'
          this.raw(out, o.addr, o.port);
          room.relayed++; this.stats.relayed++;
        }
        return;
      }
      case "K": {
        const w = this.queue.find((x) => key(x.addr, x.port) === k); if (w) w.seen = now;
        this.send("k", null, addr, port); return;
      }
      case "X": this.leave(k); return;
      case "P": {
        const j = this.json(m) ?? {};
        this.send("p", { t: Number(j.t) || 0, region: this.opts.region, rooms: this.rooms.size, queue: this.queue.length, v: this.opts.proto }, addr, port);
        return;
      }
      case "C": {
        const j = this.json(m);
        if (j == null) { this.send("E", { err: "bad_request" }, addr, port); return; }
        if (!this.versionOk(j, addr, port)) return;
        if (room) this.leave(k);
        let code = typeof j.code === "string" ? j.code.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 12) : "";
        if (code && this.rooms.has(code)) { this.send("E", { err: "code_taken" }, addr, port); return; }
        if (!code) code = this.newCode();
        if (!this.newRoom(code, addr, port, now)) return;
        this.opts.log(`room ${code} created by ${k}`);
        this.send("W", { code, slot: 0, region: this.opts.region }, addr, port);
        return;
      }
      case "J": {
        const j = this.json(m);
        if (j == null) { this.send("E", { err: "bad_request" }, addr, port); return; }
        if (!this.versionOk(j, addr, port)) return;
        const code = String(j.code ?? "").toUpperCase().slice(0, 12);
        const r = this.rooms.get(code);
        if (!r) { this.send("E", { err: "no_room" }, addr, port); return; }
        const mine = r.members.find((x) => key(x.addr, x.port) === k);
        if (mine) { // retransmitted join
          if (r.members.length === 2) {
            const o = r.members.find((x) => x !== mine)!;
            this.send("M", { slot: r.members.indexOf(mine), peer: key(o.addr, o.port), code, token: mine.token, region: this.opts.region }, addr, port);
          }
          return;
        }
        if (r.members.length >= 2) { this.send("E", { err: "room_full" }, addr, port); return; }
        if (room) this.leave(k);
        r.members.push({ addr, port, seen: now, token: randomBytes(12).toString("hex") }); this.byAddr.set(k, r);
        this.match(r, now);
        return;
      }
      case "Q": {
        const j = this.json(m);
        if (j == null) { this.send("E", { err: "bad_request" }, addr, port); return; }
        if (!this.versionOk(j, addr, port)) return;
        if (room) { // already paired (retransmitted Q): resend M
          const mine = room.members.find((x) => key(x.addr, x.port) === k)!;
          const o = room.members.find((x) => x !== mine);
          if (o && room.matched) this.send("M", { slot: room.members.indexOf(mine), peer: key(o.addr, o.port), code: room.code, token: mine.token, region: this.opts.region }, addr, port);
          return;
        }
        const pos = this.queue.findIndex((w) => key(w.addr, w.port) === k);
        if (pos >= 0) { this.queue[pos].seen = now; this.send("q", { pos }, addr, port); return; }
        const other = this.queue.shift();
        if (!other) { this.queue.push({ addr, port, seen: now }); this.stats.quick++; this.send("q", { pos: 0 }, addr, port); return; }
        const r = this.newRoom(this.newCode(), other.addr, other.port, now);
        if (!r) return;
        r.members.push({ addr, port, seen: now, token: randomBytes(12).toString("hex") }); this.byAddr.set(k, r);
        this.stats.quick++;
        this.match(r, now);
        return;
      }
      case "B": {
        const j = this.json(m) ?? {};
        const r = this.rooms.get(String(j.code ?? "").toUpperCase());
        if (!r) { this.send("E", { err: "no_room" }, addr, port); return; }
        const mb = r.members.find((x) => x.token === String(j.token ?? ""));
        if (!mb || String(j.token ?? "").length < 8) { this.send("E", { err: "bad_token" }, addr, port); return; }
        const oldK = key(mb.addr, mb.port);
        if (oldK !== k) {
          this.byAddr.delete(oldK);
          if (room && room !== r) this.leave(k);
          mb.addr = addr; mb.port = port;
          this.byAddr.set(k, r);
          this.stats.reconnects++;
          this.opts.log(`room ${r.code} slot ${r.members.indexOf(mb)} reconnected from ${k}`);
        }
        mb.seen = now; r.seen = now;
        const o = r.members.find((x) => x !== mb);
        this.send("M", { slot: r.members.indexOf(mb), peer: o ? key(o.addr, o.port) : "", code: r.code, token: mb.token, region: this.opts.region, re: 1 }, addr, port);
        if (o) this.send("b", { peer: k }, o.addr, o.port);
        return;
      }
    }
  }

  sweep(now = Date.now()) {
    this.queue = this.queue.filter((w) => now - w.seen <= this.opts.queueTtlMs);
    for (const r of [...this.rooms.values()]) {
      if (r.matched && r.members.length === 2) {
        const gone = r.members.findIndex((mb) => now - mb.seen > this.opts.graceMs);
        const other = r.members[1 - gone];
        if (gone >= 0 && other && now - other.seen <= this.opts.graceMs) { // one side abandoned: forfeit
          this.stats.abandons++;
          this.opts.log(`room ${r.code} slot ${gone} abandoned`);
          for (let i = 0; i < 3; i++) this.send("F", { slot: gone }, other.addr, other.port);
          for (const mb of r.members) this.byAddr.delete(key(mb.addr, mb.port));
          this.rooms.delete(r.code);
          continue;
        }
      }
      if (now - r.seen > this.opts.roomTtlMs) {
        for (const mb of r.members) this.byAddr.delete(key(mb.addr, mb.port));
        this.rooms.delete(r.code);
      }
    }
    for (const [k, b] of this.buckets) if (now - b.t > 120_000 && now > b.banUntil) this.buckets.delete(k);
  }

  health() {
    return { ok: true, region: this.opts.region, proto: this.opts.proto, uptime_s: Math.round((Date.now() - this.started) / 1000),
      rooms: this.rooms.size, queue: this.queue.length, ...this.stats };
  }

  metrics(): string {
    const h = this.health();
    const lines: string[] = [];
    for (const [k, v] of Object.entries(h)) if (typeof v === "number") {
      lines.push(`# TYPE arena_relay_${k} ${["rooms", "queue", "uptime_s", "proto"].includes(k) ? "gauge" : "counter"}`);
      lines.push(`arena_relay_${k}{region="${this.opts.region}"} ${v}`);
    }
    return lines.join("\n") + "\n";
  }
}
