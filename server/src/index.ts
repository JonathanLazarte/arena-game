import http from "node:http";
import { RelayServer } from "./relay.js";
const env = process.env;
const num = (v: string | undefined, d: number) => (v != null && v !== "" && !isNaN(Number(v)) ? Number(v) : d);
const port = num(env.PORT ?? process.argv[2], 47800);
// Fly.io UDP needs HOST=fly-global-services; elsewhere 0.0.0.0
const host = env.HOST ?? "0.0.0.0";
const srv = new RelayServer({
  port, host, log: (s) => console.log(new Date().toISOString(), s),
  region: env.REGION ?? "local", proto: num(env.GAME_PROTO, 11), graceMs: num(env.GRACE_MS, 20_000),
  maxPacket: num(env.MAX_PACKET, 1200), maxRooms: num(env.MAX_ROOMS, 5000),
  relayRate: num(env.RELAY_RATE, 200), ctlRate: num(env.CTL_RATE, 10),
});
srv.start().then((p) => console.log(`arena relay listening on udp/${p} region=${srv.opts.region} proto=${srv.opts.proto}`));
// health + metrics over HTTP (TCP); HEALTH_PORT=0 disables
const hp = num(env.HEALTH_PORT, 8080);
const web = hp > 0 ? http.createServer((req, res) => {
  if (req.url === "/healthz") { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify(srv.health())); }
  else if (req.url === "/metrics") { res.writeHead(200, { "content-type": "text/plain; version=0.0.4" }); res.end(srv.metrics()); }
  else { res.writeHead(404); res.end(); }
}).listen(hp, env.HEALTH_HOST ?? "0.0.0.0") : null;
const bye = () => { web?.close(); srv.stop().then(() => process.exit(0)); };
process.on("SIGINT", bye); process.on("SIGTERM", bye);
