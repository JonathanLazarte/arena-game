# arena-relay

UDP rendezvous + relay for arena-game online matches. Pairs two clients by room code, tells each the other's public address (so they try a direct NAT punch), and forwards packets when the direct path fails. Stateless apart from in-memory rooms; no accounts, no storage.

```
npm install
npm test          # unit tests (pairing, relay, errors, expiry)
npm run test:e2e  # relay + two headless Godot clients (needs `godot` on PATH or GODOT=/path/to/godot)
npm run build && npm start        # listens on udp/47800 (PORT=..., HOST=...)
docker build -t arena-relay . && docker run -p 47800:47800/udp arena-relay
```

Protocol and deployment notes: `docs/netcode.md` section 10.
