extends Node3D
## Match controller: serving, refereeing, AI decisions, input, and online play.
##
## Online versus is host-authoritative: the host phone runs the whole
## simulation. The other phone sends its stick/HIT input and receives
## snapshots (ball, players) plus score and messages, viewing from the far
## end. Traffic goes through the relay server (server/relay.js).
## You + Ana (AI) play your opponent + Leo (AI).
##
## Command-line options (after `--`):
##   --autoplay        the AI plays your player too (soak test), skips the menu
##   --mash            a bot taps HIT for you (tests the human code path)
##   --mash-kind=K     the bot plays shot K: por_cuatro | power_slice | dejada | globo | vibora | chiquita | contrapared
##   --mode=ID         skip the menu: quick | set | match | practice
##   --drill=ID        start a training drill: ground | aim | slice | glass | volley | smash | mix
##   --daily           start today's daily challenge
##   --career=VENUE    start a career match at a venue (club | regional | national | world)
##   --screen=NAME     open a menu screen: career | team | settings | stats | training
##   --relay=URL       relay server to use (default Online.RELAY_URL)
##   --online-quick    go straight into an online quick match
##   --online-create=L create a private game (quick | set | match), prints the code
##   --online-join=CODE join a private game
##   --trace           print every shot
##   --quit-after=N    quit after N seconds and print statistics
##   --screenshot=path.png@seconds

enum State { SERVE_WAIT, RALLY, POINT_OVER, MATCH_OVER }

const SERVE_ORDER := [0, 2, 1, 3]   # you, rival/friend, Ana, Leo
const BUFFER_TIME := 0.3            # a HIT pressed this early still counts
const LATCH_TIME := 1.1             # LOB / SMASH pressed this early still counts
const MOVE_ASSIST := 0.75           # auto-move towards your ball when the stick is idle (0 = off)
const DEAD_BALL_TIME := 8.0
const CHARGE_HITS := 12.0           # SMASH charges over ~10-12 hits (perfect timing counts double)
const SHOT_SPIN := {"power_slice": -1.8, "slice": -1.0, "lob": -0.2, "drive": 0.15, "smash": 0.1, "power_smash": 0.6,
	"por_cuatro": 1.6, "dejada": -1.0, "globo": 0.35, "combo": 0.15,
	"vibora": -0.9, "chiquita": -0.6, "contrapared": 0.0}

## Training drills. z = where you stand (your half), goal 0 = endless.
const DRILL_INFO := {
	"ground": {"name": "Groundstrokes", "goal": 5, "z": 7.4,
		"tip": "Hold HIT as the ball comes, let go when the ring is full.\nSwipe up for a deeper ball."},
	"aim": {"name": "Aiming", "goal": 5, "z": 7.4,
		"tip": "Swipe up-left or up-right to aim.\nLand it in the lit box."},
	"slice": {"name": "Slice", "goal": 5, "z": 7.4,
		"tip": "Flick HIT sideways to slice.\nIt stays low and dies off the glass."},
	"glass": {"name": "Off the back glass", "goal": 5, "z": 8.0,
		"tip": "Let it pass, wait for it off the glass, then hit.\nTime it well for a BAJADA."},
	"volley": {"name": "Volleys at the net", "goal": 5, "z": 3.0,
		"tip": "At the net: hit it before it bounces.\nShort, early swings."},
	"smash": {"name": "Power smash", "goal": 3, "z": 4.2,
		"tip": "Every hit charges SMASH. When it glows and the ball is high,\ntap SMASH to send it out of the court."},
	"dejada": {"name": "Dejada", "goal": 4, "z": 3.0, "shot": "dejada",
		"tip": "At the net, swipe HIT down.\nA feathered drop that dies just over the net."},
	"globo": {"name": "Globo", "goal": 4, "z": 7.4, "shot": "globo",
		"tip": "Tap LOB with good timing (the ring full).\nLand it in the last two metres."},
	"por_cuatro": {"name": "Por cuatro", "goal": 3, "z": 4.2, "shot": "por_cuatro",
		"tip": "SMASH is charged. Hold the stick left or right and tap SMASH\non the high ball: out over the side wall."},
	"walls": {"name": "Glass targets", "goal": 5, "z": 7.4,
		"tip": "Land it deep so it bounces up into the lit panel.\nSide panels: aim wide into that corner. Glass on the full is out."},
	"mix": {"name": "Free practice", "goal": 0, "z": 7.4,
		"tip": "Everything mixed. How long a streak can you build?"},
	"challenge": {"name": "Daily challenge", "goal": 0, "z": 7.6, "tip": ""},
	"vibora": {"name": "Víbora", "goal": 4, "z": 4.6, "shot": "vibora",
		"tip": "On the high ball, flick HIT sideways.\nA sliced overhead that stays low."},
	"chiquita": {"name": "Chiquita", "goal": 4, "z": 7.4, "shot": "chiquita",
		"tip": "Swipe HIT down for a soft ball\nthat dips at the net players' feet."},
	"contrapared": {"name": "Contrapared", "goal": 3, "z": 7.4, "shot": "contrapared", "assist": false,
		"tip": "Let the deep ball pass you, then tap HIT:\nyou play it into your own glass and over the net."},
}
const MIX_ORDER := ["ground", "glass", "slice", "volley", "smash", "aim", "walls"]
const TRAINING_SAVE := "user://training.cfg"
## Online: which player each guest phone controls (peer id -> players[] index).
## 1v1: the guest is a rival. Doubles: 2nd and 4th phones are rivals, the 3rd
## is the host's partner.
const SLOT_FOR_PEER := {2: 2, 3: 1, 4: 3}


## One controlling person's input. Stick and aim are in that person's screen
## space; `mirror` turns them into world space (-1 for the far-end view).
class Pad:
	var move := Vector2.ZERO
	var held := false
	var live_aim := Vector2.ZERO
	var buffer := 0.0
	var kind := "drive"
	var aim := Vector2.ZERO
	var held_fired := false   # HIT fired while held: ignore the release that follows
	var mirror := 1.0
	var touch := true          # held input comes from the touch HIT button (so flicks mean slice)
	var side := 0.0            # SMASH swiped sideways: por cuatro to that side (world x sign)
	var cut := false           # SMASH swiped down: a power slice
	var latch := 0.0           # LOB / SMASH tapped: wait this long for the ball, whatever HIT is doing

	func world_move() -> Vector3:
		var m := move.limit_length(1.0)
		return Vector3(m.x * mirror, 0, m.y * mirror)

	func world_aim(a: Vector2) -> Vector2:
		return Vector2(a.x * mirror, a.y)


var court: Court
var ball: Ball
var players: Array[Player] = []
var score := MatchScore.new()
var hud: Hud
var online: Online
var camera: Camera3D
var ring: MeshInstance3D
var aim_marker: MeshInstance3D
var machine: Node3D
var cam_base := Vector3(0, 7.2, 15.2)

var state := State.SERVE_WAIT
var state_timer := 0.0
var faults := 0
var serve_in_play := false     # true until the receiver has returned the serve
var serve_box_sign := 0.0      # x sign of the service box the serve must land in
var last_hitter_team := 0
var last_shot_kind := "drive"
var receiver_bounces := 0      # floor bounces on the receiving half since the last hit
var wall_since_bounce := false
var rally_hits := 0
var since_hit := 0.0

var prediction: Array = []
var predict_timer := 0.0
var assigned: Array = [null, null]   # per team: the player taking this ball
var intercepts := {}                  # Player -> prediction sample
var last_callout := [null, null]

var pad_local := Pad.new()
var pads := {}               # host: peer id -> Pad of that guest

var mode := "menu"          # menu | quick | set | match | practice
var attract := false        # AI-vs-AI running behind the start menu
var practice := false
var streak := 0
var best_streak := 0
var feeds := 0
var drill_id := "mix"
var drill_done := 0
var training := ConfigFile.new()
var target_sign := 1.0
var target_marker: MeshInstance3D
var last_hit_volley := false

# team, venue, career, daily challenge
var lineup: Array = []              # character ids [you, partner, rival, rival]
var venue: Dictionary = {}
var career_venue := ""              # venue id while playing a career match
var career_round := 0
var challenge := false              # the daily back-glass target challenge
var ch_goals := 0
var ch_lives := 3
var ch_best := 0
var ch_t := 0.0
var ch_rng := RandomNumberGenerator.new()
var ch_params := {}
var ch_size := Vector2(4.2, 2.4)
var goal_frame: Node3D
var sfx: Sfx
var scenery: Scenery
var menu_hero: MenuHero
var ads: Ads
var store: Store
var _coins_start := 0              # coins at the start of this match (for "Double coins")
var _my_paddle: Array = ["round", Color.BLACK, Color.BLACK]
# replays: a ring buffer of every frame of the rally, played back slowly after big points
const REC_SECONDS := 5.0
const REPLAY_SPEED := 0.45
var _rec: Array = []               # [ball pos, spin, [rig state x4]]
var _replay: Array = []
var _replay_t := -1.0              # < 0: not replaying
var _replay_wait := 0.0
var _replay_cam_side := 1.0
var _replay_snd_i := -1
var _celeb_won := 0
var tutorial := -1                 # first launch: step of the guided first rally (-1 off)
const TUT := [
	{"drill": "ground", "goal": 2, "msg": "Welcome to Off The Glass!\nHold HIT as the ball comes. Let go when the ring is full."},
	{"drill": "aim", "goal": 1, "msg": "Now aim it: hold HIT and swipe up-left or up-right\nto land the ball in the lit box."},
	{"drill": "smash", "goal": 1, "msg": "SMASH glows when it's charged.\nOn a high ball, tap SMASH to send it out of the court!"},
]
var _shake := 0.0                  # camera shake, decays
var _impact_fx: MeshInstance3D     # a flash ring where a smash lands
var _impact_t := -1.0
var _just_started := true          # a new match: flash your ring on the first serve                # the team celebrating (for after a replay)            # last replay frame whose sounds have played
var _since_replay := 99            # points since the last replay (long rallies wait their turn)
var _rec_total := 0                # frames ever recorded this point
var _last_hit_at := 0              # _rec_total when the ball was last struck
var combo := 0.0                   # partner combo meter, 0..1 (offline matches)
var combo_armed := false           # COMBO tapped: your next shot is the team's winner
const COMBO_HITS := 34.0
var _celeb_five := false           # the combo's point: the pair high-five
var _last_together := false        # the combo shot is in play this point
var _choice_default := Callable()  # what HIT does while the end-of-match buttons are up
var _celeb_team := -1              # team to celebrate once any replay has played
var _celeb_match := false
var _celeb_reason := ""            # why the celebrated point ended ("Into the net", "Double bounce"…)
var _celeb_res := ""               # what it won: point | game | set | match
var _celeb_hitter: Player = null   # who struck the ball last on that point
var _celeb_shot := ""              # and with what
var _celeb_kinds := {}             # Player -> [kind, face]: each player's reaction this time
var last_hitter_p: Player = null   # the player who struck the ball last
var _ooh_at := -10.0               # the crowd's last "ooh" (elapsed)
## Points lost by the side that hit the ball last: an error, not a winner.
const ERRORS := ["Into the net", "Out", "Hit the glass on the full", "Into the fence", "Double fault"]
var _celeb_cam := -1               # team the camera is showing celebrating (-1: normal camera)
var _orbit_t := -1.0               # >= 0: circling the winners after a match
var _orbit_a0 := 0.0
var _orbit_centre := Vector3.ZERO
var wall_target: Node3D            # "Glass targets" drill: the lit panel
var _wt_side := 0                  # 0 back glass, -1 / 1 side glass at the far end
var _wt_centre := Vector2.ZERO     # back: (x, y); side: (z, y)
const WT_SIZE := Vector2(2.2, 1.4)
var _last_move := Vector3.ZERO
var _squeak_cd := 0.0
var _over_at := 0.0               # when the match/challenge ended (taps ignored briefly)

# versus
var net_role := ""          # "" offline | "host" | "client"
var remotes := {}            # host: peer id -> the Player that guest controls
var my_index := 0            # guests: which player this phone controls
var room_size := 2           # 2 = 1v1 with AI partners, 4 = doubles room
var lobby := false           # host of a doubles room, waiting for phones
var _snap: Array = []
var _snap_age := 0.0
var _client_prev_vel := Vector3.ZERO
var _seen_swings := [0, 0, 0, 0]
var opp_label := "OPPONENT"   # "FRIEND" in a private game
var ranked := false            # random quick matches are rated; private games aren't
var opp_rating := 1000
var _rematch := {}             # peer id (1 = host) -> tapped HIT for a rematch
var rtt_ms := -1
var _ping_timer := 0.0
var debug_overlay: DebugOverlay

# test switches
var autoplay := false
var trace := false
var mash := false
var test_games := 0
var test_room := 2         # --room=4: --online-create makes a doubles room
var test_court := ""      # --court=ID: quick play on that venue
var shot_replay := false  # --screenshot=path@replay: capture during the first replay       # --games=N: shorter matches for tests
var test_celebrate := ""  # --test-celebrate=point|match: fake a won point / match 4 s in
var aim_test := false     # --aim-test: show the aim crosshair as if HIT were held
var shot_event := ""     # --screenshot=path@celebrate | @orbit
var _celeb_at := -1.0
var mash_kind := ""      # --mash-kind=chiquita|contrapared|vibora: the bot plays that shot
var start_mode := ""
var start_relay := ""
var start_online := ""   # "quick" | "create:<length>" | "join:<code>"
var shot_path := ""
var shot_at := -1.0
var quit_after := -1.0
var elapsed := 0.0
var stats := {"points": 0, "hits": 0, "faults": 0, "reasons": {}, "rallies": [], "snapshots": 0}


