import { test } from "node:test";
import assert from "node:assert/strict";
import dgram from "node:dgram";
import { RelayServer } from "../src/relay.js";

function client() {
  const s = dgram.createSocket("udp4");
  const inbox: Buffer[] = [];
  const waiters: ((b: Buffer) => void)[] = [];
  s.on("message", (m) => { const w = waiters.shift(); if (w) w(m); else inbox.push(m); });
  return {
    s,
    bind: () => new Promise<void>((r) => s.bind(0, "127.0.0.1", () => r())),
    send: (port: number, type: string, body?: object | Buffer) => {
      const p = body == null ? Buffer.alloc(0) : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
      s.send(Buffer.concat([Buffer.from(type), p]), port, "127.0.0.1");
    },
    next: (ms = 1000) => new Promise<Buffer>((res, rej) => {
      const b = inbox.shift(); if (b) return res(b);
      const t = setTimeout(() => rej(new Error("timeout")), ms);
      waiters.push((m) => { clearTimeout(t); res(m); });
    }),
    close: () => s.close(),
  };
}
const body = (b: Buffer) => JSON.parse(b.subarray(1).toString());

test("create, join, relay, leave", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1" });
  const port = await srv.start();
  const a = client(), b = client();
  await a.bind(); await b.bind();
  a.send(port, "C", { v: 12 });
  const w = await a.next();
  assert.equal(String.fromCharCode(w[0]), "W");
  const code = body(w).code as string;
  assert.match(code, /^[A-Z2-9]{5}$/);
  b.send(port, "J", { v: 12, code: code.toLowerCase() });
  const ma = await a.next(), mb = await b.next();
  assert.equal(String.fromCharCode(ma[0]), "M");
  assert.equal(body(ma).slot, 0); assert.equal(body(mb).slot, 1);
  assert.equal(body(ma).peer, `127.0.0.1:${b.s.address().port}`);
  const payload = Buffer.from([1, 2, 3, 250]);
  a.send(port, "R", payload);
  const d = await b.next();
  assert.equal(String.fromCharCode(d[0]), "D");
  assert.deepEqual([...d.subarray(1)], [1, 2, 3, 250]);
  b.send(port, "X");
  const x = await a.next();
  assert.equal(String.fromCharCode(x[0]), "x");
  a.close(); b.close(); await srv.stop();
});

test("errors: unknown code, full room, taken code; requested code", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1" });
  const port = await srv.start();
  const a = client(), b = client(), c = client();
  await a.bind(); await b.bind(); await c.bind();
  c.send(port, "J", { v: 12, code: "NOPE1" });
  assert.equal(body(await c.next()).err, "no_room");
  a.send(port, "C", { v: 12, code: "test42" });
  assert.equal(body(await a.next()).code, "TEST42");
  c.send(port, "C", { v: 12, code: "TEST42" });
  assert.equal(body(await c.next()).err, "code_taken");
  b.send(port, "J", { v: 12, code: "TEST42" });
  await a.next(); await b.next();
  c.send(port, "J", { v: 12, code: "TEST42" });
  assert.equal(body(await c.next()).err, "room_full");
  a.close(); b.close(); c.close(); await srv.stop();
});

test("rooms expire without traffic", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", roomTtlMs: 50 });
  const port = await srv.start();
  const a = client(); await a.bind();
  a.send(port, "C", { v: 12 }); await a.next();
  assert.equal(srv.rooms.size, 1);
  srv.sweep(Date.now() + 1000);
  assert.equal(srv.rooms.size, 0);
  a.close(); await srv.stop();
});

test("version check rejects other protocols", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", proto: 12 });
  const port = await srv.start();
  const a = client(); await a.bind();
  a.send(port, "C", { v: 3 });
  const e = await a.next();
  assert.equal(String.fromCharCode(e[0]), "E"); assert.equal(body(e).err, "version"); assert.equal(body(e).need, 12);
  a.send(port, "Q"); assert.equal(body(await a.next()).err, "version");
  assert.equal(srv.stats.version_rejects, 2);
  a.close(); await srv.stop();
});

