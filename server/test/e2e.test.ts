// End-to-end: relay (in-process) + two headless Godot clients (tests/net_client.gd) on localhost
// with simulated latency/loss. Skipped when no `godot` binary is on PATH (or GODOT env).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { RelayServer } from "../src/relay.js";

const GODOT = process.env.GODOT ?? "godot";
const PROJECT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const hasGodot = spawnSync(GODOT, ["--version"]).status === 0;

function client(args: Record<string, string | number>): Promise<any> {
  const out = path.join(tmpdir(), `arena_e2e_${process.pid}_${args.role}_${Math.random().toString(36).slice(2)}.json`);
  const argv = ["--headless", "--path", PROJECT, "-s", "res://tests/net_client.gd", "--",
    ...Object.entries({ ...args, out }).map(([k, v]) => `${k}=${v}`)];
  return new Promise((res, rej) => {
    const p = spawn(GODOT, argv, { stdio: ["ignore", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => (err += d));
    p.on("exit", () => {
      try { const j = JSON.parse(readFileSync(out, "utf8")); rmSync(out); res(j); }
      catch (e) { rej(new Error(`client ${args.role} produced no result: ${err.slice(-2000)}`)); }
    });
  });
}

function checkPair(a: any, b: any, ticks: number) {
  assert.equal(a.desync, -1, "host saw no desync"); assert.equal(b.desync, -1, "guest saw no desync");
  let common = 0;
  for (const [f, c] of Object.entries(a.ck)) if (f in b.ck) { common++; assert.equal(c, b.ck[f], `checksum frame ${f}`); }
  assert.ok(common > ticks * 0.8, `common confirmed frames ${common}`);
  assert.ok(a.checked_to > ticks * 0.8 && b.checked_to > ticks * 0.8, "in-band checksum exchange covered the match");
  assert.equal(a.replay_bad, 0); assert.equal(b.replay_bad, 0);
  assert.ok(a.replay_frames > ticks * 0.8);
}

const scenarios = [
  { name: "relay, direct after punch, 0 ms", lat: 0, jit: 0, loss: 0, force: 0 },
  { name: "relay-forwarded, 50 ms RTT, 2% loss", lat: 25, jit: 4, loss: 0.02, force: 1 },
  { name: "relay, 100 ms RTT, 2% loss", lat: 50, jit: 6, loss: 0.02, force: 0 },
  { name: "relay-forwarded, 200 ms RTT, 5% loss", lat: 100, jit: 10, loss: 0.05, force: 1 },
];

for (const sc of scenarios) {
  test(`two clients stay in sync: ${sc.name}`, { skip: !hasGodot, timeout: 120_000 }, async () => {
    const srv = new RelayServer({ port: 0, host: "127.0.0.1" });
    const port = await srv.start();
    const code = "E2E" + Math.floor(Math.random() * 1e5);
    const ticks = 900;
    const common = { mode: "relay", relay: `127.0.0.1:${port}`, code, ticks, delay_ms: sc.lat, jitter_ms: sc.jit, loss: sc.loss, force_relay: sc.force };
    const [a, b] = await Promise.all([client({ ...common, role: "host" }), client({ ...common, role: "guest" })]);
    await srv.stop();
    console.log(sc.name, JSON.stringify({ rtt: [a.rtt, b.rtt], delay: a.delay, direct: [a.direct, b.direct], rollbacks: [a.rollbacks, b.rollbacks], max_resim: [a.max_resim, b.max_resim], skips: [a.sync_skips, b.sync_skips], stalls: [a.stalls, b.stalls], relayed: srv.stats.relayed, kBps: Math.round(a.bytes_out / (ticks / 60) / 100) / 10 }));
    assert.equal(a.slot, 0); assert.equal(b.slot, 1);
    assert.equal(a.direct, !sc.force); assert.equal(b.direct, !sc.force);
    if (sc.force) assert.ok(srv.stats.relayed > ticks, "packets went through the relay");
    assert.equal(a.delay, b.delay, "both use the host's input delay");
    checkPair(a, b, ticks);
  });
}

test("LAN direct join without server, 60 ms RTT", { skip: !hasGodot, timeout: 120_000 }, async () => {
  const port = 47000 + Math.floor(Math.random() * 900);
  const common = { mode: "lan", port, ip: "127.0.0.1", ticks: 900, delay_ms: 30, jitter_ms: 3, loss: 0.01 };
  const [a, b] = await Promise.all([client({ ...common, role: "host" }), client({ ...common, role: "guest" })]);
  console.log("lan", JSON.stringify({ rtt: [a.rtt, b.rtt], delay: a.delay, rollbacks: [a.rollbacks, b.rollbacks] }));
  assert.equal(a.direct, true);
  checkPair(a, b, 900);
});
