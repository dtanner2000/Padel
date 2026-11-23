# Padel: Off The Glass — Godot 4.6 (iOS + Android, landscape)

**Store name:** Padel: Off The Glass · **home-screen name:** Off The Glass (`config/name` in Project Settings; iOS truncates labels longer than about 12–13 characters).

First playable slice: a full doubles match against AI, with you and an AI partner (Ana) against two AI rivals.

Open the folder in **Godot 4.6** (4.4+ works) and press F5. On desktop, mouse clicks act as touches, and the keyboard works too.

## Modes

The start menu (with a live AI match playing behind it) offers:

- **Quick match**: one set, first to 4 games, about five minutes
- **One set**: first to 6, tie-break at 6-6
- **Full match**: best of three
- **Play online**: a quick match against a random opponent, or a private game with a friend using a 4-letter code. You and Ana (AI) take on them and Leo (AI). See below.
- **Practice**: a ball machine on the far baseline feeds six balls per drill, cycling groundstrokes → off the back glass → overheads. It counts your streak of balls landed in.

The golden point toggle is on the menu. The pause button gives **Resume / Quit to menu**.

## Play online

- **Quick match**: pairs you with the next person searching (first to 4 games). If nobody turns up within 25 seconds, a **Play the AI instead** button appears; the search keeps running until you leave.
- **Private game**: pick a length and you get a code like `K7QF`. Your friend types it under **Friend's code**.

The host phone (the first in the queue, or whoever made the code) runs the match. The other phone sends its stick and HIT input, and gets the court back about 30 times a second, viewing from its own end with its own scoreboard, messages, aim ring and "Leo: Mine!" calls. If either phone drops out, the other goes back to the menu. In a match, pause becomes **Leave match**.

### How it connects

```
phone A  ──wss──►  relay server (server/relay.js)  ◄──wss──  phone B
```

- `scripts/relay_peer.gd`: a Godot `MultiplayerPeerExtension` over a WebSocket, so the match's ordinary RPCs (`net_*` in `main.gd`) run through the relay. The host is peer 1 and the guest is peer 2.
- `scripts/online.gd`: quick match, private codes, errors; set **`RELAY_URL`** here.
- `server/`: about 200 lines of Node.js. It does the queue, codes, version check, heartbeats and flood/abuse limits, and forwards bytes blindly. Matches use roughly 10 KB/s per player.

Secure WebSockets go through home routers and mobile networks with no port forwarding, and a `wss://` hostname satisfies Apple's encrypted-traffic and IPv6-only review requirements.

### Deploy the relay (Fly.io, about £2–5/month)

```
cd server
fly launch --copy-config --no-deploy     # pick a unique app name if padel-relay is taken
fly deploy
curl https://<app-name>.fly.dev/health
```

Then set `RELAY_URL := "wss://<app-name>.fly.dev"` in `scripts/online.gd`. Keep **one** machine: matches are held in memory. One small VM handles thousands of players. `/health` shows players online, people waiting and matches started.

**Versioning:** `PROTOCOL` in `relay_peer.gd` and `relay.js` must match. When you change the netcode, bump both and deploy the server alongside the store release. Older apps get "Please update the game to play online."

### Testing

- Locally: `cd server && npm install && npm start`, then run two game instances (*Debug → Customize Run Instances → 2*) with `--relay=ws://127.0.0.1:8080` in the instance arguments.
- Headless: `--relay=ws://127.0.0.1:8080 --online-quick` in two processes, or `--online-create=set` and `--online-join=CODE`.

## Controls

