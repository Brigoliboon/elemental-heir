# Elemental Heir — Multiplayer

Real-time 1v1 PvP over LAN or a direct IP, using Godot 4's high-level
multiplayer API and `ENetMultiplayerPeer`. There is no co-op and no
turn-based mode. The host is the future authority for combat (MP3); this
milestone only establishes the session, the lobby, and a loadout handshake.

## Architecture

- **Transport:** ENet (UDP) on port **7777** by default. Either player may
  pick another port before hosting or joining.
- **Topology:** one host and one client. The ENet server accepts a single
  remote peer, so a third device cannot join.
- **Autoload:** `Net` (`scripts/net/net.gd`) owns the peer, the handshake,
  ready flags, and the start RPC. Gameplay scenes must not replace
  `multiplayer.multiplayer_peer` themselves; they call `Net.leave()` when
  the session should end.
- **Handshake:** after a client connects, both sides send
  `PROTOCOL_VERSION` (currently `1`) plus a loadout summary from
  `PlayerProgress`: display name, level, equipped item paths, and equipped
  skill paths. A version mismatch kicks the client.
- **Saved warrior:** each player brings their own local save. The handshake
  only *describes* that loadout; spawning the two pawns is MP2.
- **Match start:** each player taps Ready. The host's Start button is
  enabled when both are ready and then loads a stub arena. The dedicated
  PvP arena background will be added when the art is ready (MP2).

## Android

The Android export presets enable `INTERNET` and `ACCESS_NETWORK_STATE`.
Multicast is not required for unicast ENet and is left off. The two
devices must be on the same Wi-Fi network (or otherwise able to route to
the host's IP and port). Guest networks and AP isolation will block this.

## Testing on two devices

1. Build or run the game on both devices. Desktop is fine: open two
   instances of the project (in the editor, **Debug → Run Multiple
   Instances → 2**, or launch the binary twice).
2. On the title screen, open **Online**. Internet is not required for LAN
   play; the Online button stays available when the connectivity check
   fails.
3. On device A, confirm the shown LAN IPv4 address, set the port if
   needed, and tap **Host**. Wait until the status says it is hosting.
4. On device B, enter device A's IP and the same port, then tap **Join**.
5. Both screens should list each warrior and level. Tap **Ready** on both
   devices. The host taps **Start** and both move to the arena stub.
6. **Back** on the lobby leaves the session and returns to the title
   screen.

If Join fails, check that the port is open on the host (desktop
firewalls often block UDP 7777) and that both devices are on the same
subnet. `127.0.0.1` works for two instances on one computer.

## Headless smoke test

From the project root:

```sh
~/.local/bin/godot --headless --path . res://tests/mp_sanity.tscn -- --role=host --port=17777 &
~/.local/bin/godot --headless --path . res://tests/mp_sanity.tscn -- --role=client --port=17777
```

A passing run prints `HOST_HANDSHAKE_OK` / `HOST_OK` and
`CLIENT_HANDSHAKE_OK` / `CLIENT_OK`. The regular headless suite is:

```sh
~/.local/bin/godot --headless --path . res://tests/test_runner.tscn
```

## Later milestones

- **MP2** — two pawns in the dedicated PvP arena, input authority, remote interpolation.
- **MP3** — host-authoritative combat (clients send attack/block/skill intents).
- **MP4** — rounds, win, rematch. No loot or XP in PvP unless we decide otherwise.
- **MP5** — optional relay so phones can play over the internet, not just LAN.
