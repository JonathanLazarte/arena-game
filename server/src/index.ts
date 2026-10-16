import { RelayServer } from "./relay.js";
const port = Number(process.env.PORT ?? process.argv[2] ?? 47800);
const srv = new RelayServer({ port, log: (s) => console.log(new Date().toISOString(), s) });
srv.start().then((p) => console.log(`arena relay listening on udp/${p}`));
const bye = () => srv.stop().then(() => process.exit(0));
process.on("SIGINT", bye); process.on("SIGTERM", bye);