func _ready() -> void:
	# smooth motion on 90/120 Hz screens (also set in Project Settings → Physics)
	get_tree().physics_interpolation = true
	_parse_args()
	_setup_input()
	GameServices.sign_in()
	court = Court.new()
	add_child(court)
	scenery = Scenery.new()
	add_child(scenery)
	_setup_environment()
	ball = Ball.new()
	add_child(ball)
	ball.floor_bounce.connect(_on_floor)
	ball.wall_hit.connect(_on_wall)
	ball.net_hit.connect(func(_p: Vector3) -> void: _refresh_prediction())
	ball.out_of_court.connect(_on_out)
	sfx = Sfx.new()
	add_child(sfx)
	ball.floor_bounce.connect(func(pos: Vector3) -> void:
		sfx.at("floor", pos, clampf(ball.sim.vel.length() * 0.8 - 14.0, -16.0, -4.0)))
	ball.wall_hit.connect(func(pos: Vector3, surface: String) -> void:
		var loud := clampf(ball.sim.vel.length() * 0.9 - 12.0, -12.0, 2.0)
		if surface == "glass" and ball.sim.vel.length() > 15.0 and state == State.RALLY:
			_shake = maxf(_shake, 0.1)
		sfx.at("glass" if surface == "glass" else "mesh", pos, loud))
	ball.net_hit.connect(func(pos: Vector3) -> void: sfx.at("net", pos, -4.0))
	lineup = Roster.lineup(Profile.character(), Profile.partner())
	_spawn_players()
	_make_ring()
	_make_aim_marker()
	_make_machine()
	hud = Hud.new()
	add_child(hud)
	ads = Ads.new()
	add_child(ads)
	store = Store.new()
	add_child(store)
	hud.store = store
	store.changed.connect(func(text: String) -> void:
		if Profile.owns("remove_ads"):
			ads.ads_removed()
		hud.store_status(text))
	menu_hero = MenuHero.new()
	add_child(menu_hero)
	hud.set_hero(menu_hero)
	_refresh_hero()
	hud.shot_requested.connect(_on_shot_requested)
	hud.hit_pressed.connect(_on_hit_pressed)
	hud.mode_chosen.connect(_on_mode_chosen)
	hud.quit_to_menu.connect(_leave_to_menu)
	hud.online_quick.connect(_online_quick)
	hud.online_create.connect(_online_create)
	hud.online_join.connect(_online_join)
	hud.online_start_now.connect(_begin_online_match)
	hud.online_closed.connect(func() -> void: online.close())
	hud.training_chosen.connect(_start_training)
	hud.career_chosen.connect(_start_career)
	hud.daily_chosen.connect(_start_daily)
	hud.team_changed.connect(func() -> void:
		lineup = Roster.lineup(Profile.character(), Profile.partner())
		_apply_lineup()
		if state != State.RALLY:
			_start_point()
		hud.set_team_names(_team_name(0, 0), _team_name(1, 0)))
	hud.locker_changed.connect(func() -> void:
		_apply_styles()
		_apply_kit()
		_check_awards())
	hud.settings_changed.connect(func() -> void:
		_apply_fps()
		sfx.apply_settings()
		ball.set_look(Profile.ball_large(), Profile.ball_contrast(), Profile.ball_trail())
		if mode == "menu":
			_apply_venue(Profile.get_v("settings", "court", "club")))
	_make_goal_frame()
	_make_impact_fx()
	_apply_fps()
	wall_target = _goal_node(Color("ff7a1a"))
	wall_target.scale = Vector3(WT_SIZE.x, WT_SIZE.y, 1.0)
	ball.set_look(Profile.ball_large(), Profile.ball_contrast(), Profile.ball_trail())
	training.load(TRAINING_SAVE)
	hud.set_training_info(_training_summary())
	_make_target_marker()
	hud.play_ai_instead.connect(func() -> void:
		online.close()
		_on_mode_chosen("quick", true))
	debug_overlay = DebugOverlay.new()
	debug_overlay.main = self
	debug_overlay.hud = hud
	add_child(debug_overlay)
	if "--debug-overlay" in OS.get_cmdline_user_args():
		debug_overlay.set_on(true)
	online = Online.new()
	online.name = "Online"
	add_child(online)
	if start_relay != "":
		online.url = start_relay
	online.status.connect(func(t: String) -> void: hud.set_online_status(t))
	online.failed.connect(func(t: String) -> void:
		hud.set_online_status(t)
		if quit_after > 0.0:
			print("[net] failed: ", t))
	online.room_code.connect(_on_room_code)
	online.matched.connect(_on_online_matched)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(func() -> void: _end_versus("Your opponent left the match"))

	if start_online != "":
		_go_menu()
		hud.show_online(true)
		if start_online == "quick":
			_online_quick()
		elif start_online.begins_with("create:"):
			_online_create(start_online.get_slice(":", 1), true, test_room)
		elif start_online.begins_with("join:"):
			_online_join(start_online.get_slice(":", 1))
	elif "--tutorial" in OS.get_cmdline_user_args():
		_go_menu()
		_start_tutorial()
	elif start_mode.begins_with("drill:"):
		_start_training(start_mode.get_slice(":", 1))
	elif start_mode == "daily":
		_start_daily()
	elif start_mode.begins_with("career:"):
		_start_career(start_mode.get_slice(":", 1))
	elif start_mode != "":
		_on_mode_chosen(start_mode, true)
	elif autoplay or mash:
		_on_mode_chosen("match", true)
	else:
		_go_menu()
		# the studio ident: on a real launch (not a test run), or with --intro
		if (quit_after < 0.0 and shot_path == "" and not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--screen"))) or "--intro" in OS.get_cmdline_user_args():
			var intro := Intro.new()
			add_child(intro)
			_warm_up()
			if not bool(Profile.get_v("tutorial", "done", false)) and quit_after < 0.0:
				intro.finished.connect(_start_tutorial)

		if "--show-training" in OS.get_cmdline_user_args():
			hud.show_training(true, _training_summary())
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--screen="):
				match a.get_slice("=", 1):
					"career": hud.show_career(true)
					"team": hud.show_team(true)
					"settings": hud.show_settings(true)
					"stats": hud.show_stats(true)
					"locker": hud.show_locker(true)
					"wardrobe": hud.show_wardrobe(true)
					"awards": hud.show_awards(true)
					"training": hud.show_training(true, _training_summary())


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--test-celebrate="):
			test_celebrate = a.get_slice("=", 1)
		elif a == "--aim-test":
			aim_test = true
		elif a == "--trace":
			trace = true
		elif a == "--mash":
			mash = true
		elif a.begins_with("--court="):
			test_court = a.get_slice("=", 1)
		elif a.begins_with("--room="):
			test_room = a.get_slice("=", 1).to_int()
		elif a.begins_with("--games="):
			test_games = a.get_slice("=", 1).to_int()
		elif a.begins_with("--mash-kind="):
			mash = true
			mash_kind = a.get_slice("=", 1)
		elif a.begins_with("--relay="):
			start_relay = a.get_slice("=", 1)
		elif a == "--online-quick":
			start_online = "quick"
		elif a.begins_with("--online-create="):
			start_online = "create:" + a.get_slice("=", 1)
		elif a.begins_with("--online-join="):
			start_online = "join:" + a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			start_mode = a.get_slice("=", 1)
		elif a.begins_with("--drill="):
			start_mode = "drill:" + a.get_slice("=", 1)
		elif a == "--daily":
			start_mode = "daily"
		elif a.begins_with("--career="):
			start_mode = "career:" + a.get_slice("=", 1)
		elif a.begins_with("--screenshot="):
			var v := a.get_slice("=", 1)
			shot_path = v.get_slice("@", 0)
			shot_replay = v.get_slice("@", 1) == "replay"
			shot_event = v.get_slice("@", 1) if v.get_slice("@", 1) in ["celebrate", "orbit"] else ""
			shot_at = 99999.0 if shot_replay or shot_event != "" else v.get_slice("@", 1).to_float()
		elif a.begins_with("--quit-after="):
			quit_after = a.get_slice("=", 1).to_float()


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"hit": [KEY_SPACE, KEY_J], "lob": [KEY_K], "smash": [KEY_L], "slice": [KEY_I], "chiquita": [KEY_U],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


var _env: Environment
var _sun: DirectionalLight3D


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	_env = e
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0c1a2e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("9fb6d6")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 50.0
	# the camera follows smoothly in _process itself, so it opts out of physics interpolation
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = cam_base
	add_child(camera)
	camera.look_at(Vector3(0, 0.0, 1.0))
	camera.current = true


func _spawn_players() -> void:
	var white := Color("eef1f6")
	var orange := Color("f28c28")
	var slots := [[0, -2.5, orange, true], [0, 2.5, orange, false], [1, -2.5, white, false], [1, 2.5, white, false]]
	for i in 4:
		var c := Roster.character(lineup[i])
		var sl: Array = slots[i]
		var p := Player.new().setup(sl[0], c.name, sl[1], sl[2], c.skin, c.hair, sl[3])
		add_child(p)
		players.append(p)
	_apply_lineup()


## Characters into the four slots: names, models, styles, base pace.
func _apply_lineup() -> void:
	for i in 4:
		var c := Roster.character(lineup[i])
		var p := players[i]
		p.set_display_name(c.name)
		p.style = c.style
		# reviews of the Red Bull game called its movement "clunky and sluggish":
		# a person's player starts, stops and turns almost instantly
		p.accel = 48.0 if i == 0 else 20.0
		# generated characters (Higgsfield -> Meshy); a missing one keeps the procedural body
		var path := "res://assets/characters/%s.glb" % ("you" if c.id == "dani" else c.id)
		if ResourceLoader.exists(path):
			p.use_model(load(path))
	# your side of the court: left = revés side, right = drive side; your partner takes the other
	var left := Profile.side() != "right" or net_role != ""
	players[0].slot_x = -2.5 if left else 2.5
	players[1].slot_x = -players[0].slot_x
	_apply_styles()
	_apply_kit()


## Small style edges (offline only, so online stays even): Speed is quicker
## about the court; the others act in _ai_hit, _do_hit and _timing_quality.
func _apply_styles() -> void:
	for p in players:
		var base := 5.0 if p == players[0] or p in remotes.values() else 4.7
		if net_role == "" and p.style == "Speed":
			base *= 1.08
		elif net_role == "" and p.style == "All-rounder":
			base *= 1.03
		p.speed = base


## Your paddle and skill levels (offline only, so online stays even), and the
## AI players' paddles, picked to suit their style (looks only).
func _apply_kit() -> void:
	for p in players:
		var pid := "club"
		if p == players[0]:
			pid = Profile.paddle_id() if Profile.paddle_owned(Profile.paddle_id()) else "club"
		else:
			pid = {"Power": "diamond", "Touch": "control", "Speed": "teardrop"}.get(p.style, "club")
		var pd := Roster.paddle(pid)
		var face: Color = pd.face
		var trim: Color = pd.trim if p.team == 0 or p == players[0] else Color("7b5cd6")
		if p == players[0]:
			for sk in Roster.SKINS:
				if sk[0] != "" and sk[0] == Profile.get_v("look", "skin", "") and Profile.owns("skin_" + sk[0]):
					face = sk[2]
					trim = sk[3]
		p.set_paddle(pd.shape, face, trim)
		if p == players[0]:
			_my_paddle = [pd.shape, face, trim]
		p.reach = 1.15
	var hat: String = Profile.get_v("look", "hat", "")
	if hat != "" and not Profile.owns("hat_" + hat):
		hat = ""
	var band := Color(0, 0, 0, 0)
	if Profile.owns("wristband"):
		band = Roster.PALETTE[int(Profile.get_v("look", "band_col", 1))]
	var kit_col := Color(0, 0, 0, 0)
	for k in Roster.KITS:
		if k[0] != "" and k[0] == Profile.get_v("look", "kit", "") and Profile.owns("kit_" + k[0]):
			kit_col = k[2]
	players[0].set_cosmetics(hat, Roster.PALETTE[int(Profile.get_v("look", "hat_col", 2))], band,
		kit_col, Roster.character(lineup[0]).get("kit_key", {}))
	_hero_look = {"hat": hat, "hat_col": Roster.PALETTE[int(Profile.get_v("look", "hat_col", 2))], "band": band,
		"kit_col": kit_col, "paddle": _my_paddle}
	_refresh_hero()
	if _kit_on():
		players[0].speed *= 1.0 + 0.016 * Profile.skill("speed")
		players[0].reach = 1.15 + 0.03 * Profile.skill("reach")


var _hero_look := {}
var _hero_shown := ""


## The menu's key art: your pair in your kit (only rebuilt when that changes).
func _refresh_hero() -> void:
	if menu_hero == null or lineup.size() < 2:
		return
	var key := "%s|%s|%s" % [lineup[0], lineup[1], str(_hero_look)]
	if key == _hero_shown:
		return
	_hero_shown = key
	menu_hero.show_team([lineup[0], lineup[1]], _hero_look)


func _kit_on() -> bool:
	return net_role == "" and not _ai_human()


## Your paddle + skills for this shot: {power, touch, charge}; zeros for everyone else.
func _kit(p: Player) -> Dictionary:
	if p != players[0] or not _kit_on():
		return {"power": 0.0, "touch": 0.0, "charge": 0.0}
	var pd := Roster.paddle(Profile.paddle_id() if Profile.paddle_owned(Profile.paddle_id()) else "club")
	return {"power": pd.power + 0.35 * Profile.skill("power"),
		"touch": pd.touch + 0.012 * Profile.skill("touch"), "charge": pd.charge}


## Can this player play a signature shot? Online everyone can (fair); offline
## you need to have unlocked it in the career.
func _shot_ok(p: Player, id: String) -> bool:
	if net_role != "" or not _controlled(p):
		return true
	return Profile.shot_unlocked(id)


## A deep ball that has bounced and is running past you towards your own back
## glass: the moment for a contrapared.
func _contrapared_ball(p: Player) -> bool:
	var s := Court.team_sign(p.team)
	var bp := ball.sim.pos
	return receiver_bounces >= 1 and absf(bp.z) > 7.2 and (bp.z - p.position.z) * s > 0.12 \
		and ball.sim.vel.z * s > 0.5 and bp.y > 0.25


## A shot into your own back glass that comes back over the net: search
## launch velocities with the ball physics and keep the one landing nearest
## the target on the other side.
func _solve_contrapared(from: Vector3, aim: Vector2, s: float) -> Vector3:
	var target := Vector3(clampf(aim.x * 3.0, -3.5, 3.5), 0.0, -s * 6.0)
	var best := Vector3(0, 7.0, s * 8.0)
	var best_d := INF
	for vz in [5.0, 6.5, 8.0, 9.5, 11.0, 12.5, 14.0]:
		for vy in [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]:
			var tz: float = absf(Court.HALF_L - absf(from.z)) / vz + (Court.HALF_L + 6.0) / (vz * BallSim.GLASS_E)
			var v := Vector3((target.x - from.x) / maxf(tz, 0.5), vy, s * vz)
			var sim := BallSim.new()
			sim.pos = from
			sim.vel = v
			var landed := Vector3.INF
			for i in 480:
				var done := false
				for e in sim.step(1.0 / 120.0):
					if e[0] == "floor" or e[0] == "out" or e[0] == "net":
						landed = e[1] if e[0] == "floor" and Court.side_of(e[1].z) != (0 if s > 0.0 else 1) else Vector3.INF
						done = true
						break
					if e[0] == "wall" and e[2] == "mesh":
						done = true
						break
				if done:
					break
			if landed != Vector3.INF:
				var d := Vector2(landed.x - target.x, landed.z - target.z).length()
				if d < best_d:
					best_d = d
					best = v
	return best


## Por cuatro: a smash whose topspin kick takes it out over the side wall.
## Searched with the real ball physics (as the contrapared is): a landing spot
## on their half from which the bounce carries out sideways, preferring the
## side the stick points to. null if nothing works from here.
func _solve_por_cuatro(from: Vector3, aim: Vector2, s: float) -> Variant:
	var want := signf(aim.x) if absf(aim.x) > 0.1 else (1.0 if from.x <= 0.0 else -1.0)
	var fallback: Variant = null
	for lx in [1.5, 2.5, 0.5, 3.5, -0.5, -1.5]:
		for lz in [1.8, 1.2, 2.4, 3.0, 3.6]:
			for spd in [26.0, 22.0, 30.0]:
				var v := Shot.solve(from, Vector3(want * lx, Ball.RADIUS, -s * lz), spd, 0.05)
				var sim := BallSim.new()
				sim.pos = from
				sim.vel = v
				sim.spin = SHOT_SPIN.por_cuatro
				var bounces := 0
				var exit_x := 0.0
				for i in 480:
					var stop := false
					for e in sim.step(1.0 / 120.0):
						if e[0] == "floor":
							bounces += 1
							if bounces > 1 or Court.side_of(e[1].z) == (0 if s > 0.0 else 1):
								stop = true
						elif e[0] == "net" or (e[0] == "wall" and absf(e[1].z) > Court.HALF_L - 0.2):
							stop = true
						elif e[0] == "out":
							if bounces == 1 and absf(e[1].x) > Court.HALF_W:
								exit_x = e[1].x
							stop = true
					if stop:
						break
				if exit_x != 0.0:
					if signf(exit_x) == want:
						return v
					if fallback == null:
						fallback = v
	return fallback


func _rivals_at_net(team: int) -> bool:
	for o in _team(1 - team):
		if o.visible and absf(o.position.z) < 5.2:
			return true
	return false


func _style(p: Player) -> String:
	return p.style if net_role == "" else ""


## Court colours, sky and lights for a venue.
func _apply_venue(id: String) -> void:
	venue = Roster.venue(id)
	var cc: String = Profile.court_colour()
	court.apply_venue(venue, Roster.COURT_COLOURS[cc] if Roster.COURT_COLOURS.has(cc) else null)
	scenery.build(venue.get("scene", "hall"))
	_env.background_color = venue.bg
	_env.ambient_light_color = venue.ambient
	_env.ambient_light_energy = venue.ambient_e
	_sun.light_energy = venue.sun
	sfx.crowd_level = venue.crowd


func _make_aim_marker() -> void:
	# a bold crosshair on the floor: white with a dark outline so it reads on
	# every court colour, drawn over the lines
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := n * 0.5
	for y in n:
		for x in n:
			var dx := x + 0.5 - c
			var dy := y + 0.5 - c
			var r := sqrt(dx * dx + dy * dy) / c          # 0 centre .. 1 edge
			var cross := (absf(dx) < 4.5 or absf(dy) < 4.5) and r > 0.28 and r < 0.97
			var ring := absf(r - 0.62) < 0.09
			var dot := r < 0.1
			var core := cross or ring or dot
			var cross_o := (absf(dx) < 8.0 or absf(dy) < 8.0) and r > 0.24 and r < 1.0
			var ring_o := absf(r - 0.62) < 0.14
			var outline := cross_o or ring_o or r < 0.15
			if core:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			elif outline:
				img.set_pixel(x, y, Color(0.05, 0.07, 0.1, 0.8))
	img.generate_mipmaps()
	aim_marker = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.1, 2.1)
	qm.orientation = PlaneMesh.FACE_Y
	aim_marker.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 2
	aim_marker.material_override = m
	aim_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aim_marker.visible = false
	add_child(aim_marker)


## Ball machine for practice: sits on the far baseline.
func _make_machine() -> void:
	machine = Node3D.new()
	machine.position = Vector3(0, 0, -9.3)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.7, 0.5)
	body.mesh = bm
	body.position.y = 0.35
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2c3846")
	body.material_override = m
	machine.add_child(body)
	var hopper := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.18
	cm.height = 0.35
	hopper.mesh = cm
	hopper.position.y = 0.88
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("c6f432")
	hopper.material_override = hm
	machine.add_child(hopper)
	machine.visible = false
	add_child(machine)


func _make_ring() -> void:
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.34
	tm.rings = 32
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c6f432")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


# --- helpers --------------------------------------------------------------------

func _team(t: int) -> Array[Player]:
	var out: Array[Player] = []
	for p in players:
		if p.team == t:
			out.append(p)
	return out


func _partner(p: Player) -> Player:
	for o in players:
		if o.team == p.team and o != p:
			return o
	return p


func _server_index() -> int:
	if score.tiebreak:
		var n := score.points_in_game()
		return SERVE_ORDER[(score.games_played + int((n + 1) / 2.0)) % 4]
	return SERVE_ORDER[score.games_played % 4]


func _ai_human() -> bool:
	return autoplay or attract


func _human() -> Player:
	return players[0]


## The player this device controls.
func _me() -> Player:
	return players[my_index] if net_role == "client" else players[0]


func _my_team() -> int:
	return _me().team


## Is this player driven by a person (here or on the friend's phone)?
func _controlled(p: Player) -> bool:
	return (p == players[0] and not _ai_human()) or p in remotes.values()


func _team_has_person(t: int) -> bool:
	for p in _team(t):
		if _controlled(p):
			return true
	return false


func _pad_for(p: Player) -> Pad:
	var id := _peer_of(p)
	return pads[id] if id > 0 else pad_local


## The guest phone controlling this player (0 = none: this phone or the AI).
func _peer_of(p: Player) -> int:
	for id in remotes:
		if remotes[id] == p:
			return id
	return 0


## What the other phones call player i: P1..P4 in doubles, FRIEND/OPPONENT
## for the host in 1v1, and AI players by their character name.
func _label_of(i: int) -> String:
	if net_role == "client" or not (i == 0 or players[i] in remotes.values()):
		return players[i].display_name
	if room_size == 2:
		return opp_label
	return "P%d" % (1 if i == 0 else _peer_of(players[i]))


## Scoreboard name for a team, as seen by player `viewer` ("YOU · ANA").
func _team_name(team: int, viewer: int) -> String:
	var names: Array = []
	for i in players.size():
		if players[i].team != team:
			continue
		if i == viewer:
			names.push_front("YOU")
		else:
			names.append(players[i].display_name if net_role == "" else _label_of(i))
	return " · ".join(names)


# --- modes ----------------------------------------------------------------------

func _go_menu() -> void:
	if tutorial >= 0:
		tutorial = -1
		Profile.set_v("tutorial", "done", true)
	mode = "menu"
	attract = true
	practice = false
	challenge = false
	career_venue = ""
	goal_frame.visible = false
	wall_target.visible = false
	machine.position = Vector3(0, 0, -9.3)
	Profile.save()
	_apply_venue(Profile.get_v("settings", "court", "club"))
	_apply_ai_levels(0.7, [0.68, 0.7])
	score = MatchScore.create(6, 2, true)
	faults = 0
	for p in players:
		p.visible = true
	machine.visible = false
	target_marker.visible = false
	court.set_viewer_end(0)
	hud.set_training_info(_training_summary())
	hud.show_menu(true)
	hud.set_team_names(_team_name(0, 0), _team_name(1, 0))
	_start_point()


