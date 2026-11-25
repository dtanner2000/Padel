# Padel: Off The Glass — Godot 4.6 (iOS + Android, landscape)

**Store name:** Padel: Off The Glass · **home-screen name:** Off The Glass (`config/name` in Project Settings; iOS truncates labels longer than about 12–13 characters).

First playable slice: a full doubles match against AI, with you and an AI partner (Ana) against two AI rivals.

Open the folder in **Godot 4.6** (4.4+ works) and press F5. On desktop, mouse clicks act as touches, and the keyboard works too.

## Start menu

A poster layout: the mode list on a dark slab cut by a diagonal of lime and blue stripes, with your pair celebrating on the right in your own kit (a small 3D scene rendered live into a `SubViewport`, `scripts/menu_hero.gd`, paused when the menu is hidden). Headings use **Anton** and the rest of the UI **Fira Sans** (both SIL Open Font License; licences in `assets/fonts/`). `tools/hero_render.gd` renders the same pair to a transparent PNG for store art.

## Modes

The start menu (with a live AI match playing behind it) offers:

- **Career**: four tournaments, each at its own venue and court: *Club Night* (blue, floodlit), *Regional Open* (green, sunny), *National Championship* (clay-red, sunset) and *World Tour Finals* (purple, arena). Win the quarter-final, semi-final and final (a full set) to take the title and unlock the next venue. A loss sends you back to the quarter-final. Rivals get sharper each round and at each venue.
- **Quick match**: one set, first to 4 games, about five minutes
- **Training**: drills with a ball machine (groundstrokes, aiming, slice, off the glass, volleys, power smash, glass targets, free practice). **Glass targets**: land the ball deep so it bounces up into a lit panel on the far back or side glass (glass on the full is out, as in a match)
- **Daily challenge**: a goal slides across the rival back glass. Score by putting the ball into it, on the full or after a bounce. Each goal shrinks it and speeds it up, and three misses ends the run. The movement pattern is seeded by the date, so it changes daily and is the same for everyone. Today's best and your all-time best are saved.
- **Play online**: a quick match against a random opponent, or a private game with a friend using a 4-letter code. See below.
- **Longer match**: one set (first to 6, tie-break at 6-6) or best of three