test("quick match pairs two queued players in the region; ping reports region", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", region: "sa-east" });
  const port = await srv.start();
  const a = client(), b = client(); await a.bind(); await b.bind();
  a.send(port, "P", { t: 123 });
  const p = await a.next();
  assert.equal(String.fromCharCode(p[0]), "p"); assert.equal(body(p).t, 123); assert.equal(body(p).region, "sa-east");
  a.send(port, "Q", { v: 12 });
  const q = await a.next(); assert.equal(String.fromCharCode(q[0]), "q"); assert.equal(body(q).pos, 0);
  assert.equal(srv.queue.length, 1);
  b.send(port, "Q", { v: 12 });
  const ma = body(await a.next()), mb = body(await b.next());
  assert.equal(ma.slot, 0); assert.equal(mb.slot, 1); assert.equal(ma.code, mb.code); assert.equal(ma.region, "sa-east");
  assert.ok(ma.token.length >= 16 && ma.token !== mb.token);
  assert.equal(srv.queue.length, 0);
  a.send(port, "R", Buffer.from([7])); const d = await b.next(); assert.equal(d[1], 7);
  a.close(); b.close(); await srv.stop();
});

test("queue entries expire; X leaves the queue", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", queueTtlMs: 50 });
  const port = await srv.start();
  const a = client(); await a.bind();
  a.send(port, "Q", { v: 12 }); await a.next();
  srv.sweep(Date.now() + 1000); assert.equal(srv.queue.length, 0);
  a.send(port, "Q", { v: 12 }); await a.next();
  a.send(port, "X"); await new Promise((r) => setTimeout(r, 50)); assert.equal(srv.queue.length, 0);
  a.close(); await srv.stop();
});

test("reconnect with session token from a new address; bad token rejected", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1" });
  const port = await srv.start();
  const a = client(), b = client(), b2 = client(), z = client();
  await a.bind(); await b.bind(); await b2.bind(); await z.bind();
  a.send(port, "C", { v: 12 }); const code = body(await a.next()).code;
  b.send(port, "J", { v: 12, code }); await a.next(); const tb = body(await b.next()).token;
  z.send(port, "B", { code, token: "deadbeefdeadbeef" }); assert.equal(body(await z.next()).err, "bad_token");
  b2.send(port, "B", { code, token: tb });
  const re = body(await b2.next()); assert.equal(re.re, 1); assert.equal(re.slot, 1);
  const nb = await a.next(); assert.equal(String.fromCharCode(nb[0]), "b"); assert.equal(body(nb).peer, `127.0.0.1:${b2.s.address().port}`);
  a.send(port, "R", Buffer.from([9])); const d = await b2.next(); assert.equal(d[1], 9);
  b.send(port, "R", Buffer.from([1])); // old address no longer in the room
  await assert.rejects(a.next(200));
  assert.equal(srv.stats.reconnects, 1);
  a.close(); b.close(); b2.close(); z.close(); await srv.stop();
});

test("abandon past the grace window: the remaining player gets F (forfeit)", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", graceMs: 1000 });
  const port = await srv.start();
  const a = client(), b = client(); await a.bind(); await b.bind();
  a.send(port, "C", { v: 12 }); const code = body(await a.next()).code;
  b.send(port, "J", { v: 12, code }); await a.next(); await b.next();
  const r = srv.rooms.get(code)!; r.members[1].seen -= 5000; // guest silent
  srv.sweep();
  const f = await a.next(); assert.equal(String.fromCharCode(f[0]), "F"); assert.equal(body(f).slot, 1);
  assert.equal(srv.rooms.size, 0); assert.equal(srv.stats.abandons, 1);
  a.close(); b.close(); await srv.stop();
});

test("hardening: size cap, rate limit, ban, bad json, room cap", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", maxPacket: 100, ctlRate: 1, ctlBurst: 3, banViolations: 5, banMs: 60_000, maxRooms: 1 });
  const port = await srv.start();
  const a = client(), b = client(), c = client(); await a.bind(); await b.bind(); await c.bind();
  a.send(port, "C", Buffer.from("{nope")); assert.equal(body(await a.next()).err, "bad_request");
  a.send(port, "C", { v: 12 }); await a.next();
  c.send(port, "C", { v: 12 }); assert.equal(body(await c.next()).err, "busy");
  a.send(port, "R", Buffer.alloc(500)); await new Promise((r) => setTimeout(r, 30));
  assert.equal(srv.stats.dropped_size, 1);
  for (let i = 0; i < 12; i++) b.send(port, "P", { t: i });
  await new Promise((r) => setTimeout(r, 100));
  let got = 0; for (;;) { try { await b.next(50); got++; } catch { break; } }
  assert.ok(got <= 4, `rate-limited pings answered: ${got}`);
  assert.ok(srv.stats.dropped_rate + srv.stats.dropped_banned >= 8 && srv.stats.bans === 1, JSON.stringify(srv.stats));
  b.send(port, "P", { t: 1 }); await assert.rejects(b.next(150)); // banned
  const h = srv.health(); assert.equal(h.ok, true); assert.match(srv.metrics(), /arena_relay_dropped_rate\{region="local"\} \d+/);
  a.close(); b.close(); c.close(); await srv.stop();
});