func _leave_to_menu() -> void:
	if net_role != "":
		_end_versus("")
	else:
		_go_menu()


func _on_mode_chosen(id: String, golden: bool) -> void:
	mode = id
	attract = false
	practice = id == "practice" or challenge
	if career_venue == "" and not practice:
		_apply_venue(test_court if test_court != "" else Profile.get_v("settings", "court", "club"))
		_apply_ai_levels(0.74, [0.68, 0.7])
	match id:
		"quick": score = MatchScore.create(test_games if test_games > 0 else 4, 1, golden)
		"set": score = MatchScore.create(6, 1, golden)
		_: score = MatchScore.create(6, 2, golden)
	faults = 0
	streak = 0
	feeds = 0
	drill_done = 0
	_just_started = true
	_coins_start = Profile.coins()
	combo = 0.0
	combo_armed = false
	for p in players:
		p.visible = p.is_human or not practice
		p.smash_charge = 0.0
	target_marker.visible = false
	wall_target.visible = false
	machine.visible = practice
	if not challenge:
		goal_frame.visible = false
		machine.position = Vector3(0, 0, -9.3)
	hud.show_menu(false)
	hud.set_practice(practice)
	hud.set_team_names(_team_name(0, 0), _team_name(1, 0))
	_start_point()


## AI skill for this match: your partner, then the two rivals, shifted by the
## AI level setting (Easy plays looser and reacts later, Hard is sharper).
func _apply_ai_levels(partner: float, rivals: Array) -> void:
	var off: float = [-0.13, 0.0, 0.1][Profile.difficulty()]
	players[1].skill = clampf(partner + off * 0.3, 0.4, 0.95)
	players[2].skill = clampf(rivals[0] + off, 0.35, 0.95)
	players[3].skill = clampf(rivals[1] + off, 0.35, 0.95)
	players[0].skill = 0.75


# --- career ---------------------------------------------------------------------

func _start_career(id: String) -> void:
	career_venue = id
	career_round = Profile.career_round(id)
	var v := Roster.venue(id)
	_apply_venue(id)
	var r: float = v.rivals[career_round]
	_apply_ai_levels(v.partner, [r - 0.02, r])
	# early rounds are first to 4 games; the final is a full set
	var games := 6 if career_round == Roster.ROUNDS.size() - 1 else 4
	_on_mode_chosen("career", Profile.golden_point())
	score = MatchScore.create(games, 1, Profile.golden_point())
	_send_score()
	hud.show_message("%s · %s\nvs %s & %s" % [v.name, Roster.ROUNDS[career_round], players[2].display_name, players[3].display_name], 3.0)


## A career match just ended: move the run on, or end it.
func _career_result(won: bool) -> String:
	var v := Roster.venue(career_venue)
	var rnd := career_round
	if won:
		Profile.add_stat("skill_points_earned", 1 if rnd < Roster.ROUNDS.size() - 1 else 3)
		Profile.add_stat("coins", 25 if rnd < Roster.ROUNDS.size() - 1 else 100)
	if won and rnd == Roster.ROUNDS.size() - 1:
		var first := not Profile.career_won(career_venue)
		var extras := ""
		if first:
			Profile.add_stat("titles")
			for sid in Roster.SHOTS:
				if Roster.SHOTS[sid].unlock == career_venue:
					extras += "\nNew shot: %s (try it in Training)" % Roster.SHOTS[sid].name
			for pd in Roster.PADDLES:
				if pd.unlock == career_venue:
					extras += "\nNew paddle: %s (in the Locker)" % pd.name
		Profile.set_v("career", career_venue + "_won", true)
		Profile.set_v("career", career_venue + "_round", 0)
		var i := Roster.VENUES.find(v)
		var unlock: String = "\n%s unlocked!" % Roster.VENUES[i + 1].name if i + 1 < Roster.VENUES.size() and not Profile.venue_unlocked(i + 1) else ""
		Profile.save()
		return "CHAMPIONS!  +3 skill points\n%s title is yours%s%s" % [v.name, unlock, extras]
	if won:
		Profile.set_v("career", career_venue + "_round", rnd + 1)
		Profile.save()
		return "You win the %s!  +1 skill point\nNext: the %s" % [Roster.ROUNDS[rnd].to_lower(), Roster.ROUNDS[rnd + 1].to_lower()]
	Profile.set_v("career", career_venue + "_round", 0)
	Profile.save()
	return "Knocked out in the %s\nTry again from the quarter-final" % Roster.ROUNDS[rnd].to_lower()


## Buttons after a career match: the next round or tour, or try again.
func _career_choices(won: bool) -> Array:
	var id := career_venue
	var i := Roster.VENUES.find(Roster.venue(id))
	var back := ["Career", _career_continue]
	if won and career_round == Roster.ROUNDS.size() - 1:
		var out: Array = []
		if i + 1 < Roster.VENUES.size() and Profile.venue_unlocked(i + 1):
			var nid: String = Roster.VENUES[i + 1].id
			out.append(["Next: %s ›" % Roster.VENUES[i + 1].name, func() -> void: _start_career(nid)])
		out.append(back)
		out.append(["Menu", _go_menu])
		return out
	if won:
		return [["Next: %s ›" % Roster.ROUNDS[career_round + 1], func() -> void: _start_career(id)], back]
	return [["Try again", func() -> void: _start_career(id)], back]


func _career_continue() -> void:
	_go_menu()
	hud.show_career(true)


# --- daily challenge ----------------------------------------------------------------

## Today's challenge: the ball machine feeds you, and a goal slides across the
## rival back glass. Put the ball into it (on the full or after a bounce) to
## score; each goal shrinks it and speeds it up. Three misses and it's over.
## The goal's movement is seeded by the date, so everyone gets the same one.
func _start_daily() -> void:
	challenge = true
	career_venue = ""
	var today := Profile.today()
	ch_rng.seed = hash("off-the-glass-" + today)
	var patterns := ["sweep", "pingpong", "jumps", "figure"]
	ch_params = {
		"pattern": patterns[ch_rng.randi() % patterns.size()],
		"speed": ch_rng.randf_range(0.55, 0.95),
		"phase": ch_rng.randf_range(0.0, TAU),
		"height": ch_rng.randf_range(0.7, 1.0),   # low on the glass: a ball off the bounce rises into it
	}
	ch_goals = 0
	ch_lives = 3
	ch_t = 0.0
	ch_size = Vector2(4.2, 2.4)
	ch_best = Profile.daily_best(today)
	drill_id = "challenge"
	_apply_venue(Profile.get_v("settings", "court", "club"))
	_on_mode_chosen("practice", true)
	machine.position = Vector3(-3.6, 0, -9.3)   # out of the goal's way
	ball.place(machine.position + Vector3(0, 1.0, 0.4))
	goal_frame.visible = true
	_place_goal(0.0)
	hud.show_message("Daily challenge · %s\nHit the moving goal on the back glass.\nIt shrinks every time you score. Three misses and you're out." % today, 4.0)
	_challenge_hud()


func _challenge_hud() -> void:
	hud.set_rally_text("GOALS %d  ·  LIVES %d  ·  BEST %d" % [ch_goals, ch_lives, maxi(ch_best, ch_goals)])


## Goal frame centre on the far back glass at challenge time t.
func _goal_centre(t: float) -> Vector2:
	var span := Court.HALF_W - ch_size.x * 0.5 - 0.15
	var ph: float = ch_params.phase
	var sp: float = ch_params.speed * (1.0 + ch_goals * 0.07)
	var x := 0.0
	var y: float = ch_params.height
	match ch_params.pattern:
		"pingpong":
			x = span * (absf(fposmod(t * sp * 0.35 + ph, 2.0) - 1.0) * 2.0 - 1.0)
		"jumps":
			# holds still, then hops to a new spot every 2.6 s
			var slot := int(t / 2.6 + ph)
			x = span * sin(slot * 2.39996)
		"figure":
			x = span * sin(t * sp + ph)
			y += 0.35 * sin(t * sp * 2.0 + ph)
		_:
			x = span * sin(t * sp + ph)
	y = clampf(y, ch_size.y * 0.5 + 0.05, Court.GLASS_H - ch_size.y * 0.5 - 0.05)
	return Vector2(x, y)


func _place_goal(t: float) -> void:
	var c := _goal_centre(t)
	goal_frame.position = Vector3(c.x, c.y, -Court.HALF_L + 0.07)
	goal_frame.scale = Vector3(ch_size.x, ch_size.y, 1.0)


func _make_goal_frame() -> void:
	goal_frame = _goal_node(Color("c6f432"))