The bottom row has **Team** (pick who you play as and your partner; the other two are your rivals), **AI** level (Easy/Normal/Hard, tap to cycle), **Court** (any venue you've unlocked, for quick and longer matches), **Stats** and **Settings** (sound, vibration, left-handed controls, button size, AI level, golden point).

Each character has a style: Dani *All-rounder*, Ana *Touch* (cleaner timing, more lobs and slices), Marco *Power* (harder drives, more smashes) and Leo *Speed* (quicker about the court). The edge is small and applies offline only, so online play stays even. A coloured ring at each player's feet shows their team (orange = yours, purple = rivals), since the character kits are baked into the models. On the Team screen you also choose your **side**: left (revés) or right (drive); your partner takes the other.

### Locker: skills and paddles (offline only)

- **Skill points** come from career wins (1 per round, 3 for a title), completing a training drill for the first time (1), and scoring 5+ in the daily challenge (1 a day). Spend them on **Power** (+0.35 m/s a level), **Speed** (+1.6 %), **Reach** (+3 cm) and **Touch** (+0.012 timing), up to level 5 each.
- **Paddles** trade control for power by shape, as real ones do. *Club Round* is the starter. *Teardrop Pro* comes from the Club Night title, *Diamond Power* from the Regional Open (most power, smaller sweet spot), *Carbon Control* from the Nationals (biggest sweet spot) and *Tour Diamond* from the World Tour Finals. Each also changes how fast SMASH charges, and the paddle in your hand changes shape and colour. AI players carry paddles that suit their style (looks only).

### Signature shots

Unlocked by career titles. Each also gets its own training drill.

| Shot | Unlock | How |
|---|---|---|
| **Víbora** | Club Night | On a high ball, flick HIT sideways: a sliced overhead into a deep corner that skids low |
| **Chiquita** | Regional Open | Swipe HIT straight down: a soft dipping ball at the net players' feet |
| **Contrapared** | National Championship | Beaten by a deep ball? Let it pass you and tap HIT. You play it into your own back glass and back over the net (the shot is found by simulating the ball physics) |

| **Dejada** | Club Night | At the net, swipe HIT down: a feathered drop shot with heavy backspin that dies just over the net |
| **Globo** | Regional Open | Tap LOB with good timing (ring full) when they're at the net: a higher, deeper lob; net players react late |
| **Por cuatro** | World Tour Finals | With SMASH charged, tap SMASH and swipe sideways (or hold the stick sideways): the topspin kick takes it out over the side wall. Found by simulating the ball physics, like the contrapared |

The AI also plays víboras, chiquitas, dejadas, globos and the odd por cuatro. Online, everyone has every shot.

### Partner combo

In offline matches the **COMBO** button (above LOB) fills as your team plays good rallies: every hit by you or your partner, double for perfect timing, and a bonus for each point won. When it's full, tap it: your partner calls "Together! Next one's yours!", and your next shot is the team's winner (a por cuatro or power smash on a high ball, otherwise a hard drive into the open corner) while the rivals are wrong-footed. Win the point and the pair high-five.

### Venues, wind and court colours

Each venue has its own surroundings: an indoor club hall (Club Night), a park (Regional Open), a beach at sunset (Nationals), and a packed arena with a panoramic all-glass court (World Tour Finals, where the crowd jumps on big points). The **City Rooftop** (teal court, skyline) is open for quick play from the start. Outdoor courts have **wind**: a new gust each point, shown under the scoreboard ("Breezy · blowing left"). It is part of the ball physics, so the AI reads it too. There is no wind indoors, in training or online. Settings → **Court colour** overrides any venue's colour (blue, green, red, teal, purple, pink, grey).

### Replays

Big points get a slow-motion replay from a low side-on camera: a winning power smash, víbora, chiquita or contrapared, or (at most every fourth point) a 20-shot rally or a smash out of the court. Tap HIT to skip, or turn replays off in Settings. Offline only. Every frame of the rally is kept in a 5-second ring buffer (positions plus each player's rig pose); the replay shows from a second before the decisive shot to 1.7 s after it, blended back at 45 % speed. The players celebrate first, then the replay plays with a whoosh, the crowd fades out, and the rally's own hit and bounce sounds play back slowed down with the picture.

### Celebrations

After a winning special shot, a smash out of the court, or a set, the winning pair celebrates (jumps or fist pumps) and the losers hang their heads, with the camera brought round in front of the winners; tap HIT to skip. After a match the winners turn and high-five, and the camera does a slow 360° lap around them. After a match, a finished drill or a daily challenge, buttons offer the next step: next round or tour, try again, next drill, keep going, or back to the menu (HIT does the first).

### Wardrobe, coins and achievements

You earn **coins** for points won (2), matches (5, plus 15 for a win), career rounds (25, a title 100), first-time drills (20), daily goals (3 each) and achievements (50). The Wardrobe (Locker → Wardrobe) sells headwear (headband, Nadal-style bandana, visor, cap), 90s neon shirts (neon yellow, hot pink, blaze orange, acid green, electric blue, tournament white: a shader repaints your character's shirt colour, keyed per character in `Roster.CHARACTERS`), a pair of sweatbands, colours including four neons, and paddle colourways. Looks only. Real-money purchases would need the App Store / Play billing plugins; the coin economy is ready for that.

There are 25 **achievements** (Stats → Achievements).

**Game Center (iOS).** The game signs in at launch, reports achievements and posts three leaderboards: `daily_best`, `longest_rally` and `online_rating` (`scripts/game_services.gd`). Stats has a Game Center button for the dashboard once signed in. It uses [GodotApplePlugins](https://github.com/xibbon/GodotApplePlugins) (GameCenter + Runtime), which the Codemagic iOS build downloads at a pinned release because it's ~300 MB; everything is looked up by name, so the editor, desktop and Android builds run without it. Needs iOS 17+ and `entitlements/game_center` (both set in `export_presets.cfg`). In App Store Connect → the app → Game Center, create each achievement with the same id as `Awards.list()`, and the three leaderboards as "Classic, best score, high to low". Google Play Games is a later step (`report()` already calls it if its plugin is present).

### Accessibility

Settings: **Ball trail** (a fading trail behind the ball), **Ball colour** (high-contrast magenta), **Ball size** (large), **One-handed** (no stick: your player moves itself like a partner would; you just hit), left-handed layout and button size.

### Four-player doubles

Online → **Doubles, 4 phones** makes a room code for up to four phones: the 2nd and 4th to join play against you, and the 3rd is your partner. The host can tap **Start now** with fewer, and the AI plays the empty places. If a phone drops out mid-match, the AI takes over its player. Doubles rooms are unranked. The relay protocol is now 3: each frame carries a slot byte (the target going out, the sender coming in).

### Ranked online

Random quick matches are ranked (Elo, starting at 1000, K = 32; Bronze, Silver from 1050, Gold 1150, Platinum 1300, Diamond 1500). Private games with a code are unranked. The relay pairs players by rating, starting within 150 points and widening by 40 a second, so nobody waits long. After a match, both players tap HIT for a **rematch**, and each phone shows whether the other has asked. Ratings live on each phone; a server-side ladder would need accounts, which the game avoids. Ratings are also posted to the Game Center `online_rating` leaderboard.

Everything is saved in `user://profile.cfg` (`scripts/profile.gd`). Training progress is in `user://training.cfg`.

## Sound

`assets/sfx/` holds the game's sounds. Paddle, smash, floor, glass, mesh, net, trainer squeak, UI click, goal ding and miss buzz are synthesised by `tools/sfx/make_sfx.py` (numpy + scipy, no samples). The crowd applause is two real recordings from [Mixkit](https://mixkit.co/free-sound-effects/applause/) (free licence, no attribution required): `applause.ogg` ("Small crowd clapping") for normal points and `applause_big.ogg` ("Cheering crowd loud whistle") for big ones, trimmed to 3 and 5 seconds with fades, mono, loudness-normalised, about 95 KB together. After a big point one of the winners shouts: `voice_cheer.ogg` is Mixkit's "Male voice cheer" (any `assets/sfx/voice_*.ogg` is picked at random). Ball sounds are positional (`scripts/sfx.gd`), louder for faster balls, and the crowd scales with the venue. On the online guest's phone, bounces are inferred from the snapshots.

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

**Versioning:** `PROTOCOL` in `relay_peer.gd` and `relay.js` must match (now 3: ratings, rematch and 4-phone rooms). When you change the netcode, bump both and deploy the server alongside the store release. Older apps get "Please update the game to play online."

### Testing

- Locally: `cd server && npm install && npm start`, then run two game instances (*Debug → Customize Run Instances → 2*) with `--relay=ws://127.0.0.1:8080` in the instance arguments.
- Headless: `--relay=ws://127.0.0.1:8080 --online-quick` in two processes, or `--online-create=set` and `--online-join=CODE`.

## Controls

| Touch | Keyboard | What it does |
|---|---|---|
| Left thumbstick (floats where you touch) | WASD / arrows | Move |
| **HIT**: hold, swipe to aim | Hold Space / J, aim with move keys | Touching HIT starts the backswing. While you hold it, a white ring marks where the shot will land, and it fires the moment the ball is in reach. Swipe up for depth, up-left/up-right to aim. A quick tap still works. The lime arc shows timing |
| **Flick HIT sideways** | I | **Slice**: backspin that stays low, skids and dies off the glass (the ball glows blue) |
| **LOB** | K | Lob (fires on touch-down) |
| **SMASH** (orange ring fills as you play) | L | Charges over about 10–12 hits (perfect timing counts double). When it glows, a high ball becomes a **power smash** that kicks up and out of the court. A high ball played with HIT is a bandeja |
| II | — | Pause menu |

With the stick idle, *move-assist* steers you to your ball (the lime ring); set `MOVE_ASSIST` in `main.gd`. A well-timed ball taken off your own back glass is a **bajada**, with extra pace. Hits trigger haptics on iPhone.

**Players** are a light code-driven rig in `player.gd`: shoulder → elbow → hand holding the paddle (head up, face to the net), legs and free arm that swing when running, and swing tweens for the forehand, slice, overhead and underarm serve. No animation files are needed.

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

## Characters (Higgsfield → Meshy → Godot)

All four players use generated characters (`assets/characters/you.glb`, `ana.glb`, `marco.glb`, `leo.glb`), about 0.8 MB each. `main.gd` loads whichever exist; a missing one falls back to the procedural body. The pipeline for more:

1. **Concept image** (Higgsfield `gpt_image_2_6`, 3:4): full body, **A-pose, hands empty**, plain white background, team kit, no logos.
2. **3D model** (`meshy_v7_image_to_3d`): `should_texture`, `enable_rigging`, `pose_mode: a-pose`, `target_polycount: 8000`. About 44 credits; the image is a few more.
3. **Slim it:** `cd tools/gltf && npm install && node optimise.mjs raw.glb ../../assets/characters/NAME.glb`. This removes the baked animation and tangents and makes the texture a 1024 px JPEG: 3.9 MB → 0.8 MB.
4. In the `.glb.import`, set `meshes/ensure_tangents=false` and `animation/import=false`.
5. Add the name to `models` in `_spawn_players()` in `main.gd`.

No animation files are used. The procedural rig in `player.gd` keeps animating, invisibly, and each frame the model's bones are aimed at it (upper arm → elbow, forearm → hand, thigh → knee, shin → ankle). The paddle sits in the model's right hand. Swings, running and the ready pose all carry over. Bones expected: Meshy/Mixamo names (`RightArm`, `RightForeArm`, `RightHand`, `LeftUpLeg`, …), model facing +Z. `tools/inspect_char.gd` prints a model's bones and size, and `tools/pose_test.gd -- out res://assets/characters/NAME.glb` renders it in the ready, forehand and smash poses.

## Code map

| File | Role |
|---|---|
| `scripts/main.gd` | Match flow, referee, AI decisions, human input, shot execution |
| `scripts/ball_sim.gd` | Deterministic ball physics (gravity, floor, glass/mesh, net), shared by the live ball and AI prediction |
| `scripts/ball.gd` | Live ball node, substepping, trajectory prediction |
| `scripts/shot.gd` | Projectile solver: lands a shot on a target and clears the net |
| `scripts/court.gd` | Dimensions, wall surface lookup, procedural court geometry |
| `scripts/player.gd` | Player movement, procedural rig driving the character model, paddle swing |
| `scripts/roster.gd`, `profile.gd` | Characters, venues, career rounds; saved settings, team, progress, stats |
| `scripts/sfx.gd` | Sound effects |
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
--career=club|regional|national|world  --daily                             # career match / daily challenge
--mash-kind=chiquita|vibora|contrapared|dejada|globo|por_cuatro                                # the test bot plays that shot
--games=N                                                                 # shorter quick matches (for tests)
--court=ID                                                                # quick play on a venue (e.g. rooftop)
--online-create=quick --room=4                                            # doubles room (join with --online-join=CODE)
--screenshot=path.png@replay                                              # capture during the first replay
--screenshot=path.png@celebrate | @orbit                                  # capture a celebration / the after-match 360
--aim-test                                                                # show the aim crosshair as if HIT were held
--screen=career|team|locker|settings|stats|training                       # open a menu screen
--relay=ws://127.0.0.1:8080 --online-quick                                # online test (run two copies)
--drill=ground|aim|slice|glass|volley|smash|walls|dejada|globo|por_cuatro|mix                         # start a training drill
godot --path . -s tools/pose_test.gd -- out                               # render the player rig in poses
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