| Touch | Keyboard | What it does |
|---|---|---|
| Left thumbstick (floats where you touch) | WASD / arrows | Move |
| **HIT**: hold, swipe to aim | Hold Space / J, aim with move keys | Touching HIT shows your backswing at once. While you hold it, a white ring marks where the shot will land, and the shot fires the moment the ball is in reach. A quick tap still works (it's buffered for 0.3 s). The lime arc shows timing |
| **LOB** | K | Lob (fires on touch-down) |
| **SMASH** (lit when the ball is overhead) | L | Flat smash. A high ball played with HIT becomes a bandeja |
| II | — | Pause menu |

With the stick idle, *move-assist* steers you to your ball (the lime ring); set `MOVE_ASSIST` in `main.gd`. Hitting a well-timed ball after it comes off your own back glass is a **bajada**, with extra pace. Hits trigger haptics on iPhone.

## Design notes from Red Bull Padel: Court Legends reviews

| What players said | What this build does |
|---|---|
| "swing timing and moving your players around feels clunky and sluggish" | Your player accelerates about 2.5× faster than the AI, the backswing starts on touch-down, and the shot fires at contact rather than waiting for you to lift your thumb |
| Red Bull later added a "swipe trail" for touch feedback | An on-court ring shows where your shot will land while you aim |
| "matches are way too short. 3 points per match… barely a warm-up" | You choose the length: 4 games, a set, or best of three |
| Wants a practice mode | Practice with drills and streaks |
| Wall play praised as central; they later patched in "improved backwall shots" | Glass rebounds are predicted exactly (the ring shows them), with a bajada reward |
| Energy running out on reopen, forced "friendly battle" loops, rewards not claimable, blocked by age/OS checks | Offline, no energy, no loot boxes, no account: open it and play |
| "add multiplayer to play with a friend" / wants private matches | Online quick match plus private codes for friends, with no account needed |

## Rules implemented

- Underarm serve from behind the service line, diagonal box, two serves; a serve into the fence after the bounce is a fault
- Ball must bounce on the other side before touching a wall; your own walls can be used freely
- Back glass and side glass (3 m) give the ball back; the mesh fence kills it; above 4 m is out
- Double bounce, net, out of court (smash *por tres*), ball coming back over (*por cuatro*)
- 15/30/40 with **golden point** (switch `golden_point = false` in `match_score.gd` for advantage), sets to 6 by 2, tie-break at 6-6, best of three
- Serve rotation you → rival → Ana → rival; you and Ana call "Mine!" / "Yours!" by halves

## Code map

| File | Role |
|---|---|
| `scripts/main.gd` | Match flow, referee, AI decisions, human input, shot execution |
| `scripts/ball_sim.gd` | Deterministic ball physics (gravity, floor, glass/mesh, net), shared by the live ball and AI prediction |
| `scripts/ball.gd` | Live ball node, substepping, trajectory prediction |
| `scripts/shot.gd` | Projectile solver: lands a shot on a target and clears the net |
| `scripts/court.gd` | Dimensions, wall surface lookup, procedural court geometry |
| `scripts/player.gd` | Player movement and placeholder low-poly body + paddle swing |
| `scripts/match_score.gd` | Padel scoring |
| `scripts/hud.gd`, `touch_*.gd` | Touch HUD, iOS safe area aware |
| `scripts/online.gd`, `relay_peer.gd` | Online play: matchmaking and the relay transport |
| `server/` | Relay server (Node.js, Dockerfile, fly.toml). Ignored by Godot via `.gdignore` |
| `scripts/debug_overlay.gd` | Playtest overlay (triple-tap top-right / F3) |
| `export_presets.cfg`, `codemagic.yaml`, `icons/` | iOS/Android export presets, CI workflows, app icons |

The ball doesn't use Godot's `RigidBody3D`. It runs a small custom simulation, so AI prediction and the real flight match exactly, and the restitution feel is easy to tune (constants at the top of `ball_sim.gd`).

## Test switches

Pass these after `--` on the command line:

```
godot --headless --path . --fixed-fps 60 -- --autoplay --quit-after=600   # AI vs AI soak test + rally stats
godot --headless --path . --fixed-fps 60 -- --mash --quit-after=600       # bot taps HIT as you
--mode=quick|set|match|practice                                           # skip the menu
--relay=ws://127.0.0.1:8080 --online-quick                                # online test (run two copies)
--trace                                                                   # print every shot
--screenshot=out.png@8                                                    # save a frame (needs a renderer)
```

## Playtesting on a device

**Debug overlay:** triple-tap the top-right corner (or press F3) during play. It shows:
- frame rate, frame time, the screen's refresh rate and whether motion is interpolated;
- device model, window size, safe area and draw calls;
- online state and round-trip time, plus snapshot age on the guest's phone;
- every control's touch zone, with a red dot wherever a finger lands, so a missed tap shows whether it was outside the zone.

**Smooth motion:** physics interpolation is on (set in code in `main.gd` and in Project Settings → Physics). The game logic still runs 60 times a second, but 90 and 120 Hz screens draw in-between frames. When players or the ball jump to a new spot, `_snap_positions()` stops them sliding there.

## Builds with Codemagic

`codemagic.yaml` follows the Jetpack Attack pipeline (`dtanner2000/JPA`), which already ships to TestFlight. Both workflows run on the **Mac mini M2**, since Linux machines aren't on the current Codemagic plan, and download Godot **4.6.3** and its export templates.

| Workflow | Output |
|---|---|
| **iOS → TestFlight** | Fetches signing files, Godot exports the Xcode project, Codemagic builds the IPA and uploads it to TestFlight (internal testers get it automatically) |
| **Android → signed APK** | A signed release APK to sideload. Play needs an AAB via Gradle later; JPA's `android-play` workflow is the pattern |

Identifiers: bundle ID / Android package **com.davidtanner.padel**, App Store Connect Apple ID **6838439193**, Team ID **3YB9G94LWA** (in `export_presets.cfg`). Build numbers come from Codemagic's `PROJECT_BUILD_NUMBER`.

**One-time setup on the Padel app in Codemagic**
1. **Add application** → the **Padel** repo → it finds `codemagic.yaml`.
2. App Store Connect key: reuses the team-level integration **JPA ASC Key**. Nothing to add.
3. **Environment variables**: create group **apple** with `CERTIFICATE_PRIVATE_KEY` (Secure), the same key Jetpack Attack's `apple` group holds. Groups are per app, so it must be added again here. If you don't have it any more, generate one (`ssh-keygen -t rsa -b 2048 -m PEM -f padel_cert_key -q -N ""`) and paste the file's contents; the first build creates a new distribution certificate.
4. Android only: **Code signing identities → Android keystores** → reference **padel_keystore** (or point the workflow at `jpa_keystore` for quick sideload tests). Keep a backup of any key you'll publish with.
5. Run **iOS → TestFlight**.

## Store release checklist

**Both stores**
- [ ] Relay deployed, `RELAY_URL` set to `wss://…` (never `ws://` or an IP address)
- [ ] Privacy policy URL (required by both). The game has no accounts or chat. The relay sees IP addresses only to connect a match, and stores nothing
- [ ] Age rating questionnaire: answer **yes** to "users can interact online" and **no** to chat or user-generated content
- [ ] Test a real match phone-to-phone over mobile data, not just Wi-Fi

**App Store (iOS)**
- [ ] Replace the placeholder icon in `icons/` (1024×1024 PNG with **no transparency**; Apple rejects icons with an alpha channel)
- [ ] App Privacy: "Data Not Collected" fits if you add no analytics or ads. Re-check if you do
- [ ] Apple reviews on an IPv6-only network. `wss://` plus a hostname works there; `curl -6 https://<app>.fly.dev/health` should answer
- [ ] No Local Network permission is needed now (that was only for the old same-Wi-Fi mode)
- [ ] In App Review notes, tell the reviewer how to see online play: "Tap Play online → Private game, and join the code from a second device, or use Quick match → Play the AI instead"

**Google Play (Android)**
- [ ] Play needs an **AAB**, not an APK: switch the Android preset to Gradle build and export format AAB (Godot installs an Android build template), and add a Codemagic step for it
- [ ] Data safety form: no data collected or shared. Data is encrypted in transit (TLS)
- [ ] Target API level: Godot 4.6 meets Play's current requirement. Re-check on each Godot upgrade

## Next steps

1. Online polish: rematch with the same opponent, a short reconnect window if a phone briefly drops, and 2v2 with four phones
2. Fairer online feel for the guest: client-side prediction of their own movement. Later, a server-run match so neither phone is host
3. Real character models and animation (run, forehand/backhand, overhead), with a contact frame that drives timing
4. Sounds: ball on glass vs mesh, paddle pop, crowd
5. Shot spin (slice/topspin) in `BallSim`, and the *víbora*
6. Difficulty setting (AI `skill`) and court colours in the menu