## A 1 x 1 frame (posts, bar, line and a faint fill), scaled to size; hidden.
func _goal_node(col: Color) -> Node3D:
	var node := Node3D.new()
	var lime := StandardMaterial3D.new()
	lime.albedo_color = col
	lime.emission_enabled = true
	lime.emission = col
	lime.emission_energy_multiplier = 0.6
	var fill := StandardMaterial3D.new()
	fill.albedo_color = Color(col.r, col.g, col.b, 0.18)
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	for part in [[Vector3(-0.5, 0, 0), Vector3(0.05, 1.0, 0.05)], [Vector3(0.5, 0, 0), Vector3(0.05, 1.0, 0.05)],
			[Vector3(0, 0.5, 0), Vector3(1.05, 0.06, 0.05)], [Vector3(0, -0.5, 0), Vector3(1.05, 0.04, 0.05)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.position = part[0]
		mi.material_override = lime
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	back.mesh = qm
	back.material_override = fill
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(back)
	node.visible = false
	add_child(node)
	return node


# --- glass targets drill --------------------------------------------------------

## A new lit panel on the far glass: left, middle or right of the back wall,
## or the back corner of either side wall. Low down, where a ball coming up
## off the bounce actually meets the glass (tools/wall_target_test.gd: higher
## panels were lit by one shot in ten, the side ones almost never).
func _place_wall_target() -> void:
	var pick := randi() % 5
	var y := randf_range(0.75, 0.9)
	if pick < 3:
		_wt_side = 0
		_wt_centre = Vector2((pick - 1) * 3.2, y)
		wall_target.position = Vector3(_wt_centre.x, y, -Court.HALF_L + 0.07)
		wall_target.rotation.y = 0.0
	else:
		_wt_side = -1 if pick == 3 else 1
		_wt_centre = Vector2(-Court.HALF_L + 1.15, y)
		wall_target.position = Vector3(_wt_side * (Court.HALF_W - 0.07), y, _wt_centre.x)
		wall_target.rotation.y = PI * 0.5
	wall_target.visible = true


func _in_wall_target(pos: Vector3) -> bool:
	var m := Ball.RADIUS + 0.06
	if absf(pos.y - _wt_centre.y) > WT_SIZE.y * 0.5 + m:
		return false
	if _wt_side == 0:
		return absf(pos.z) > Court.HALF_L - 0.3 and absf(pos.x - _wt_centre.x) <= WT_SIZE.x * 0.5 + m
	return signf(pos.x) == _wt_side and absf(pos.x) > Court.HALF_W - 0.3 and absf(pos.z - _wt_centre.x) <= WT_SIZE.x * 0.5 + m


func _challenge_result(goal: bool, reason: String) -> void:
	if state != State.RALLY:
		return
	state = State.POINT_OVER
	state_timer = 1.0
	ring.visible = false
	aim_marker.visible = false
	if goal:
		ch_goals += 1
		ch_size = Vector2(maxf(0.9, ch_size.x * 0.86), maxf(0.7, ch_size.y * 0.88))
		sfx.ui("ding", -2.0)
		hud.show_message("GOAL!  ×%d" % ch_goals, 0.9)
		Profile.vibrate(40)
	else:
		ch_lives -= 1
		sfx.ui("buzz", -6.0)
		hud.show_message("%s\n%s" % [reason, "Last life!" if ch_lives == 1 else ("%d lives left" % ch_lives if ch_lives > 1 else "")], 1.2)
	_challenge_hud()
	if quit_after > 0.0:
		print("[daily] %s %s goals=%d lives=%d" % ["GOAL" if goal else "miss", reason, ch_goals, ch_lives])
	if ch_lives <= 0:
		var today := Profile.today()
		var best := maxi(ch_best, ch_goals)
		var new_best := ch_goals > ch_best
		if ch_goals >= 5 and not Profile.get_v("daily_bonus", today, false):
			Profile.set_v("daily_bonus", today, true)
			Profile.add_stat("skill_points_earned")
		Profile.set_v("daily", today, best)
		Profile.max_stat("daily_best", ch_goals)
		Profile.add_stat("daily_played")
		Profile.add_stat("coins", ch_goals * 3)
		Profile.save()
		ch_best = best
		_check_awards()
		state = State.MATCH_OVER
		state_timer = 4.5
		_over_at = elapsed
		sfx.crowd(ch_goals >= 5)
		if new_best and ch_goals > 0:
			sfx.ui("success", -3.0)
		_offer_match_end([["Try again", _start_daily], ["Menu", _go_menu]])
		hud.show_message("%d goal%s%s\nToday's best %d  ·  all-time best %d" % [
			ch_goals, "" if ch_goals == 1 else "s", "  NEW BEST!" if new_best and ch_goals > 0 else "", best, Profile.stat("daily_best")], 4.5)


## The drill feeding the current ball (Free practice cycles through them).
func _drill() -> String:
	if drill_id == "mix":
		return MIX_ORDER[int(feeds / 4.0) % MIX_ORDER.size()]
	return drill_id


func _start_training(id: String) -> void:
	challenge = false
	career_venue = ""
	drill_id = id
	best_streak = int(training.get_value(id, "best", 0))
	_on_mode_chosen("practice", true)
	hud.show_message("%s\n%s" % [DRILL_INFO[id].name, DRILL_INFO[id].tip], 4.0)


func _drill_goal() -> int:
	return TUT[tutorial].goal if tutorial >= 0 else DRILL_INFO[drill_id].goal


# --- first launch: a guided first rally ---------------------------------------------

func _start_tutorial() -> void:
	tutorial = 0
	_tut_step()


func _tut_step() -> void:
	var st: Dictionary = TUT[tutorial]
	_start_training(st.drill)
	hud.show_message(st.msg, 6.0)


func _tut_next() -> void:
	tutorial += 1
	sfx.ui("ding", -4.0)
	if tutorial < TUT.size():
		hud.show_message("✓ Nice!", 1.0)
		get_tree().create_timer(1.1).timeout.connect(func() -> void:
			if tutorial > 0 and practice:
				_tut_step())
		return
	tutorial = -1
	Profile.set_v("tutorial", "done", true)
	Profile.save()
	sfx.ui("success", -3.0)
	state = State.MATCH_OVER
	_over_at = elapsed
	hud.show_message("You're ready!\nYour Career starts at Club Night.", 30.0)
	_offer([["Start Career ›", func() -> void:
			_go_menu()
			hud.show_career(true)],
		["Menu", _go_menu]])


func _training_summary() -> Dictionary:
	var out := {}
	for id in DRILL_INFO:
		var best := int(training.get_value(id, "best", 0))
		var goal: int = DRILL_INFO[id].goal
		if bool(training.get_value(id, "done", false)):
			out[id] = "✓ Done · best streak %d" % best
		elif best > 0:
			out[id] = "Best streak %d%s" % [best, " · goal %d" % goal if goal > 0 else ""]
	return out


func _training_hud() -> void:
	var goal: int = _drill_goal()
	if goal > 0 and drill_done < goal:
		hud.set_rally_text("GOAL %d/%d  ·  STREAK %d" % [drill_done, goal, streak])
	else:
		hud.set_rally_text("STREAK %d  ·  BEST %d" % [streak, best_streak])


func _make_target_marker() -> void:
	target_marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.01, 3.2)
	target_marker.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.96, 0.2, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_marker.material_override = m
	target_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target_marker.visible = false
	add_child(target_marker)


# --- versus: connection ---------------------------------------------------------

func _online_quick() -> void:
	opp_label = "OPPONENT"
	online.quick("quick")


func _online_create(length: String, golden: bool, size := 2) -> void:
	opp_label = "FRIEND"
	online.create(length, golden, size)


func _online_join(code: String) -> void:
	opp_label = "FRIEND"
	online.join(code)


func _on_room_code(code: String) -> void:
	hud.show_room_code(code)
	if quit_after > 0.0:
		print("[net] room code ", code)


## The relay paired us. The host sets up the match; guests wait for net_start.
func _on_online_matched(is_host: bool, length: String, golden: bool, size: int) -> void:
	room_size = size
	hud.set_online_status("Opponent found!" if opp_label == "OPPONENT" else "Your friend is here!")
	if is_host:
		mode = length
		score = MatchScore.create(test_games if test_games > 0 else (4 if length == "quick" else 6), 2 if length == "match" else 1, golden)
		lobby = size > 2
	if quit_after > 0.0:
		print("[net] matched, host=", is_host, " size=", size)


## Host: a phone arrived. 1v1 starts at once; a doubles room waits for four
## phones, or for the host to tap Start now (AI plays any empty places).
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server() or net_role != "" or remotes.has(id):
		return
	var slot: int = SLOT_FOR_PEER.get(id, -1)
	if slot < 0:
		return
	var p := players[slot]
	remotes[id] = p
	p.accel = 48.0
	var pad := Pad.new()
	pad.mirror = -1.0 if p.team == 1 else 1.0
	pads[id] = pad
	if quit_after > 0.0:
		print("[net] phone joined: ", id)
	if room_size <= 2 or remotes.size() >= room_size - 1:
		_begin_online_match()
	else:
		hud.set_online_status("%d of 4 phones here. Waiting for more, or start now: AI plays the empty places." % (remotes.size() + 1))
		hud.show_start_now(true)


func _begin_online_match() -> void:
	if remotes.is_empty() or net_role != "":
		return
	online.start_room()
	lobby = false
	hud.show_start_now(false)
	net_role = "host"
	hud.net_mode = true
	for id in remotes:
		remotes[id].set_display_name(_label_of(SLOT_FOR_PEER[id]))
	var golden := score.golden_point
	ranked = opp_label == "OPPONENT" and room_size == 2
	_rematch = {}
	_apply_styles()
	_on_mode_chosen(mode, golden)
	var names: Array = []
	for i in players.size():
		names.append(_label_of(i))
	for id in remotes:
		net_start.rpc_id(id, mode, golden, Profile.rating(), ranked, SLOT_FOR_PEER[id], names)
	_send_score()
	var who := "%s joined" % opp_label.capitalize() if room_size == 2 else "%d phones" % (remotes.size() + 1)
	hud.show_message("%s. You serve first%s" % [who, "\nRanked match" if ranked else ""], 1.8)
	if quit_after > 0.0:
		print("[net] match started with %d phones" % (remotes.size() + 1))


func _on_peer_disconnected(id: int) -> void:
	if lobby and remotes.has(id):
		remotes.erase(id)
		pads.erase(id)
		hud.set_online_status("%d of 4 phones here." % (remotes.size() + 1))
		hud.show_start_now(not remotes.is_empty())
	elif net_role == "host" and room_size > 2 and remotes.size() > 1 and remotes.has(id):
		# doubles: the AI takes over a phone that drops out, and play goes on
		var p: Player = remotes[id]
		remotes.erase(id)
		pads.erase(id)
		p.accel = 20.0
		_apply_styles()
		_message("P%d left: the AI takes over" % id, "P%d left: the AI takes over" % id, 2.0)
	elif net_role == "host":
		var who := "Your %s" % opp_label.to_lower() if room_size == 2 else "P%d" % id
		_end_versus("%s left the match" % who)


func _end_versus(msg: String) -> void:
	if net_role == "" and not lobby and msg != "" and not online.is_active():
		return
	online.close()
	net_role = ""
	lobby = false
	remotes.clear()
	pads.clear()
	my_index = 0
	room_size = 2
	hud.show_start_now(false)
	_apply_lineup()
	players[0].set_tag("")
	hud.net_mode = false
	_snap = []
	court.set_viewer_end(0)
	_go_menu()
	if msg != "":
		hud.show_message(msg, 3.0)
	if quit_after > 0.0:
		print("[net] versus ended: ", msg)


# --- versus: host → client ------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func net_start(mode_id: String, golden: bool, host_rating := 1000, is_ranked := false, slot := 2, names := []) -> void:
	net_role = "client"
	my_index = slot
	if quit_after > 0.0:
		print("[net] started as player %d" % slot)
	opp_rating = host_rating
	ranked = is_ranked
	_rematch = {}
	net_hello_rating.rpc_id(1, Profile.rating())
	mode = mode_id
	attract = false
	practice = false
	score = MatchScore.create(4 if mode_id == "quick" else 6, 2 if mode_id == "match" else 1, golden)
	for i in players.size():
		var p := players[i]
		p.visible = true
		if i < names.size():
			p.set_display_name(str(names[i]))
		p.is_human = i == slot
		p.set_tag("" if i == slot else p.display_name)
	players[slot].display_name = "YOU"
	machine.visible = false
	ball.live = false
	ring.visible = false
	hud.net_mode = true
	hud.show_menu(false)
	hud.set_practice(false)
	hud.set_team_names(_team_name(0, slot), _team_name(1, slot))
	var far := players[slot].team == 1
	hud.show_message("Connected! You're at the %s end" % ("far" if far else "near"), 2.0)
	for i in 4:
		_seen_swings[i] = players[i].swing_count
	camera.position = Vector3(0, cam_base.y, -cam_base.z if far else cam_base.z)
	court.set_viewer_end(1 if far else 0)


## Guest -> host: my rating, for the ranked result.
@rpc("any_peer", "call_remote", "reliable")
func net_hello_rating(r: int) -> void:
	if remotes.has(multiplayer.get_remote_sender_id()):
		opp_rating = clampi(r, 0, 4000)


## Host -> guest: the match ended. The guest records it, and its new rating if ranked.
@rpc("authority", "call_remote", "reliable")
func net_match_result(won: bool, new_rating: int, delta: int) -> void:
	Profile.add_stat("online_matches")
	if won:
		Profile.add_stat("online_wins")
	Profile.add_stat("matches")
	if won:
		Profile.add_stat("wins")
	if ranked:
		Profile.set_v("online", "rating", new_rating)
	Profile.save()
	_check_awards()


## Guest -> host: tapped HIT after the match for a rematch.
@rpc("any_peer", "call_remote", "reliable")
func net_rematch_vote() -> void:
	if remotes.has(multiplayer.get_remote_sender_id()) and state == State.MATCH_OVER:
		_rematch[multiplayer.get_remote_sender_id()] = true
		_check_rematch()


## Every phone tapped HIT: play again. Otherwise say who we're waiting for.
func _check_rematch() -> void:
	var waiting := 0
	if not _rematch.has(1):
		waiting += 1
	for id in remotes:
		if not _rematch.has(id):
			waiting += 1
	if waiting == 0:
		_rematch = {}
		_on_mode_chosen(mode, score.golden_point)
		var names: Array = []
		for i in players.size():
			names.append(_label_of(i))
		for id in remotes:
			net_start.rpc_id(id, mode, score.golden_point, Profile.rating(), ranked, SLOT_FOR_PEER[id], names)
		_send_score()
		_message("Rematch!", "Rematch!", 1.5)
		return
	var asks := "Rematch? Tap HIT to play again"
	var waits := "Waiting for %d more to tap HIT…" % waiting
	if _rematch.has(1):
		hud.show_message(waits, 30.0)
	else:
		hud.show_message(asks, 30.0)
	for id in remotes:
		net_message.rpc_id(id, waits if _rematch.has(id) else asks, 30.0)


## Elo: [new rating, change] for a player rated `mine` against `theirs`.
static func _elo(mine: int, theirs: int, won: bool) -> Array:
	var expected := 1.0 / (1.0 + pow(10.0, (theirs - mine) / 400.0))
	var delta := roundi(32.0 * ((1.0 if won else 0.0) - expected))
	return [maxi(0, mine + delta), delta]


@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(data: Array) -> void:
	_snap = data
	_snap_age = 0.0
	stats.snapshots += 1


@rpc("authority", "call_remote", "reliable")
func net_score(d: Dictionary) -> void:
	if d.points != score.points or d.games != score.games:
		sfx.crowd(d.games != score.games)
	score.points = d.points
	score.games = d.games
	score.sets = d.sets
	score.tiebreak = d.tiebreak
	score.games_per_set = d.games_per_set
	score.sets_to_win = d.sets_to_win
	score.golden_point = d.golden
	score.winner = d.winner
	hud.update_score(score, d.serving)


@rpc("authority", "call_remote", "reliable")
func net_message(text: String, secs: float) -> void:
	hud.show_message(text, secs)


@rpc("authority", "call_remote", "reliable")
func net_callout(text: String) -> void:
	hud.callout(text)


@rpc("authority", "call_remote", "reliable")
func net_feedback(text: String, ms: int) -> void:
	if text != "":
		hud.flash(text)
	Profile.vibrate(ms)


@rpc("authority", "call_remote", "reliable")
func net_rally(text: String) -> void:
	hud.set_rally_text(text)


## Round-trip timing for the debug overlay: each phone pings the other once a second.
@rpc("any_peer", "call_remote", "unreliable")
func net_ping(t: int) -> void:
	net_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("any_peer", "call_remote", "unreliable")
func net_pong(t: int) -> void:
	rtt_ms = Time.get_ticks_msec() - t


func net_debug_text() -> String:
	if net_role == "":
		if online.is_active():
			var w := online.search_seconds()
			return "online: connected to relay%s" % (", searching %d s" % w if w > 0.0 else "")
		return "online: not connected  ·  relay %s" % online.url
	var lag := "measuring…" if rtt_ms < 0 else "%d ms" % rtt_ms
	var extra := ""
	if net_role == "client":
		extra = "  ·  snapshot age %d ms" % roundi(_snap_age * 1000.0)
	return "online: %s  ·  round trip %s%s" % [net_role, lag, extra]


func _send_score() -> void:
	var serving := players[_server_index()].team
	hud.update_score(score, serving)
	for id in (remotes.keys() if net_role == "host" else []):
		net_score.rpc_id(id, {
			"points": score.points, "games": score.games, "sets": score.sets,
			"tiebreak": score.tiebreak, "games_per_set": score.games_per_set,
			"sets_to_win": score.sets_to_win, "golden": score.golden_point,
			"winner": score.winner, "serving": serving})


## Show a message here and, in versus, its counterpart on the other phones
## (text_friend: the far end's version in 1v1; doubles guests get their own).
func _message(text_here: String, text_friend: String, secs: float) -> void:
	if text_here != "":
		hud.show_message(text_here, secs)
	if net_role == "host" and text_friend != "":
		for id in remotes:
			net_message.rpc_id(id, text_friend, secs)


## A message worded for each viewer: f(player index) -> text.
func _announce(f: Callable, secs: float) -> void:
	hud.show_message(f.call(0), secs)
	if net_role == "host":
		for id in remotes:
			net_message.rpc_id(id, f.call(SLOT_FOR_PEER[id]), secs)


func _set_rally(n: int) -> void:
	hud.set_rally(n)
	if net_role == "host":
		for id in remotes:
			net_rally.rpc_id(id, "RALLY  %d" % n)


func _send_snapshot() -> void:
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var swings := PackedInt32Array()
	var kinds := PackedStringArray()
	for p in players:
		pos.append(p.position)
		vel.append(p.vel)
		swings.append(p.swing_count)
		kinds.append(p.last_swing)
	for id in remotes:
		var rp_player: Player = remotes[id]
		var rp := Vector3.ZERO
		var rv := false
		if assigned[rp_player.team] == rp_player and intercepts.has(rp_player) and state == State.RALLY:
			rv = true
			rp = intercepts[rp_player].pos
		var ready := _readiness(rp_player)
		net_snapshot.rpc_id(id, [
			state, last_hitter_team, ball.sim.pos, ball.sim.vel if ball.live else Vector3.ZERO,
			pos, vel, swings, rv, rp, ready[0], ready[1], kinds, ball.sim.spin])


# --- versus: client → host ------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(move: Vector2, held: bool, aim: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not pads.has(id):
		return
	pads[id].move = move
	pads[id].held = held
	pads[id].live_aim = aim


@rpc("any_peer", "call_remote", "reliable")
func net_shot(kind: String, aim: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if pads.has(id):
		_pad_shot(pads[id], kind, aim)


@rpc("any_peer", "call_remote", "reliable")
func net_hit_pressed() -> void:
	var id := multiplayer.get_remote_sender_id()
	if pads.has(id):
		_pad_pressed(pads[id], remotes[id])


# --- client loop ----------------------------------------------------------------

func _client_tick(delta: float) -> void:
	pad_local.mirror = -1.0 if _my_team() == 1 else 1.0
	pad_local.move = hud.joystick.value + Input.get_vector("move_left", "move_right", "move_up", "move_down")
	pad_local.held = _hit_held()
	pad_local.live_aim = _held_aim()
	net_input.rpc_id(1, pad_local.move, pad_local.held, pad_local.live_aim)
	if _snap.is_empty():
		return
	_snap_age += delta
	var st: int = _snap[0]
	var last_hitter: int = _snap[1]
	var bp: Vector3 = _snap[2]
	var bv: Vector3 = _snap[3]
	var t := minf(_snap_age, 0.1)
	# dead-reckon the ball between snapshots
	var bpos := bp
	if bv != Vector3.ZERO:
		bpos = bp + bv * t + Vector3(0, -0.5 * BallSim.GRAVITY * t * t, 0)
	bpos.y = maxf(bpos.y, BallSim.RADIUS)
	ball.position = bpos
	var pos: PackedVector3Array = _snap[4]
	var vel: PackedVector3Array = _snap[5]
	var swings: PackedInt32Array = _snap[6]
	var kinds: PackedStringArray = _snap[11]
	ball.shown_spin = _snap[12]
	# the ball isn't simulated here: hear bounces from velocity flips between snapshots
	if _client_prev_vel != Vector3.ZERO and bv != Vector3.ZERO and _snap_age == delta:
		if _client_prev_vel.y < -1.0 and bv.y > 0.5 and bp.y < 0.4:
			sfx.at("floor", bp, -8.0)
		elif signf(_client_prev_vel.z) != signf(bv.z) and absf(bp.z) > Court.HALF_L - 1.0:
			sfx.at("glass" if bp.y < Court.GLASS_H else "mesh", bp, -4.0)
	if _snap_age == delta:
		_client_prev_vel = bv
	var k := 1.0 - exp(-18.0 * delta)
	for i in 4:
		var p := players[i]
		p.position = p.position.lerp(pos[i] + vel[i] * t, k)
		p.vel = vel[i]
		if swings[i] != _seen_swings[i]:
			_seen_swings[i] = swings[i]
			p.swing(kinds[i])
			var hard := kinds[i] in ["smash", "power_smash"]
			sfx.at("smash" if hard else "paddle", bp, 0.0 if hard else -3.0)
	ring.visible = _snap[7]
	if ring.visible:
		var rp: Vector3 = _snap[8]
		ring.position = Vector3(rp.x, 0.02, rp.z)
	var rallying := st == State.RALLY
	hud.hit_btn.readiness = _snap[9] if rallying else 0.0
	hud.smash_btn.charge = _snap[10]
	hud.smash_btn.enabled = _snap[10] >= 1.0
	var aiming := rallying and last_hitter != _my_team() and pad_local.held
	aim_marker.visible = aiming
	if aiming:
		var kind := "bandeja" if bp.y > 2.0 else "drive"
		var tg: Array = _shot_target(kind, pad_local.world_aim(pad_local.live_aim), Court.team_sign(_my_team()), 0.75)
		var to: Vector3 = tg[0]
		aim_marker.position = Vector3(to.x, 0.03, to.z)
		aim_marker.rotation.y = elapsed * 1.2
		aim_marker.scale = Vector3.ONE * (1.0 + 0.08 * sin(elapsed * 9.0))


# --- point flow -----------------------------------------------------------------

func _start_point() -> void:
	_end_replay()
	_rec.clear()
	_rec_total = 0
	_last_hit_at = 0
	_celeb_team = -1
	_celeb_cam = -1
	_celeb_five = false
	_orbit_t = -1.0
	_choice_default = Callable()
	hud.show_choices([])
	for p in players:
		p.stop_celebrating()
	_roll_wind()
	state = State.SERVE_WAIT
	serve_in_play = false
	receiver_bounces = 0
	rally_hits = 0
	since_hit = 0.0
	wall_since_bounce = false
	assigned = [null, null]
	intercepts.clear()
	prediction = []
	last_callout = [null, null]
	ring.visible = false
	aim_marker.visible = false
	pad_local.buffer = 0.0
	pad_local.latch = 0.0
	for pd in pads.values():
		pd.buffer = 0.0
		pd.latch = 0.0
	_set_rally(0)

	if practice:
		var h := _human()
		var d := _drill()
		h.position = Vector3(0, 0, DRILL_INFO[d].z)
		h.vel = Vector3.ZERO
		h.face_net()
		if feeds == 0:
			h.flash_ring()
		if d in ["smash", "por_cuatro"]:
			h.smash_charge = 1.0
		ball.live = false
		ball.place(machine.position + Vector3(0, 1.0, 0.4))
		target_marker.visible = d == "aim"
		if d == "walls":
			_place_wall_target()
		else:
			wall_target.visible = false
		if d == "aim":
			target_sign = -target_sign
			target_marker.position = Vector3(target_sign * 2.6, 0.02, -7.4)
		_snap_positions()
		last_hitter_team = 1
		state_timer = 4.4 if feeds == 0 else 1.0   # first ball waits for the instructions to clear
		if drill_id == "mix" and feeds > 0 and feeds % 4 == 0:
			hud.show_message(DRILL_INFO[d].name, 1.2)
		if challenge:
			_challenge_hud()
		else:
			_training_hud()
		return

	var srv := players[_server_index()]
	var st := srv.team
	var s := Court.team_sign(st)
	var right := 1.0 if st == 0 else -1.0
	var from_right := score.points_in_game() % 2 == 0
	var sx := right * (1.0 if from_right else -1.0) * 2.2
	srv.position = Vector3(sx, 0, s * 7.6)
	_partner(srv).position = Vector3(-signf(sx) * 2.4, 0, s * 3.2)
	serve_box_sign = -signf(sx)
	var rs := Court.team_sign(1 - st)
	for p in _team(1 - st):
		var receiving := signf(p.slot_x) == serve_box_sign
		p.position = Vector3(p.slot_x * (0.9 if receiving else 1.0), 0, rs * (8.4 if receiving else 7.0))
	for p in players:
		p.vel = Vector3.ZERO
		p.face_net()

	ball.live = false
	_hold_ball(srv)
	_snap_positions()
	if not _ai_human() and (rally_hits == 0) and (score.points_in_game() == 0 or _just_started):
		_me().flash_ring()
	_just_started = false
	last_hitter_team = st
	state_timer = 0.9
	if srv == players[0] and not _ai_human():
		hud.show_message("Your serve — tap HIT", 2.0)
	elif _peer_of(srv) > 0:
		net_message.rpc_id(_peer_of(srv), "Your serve — tap HIT", 2.0)
	_send_score()


## Newly earned achievements: pay out and announce them.
func _check_awards() -> void:
	if _ai_human():
		return
	GameServices.submit_bests()
	var done := 0
	for id in DRILL_INFO:
		if bool(training.get_value(id, "done", false)):
			done += 1
	var total := 0
	for id in DRILL_INFO:
		if DRILL_INFO[id].goal > 0:
			total += 1
	var fresh := Awards.check({"drills": done, "drills_total": total})
	if not fresh.is_empty():
		hud.flash("ACHIEVEMENT: %s%s  +%d coins" % [fresh[0], "  (+%d more)" % (fresh.size() - 1) if fresh.size() > 1 else "", Awards.COINS * fresh.size()], 2.5)
		sfx.ui("unlock", -3.0)   # achievement


## A fresh gust for each point on outdoor courts (none indoors, in training or online).
func _roll_wind() -> void:
	var strength: float = venue.get("wind", 0.0)
	if practice or net_role != "" or strength <= 0.0 or mode == "menu":
		BallSim.wind = Vector3.ZERO
		hud.set_wind("")
		return
	var a := randf() * TAU
	var mag := strength * randf_range(0.35, 1.0)
	BallSim.wind = Vector3(cos(a), 0, sin(a) * 0.6) * mag
	var w := BallSim.wind
	var dir := ""
	if absf(w.x) >= absf(w.z):
		dir = "blowing left" if w.x < 0.0 else "blowing right"
	else:
		dir = "blowing towards you" if w.z > 0.0 else "blowing away from you"
	var word := "Light wind" if mag < 0.6 else ("Breezy" if mag < 1.0 else "Strong wind")
	hud.set_wind("%s · %s" % [word, dir])


## Record this frame of the rally for a possible replay.
func _record_frame() -> void:
	var rigs: Array = []
	for p in players:
		rigs.append(p.rig_state())
	var snd: Array = sfx.log.duplicate()
	sfx.log.clear()
	_rec.append([ball.position, ball.shown_spin, rigs, snd])
	_rec_total += 1
	if _rec.size() > int(REC_SECONDS * Engine.physics_ticks_per_second):
		_rec.pop_front()


## Big points get a slow-motion replay: a winning special shot, a long rally,
## or a smash out of the court. Offline only.
func _maybe_replay(team: int, reason: String) -> void:
	if not Profile.replays() or net_role != "" or _ai_human() or practice or _rec.size() < 30:
		return
	_since_replay += 1
	var special := last_shot_kind in ["power_smash", "power_slice", "vibora", "contrapared", "chiquita", "por_cuatro", "dejada", "globo", "combo"] and team == last_hitter_team
	var epic := (rally_hits >= 20 or reason == "Out of the court!") and _since_replay >= 4
	if special or epic:
		_since_replay = 0
		# from just before the decisive shot to just after: the shot, not the
		# ball rolling about afterwards
		var fps := Engine.physics_ticks_per_second
		var hit_i := _rec.size() - 1 - (_rec_total - _last_hit_at)
		var a := maxi(0, hit_i - int(1.0 * fps))
		var b := mini(_rec.size(), maxi(hit_i, 0) + int(1.7 * fps))
		_replay = _rec.slice(a, b)
		if _replay.size() < 30:
			_replay = _rec.slice(maxi(0, _rec.size() - int(2.4 * fps)))
		# the players' reaction first, then the replay (like TV)
		_replay_wait = (3.2 if _celeb_match else 2.3) if _celeb_team >= 0 else 0.9
		_replay_cam_side = 1.0 if randf() < 0.5 else -1.0
		state_timer = maxf(state_timer, _replay_wait + _replay.size() / (Engine.physics_ticks_per_second * REPLAY_SPEED) + 0.6)


func _tick_replay(delta: float) -> void:
	if _replay.is_empty():
		return
	if _replay_t < 0.0:
		_replay_wait -= delta
		if _replay_wait > 0.0:
			return
		_replay_t = 0.0
		_replay_snd_i = -1
		sfx.duck_crowd(0.4)
		_celeb_cam = -1
		for p in players:
			p.stop_celebrating()
			p.replaying = true
		hud.set_banner("REPLAY  ·  tap HIT to skip")
		if quit_after > 0.0:
			print("[replay] t=%.1f %d frames, %s" % [elapsed, _replay.size(), last_shot_kind])
	_replay_t += delta * REPLAY_SPEED * Engine.physics_ticks_per_second
	var i := int(_replay_t)
	if i >= _replay.size() - 1:
		_end_replay()
		if state == State.POINT_OVER:
			state_timer = minf(state_timer, 0.5)
		return
	# the rally's own sounds, slowed down with the picture
	while _replay_snd_i < i:
		_replay_snd_i += 1
		for sd in (_replay[_replay_snd_i][3] if _replay[_replay_snd_i].size() > 3 else []):
			sfx.at(sd[0], sd[1], sd[2] - 2.0, 0.72)
	var a: Array = _replay[i]
	var b: Array = _replay[i + 1]
	var k := _replay_t - i
	ball.position = (a[0] as Vector3).lerp(b[0], k)
	ball.shown_spin = a[1]
	for j in players.size():
		var ra: Array = a[2][j]
		var rb: Array = b[2][j]
		var mix := ra.duplicate()
		mix[0] = (ra[0] as Vector3).lerp(rb[0], k)
		mix[8] = (ra[8] as Quaternion).slerp(rb[8], k)
		for f in [1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15]:
			mix[f] = lerpf(ra[f], rb[f], k)
		players[j].apply_rig_state(mix)


func _end_replay() -> void:
	if _replay.is_empty() and _replay_t < 0.0:
		return
	_replay = []
	_replay_t = -1.0
	for p in players:
		p.replaying = false
	hud.set_banner("")
	if state == State.MATCH_OVER and _orbit_t >= 0.0:
		# back to the winners for the rest of the lap
		_orbit_centre = _team_centre(_celeb_won)
		for p in players:
			if p.visible:
				var pick: Array = _celeb_kinds.get(p, ["jump" if p.team == _celeb_won else "sad", null])
				p.celebrate(pick[0], pick[1])


## Each player's reaction to the point: [kind, face point or null] (see
## Player.celebrate()). Winners: a high five or chest bump after a match, a
## partner pointing at whoever hit the winner, a twirl or a roar to the
## crowd on a big one, just a nod for a plain game. Losers: whoever made the
## error is angry or has their head in their hands, and their partner may
## throw their arms out at them (and get a shrug back); beaten by a great
## shot they stand hands on hips, or applaud it after a long rally; a lost
## match leaves them hands on knees.
func _pick_reactions(team: int, mid: Vector3) -> Dictionary:
	var out := {}
	var winners := _team(team).filter(func(p: Player) -> bool: return p.visible)
	var losers := _team(1 - team).filter(func(p: Player) -> bool: return p.visible)
	var pick := func(options: Array) -> String: return options[randi() % options.size()]
	# --- winners
	var together := winners.size() == 2
	var by_shot := _celeb_hitter != null and _celeb_hitter.team == team and not _celeb_reason in ERRORS
	var arena := sfx.crowd_level >= 0.75
	if _celeb_match and together:
		var k: String = pick.call(["five", "chest"])
		for p in winners:
			out[p] = [k, mid]
	elif _celeb_five and together:
		for p in winners:
			out[p] = ["five", mid]
	else:
		for p in winners:
			var big := _celeb_res == "set" or _celeb_shot in ["por_cuatro", "power_smash", "power_slice", "combo"] or _celeb_reason == "Out of the court!"
			var opts := ["jump", "pump", "twirl"] if big else (["nod", "pump"] if _celeb_res == "game" else ["jump", "pump"])
			if arena and big:
				opts.append("crowd")
			out[p] = [pick.call(opts), null]
		# the partner points at whoever hit the winner
		if together and by_shot and _celeb_hitter in winners and randf() < 0.5:
			out[_partner(_celeb_hitter)] = ["point", _celeb_hitter.position]
	for p in winners:
		if out[p][0] == "crowd":
			var sx := signf(p.position.x) if absf(p.position.x) > 0.3 else 1.0
			out[p] = ["crowd", p.position + Vector3(sx * 6.0, 0, 0)]
	# --- losers
	if _celeb_match:
		for i in losers.size():
			out[losers[i]] = ["slump" if i == 0 or randf() < 0.5 else "sad", null]
		return out
	var culprit: Player = _celeb_hitter if _celeb_hitter in losers and _celeb_reason in ERRORS else null
	if culprit:
		out[culprit] = [pick.call(["angry", "head", "angry", "sad"]), null]
		var mate := _partner(culprit)
		if mate in losers:
			if randf() < 0.45:
				out[mate] = ["blame", culprit.position]
				if randf() < 0.5:
					out[culprit] = ["shrug", mate.position]
			else:
				out[mate] = [pick.call(["sad", "hips"]), null]
	else:
		var stunned := _celeb_shot in ["por_cuatro", "power_smash", "power_slice", "contrapared", "vibora", "combo", "dejada", "globo"] or _celeb_reason == "Out of the court!"
		var clapper := -1
		if rally_hits >= 12 and randf() < 0.6:
			clapper = randi() % maxi(1, losers.size())
		for i in losers.size():
			if i == clapper and not winners.is_empty():
				out[losers[i]] = ["applaud", winners[0].position]
			else:
				out[losers[i]] = [pick.call(["hips", "head"] if stunned else ["sad", "hips"]), null]
	return out


## The winners celebrate and the other side reacts (see _pick_reactions()). The camera comes
## round in front of the winners, or circles them after a match.
func _start_celebration() -> void:
	var team := _celeb_team
	_celeb_team = -1
	_celeb_won = team
	# partners come together (on a line across the court), then celebrate
	var mid := _team_centre(team)
	mid.z = Court.team_sign(team) * clampf(absf(mid.z), 3.0, 7.5)
	_celeb_kinds = _pick_reactions(team, mid)
	for i in players.size():
		var p := players[i]
		if not p.visible or not _celeb_kinds.has(p):
			continue
		var pick: Array = _celeb_kinds[p]
		var kind: String = pick[0]
		var meet: Variant = null
		if p.team == team and kind in ["five", "chest", "jump", "pump"] and _partner(p).visible:
			var side := signf(p.position.x - _partner(p).position.x)
			if side == 0.0:
				side = 1.0 if i % 2 == 0 else -1.0
			meet = Vector3(mid.x + side * (0.36 if kind == "chest" else 0.5), 0.0, mid.z)
		p.celebrate(kind, pick[1], meet)
	_celeb_cam = team
	_celeb_at = elapsed
	# a shout from the winners ("yes!", a whoop): from the nearest of them
	var shouter: Player = null
	for p in _team(team):
		if p.visible and (shouter == null or p == _me()):
			shouter = p
	if shouter:
		sfx.voice(shouter.position + Vector3(0, 1.6, 0))
	if quit_after > 0.0:
		var names := []
		for p in _celeb_kinds:
			names.append("%s:%s" % [p.display_name, _celeb_kinds[p][0]])
		print("[celebrate] t=%.1f team %d %s/%s %s" % [elapsed, team, _celeb_res, _celeb_reason, " ".join(names)])
	scenery.cheer(1.0)
	if _celeb_match:
		_orbit_t = 0.0
		_orbit_centre = _team_centre(team)
		_orbit_a0 = atan2(camera.position.x - _orbit_centre.x, camera.position.z - _orbit_centre.z)
		if _ai_human():
			state_timer = maxf(state_timer, 8.0)
	elif state == State.POINT_OVER:
		state_timer = maxf(state_timer, 3.4)


## Middle of a team's visible players, kept off the back glass for the camera.
func _team_centre(team: int) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for p in _team(team):
		if p.visible:
			c += p.position
			n += 1
	c /= maxf(1.0, n)
	c.z = clampf(c.z, -6.2, 6.2)
	return c


## End-of-match buttons; the first is also what HIT does.
func _offer(items: Array) -> void:
	_choice_default = items[0][1]
	hud.show_choices(items)


## After a match: the same buttons, but moving on may pass through an
## interstitial first (ads.gd decides: at most every 2nd match, never in your
## first two, never with Remove Ads). If a rewarded ad is loaded and you
## earned coins, "Double coins" is offered too.
func _offer_match_end(items: Array) -> void:
	var wrapped: Array = []
	for it in items:
		var f: Callable = it[1]
		wrapped.append([it[0], func() -> void: ads.between_matches(f)])
	var earned := Profile.coins() - _coins_start
	if earned > 0 and ads.rewarded_ready():
		wrapped.insert(1, ["▶ Double coins +%d" % earned, func() -> void:
			ads.show_rewarded(func() -> void:
				Profile.add_stat("coins", earned)
				Profile.save()
				sfx.ui("success", -4.0)
				hud.show_message("+%d coins!" % earned, 2.0),
				func() -> void:
					_coins_start = Profile.coins()   # once per match
					_offer(wrapped.filter(func(w: Array) -> bool: return not String(w[0]).begins_with("▶"))))])
	_offer(wrapped)


## Training: the drill's goal was reached. Next drill, keep going, or back.
func _offer_after_drill() -> void:
	var order: Array = []
	for d in Hud.TRAINING:
		var id: String = d[0]
		if id == "mix" or (Roster.SHOTS.has(id) and not Profile.shot_unlocked(id)):
			continue
		order.append(id)
	var next := ""
	var at := order.find(drill_id)
	for k in range(1, order.size() + 1):
		var cand: String = order[(at + k) % order.size()]
		if not bool(training.get_value(cand, "done", false)):
			next = cand
			break
	if next == "":
		next = "mix"
	state = State.MATCH_OVER
	_over_at = elapsed
	var keep := func() -> void:
		hud.show_choices([])
		state = State.POINT_OVER
		state_timer = 0.3
	_offer([["Next: %s ›" % DRILL_INFO[next].name, func() -> void: _start_training(next)],
		["Keep going", keep],
		["Training", func() -> void:
			_go_menu()
			hud.show_training(true, _training_summary())]])


## Players and ball were just moved to new spots: tell physics interpolation
## not to slide them there from where they were (smooth 90/120 Hz screens).
func _snap_positions() -> void:
	for p in players:
		p.reset_physics_interpolation()
	ball.reset_physics_interpolation()
	ring.reset_physics_interpolation()
	aim_marker.reset_physics_interpolation()


func _hold_ball(srv: Player) -> void:
	ball.place(srv.position + Vector3(0.35 * srv.right_x(), 0.95, -Court.team_sign(srv.team) * 0.35))


func _serve(srv: Player, aim: Vector2) -> void:
	var s := Court.team_sign(srv.team)
	var err := 0.25 if _controlled(srv) else (1.0 - srv.skill) * 0.9
	if not _controlled(srv) and randf() < 0.07:
		err = 3.2   # the occasional loose serve
	var tx := serve_box_sign * 2.4 + aim.x * 1.4 + randf_range(-err, err)
	var tz := -s * clampf(5.0 + aim.y * 1.2 + randf_range(-err, err), 2.5, 8.0)
	var to := Vector3(tx, Ball.RADIUS, tz)
	ball.velocity = Shot.solve(ball.sim.pos, to, 12.5, 0.3)
	ball.live = true
	srv.swing("serve")
	_last_hit_at = _rec_total
	sfx.at("paddle", ball.sim.pos, -3.0)
	serve_in_play = true
	last_hitter_team = srv.team
	last_hitter_p = srv
	last_shot_kind = "serve"
	receiver_bounces = 0
	since_hit = 0.0
	state = State.RALLY
	_refresh_prediction()


func _feed() -> void:
	var kind := _drill()
	var from := ball.sim.pos
	var r := Ball.RADIUS
	match kind:
		"glass":
			ball.velocity = Shot.solve(from, Vector3(randf_range(-3.0, 3.0), r, 8.9), 15.5, 0.4)
		"smash", "por_cuatro":
			ball.velocity = Shot.launch_velocity(from, Vector3(randf_range(-2.5, 2.5), r, randf_range(5.0, 6.5)), 1.75)
		"vibora":
			ball.velocity = Shot.launch_velocity(from, Vector3(randf_range(-2.5, 2.5), r, randf_range(5.6, 6.8)), 1.6)
		"contrapared":
			# a deep lob that bounces just in front of you and runs on to the glass
			ball.velocity = Shot.launch_velocity(from, Vector3(randf_range(-2.0, 2.0), r, randf_range(6.6, 7.2)), 1.85)
		"volley", "dejada":
			# flat and quick, passing the net player at chest height
			ball.velocity = Shot.solve(from, Vector3(randf_range(-2.2, 2.2), r, randf_range(5.6, 6.6)), 13.0, 0.5)
		_:
			ball.velocity = Shot.solve(from, Vector3(randf_range(-3.2, 3.2), r, randf_range(5.5, 7.6)), 12.0, 0.4)
	ball.live = true
	sfx.at("floor", from, -6.0, 0.7)
	feeds += 1
	serve_in_play = false
	last_hitter_team = 1
	last_shot_kind = "feed"
	receiver_bounces = 0
	wall_since_bounce = false
	since_hit = 0.0
	state = State.RALLY
	_refresh_prediction()


func _practice_result(good: bool, reason: String) -> void:
	if state != State.RALLY:
		return
	state = State.POINT_OVER
	state_timer = 0.9
	ring.visible = false
	aim_marker.visible = false
	stats.points += 1
	stats.reasons[reason] = stats.reasons.get(reason, 0) + 1
	var goal: int = _drill_goal()
	if good:
		streak += 1
		drill_done += 1
		best_streak = maxi(best_streak, streak)
		if goal > 0 and drill_done == goal and tutorial >= 0:
			_tut_next()
		elif goal > 0 and drill_done == goal:
			var first := not bool(training.get_value(drill_id, "done", false))
			if first:
				Profile.add_stat("skill_points_earned")
				Profile.add_stat("coins", 20)
				Profile.save()
				training.set_value(drill_id, "done", true)
				_check_awards()
			hud.show_message("✓ Drill complete!\n%s%s" % [DRILL_INFO[drill_id].name, "\n+1 skill point" if first else ""], 30.0)
			training.set_value(drill_id, "done", true)
			training.save(TRAINING_SAVE)
			sfx.ui("success", -3.0)
			_offer_after_drill.call_deferred()
		else:
			hud.show_message("%s  ×%d" % [reason, streak], 0.9)
	else:
		streak = 0
		hud.show_message(reason, 1.3)
	if best_streak > int(training.get_value(drill_id, "best", 0)) or (good and goal > 0 and drill_done == goal):
		training.set_value(drill_id, "best", maxi(best_streak, int(training.get_value(drill_id, "best", 0))))
		training.save(TRAINING_SAVE)
	_training_hud()
	if quit_after > 0.0:
		print("[practice] %s %s streak=%d done=%d" % [drill_id, reason, streak, drill_done])


## Training: did the ball you just hit land the way this drill asks?
func _practice_judge(pos: Vector3, landed: bool) -> void:
	var ok := true
	var why := "In!" if landed else "Out of the court!"
	match _drill():
		"aim":
			ok = landed and signf(pos.x) == target_sign and absf(pos.x) > 1.2 and absf(pos.z) > 5.6
			why = "On target!" if ok else "In, but missed the box"
		"slice":
			ok = last_shot_kind == "slice"
			why = "Slice!" if ok else "In, but flick sideways to slice"
		"smash":
			ok = last_shot_kind == "power_smash"
			why = ("Power smash!" if landed else "Por tres! Out of the court!") if ok else "In, now save it for SMASH"
		"volley":
			ok = last_hit_volley
			why = "Volley!" if ok else "In, but volley it before the bounce"
		"vibora":
			ok = landed and last_shot_kind == "vibora"
			why = "Víbora!" if ok else "In, now flick sideways on the high ball"
		"chiquita":
			ok = landed and last_shot_kind == "chiquita" and absf(pos.z) < 4.8
			why = "Chiquita!" if ok else ("In, but swipe down for the soft one" if last_shot_kind != "chiquita" else "Too deep: keep it short")
		"contrapared":
			ok = landed and last_shot_kind == "contrapared"
			why = "Contrapared!" if ok else "In, now let it pass you first"
		"dejada":
			ok = landed and last_shot_kind == "dejada" and absf(pos.z) < 3.2
			why = "Dejada!" if ok else ("In, now swipe down at the net" if last_shot_kind != "dejada" else "Too deep: softer")
		"globo":
			ok = landed and last_shot_kind == "globo" and absf(pos.z) > 8.0
			why = "Globo!" if ok else ("In, now tap LOB with the ring full" if last_shot_kind != "globo" else "Short: they'd smash that")
		"por_cuatro":
			ok = not landed and last_shot_kind == "por_cuatro" and absf(pos.x) > Court.HALF_W
			why = "Por cuatro! Over the side wall" if ok else ("In, now hold the stick sideways and tap SMASH" if landed else "Out the back: that's por tres")
	_practice_result(ok, why)


## The point/game/match message as player `viewer` should read it.
func _point_text(team: int, reason: String, res: String, viewer: int) -> String:
	var who := _team_name(team, viewer)
	var viewer_team := players[viewer].team
	match res:
		"game":
			return "%s\nGame %s" % [reason, who]
		"set":
			return "%s\nSet %s" % [reason, who]
		"match":
			var tail := "\nTap HIT for a rematch" if net_role != "" else ""
			return ("You win the match!" if team == viewer_team else "%s take the match" % who) + tail
	return "%s\nPoint %s" % [reason, who]


func _award(team: int, reason: String) -> void:
	if state != State.RALLY:
		return
	if challenge:
		var why: String = {"Double bounce": "Short of the glass", "Into the net": "Into the net",
			"Out of the court!": "Over the wall", "Out": "Out"}.get(reason, reason)
		if last_hitter_team == 1:
			why = "Missed it"
		_challenge_result(false, why)
		return
	if practice:
		if _drill() == "walls" and last_hitter_team == 0:
			_practice_result(false, "Missed the panel" if reason != "Into the net" else reason)
			return
		if team == 0 and reason == "Out of the court!":
			_practice_judge(ball.sim.pos, false)
		else:
			_practice_result(team == 0, "Missed it" if reason == "Double bounce" else reason)
		return
	state = State.POINT_OVER
	state_timer = 1.8
	faults = 0
	ring.visible = false
	aim_marker.visible = false
	stats.points += 1
	stats.rallies.append(rally_hits)
	stats.reasons[reason] = stats.reasons.get(reason, 0) + 1
	var res := score.point_won(team)
	var big := rally_hits >= 8 or reason == "Out of the court!" or res in ["set", "match"]
	if reason in ERRORS and rally_hits >= 5 and res == "point":
		sfx.react("groan")         # so close: a long rally thrown away
	else:
		sfx.crowd(big)
	if reason == "Out of the court!" and elapsed - _ooh_at > 2.0:
		_ooh_at = elapsed
		sfx.react("ooh")
	scenery.cheer(1.0 if big else 0.4)
	var special := last_shot_kind in ["power_smash", "power_slice", "vibora", "contrapared", "chiquita", "por_cuatro", "dejada", "globo", "combo"] and team == last_hitter_team
	if special or res in ["game", "set", "match"] or rally_hits >= 12 or (reason == "Out of the court!" and team == last_hitter_team):
		_celeb_team = team
		_celeb_match = res == "match"
		_celeb_reason = reason
		_celeb_res = res
		_celeb_hitter = last_hitter_p
		_celeb_shot = last_shot_kind
	_celeb_five = _last_together and team == 0
	_last_together = false
	_maybe_replay(team, reason)   # after the celebration (it waits for it)
	if team == 0 and net_role == "" and not _ai_human() and not combo_armed:
		combo = minf(1.0, combo + 3.0 / COMBO_HITS)
	var mine := _my_team()
	var counted := not _ai_human()
	if counted:
		Profile.add_stat("points_played")
		if team == mine:
			Profile.add_stat("points_won")
			Profile.add_stat("coins", 2)
		Profile.max_stat("longest_rally", rally_hits)
	var here := _point_text(team, reason, res, 0)
	if res == "match":
		state = State.MATCH_OVER
		state_timer = 4.0
		_over_at = elapsed
		if counted:
			Profile.add_stat("matches")
			Profile.add_stat("coins", 5)
			if team == mine:
				Profile.add_stat("wins")
				Profile.add_stat("coins", 15)
			if net_role != "":
				Profile.add_stat("online_matches")
				if team == mine:
					Profile.add_stat("online_wins")
		if career_venue != "":
			if team == 0 and counted:
				sfx.ui("success", -4.0)
			here = _career_result(team == 0)
			state_timer = 6.0
		if net_role == "" and counted and team == 0:
			get_tree().create_timer(3.0).timeout.connect(GameServices.maybe_ask_review)
		if net_role == "" and counted:
			if career_venue != "":
				_offer_match_end(_career_choices(team == 0))
			else:
				_offer_match_end([["Play again", func() -> void: _on_mode_chosen(mode, score.golden_point)], ["Menu", _go_menu]])
		if net_role == "host":
			var h: Array = [Profile.rating(), 0]
			var g: Array = [opp_rating, 0]
			if ranked:
				h = _elo(Profile.rating(), opp_rating, team == 0)
				g = _elo(opp_rating, Profile.rating(), team == 1)
				Profile.set_v("online", "rating", h[0])
				here += "\nRating %d (%+d) · %s" % [h[0], h[1], Roster.tier(h[0])]
			hud.show_message(here, 30.0)
			for id in remotes:
				var their: Player = remotes[id]
				var text := _point_text(team, reason, res, SLOT_FOR_PEER[id])
				if ranked:
					text += "\nRating %d (%+d) · %s" % [g[0], g[1], Roster.tier(g[0])]
				net_match_result.rpc_id(id, team == their.team, g[0], g[1])
				net_message.rpc_id(id, text, 30.0)
			if counted:
				Profile.save()
			return
	if counted:
		Profile.save()
		_check_awards()
	var secs := 1.7 if res != "match" else (6.0 if career_venue != "" else 4.0)
	if net_role == "host":
		_announce(func(v: int) -> String: return here if v == 0 else _point_text(team, reason, res, v), secs)
	else:
		hud.show_message(here, secs)
	_send_score()
	if quit_after > 0.0:
		print("[point] %-26s -> team %d (%s)  hits=%d  sets %s games %s pts %s/%s" % [
			reason, team, res, rally_hits, score.sets, score.games, score.point_text(0), score.point_text(1)])


func _fault() -> void:
	if state != State.RALLY:
		return
	faults += 1
	stats.faults += 1
	if faults >= 2:
		_award(1 - last_hitter_team, "Double fault")
		return
	state = State.POINT_OVER
	state_timer = 1.2
	ring.visible = false
	_message("Fault — second serve", "Fault — second serve", 1.1)
	if quit_after > 0.0:
		print("[fault]")


# --- referee --------------------------------------------------------------------

func _on_floor(pos: Vector3) -> void:
	if state != State.RALLY:
		return
	if receiver_bounces == 0 and last_shot_kind in ["power_smash", "por_cuatro", "power_slice", "smash"] and Court.side_of(pos.z) != last_hitter_team:
		_impact(pos)
		_shake = maxf(_shake, 0.18 if last_shot_kind == "smash" else 0.3)
	var side := Court.side_of(pos.z)
	if side == last_hitter_team:
		if serve_in_play:
			_fault()
		elif receiver_bounces >= 1:
			_award(last_hitter_team, "Came back over!")
		else:
			_award(1 - last_hitter_team, "Into the net")
		return
	if practice and last_hitter_team == 0 and not challenge and _drill() == "por_cuatro" and last_shot_kind == "por_cuatro":
		# it has to bounce first, then kick out over the side
		receiver_bounces += 1
		if receiver_bounces >= 2:
			_practice_result(false, "Stayed in: hit it harder and wider")
		else:
			_refresh_prediction()
		return
	if practice and last_hitter_team == 0 and not challenge and _drill() == "walls":
		receiver_bounces += 1
		if receiver_bounces >= 2:
			_practice_result(false, "Missed the panel" if wall_since_bounce else "Too short to reach the glass")
		else:
			wall_since_bounce = false
			_refresh_prediction()
		return
	if practice and last_hitter_team == 0 and not challenge:
		_practice_judge(pos, true)
		return
	receiver_bounces += 1
	wall_since_bounce = false
	if serve_in_play and receiver_bounces == 1:
		var in_box := absf(pos.z) <= Court.SERVICE_Z + 0.05 and signf(pos.x) == serve_box_sign
		if not in_box:
			_fault()
			return
	if receiver_bounces >= 2:
		_award(last_hitter_team, "Double bounce")
	else:
		_refresh_prediction()


func _on_wall(pos: Vector3, surface: String) -> void:
	if state != State.RALLY:
		return
	var end := Court.side_of(pos.z)
	if practice and not challenge and last_hitter_team == 0 and end == 1 and _drill() == "walls":
		if receiver_bounces == 0:
			_practice_result(false, "Glass on the full: that's out")
		elif surface == "glass" and _in_wall_target(pos):
			_practice_result(true, "On the panel!")
		else:
			wall_since_bounce = true
			_refresh_prediction()
		return
	if challenge and last_hitter_team == 0 and end == 1:
		if absf(pos.z) > Court.HALF_L - 0.3:
			var c := _goal_centre(ch_t)
			var inside := surface == "glass" and absf(pos.x - c.x) <= ch_size.x * 0.5 + Ball.RADIUS \
				and absf(pos.y - c.y) <= ch_size.y * 0.5 + Ball.RADIUS
			_challenge_result(inside, "" if inside else ("Into the fence" if surface == "mesh" else "Wide of the goal"))
			return
		if surface == "mesh":
			_challenge_result(false, "Into the fence")
			return
		_refresh_prediction()   # off the side glass: it can still reach the goal
		return
	if end != last_hitter_team:
		if receiver_bounces == 0:
			if serve_in_play:
				_fault()
			else:
				_award(1 - last_hitter_team, "Hit the glass on the full" if surface == "glass" else "Into the fence")
			return
		if serve_in_play and surface == "mesh":
			_fault()
			return
		wall_since_bounce = true
	_refresh_prediction()


func _on_out(_pos: Vector3) -> void:
	if state != State.RALLY:
		return
	if receiver_bounces >= 1:
		_award(last_hitter_team, "Out of the court!")
	elif serve_in_play:
		_fault()
	else:
		_award(1 - last_hitter_team, "Out")


# --- frame loop -----------------------------------------------------------------

## Gentle follow: drifts with the ball and your player, pulls back when you go deep.
## In versus the friend's camera sits at the far end, looking the other way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Profile.save()
		# a call or a swipe home mid-point: stop the game (online can't pause)
		if mode != "menu" and not attract and net_role == "" and hud and state != State.MATCH_OVER:
			hud.pause()


## Battery saver: 30 fps; otherwise 60 (no point running 120 Hz flat out).
func _apply_fps() -> void:
	Engine.max_fps = 30 if Profile.get_v("settings", "battery", false) else 60


## Smashes land with a thump: a 60-ish ms freeze (offline only, so online
## stays in step) and a camera kick.
func _hitstop(secs: float, shake := 0.0) -> void:
	_shake = maxf(_shake, shake)
	if net_role != "" or secs <= 0.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(secs, true, false, true).timeout
	Engine.time_scale = 1.0


func _make_impact_fx() -> void:
	_impact_fx = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 32
	_impact_fx.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.65, 0.2, 0.9)
	_impact_fx.material_override = m
	_impact_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact_fx.visible = false
	add_child(_impact_fx)


func _impact(pos: Vector3) -> void:
	_impact_fx.position = Vector3(pos.x, 0.03, pos.z)
	_impact_t = 0.0
	_impact_fx.visible = true


## While the ident plays: show every venue, marker and effect for a frame
## behind it, so their shaders compile now and not mid-rally (no stutter on
## the first smash or the first visit to a court).
func _warm_up() -> void:
	var extras: Array[Node3D] = [aim_marker, goal_frame, wall_target, target_marker, machine, _impact_fx, ring]
	for n in extras:
		n.visible = true
	ball.burst(0.5)
	for v in Roster.VENUES + Roster.EXTRA_VENUES:
		_apply_venue(v.id)
		await get_tree().process_frame
		await get_tree().process_frame
	for n in extras:
		n.visible = false
	_apply_venue(Profile.get_v("settings", "court", "club"))


func _process(delta: float) -> void:
	# quick match: offer the AI if nobody turns up (new games have quiet queues)
	var waited := online.search_seconds() > 25.0
	if waited and quit_after > 0.0 and not stats.has("fallback"):
		stats.fallback = true
		print("[net] offering the AI after %.0f s" % online.search_seconds())
	hud.show_ai_fallback(waited)
	if net_role != "":
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			net_ping.rpc_id(remotes.keys()[0] if net_role == "host" and not remotes.is_empty() else 1, Time.get_ticks_msec())
	if _impact_t >= 0.0:
		_impact_t += delta
		var k := _impact_t / 0.4
		var r := 0.4 + 2.2 * k
		_impact_fx.scale = Vector3(r, 0.04, r)
		(_impact_fx.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - k)
		if k >= 1.0:
			_impact_t = -1.0
			_impact_fx.visible = false
	if _replay_t >= 0.0:
		# replay camera: low, beside the court, tracking the ball
		var bp := ball.position
		var want := Vector3(_replay_cam_side * 6.5, 2.6, clampf(bp.z * 0.6 + 4.0, -6.0, 9.0))
		camera.position = camera.position.lerp(want, 1.0 - exp(-2.5 * delta))
		camera.look_at(bp.lerp(Vector3(0, 1.0, bp.z), 0.4))
		return
	if _orbit_t >= 0.0:
		# match won: a slow lap round the winners
		_orbit_t += delta
		var a := _orbit_a0 + _orbit_t * 0.65
		var want := _orbit_centre + Vector3(sin(a) * 4.0, 1.85, cos(a) * 4.0)
		want.x = clampf(want.x, -Court.HALF_W + 0.5, Court.HALF_W - 0.5)   # stay inside the glass
		want.z = clampf(want.z, -Court.HALF_L + 0.5, Court.HALF_L - 0.5)
		camera.position = camera.position.lerp(want, 1.0 - exp(-lerpf(1.2, 9.0, clampf(_orbit_t / 1.6, 0.0, 1.0)) * delta))
		camera.look_at(_orbit_centre + Vector3(0, 1.05, 0))
		return
	if _celeb_cam >= 0:
		# in front of the celebrating pair, from the net side
		var c := _team_centre(_celeb_cam)
		var sg := Court.team_sign(_celeb_cam)
		var spread := 0.0
		for p in _team(_celeb_cam):
			spread = maxf(spread, Vector2(p.position.x - c.x, p.position.z - c.z).length())
		var want := Vector3(c.x * 0.5 + 1.3 * sg, 1.75 + spread * 0.15, c.z - sg * (3.6 + spread * 0.9))
		camera.position = camera.position.lerp(want, 1.0 - exp(-2.8 * delta))
		camera.look_at(c + Vector3(0, 1.0, 0))
		return
	var me := _me()
	var sgn := Court.team_sign(me.team)
	var bx := ball.position.x if (ball.live or net_role == "client") else 0.0
	var target := Vector3(
		clampf(bx * 0.18 + me.position.x * 0.12, -1.1, 1.1),
		cam_base.y,
		sgn * (cam_base.z + maxf(0.0, absf(me.position.z) - 8.0) * 0.6))
	camera.position = camera.position.lerp(target, 1.0 - exp(-3.0 * delta))
	camera.look_at(Vector3(camera.position.x * 0.5, 0.0, sgn * 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.14
		camera.v_offset = randf_range(-1, 1) * _shake * 0.1
	elif camera.h_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _physics_process(delta: float) -> void:
	elapsed += delta
	if quit_after > 0.0 and elapsed >= quit_after:
		_print_stats()
		get_tree().quit()
		set_physics_process(false)
		return
	if shot_replay and _replay_t > 26.0:
		shot_replay = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("saved ", shot_path)
	if (shot_event == "celebrate" and _celeb_cam >= 0 and elapsed - _celeb_at > 2.4) or (shot_event == "orbit" and _orbit_t > 2.6):
		shot_event = ""
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("saved ", shot_path)
	if shot_at > 0.0 and elapsed >= shot_at and (state == State.RALLY or net_role == "client" or practice or "--intro" in OS.get_cmdline_user_args()):
		shot_at = -1.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("saved ", shot_path)
	if mash_kind == "contrapared" and state == State.RALLY and _contrapared_ball(_human()) and _can_hit(_human()):
		_on_shot_requested("drive", Vector2(randf_range(-1, 1), 0.3))
	elif mash_kind == "por_cuatro" and Engine.get_physics_frames() % 15 == 0:
		_on_shot_requested("smash", Vector2.ZERO)
		_on_shot_requested("smash_side", Vector2(1.0, 0.0))
	elif mash_kind == "power_slice" and Engine.get_physics_frames() % 15 == 0:
		_on_shot_requested("smash", Vector2.ZERO)
		_on_shot_requested("smash_side", Vector2(randf_range(-0.4, 0.4), -1.0))
	elif mash_kind == "dejada" and Engine.get_physics_frames() % 15 == 0:
		_on_shot_requested("chiquita", Vector2(0.0, -1.0))
	elif mash_kind == "globo" and Engine.get_physics_frames() % 15 == 0:
		_on_shot_requested("lob", Vector2(0.0, 0.3))
	elif mash_kind in ["chiquita", "vibora"] and Engine.get_physics_frames() % 15 == 0:
		_on_shot_requested("chiquita" if mash_kind == "chiquita" else "slice", Vector2(randf_range(-0.4, 0.4), -1.0) if mash_kind == "chiquita" else Vector2(1.0, 0.0))
	elif mash and mash_kind == "" and combo >= 1.0 and state == State.RALLY:
		_on_shot_requested("combo", Vector2.ZERO)
		if quit_after > 0.0:
			print("[combo] armed at t=%.1f" % elapsed)
	elif mash and mash_kind == "" and Engine.get_physics_frames() % 15 == 0 and state != State.POINT_OVER:
		var a := Vector2(randf_range(-1, 1), randf_range(-0.5, 0.8))
		_on_shot_requested("smash" if randf() < 0.15 else Hud.swipe_kind(a), a)
	_read_keyboard()
	if test_celebrate != "" and elapsed > 4.0 and state == State.RALLY:
		_celeb_team = 0
		_celeb_match = test_celebrate == "match"
		state = State.MATCH_OVER if _celeb_match else State.POINT_OVER
		state_timer = 30.0
		ring.visible = false
		aim_marker.visible = false
		if _celeb_match and not _ai_human():
			_over_at = elapsed
			_offer([["Play again", _go_menu], ["Menu", _go_menu]])
			hud.show_message("You win the match!", 4.0)
		test_celebrate = ""
	if challenge:
		if state != State.MATCH_OVER:
			ch_t += delta
		_place_goal(ch_t)
	_squeak_cd = maxf(0.0, _squeak_cd - delta)
	if net_role == "client":
		_client_tick(delta)
		return
	pad_local.buffer = maxf(0.0, pad_local.buffer - delta)
	pad_local.latch = maxf(0.0, pad_local.latch - delta)
	for pd in pads.values():
		pd.buffer = maxf(0.0, pd.buffer - delta)
		pd.latch = maxf(0.0, pd.latch - delta)
	pad_local.mirror = 1.0
	pad_local.touch = hud.hit_btn.is_held()
	pad_local.move = hud.joystick.value + Input.get_vector("move_left", "move_right", "move_up", "move_down")
	pad_local.held = _hit_held()
	pad_local.live_aim = _held_aim()
	match state:
		State.SERVE_WAIT:
			_tick_serve(delta)
		State.RALLY:
			sfx.log_on = true
			_tick_rally(delta)
			_record_frame()
			sfx.log_on = false
		State.POINT_OVER:
			if _celeb_team >= 0:
				_start_celebration()
			_tick_replay(delta)
			for p in players:
				if not p.replaying:
					p.move_dir(Vector3.ZERO, delta)
			state_timer -= delta
			if state_timer <= 0.0:
				_start_point()
		State.MATCH_OVER:
			if _celeb_team >= 0:
				_start_celebration()
			_tick_replay(delta)
			state_timer -= delta
			if state_timer <= 0.0 and _ai_human():
				score = MatchScore.create(score.games_per_set, score.sets_to_win, score.golden_point)
				_start_point()
	_update_hud()
	if net_role == "host" and Engine.get_physics_frames() % 2 == 0:
		_send_snapshot()


func _tick_serve(delta: float) -> void:
	if practice:
		state_timer -= delta
		if state_timer <= 0.0:
			_feed()
		return
	var srv := players[_server_index()]
	_hold_ball(srv)
	state_timer -= delta
	if _controlled(srv):
		var pad := _pad_for(srv)
		if pad.buffer > 0.0 and state_timer <= 0.0:
			pad.buffer = 0.0
			pad.latch = 0.0
			_serve(srv, pad.world_aim(pad.aim))
	elif state_timer <= 0.0:
		_serve(srv, Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)))


func _tick_rally(delta: float) -> void:
	since_hit += delta
	if since_hit > DEAD_BALL_TIME:
		_award(last_hitter_team, "Dead ball")
		return
	predict_timer -= delta
	if predict_timer <= 0.0:
		_refresh_prediction()
	var next_team := 1 - last_hitter_team
	for p in players:
		if practice and not p.is_human:
			continue
		p.hit_cooldown = maxf(0.0, p.hit_cooldown - delta)
		if _controlled(p):
			_tick_controlled(p, _pad_for(p), delta)
		else:
			_tick_ai(p, delta, next_team)
		if state != State.RALLY:
			return
	var h := _human()
	ring.visible = not _ai_human() and assigned[0] == h and intercepts.has(h)
	if ring.visible:
		var ip: Vector3 = intercepts[h].pos
		ring.position = Vector3(ip.x, 0.02, ip.z)
	# where your shot will land while you hold HIT (Red Bull added a swipe
	# trail for touch feedback; this shows the result on court instead)
	var aiming := (not _ai_human() or aim_test) and last_hitter_team == 1 and (pad_local.held or aim_test)
	aim_marker.visible = aiming
	if aiming:
		var kind := "bandeja" if ball.sim.pos.y > 2.0 else "drive"
		var t: Array = _shot_target(kind, pad_local.world_aim(pad_local.live_aim), Court.team_sign(0), 0.75)
		var to: Vector3 = t[0]
		aim_marker.position = Vector3(to.x, 0.03, to.z)
		aim_marker.rotation.y = elapsed * 1.2
		aim_marker.scale = Vector3.ONE * (1.0 + 0.08 * sin(elapsed * 9.0))


# --- prediction & assignment ------------------------------------------------------

func _refresh_prediction() -> void:
	if state != State.RALLY:
		return
	predict_timer = 0.12
	prediction = ball.predict(3.0)
	var next_team := 1 - last_hitter_team
	intercepts.clear()
	if practice:
		if next_team == 0:
			var hs := _find_intercept(_human(), 0)
			if not hs.is_empty():
				intercepts[_human()] = hs
			assigned = [_human(), null]
		else:
			assigned = [null, null]
		return
	var mates := _team(next_team)
	for p in mates:
		var s := _find_intercept(p, next_team)
		if not s.is_empty():
			intercepts[p] = s
	var current: Player = assigned[next_team]
	if current != null and intercepts.has(current):
		return   # sticky: don't flip-flop once a player has called it
	var left: Player = mates[0] if mates[0].position.x <= mates[1].position.x else mates[1]
	var right: Player = mates[1] if left == mates[0] else mates[0]
	var mid := (left.position.x + right.position.x) * 0.5
	var pick: Player = left if _first_x_on(next_team) < mid else right
	if not intercepts.has(pick):
		var other: Player = right if pick == left else left
		if intercepts.has(other):
			pick = other
	assigned[next_team] = pick
	assigned[last_hitter_team] = null
	if pick != last_callout[next_team]:
		last_callout[next_team] = pick
		# an AI partner calls the ball for its person (people partnering each other talk)
		for i in players.size():
			var me_p := players[i]
			if me_p.team != next_team or not _controlled(me_p) or _controlled(_partner(me_p)):
				continue
			var call := "%s: %s" % [_partner(me_p).display_name, "MINE!" if pick != me_p else "YOURS!"]
			if i == 0 and not _ai_human():
				hud.callout(call)
			elif _peer_of(me_p) > 0:
				net_callout.rpc_id(_peer_of(me_p), call)


func _first_x_on(team: int) -> float:
	for s in prediction:
		if Court.side_of(s.pos.z) == team:
			return s.pos.x
	return ball.sim.pos.x


## Earliest point on the predicted path this player can reach and play.
func _find_intercept(p: Player, team: int) -> Dictionary:
	var fallback := {}
	for s in prediction:
		var pos: Vector3 = s.pos
		if s.floors[1 - team] > 0:
			break   # it bounced back on the hitter's side: point over
		var b: int = receiver_bounces + s.floors[team]
		if b >= 2:
			break
		if Court.side_of(pos.z) != team:
			continue
		if serve_in_play and b < 1:
			continue
		if pos.y < 0.15 or pos.y > 2.6:
			continue
		var d := Vector2(pos.x - p.position.x, pos.z - p.position.z).length()
		if maxf(0.0, d - p.reach * 0.7) > p.speed * maxf(0.0, s.t - p.react) * 0.9:
			continue
		var vy: float = s.vel.y
		var rebound: bool = b >= 1 and signf(s.vel.z) == -Court.team_sign(team) and pos.y >= 0.3 and pos.y <= 1.9
		var ground := (b >= 1 and vy < 0.0 and pos.y >= 0.35 and pos.y <= 1.5) or rebound
		var volley := b == 0 and not serve_in_play and absf(pos.z) < 5.0 and pos.y >= 0.6 and pos.y <= 1.8
		var overhead := b == 0 and not serve_in_play and pos.y >= 2.0
		if ground or volley or overhead:
			return s
		if fallback.is_empty():
			fallback = s
	return fallback


func _can_hit(p: Player) -> bool:
	if p.hit_cooldown > 0.0 or p.team == last_hitter_team:
		return false
	var bp := ball.sim.pos
	if Court.side_of(bp.z) != p.team or receiver_bounces >= 2:
		return false
	if serve_in_play and receiver_bounces < 1:
		return false
	if bp.y < 0.12 or bp.y > 2.7:
		return false
	return Vector2(bp.x - p.position.x, bp.z - p.position.z).length() <= p.reach


func _intercept_stand(p: Player, ip: Vector3) -> Vector3:
	# stand so the ball arrives on the forehand side, slightly in front
	return Vector3(ip.x - 0.45 * p.right_x(), 0, ip.z + Court.team_sign(p.team) * 0.25)


# --- AI -------------------------------------------------------------------------

func _home_for(p: Player, next_team: int) -> Vector3:
	var s := Court.team_sign(p.team)
	var mate := _partner(p)
	var zx := 2.4 if p.position.x > mate.position.x else -2.4
	if _controlled(mate):
		# a person goes where they like; their AI partner covers the other half
		zx = -2.4 if mate.position.x > 0.0 else 2.4
	if p.team == next_team:
		return Vector3(zx, 0, s * 7.8)          # defend from the back
	if last_shot_kind == "lob" or last_shot_kind == "smash":
		return Vector3(zx, 0, s * 3.2)          # take the net
	return Vector3(zx, 0, s * 4.2)


func _tick_ai(p: Player, delta: float, next_team: int) -> void:
	p.react = maxf(0.0, p.react - delta)
	if p.react > 0.0:
		p.move_dir(Vector3.ZERO, delta)
		return
	var target := _home_for(p, next_team)
	var mine: bool = p.team == next_team and assigned[next_team] == p
	if mine and intercepts.has(p):
		target = _intercept_stand(p, intercepts[p].pos)
	p.move_towards(target, delta)
	# AI partners leave their person's balls alone
	if (p.team == 0 or _team_has_person(p.team)) and not mine:
		return
	if not _can_hit(p):
		return
	var bp := ball.sim.pos
	var vy := ball.sim.vel.y
	var b := receiver_bounces
	var coming_off_glass := b >= 1 and signf(ball.sim.vel.z) == -Court.team_sign(p.team) and bp.y < 1.9
	var ok := (b >= 1 and vy < 0.0 and bp.y < 1.45) or coming_off_glass \
		or (b >= 1 and bp.y < 0.4) \
		or (b == 0 and not serve_in_play and absf(bp.z) < 5.0 and bp.y > 0.6 and bp.y < 1.9) \
		or (b == 0 and not serve_in_play and bp.y > 2.0)
	if ok:
		_ai_hit(p)


func _ai_hit(p: Player) -> void:
	var bp := ball.sim.pos
	var kind := "drive"
	var opp_at_net := true
	for o in _team(1 - p.team):
		if absf(o.position.z) > 5.2:
			opp_at_net = false
	var opp_deep := true
	for o in _team(1 - p.team):
		if absf(o.position.z) < 7.0:
			opp_deep = false
	var st := _style(p)
	if bp.y > 2.6 and absf(bp.z) < 5.0 and randf() < (0.12 if st == "Power" else 0.04):
		kind = "por_cuatro"
	elif bp.y > 2.0:
		kind = "smash" if absf(bp.z) < 6.0 and randf() < (0.8 if st == "Power" else 0.55) else ("vibora" if randf() < 0.4 else "bandeja")
	elif opp_deep and absf(p.position.z) < 4.6 and bp.y < 1.6 and randf() < (0.3 if st == "Touch" else 0.12):
		kind = "dejada"
	elif opp_at_net and bp.y < 1.2 and randf() < (0.35 if st == "Touch" else 0.15):
		kind = "chiquita"
	elif opp_at_net and randf() < (0.55 if st == "Touch" else 0.4):
		kind = "globo" if randf() < 0.3 else "lob"
	elif absf(p.position.z) > 7.5 and randf() < (0.28 if st == "Touch" else 0.18):
		kind = "lob"   # defensive lob from the back
	elif receiver_bounces >= 1 and bp.y < 1.15 and randf() < (0.5 if st == "Touch" else 0.3):
		kind = "slice"  # low ball: cut it
	# aim away from the nearer opponent
	var nearest := 0.0
	var best := INF
	for o in _team(1 - p.team):
		var d := o.position.distance_to(bp)
		if d < best:
			best = d
			nearest = o.position.x
	var away := -signf(nearest) if nearest != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	var aim := Vector2(clampf(away * randf_range(0.2, 0.9) + randf_range(-0.3, 0.3), -1, 1), randf_range(-0.4, 0.7))
	var diff := _difficulty(p)
	var edge := 0.05 if st == "Touch" else (0.02 if st == "All-rounder" else 0.0)
	var q := clampf(p.skill + edge - diff * 0.6 + randf_range(-0.15, 0.15), 0.15, 1.0)
	_do_hit(p, kind, aim, q, 0.02 + diff * 0.2)


## 0 (easy sitter) .. ~1 (fast, low, at full stretch). Raises error and miss chance.
func _difficulty(p: Player) -> float:
	var bp := ball.sim.pos
	var pace := ball.sim.vel.length()
	var stretch := clampf(Vector2(bp.x - p.position.x, bp.z - p.position.z).length() / p.reach, 0.0, 1.0)
	var d := clampf((pace - 9.0) / 18.0, 0.0, 0.45) + stretch * stretch * 0.3
	if bp.y < 0.45:
		d += 0.25
	if receiver_bounces == 0:
		d += 0.12   # volleys and overheads are harder
	if wall_since_bounce:
		d += 0.1    # reading the glass
	if ball.sim.spin < -0.3:
		d += 0.12   # a slice stays low and skids
	return d


# --- people ---------------------------------------------------------------------

func _key_aim() -> Vector2:
	var k := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector2(k.x, -k.y)


func _hit_held() -> bool:
	return hud.hit_btn.is_held() or Input.is_action_pressed("hit")


func _held_aim() -> Vector2:
	return hud.hit_btn.live_aim() if hud.hit_btn.is_held() else _key_aim()


func _read_keyboard() -> void:
	var aim := _key_aim()
	if Input.is_action_just_pressed("hit"):
		_on_hit_pressed()
	if Input.is_action_just_released("hit"):
		_on_shot_requested("drive", aim)
	if Input.is_action_just_pressed("lob"):
		_on_shot_requested("lob", aim)
	if Input.is_action_just_pressed("smash"):
		_on_shot_requested("smash", aim)
	if Input.is_action_just_pressed("chiquita"):
		_on_shot_requested("chiquita", Vector2(aim.x, -1.0))
	if Input.is_action_just_pressed("slice"):
		_on_shot_requested("slice", Vector2(aim.x if aim.x != 0.0 else 1.0, 0.0))


## Touch-down on HIT: the player shows a backswing straight away.
func _on_hit_pressed() -> void:
	if net_role == "client":
		_me().ready_swing(ball.position.y > 2.0)
		net_hit_pressed.rpc_id(1)
		return
	if not _ai_human():
		_pad_pressed(pad_local, _human())


func _on_shot_requested(kind: String, aim: Vector2) -> void:
	if kind == "combo":
		if combo >= 1.0 and not combo_armed and net_role == "" and state in [State.RALLY, State.SERVE_WAIT]:
			combo = 0.0
			combo_armed = true
			hud.callout("%s: \"Together! Next one's yours!\"" % players[1].display_name, 1.6)
			sfx.ui("ding", -4.0)
			Profile.vibrate(40)
		return
	if _replay_t >= 0.0:
		_end_replay()
		state_timer = minf(state_timer, 0.4)
		return
	if net_role == "client":
		if not _snap.is_empty() and _snap[0] == State.MATCH_OVER:
			net_rematch_vote.rpc_id(1)
			return
		net_shot.rpc_id(1, kind, aim)
		return
	if state == State.MATCH_OVER and elapsed - _over_at < 1.2:
		return   # a stray tap straight after the end: let them read the result
	if state == State.MATCH_OVER and _choice_default.is_valid():
		var f := _choice_default
		_choice_default = Callable()
		hud.show_choices([])
		f.call()
		return
	if practice and state == State.SERVE_WAIT and feeds == 0 and state_timer > 0.8:
		hud.show_message("", 0.0)
		state_timer = 0.8   # read it already: start now
		return
	if state == State.POINT_OVER and _celeb_cam >= 0 and not _celeb_match:
		state_timer = minf(state_timer, 0.2)   # skip the celebration
		return
	if state == State.MATCH_OVER and not _ai_human() and challenge:
		_start_daily()
		return
	if state == State.MATCH_OVER and not _ai_human() and career_venue != "":
		_career_continue()
		return
	if state == State.MATCH_OVER and net_role == "host":
		_rematch[1] = true
		_check_rematch()
		return
	if state == State.MATCH_OVER and not _ai_human():
		_on_mode_chosen(mode, score.golden_point)
		return
	_pad_shot(pad_local, kind, aim)


func _pad_pressed(pad: Pad, p: Player) -> void:
	pad.held_fired = false
	if state == State.RALLY:
		p.ready_swing(ball.sim.pos.y > 2.0)


func _pad_shot(pad: Pad, kind: String, aim: Vector2) -> void:
	if kind == "smash_side":
		# SMASH, then a swipe before letting go: sideways = por cuatro that
		# way, down = a power slice
		if aim.y <= -0.45 and absf(aim.y) > absf(aim.x):
			pad.cut = true
			pad.side = 0.0
			pad.aim = Vector2(clampf(aim.x, -1.0, 1.0), 0.6)
		elif absf(aim.x) < 0.4:
			return
		else:
			pad.cut = false
			pad.side = signf(pad.world_aim(aim).x)
		if pad.kind != "smash" or pad.buffer <= 0.0:
			pad.kind = "smash"
			pad.buffer = LATCH_TIME
			pad.latch = LATCH_TIME
		return
	if kind == "smash":
		pad.side = 0.0
		pad.cut = false
	if kind == "drive" and pad.held_fired:
		pad.held_fired = false   # this release belongs to a shot already played
		return
	if kind in ["lob", "smash"]:
		# a tap on LOB / SMASH is a decision: hold it until the ball arrives
		pad.buffer = LATCH_TIME
		pad.latch = LATCH_TIME
	else:
		pad.buffer = BUFFER_TIME
		pad.latch = 0.0
	pad.kind = kind
	pad.aim = aim


## A person's player: stick or move-assist, and HIT that fires at contact while held.
func _tick_controlled(p: Player, pad: Pad, delta: float) -> void:
	# trainers squeak on a hard change of direction
	var mv := pad.world_move()
	if mv.length() > 0.6 and p.vel.length() > 2.6 and p.vel.normalized().dot(mv.normalized()) < -0.3 and _squeak_cd <= 0.0:
		_squeak_cd = 0.6
		sfx.at("squeak", p.position, -10.0)
	if pad.move.length() > 0.1:
		p.move_dir(pad.world_move(), delta)
	elif Profile.one_handed() and p == players[0] and net_role != "client":
		# one-handed play: your player moves itself, like an AI, and you just hit
		if assigned[p.team] == p and intercepts.has(p):
			p.move_towards(_intercept_stand(p, intercepts[p].pos), delta)
		else:
			p.move_towards(_home_for(p, 1 - last_hitter_team), delta)
	elif MOVE_ASSIST > 0.0 and assigned[p.team] == p and intercepts.has(p) and not (practice and not DRILL_INFO[_drill()].get("assist", true)):
		p.move_towards(_intercept_stand(p, intercepts[p].pos), delta, MOVE_ASSIST)
	else:
		p.move_dir(Vector3.ZERO, delta)
	# holding HIT keeps the shot armed; it fires the moment the ball is in reach,
	# aimed by wherever the thumb is at that instant
	var held := pad.held and state == State.RALLY
	if held and pad.latch <= 0.0:
		pad.buffer = maxf(pad.buffer, 0.05)
		pad.kind = Hud.swipe_kind(pad.live_aim) if pad.touch else "drive"
		pad.aim = pad.live_aim
	if pad.buffer > 0.0 and _can_hit(p):
		var bp := ball.sim.pos
		var kind := pad.kind
		if kind == "smash":
			# SMASH only fires charged and with the ball high; otherwise a normal shot.
			# With the stick held sideways it's a por cuatro (out over the side wall).
			if p.smash_charge >= 1.0 and bp.y > 1.6:
				var side := pad.side if pad.side != 0.0 else (signf(pad.world_move().x) if absf(pad.world_move().x) > 0.55 else 0.0)
				if pad.cut:
					kind = "power_slice"
				elif side != 0.0 and _shot_ok(p, "por_cuatro"):
					kind = "por_cuatro"
					pad.aim = Vector2(side * pad.mirror, 0.0)   # world_aim() turns it back into world x
				else:
					kind = "power_smash"
			else:
				kind = "bandeja" if bp.y > 2.0 else "drive"
		elif kind == "chiquita" and bp.y < 2.0 and absf(p.position.z) < 4.6 and _shot_ok(p, "dejada"):
			kind = "dejada"   # swipe down at the net: a drop shot
		elif _contrapared_ball(p) and _shot_ok(p, "contrapared"):
			kind = "contrapared"
		elif kind == "slice" and bp.y > 2.0 and _shot_ok(p, "vibora"):
			kind = "vibora"
		elif kind in ["drive", "slice", "chiquita"] and bp.y > 2.0:
			kind = "bandeja"
		elif kind == "chiquita" and not _shot_ok(p, "chiquita"):
			kind = "drive"
		elif kind == "lob" and bp.y > 2.0:
			kind = "bandeja"
		var q := _timing_quality(p)
		if kind == "lob" and q >= 0.7 and _shot_ok(p, "globo") and (practice or _rivals_at_net(p.team)):
			kind = "globo"
		var together := combo_armed and p == _human() and net_role == ""
		if together:
			# the partner combo: your partner set it up, you finish it
			combo_armed = false
			kind = "por_cuatro" if bp.y > 1.6 and _shot_ok(p, "por_cuatro") else ("power_smash" if bp.y > 1.6 else "combo")
			q = 1.0
		var glass := wall_since_bounce
		pad.buffer = 0.0
		pad.latch = 0.0
		pad.side = 0.0
		pad.cut = false
		pad.held_fired = held
		var miss := maxf(0.0, (0.7 - q) * 0.6) + _difficulty(p) * 0.12
		if kind in ["power_smash", "por_cuatro", "power_slice"]:
			miss *= 0.5
		if together:
			miss = 0.0
		_do_hit(p, kind, pad.world_aim(pad.aim), q, miss)
		if kind in ["power_smash", "por_cuatro", "power_slice"] or together:
			_hitstop(0.075, 0.4)
		elif q > 0.85:
			_hitstop(0.035, 0.08)
		var was_full := p.smash_charge >= 1.0
		_last_together = together
		if together:
			for o in _team(1 - p.team):
				o.react = 2.2          # wrong-footed: they don't move until it's past them
		if kind in ["power_smash", "por_cuatro", "power_slice"] and not together:
			p.smash_charge = 0.0
		else:
			# adding 1/12ths in floating point can stop a hair short of 1.0 (0.9999999):
			# the ring looked full but stayed orange and SMASH never armed. Snap it.
			var c: float = p.smash_charge + (2.0 if q > 0.85 else 1.0) / CHARGE_HITS * (1.0 + _kit(p).charge)
			p.smash_charge = 1.0 if c >= 0.995 else c
		var fx := ""
		if together:
			fx = "TOGETHER!"
		elif kind == "power_smash":
			fx = "POWER SMASH!"
		elif kind == "power_slice":
			fx = "POWER SLICE!"
		elif kind in Roster.SHOTS:
			fx = Roster.SHOTS[kind].name.to_upper() + "!"
		elif not was_full and p.smash_charge >= 1.0:
			fx = "SMASH READY!"
		elif glass and q >= 0.7 and kind == "drive":
			fx = "BAJADA!"
		elif q > 0.85:
			fx = "PERFECT!"
		elif glass:
			fx = "OFF THE GLASS!"
		elif kind == "slice":
			fx = "SLICE"
		if p == _human() and not _ai_human():
			if kind in ["power_smash", "power_slice"]:
				Profile.add_stat("power_smashes")
			elif fx == "BAJADA!":
				Profile.add_stat("bajadas")
			if kind == "slice":
				Profile.add_stat("slices")
			if kind in Roster.SHOTS:
				Profile.add_stat(kind)
			if together:
				Profile.add_stat("combos")
			if q > 0.85:
				Profile.add_stat("perfect")
		var ms := 60 if q > 0.85 else 25
		if _peer_of(p) > 0:
			net_feedback.rpc_id(_peer_of(p), fx, ms)
		else:
			if fx != "":
				hud.flash(fx)
			if fx == "SMASH READY!" and not practice and not challenge and Profile.get_v("hints", "power_slice", 0) < 2:
				# the first couple of times: how to use it
				Profile.set_v("hints", "power_slice", int(Profile.get_v("hints", "power_slice", 0)) + 1)
				Profile.save()
				hud.show_message("SMASH is charged: tap it on a high ball.\nSwipe down on it for a POWER SLICE.", 2.6)
			Profile.vibrate(ms)


func _timing_quality(p: Player) -> float:
	var bp := ball.sim.pos
	var ideal := 2.3 if bp.y > 2.0 else 1.0
	var d := Vector2(bp.x - p.position.x, bp.z - p.position.z).length()
	var bonus: float = (0.06 if _style(p) == "Touch" else (0.02 if _style(p) == "All-rounder" else 0.0)) + _kit(p).touch
	return clampf(1.0 - absf(bp.y - ideal) * 0.45 - absf(d - 0.55) * 0.35 + bonus, 0.25, 1.0)


## [timing arc 0..1, SMASH charge 0..1] for a person's player.
func _readiness(p: Player) -> Array:
	if p == null:
		return [0.0, 0.0]
	if state != State.RALLY:
		return [0.0, p.smash_charge]
	if _can_hit(p):
		return [_timing_quality(p), p.smash_charge]
	if assigned[p.team] == p:
		var d := ball.sim.pos.distance_to(p.position + Vector3(0, 1, 0))
		return [clampf(1.0 - (d - 1.0) / 6.0, 0.0, 0.8), p.smash_charge]
	return [0.0, p.smash_charge]


func _update_hud() -> void:
	if _ai_human():
		hud.hit_btn.readiness = 0.0
		hud.smash_btn.enabled = false
		hud.smash_btn.charge = 0.0
		hud.combo_btn.visible = false
		return
	var r := _readiness(_human())
	hud.hit_btn.readiness = r[0]
	hud.smash_btn.charge = r[1]
	hud.smash_btn.enabled = r[1] >= 1.0
	hud.lob_btn.armed = pad_local.latch > 0.0 and pad_local.kind == "lob"
	hud.smash_btn.armed = pad_local.latch > 0.0 and pad_local.kind == "smash"
	var show_combo := net_role == "" and not practice and players[1].visible
	hud.combo_btn.visible = show_combo
	hud.combo_btn.charge = 1.0 if combo_armed else combo
	hud.combo_btn.enabled = combo >= 1.0 and not combo_armed


# --- shots ----------------------------------------------------------------------

## Intended landing point and pace for a shot before any error: [to, speed, clear, depth].
func _shot_target(kind: String, aim: Vector2, s: float, q: float) -> Array:
	var r := Ball.RADIUS
	var depth := clampf(0.6 + 0.3 * aim.y, 0.2, 1.0)
	var to: Vector3
	var speed := 14.0
	var clear := 0.25
	match kind:
		"smash":
			to = Vector3(aim.x * 3.5, r, -s * lerpf(3.0, 6.0, depth))
			speed = lerpf(20.0, 27.0, q)
			clear = 0.1
		"power_slice":
			# cut hard and deep with heavy backspin: skids low and dies off the glass
			to = Vector3(aim.x * 3.6, r, -s * lerpf(6.2, 7.8, depth))
			speed = lerpf(22.0, 27.0, q)
			clear = 0.1
		"power_smash", "por_cuatro":
			# lands near the service line with topspin: kicks up and over the back wall
			to = Vector3(aim.x * 3.0, r, -s * lerpf(2.8, 4.4, depth))
			speed = lerpf(26.0, 32.0, q)
			clear = 0.06
		"slice":
			to = Vector3(signf(aim.x) * lerpf(1.5, 3.8, absf(aim.x)), r, -s * lerpf(6.0, 8.8, depth))
			speed = lerpf(12.0, 15.0, q)
			clear = 0.12
		"bandeja":
			to = Vector3(aim.x * 3.5, r, -s * lerpf(6.0, 8.5, depth))
			speed = 12.0
			clear = 0.3
		"vibora":
			# sliced, flatter than a bandeja, into a deep corner where it skids off the side glass
			var side := signf(aim.x) if absf(aim.x) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
			to = Vector3(side * lerpf(2.6, 4.3, absf(aim.x)), r, -s * lerpf(7.2, 9.0, depth))
			speed = lerpf(15.5, 19.5, q)
			clear = 0.14
		"chiquita":
			# soft, dipping, just over the net at the volleyers' feet
			to = Vector3(aim.x * 3.0, r, -s * lerpf(2.0, 3.6, clampf(q, 0.0, 1.0) * 0.5 + 0.25))
			speed = lerpf(8.0, 9.5, q)
			clear = 0.06
		"lob":
			to = Vector3(aim.x * 3.5, r, -s * lerpf(8.0, 9.3, depth))
		"globo":
			to = Vector3(aim.x * 3.0, r, -s * lerpf(8.4, 9.2, depth))
		"dejada":
			# feathered just over the net with heavy backspin: it dies
			to = Vector3(aim.x * 3.2, r, -s * lerpf(1.0, 2.0, depth * 0.6))
			speed = lerpf(6.5, 7.6, q)
			clear = 0.16
		"combo":
			# into the open corner, hard and deep
			var side := signf(aim.x) if absf(aim.x) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
			to = Vector3(side * 3.5, r, -s * 7.4)
			speed = 19.0
			clear = 0.22
		_:
			# glass targets drill: you can aim right into the corners
			var reach := 4.6 if practice and _drill() == "walls" else 3.8
			to = Vector3(aim.x * reach, r, -s * lerpf(3.0, 8.6, depth))
			speed = lerpf(10.0, 18.0, q * 0.6 + depth * 0.4)
	return [to, speed, clear, depth]


func _do_hit(p: Player, kind: String, aim: Vector2, q: float, miss_chance := 0.0) -> void:
	var s := Court.team_sign(p.team)
	var from := ball.sim.pos
	var r := Ball.RADIUS
	var t := _shot_target(kind, aim, s, q)
	var to: Vector3 = t[0]
	var speed: float = t[1]
	var clear: float = t[2]
	var depth: float = t[3]
	# bajada: a well-timed ball taken off your own back glass comes out with extra pace
	if wall_since_bounce and q >= 0.7 and kind == "drive":
		speed += 3.5
	if _style(p) == "Power" and kind in ["drive", "smash", "power_smash", "power_slice"]:
		speed += 1.5
	if kind in ["drive", "smash", "power_smash", "vibora"]:
		speed += _kit(p).power
	var err := (1.0 - q) * 1.4
	to.x = clampf(to.x + randf_range(-err, err), -4.6, 4.6)
	to.z = -s * clampf(absf(to.z) + randf_range(-err, err) * 0.8, 0.8, 10.6)
	var missed := randf() < miss_chance
	if missed and randf() < 0.55:
		# framed it into the net
		to = Vector3(to.x, r, -s * randf_range(1.0, 2.5))
		ball.velocity = Shot.launch_velocity(from, to, randf_range(0.25, 0.4))
	elif missed:
		# overhit: flies long onto the glass on the full, or over the wall
		to = Vector3(to.x, r, -s * randf_range(10.4, 12.0))
		ball.velocity = Shot.solve(from, to, speed + 4.0, 0.3)
	elif kind == "lob":
		ball.velocity = Shot.launch_velocity(from, to, lerpf(1.7, 2.1, depth))
	elif kind == "globo":
		ball.velocity = Shot.launch_velocity(from, to, lerpf(2.25, 2.5, depth))
	elif kind == "por_cuatro":
		var v4: Variant = _solve_por_cuatro(from, aim, s)
		ball.velocity = v4 if v4 != null else Shot.solve(from, to, speed, clear)
	elif kind == "contrapared":
		ball.velocity = _solve_contrapared(from, aim, s)
	else:
		ball.velocity = Shot.solve(from, to, speed, clear)
	ball.sim.spin = SHOT_SPIN.get(kind, 0.0)
	last_hit_volley = receiver_bounces == 0
	if trace:
		print("[hit] t=%.1f %s %s from=%s to=%s q=%.2f b=%d" % [elapsed, p.display_name, kind, from.snapped(Vector3.ONE * 0.1), to.snapped(Vector3.ONE * 0.1), q, receiver_bounces])
	var hard := kind in ["smash", "power_smash", "power_slice"]
	sfx.at("smash" if hard else "paddle", from, (2.0 if kind in ["power_smash", "power_slice"] else 0.0) if hard else clampf(speed * 0.35 - 6.0, -6.0, 0.0))
	p.swing(kind)
	if kind in ["power_smash", "por_cuatro", "power_slice", "smash", "combo"]:
		ball.burst(0.9)
	p.hit_cooldown = 0.4
	_last_hit_at = _rec_total
	# a smash dug out and sent back: the crowd goes "ooh"
	if last_hitter_team != p.team and last_shot_kind in ["power_smash", "power_slice", "smash", "por_cuatro"] and rally_hits > 1 and elapsed - _ooh_at > 6.0:
		_ooh_at = elapsed
		sfx.react("ooh")
	last_hitter_p = p
	last_hitter_team = p.team
	last_shot_kind = kind
	receiver_bounces = 0
	serve_in_play = false
	wall_since_bounce = false
	since_hit = 0.0
	rally_hits += 1
	stats.hits += 1
	assigned = [null, null]
	last_callout = [null, null]
	for o in _team(1 - p.team):
		o.react = randf_range(0.1, 0.3) * (1.3 - o.skill)
		if kind == "globo" and absf(o.position.z) < 5.2:
			o.react += 0.35          # caught at the net: turn and run
	if p.team == 0 and net_role == "" and not practice and not _ai_human() and not combo_armed:
		combo = minf(1.0, combo + (2.0 if q > 0.85 else 1.0) / COMBO_HITS)
	_set_rally(rally_hits)
	_refresh_prediction()


func _print_stats() -> void:
	if net_role == "client":
		print("=== client: %d snapshots, rtt %d ms, score sets %s games %s pts %s/%s" % [stats.snapshots, rtt_ms, score.sets, score.games, score.point_text(0), score.point_text(1)])
		return
	var rallies: Array = stats.rallies
	var total := 0
	var longest := 0
	for r in rallies:
		total += r
		longest = maxi(longest, r)
	var avg := float(total) / maxf(1.0, rallies.size())
	print("=== %d points, %d hits, %d faults, avg rally %.1f, longest %d" % [stats.points, stats.hits, stats.faults, avg, longest])
	print("=== score: sets %s games %s  history %s" % [score.sets, score.games, score.set_history])
	print("=== reasons: %s" % [stats.reasons])

