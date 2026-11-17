# Dedicated multiplayer server

From a Linux x86-64 Git checkout, run \`./server.sh\`. The script finds a local Godot 4.6 binary or downloads Godot 4.6.3 once, starts a headless ENet server and stores persistent saves in \`server-data/\`. If your checkout loses executable bits, run \`bash server.sh\`.

\`\`\`bash
git clone https://github.com/requiredtruth/no-mans-drive-game.git
cd no-mans-drive-game
./server.sh
# optional:
PORT=24680 SEED=4242 MAP=starter ./server.sh
# other modes: MAP=regular or MAP=everything
\`\`\`

In the Android game choose **Online multiplayer / Join server**, then enter \`your-domain.example:24680\` or \`203.0.113.20:24680\`. The port is **UDP**, not TCP/HTTP. Allow and forward UDP 24680 on the hosting Linux firewall, VPS security group and router as applicable. Point an A/AAAA DNS record at the server's public address. A NAT-forwarded LAN host requires port forwarding (or an appropriate VPN). The script cannot configure your external firewall.

The host is a shared persistent world; connected Android clients receive world snapshots and periodic player position/customization updates. Names and wardrobes are saved on individual devices, while server world progress persists under \`server-data/\`.

**Current limits:** This is a friends-first prototype. It does not authenticate users or prevent malicious clients. Simultaneous players and complex multi-vehicle editing require more authoritative server validation and end-to-end WAN playtests. The configured limit is 15 connected clients; performance is not guaranteed. Existing co-op should not be exposed to untrusted public traffic.
