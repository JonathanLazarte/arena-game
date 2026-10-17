# Deploying the relay (docs only, nothing is deployed)

The relay is a single Node 20 process: UDP 47800 for the game, plus optional HTTP on 8080 for `/healthz` (JSON) and `/metrics` (Prometheus text). It keeps everything in memory, so it needs no database and no accounts.

## Why the Node/TS relay and not Nakama
The game only needs four things from a server: pairing (room codes or a quick-match queue), NAT punch hints, packet relay and reconnect tokens. The existing relay already speaks the game's UDP protocol, and the extension is about 300 lines with tests. Nakama would add a database (Postgres/CockroachDB), user accounts or device auth, and a WebSocket/RUDP transport the Godot client doesn't use. That is more to operate and more to secure, and it conflicts with "no accounts". Revisit Nakama if you add persistent profiles, ranking or friends.

## Regions
Run one relay per region and set `REGION` on each. Put the full list in the game's relay field: `sa=sp.example.com:47800, us=us.example.com:47800`. The "Medir ping / región" button pings every relay ('P'/'p') and picks the lowest. "Partida rápida" queues on the chosen relay, so the queue is per region. Room codes are created on the chosen relay, and both players must use the same one.

## Oracle Cloud Free Tier, São Paulo (sa-saopaulo-1)
1. Create an Always Free VM (Ampere A1 arm64 or E2.1.Micro) with Ubuntu 22.04 or Oracle Linux in São Paulo, the closest region to Montevideo (about 30–40 ms).
2. Networking: VCN → Security List → add an ingress rule for UDP 47800 from 0.0.0.0/0. Do not open 8080.
3. VM firewall:
   - Oracle Linux: `sudo firewall-cmd --add-port=47800/udp --permanent && sudo firewall-cmd --reload`
   - Ubuntu image (iptables rules ship by default): `sudo iptables -I INPUT -p udp --dport 47800 -j ACCEPT && sudo netfilter-persistent save`
4. Install Docker: `curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker $USER`, then log in again.
5. `git clone <repo> && cd arena-game/server/deploy && docker compose up -d --build`. The node:20-alpine image is multi-arch, so it works on Ampere.
6. Check it:
   - `curl -s localhost:8080/healthz`
   - From a PC: in-game ping, or `npm test` locally.
   - Logs: `docker compose logs -f`.
7. Point the game at it: `sa=<public-ip>:47800`. A DNS name is optional.

Without Docker: `npm ci && npm run build && PORT=47800 REGION=sa-east node dist/src/index.js` under systemd (`Restart=always`, `User=nobody`).

## Hardening already in the relay (env to tune)
- Version check: C/J/Q must carry `v == GAME_PROTO` (default 11), otherwise the client gets `E version`. Bump both together.
- Session tokens: 96-bit random per member. Reconnect ('B' code+token) rebinds a new address within `GRACE_MS` (default 20 s). After that the remaining player gets 'F' and wins by forfeit.
- Rate limits per address (token buckets): relay `RELAY_RATE`/s (200, burst 400) and control 10/s (`CTL_RATE`, burst 20). 600 violations within a minute bans the address for 60 s.
- Packet size cap `MAX_PACKET` (1200 bytes). The client's reconnect snapshots are chunked to 900 bytes.
- Room cap `MAX_ROOMS` (5000, `E busy`). Rooms expire after 120 s of silence, and queue entries after 10 s without keepalive.
- Metrics: packets, relayed, matches, quick, reconnects, abandons, dropped_rate/size/banned, bans, version_rejects, bytes_in/out, plus rooms and queue gauges.

Fly.io (`fly.toml`) remains an alternative (region `gru`). It was not deployed either.
