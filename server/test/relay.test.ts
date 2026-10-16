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
  a.send(port, "C");
  const w = await a.next();
  assert.equal(String.fromCharCode(w[0]), "W");
  const code = body(w).code as string;
  assert.match(code, /^[A-Z2-9]{5}$/);
  b.send(port, "J", { code: code.toLowerCase() });
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
  c.send(port, "J", { code: "NOPE1" });
  assert.equal(body(await c.next()).err, "no_room");
  a.send(port, "C", { code: "test42" });
  assert.equal(body(await a.next()).code, "TEST42");
  c.send(port, "C", { code: "TEST42" });
  assert.equal(body(await c.next()).err, "code_taken");
  b.send(port, "J", { code: "TEST42" });
  await a.next(); await b.next();
  c.send(port, "J", { code: "TEST42" });
  assert.equal(body(await c.next()).err, "room_full");
  a.close(); b.close(); c.close(); await srv.stop();
});

test("rooms expire without traffic", async () => {
  const srv = new RelayServer({ port: 0, host: "127.0.0.1", roomTtlMs: 50 });
  const port = await srv.start();
  const a = client(); await a.bind();
  a.send(port, "C"); await a.next();
  assert.equal(srv.rooms.size, 1);
  srv.sweep(Date.now() + 1000);
  assert.equal(srv.rooms.size, 0);
  a.close(); await srv.stop();
});
