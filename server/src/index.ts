import { RelayServer } from "./relay.js";
const port = Number(process.env.PORT ?? process.argv[2] ?? 47800);
// Fly.io UDP needs HOST=fly-global-services; elsewhere 0.0.0.0
const host = process.env.HOST ?? "0.0.0.0";
const srv = new RelayServer({ port, host, log: (s) => console.log(new Date().toISOString(), s) });
srv.start().then((p) => console.log(`arena relay listening on udp/${p}`));
const bye = () => srv.stop().then(() => process.exit(0));
process.on("SIGINT", bye); process.on("SIGTERM", bye);
