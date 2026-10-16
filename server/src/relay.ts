// UDP rendezvous + relay. Wire format: byte 0 = message type (ASCII), rest = payload.
//  client -> server
//   'C' {code?}        create room (optional requested code), reply 'W' {code, slot: 0}
//   'J' {code}         join room, reply 'M' {slot, peer, code} to both, or 'E' {err}
//   'R' <bytes>        relay: forwarded verbatim to the other member as 'D' <bytes>
//   'K'                keepalive (refreshes room + NAT mapping), reply 'k'
//   'X'                leave room; the other member gets 'x'
//  Rooms expire after `roomTtlMs` without traffic.
import dgram from "node:dgram";

export interface RelayOptions { port?: number; host?: string; roomTtlMs?: number; codeLength?: number; log?: (s: string) => void; }
interface Member { addr: string; port: number; seen: number; }
interface Room { code: string; members: Member[]; created: number; seen: number; relayed: number; }

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const key = (a: string, p: number) => `${a}:${p}`;

export class RelayServer {
  readonly sock: dgram.Socket;
  readonly rooms = new Map<string, Room>();
  readonly byAddr = new Map<string, Room>();
  private timer?: NodeJS.Timeout;
  private opts: Required<RelayOptions>;
  stats = { packets: 0, relayed: 0, rooms: 0 };

  constructor(opts: RelayOptions = {}) {
    this.opts = { port: 47800, host: "0.0.0.0", roomTtlMs: 120_000, codeLength: 5, log: () => {}, ...opts };
    this.sock = dgram.createSocket("udp4");
    this.sock.on("message", (m, r) => this.onMessage(m, r.address, r.port));
  }

  start(): Promise<number> {
    return new Promise((res) => {
      this.sock.bind(this.opts.port, this.opts.host, () => {
        this.timer = setInterval(() => this.sweep(), 5_000);
        this.timer.unref();
        res(this.sock.address().port);
      });
    });
  }

  stop(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    return new Promise((res) => this.sock.close(() => res()));
  }

  private send(type: string, body: Buffer | object | null, addr: string, port: number) {
    const head = Buffer.from(type, "ascii");
    const payload = body == null ? Buffer.alloc(0) : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
    this.sock.send(Buffer.concat([head, payload]), port, addr);
  }

  newCode(): string {
    for (;;) {
      let c = "";
      for (let i = 0; i < this.opts.codeLength; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
      if (!this.rooms.has(c)) return c;
    }
  }

  private json(m: Buffer): any {
    try { return m.length > 1 ? JSON.parse(m.subarray(1).toString("utf8")) : {}; } catch { return null; }
  }

  private leave(k: string) {
    const room = this.byAddr.get(k);
    if (!room) return;
    this.byAddr.delete(k);
    room.members = room.members.filter((m) => key(m.addr, m.port) !== k);
    for (const m of room.members) this.send("x", null, m.addr, m.port);
    if (room.members.length === 0) this.rooms.delete(room.code);
  }

  onMessage(m: Buffer, addr: string, port: number) {
    if (m.length === 0) return;
    this.stats.packets++;
    const t = String.fromCharCode(m[0]);
    const k = key(addr, port);
    const now = Date.now();
    const room = this.byAddr.get(k);
    if (room) { room.seen = now; const me = room.members.find((x) => key(x.addr, x.port) === k); if (me) me.seen = now; }
    switch (t) {
      case "R": {
        if (!room) return;
        for (const o of room.members) if (key(o.addr, o.port) !== k) {
          const out = Buffer.from(m); out[0] = 0x44; // 'D'
          this.sock.send(out, o.port, o.addr);
          room.relayed++; this.stats.relayed++;
        }
        return;
      }
      case "K": this.send("k", null, addr, port); return;
      case "X": this.leave(k); return;
      case "C": {
        const j = this.json(m) ?? {};
        if (room) this.leave(k);
        let code = typeof j.code === "string" ? j.code.toUpperCase().slice(0, 12) : "";
        if (code && this.rooms.has(code)) { this.send("E", { err: "code_taken" }, addr, port); return; }
        if (!code) code = this.newCode();
        const r: Room = { code, members: [{ addr, port, seen: now }], created: now, seen: now, relayed: 0 };
        this.rooms.set(code, r); this.byAddr.set(k, r); this.stats.rooms++;
        this.opts.log(`room ${code} created by ${k}`);
        this.send("W", { code, slot: 0 }, addr, port);
        return;
      }
      case "J": {
        const j = this.json(m) ?? {};
        const code = String(j.code ?? "").toUpperCase();
        const r = this.rooms.get(code);
        if (!r) { this.send("E", { err: "no_room" }, addr, port); return; }
        if (r.members.some((x) => key(x.addr, x.port) === k)) { // retransmitted join
          if (r.members.length === 2) this.send("M", { slot: 1, peer: key(r.members[0].addr, r.members[0].port), code }, addr, port);
          return;
        }
        if (r.members.length >= 2) { this.send("E", { err: "room_full" }, addr, port); return; }
        if (room) this.leave(k);
        r.members.push({ addr, port, seen: now }); this.byAddr.set(k, r); r.seen = now;
        const [h, g] = r.members;
        this.opts.log(`room ${code} matched ${key(h.addr, h.port)} <-> ${k}`);
        this.send("M", { slot: 0, peer: key(g.addr, g.port), code }, h.addr, h.port);
        this.send("M", { slot: 1, peer: key(h.addr, h.port), code }, g.addr, g.port);
        return;
      }
    }
  }

  sweep(now = Date.now()) {
    for (const r of [...this.rooms.values()]) {
      if (now - r.seen > this.opts.roomTtlMs) {
        for (const mb of r.members) this.byAddr.delete(key(mb.addr, mb.port));
        this.rooms.delete(r.code);
      }
    }
  }
}
