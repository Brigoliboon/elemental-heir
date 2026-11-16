# Elemental Heir — Multiplayer

Real-time 1v1 PvP over LAN or a direct IP, using Godot 4's high-level
multiplayer API and `ENetMultiplayerPeer`. There is no co-op and no
turn-based mode. The host is the authority for combat. Clients send attack, block, and skill
intents; the host resolves hits and replicates health.

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
  describes that loadout; the arena applies it to the spawned pawn.
- **Match start:** each player taps Ready. The host's Start button is
  enabled when both are ready and then loads `scenes/pvp/pvp_arena.tscn` on
  both peers via the `match_ready` signal. `Net` and the ENet peer stay
  alive across that scene change.


## PvP arena

The match plays in `scenes/pvp/pvp_arena.tscn` (`scripts/pvp/pvp_arena.gd`).
There is no `Player` node, no monsters, and no loot or XP.

**Background art.** Drop the final image over this file, keeping the size:

- Path: `assets/backgrounds/pvp/pvp_arena.png`
- Node: `Background` (Sprite2D, `centered = false`, bottom-anchored and
  scaled like the other areas)
- Expected size: **1920 × 1080**
- Floor band, in texture pixels from the top of the image: `ground_far_px`
  420 and `ground_near_px` 850 (exports on `PvpArena`). Tweak these if the
  new art's floor sits elsewhere.
- Spawn points: `SpawnHost` and `SpawnChallenger` (Marker2D), authored in
  the same texture-pixel space (defaults: `(420, 650)` and `(1500, 650)`).

**Pawns.** `MultiplayerSpawner` under the arena root spawns
`entities/characters/pvp_warrior.tscn` into `Pawns`. Each pawn is named
`Pawn_<peer_id>`, has `set_multiplayer_authority(peer_id)`, and runs
`configure_for_pvp()` / `apply_loadout()` from the handshake. The pawn
leaves the `player` group and joins `pvp_pawns`.

**Input and movement.** Only the local pawn reads the HUD joystick, attack
/ block / skill buttons, and keyboard (WASD, J/K, 1–3). Remote pawns
interpolate `sync_x` / `sync_y` / facing / animation / scale from a
`MultiplayerSynchronizer` on `PvpController`. The camera follows the
local pawn and stays inside the background.

**Combat.** Sword and skill hitboxes in PvP target `pvp_pawns` on the
Player collision layer and set `authority_only`, so only the host applies
damage. They also skip the attacker, so a pawn cannot hit itself. The
host then replicates health, knockback, and death to the client. Offline
single-player is unchanged: `pvp_mode` stays off and hitboxes still
target `enemies`.

**Match end.** The first KO wins. Both peers see a result banner
(Victory / Defeat / Draw). The host can Rematch (resets health and
returns both warriors to their spawns, no scene change). Leave ends the
session and returns to the title screen. If a peer disconnects, the
other sees "Opponent left".

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
   devices. The host taps **Start** and both move to the PvP arena, each
   with their saved warrior and gear.
6. Fight. Movement is immediate on your own warrior; attacks, blocks, and
   skills are confirmed by the host. First KO wins. The host can Rematch;
   Leave returns both players to the title screen.
7. **Back** on the lobby (before Start) leaves the session and returns to
   the title screen.

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
`CLIENT_HANDSHAKE_OK` / `CLIENT_OK`.

The combat smoke test (two pawns plus one host-authoritative hit):

```sh
~/.local/bin/godot --headless --path . res://tests/mp_combat.tscn -- --role=host --port=17778 &
~/.local/bin/godot --headless --path . res://tests/mp_combat.tscn -- --role=client --port=17778
```

A passing run prints `HOST_SPAWN_OK` / `HOST_HIT_SENT` / `HOST_OK` and
`CLIENT_SPAWN_OK` / `CLIENT_HIT_OK` / `CLIENT_OK`. The regular headless
suite (including `tests/test_pvp.gd`) is:

```sh
~/.local/bin/godot --headless --path . res://tests/test_runner.tscn
```

## Later milestones

- **MP2** and **MP3** are in place (arena, two pawns, input authority,
  interpolation, and host-authoritative combat). First KO, Rematch, and
  Leave are included as a simple match flow.
- **MP4** (optional) — best-of rounds or a more structured match flow.
- **MP5** — optional relay so phones can play over the internet, not just LAN.
