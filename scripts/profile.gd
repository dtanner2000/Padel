class_name Profile
extends RefCounted
## The player's saved profile: settings, chosen team, career progress, stats
## and daily-challenge scores. One ConfigFile at user://profile.cfg.

const PATH := "user://profile.cfg"
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

static var cfg := ConfigFile.new()
static var _loaded := false
static var dirty := false


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		cfg.load(PATH)   # a missing file just leaves the defaults


static func get_v(section: String, key: String, default: Variant = null) -> Variant:
	_ensure()
	return cfg.get_value(section, key, default)


static func set_v(section: String, key: String, value: Variant) -> void:
	_ensure()
	cfg.set_value(section, key, value)
	dirty = true


static func save() -> void:
	if dirty:
		cfg.save(PATH)
		dirty = false


# --- settings -------------------------------------------------------------------

static func sound() -> bool: return get_v("settings", "sound", true)
static func haptics() -> bool: return get_v("settings", "haptics", true)
static func left_handed() -> bool: return get_v("settings", "left_handed", false)
static func button_scale() -> float: return [0.85, 1.0, 1.2][int(get_v("settings", "button_size", 1))]
static func difficulty() -> int: return int(get_v("settings", "difficulty", 1))
static func golden_point() -> bool: return get_v("settings", "golden_point", true)


static func vibrate(ms: int) -> void:
	if haptics():
		Input.vibrate_handheld(ms)


# --- team -----------------------------------------------------------------------

static func character() -> String: return get_v("team", "me", "dani")
static func partner() -> String: return get_v("team", "partner", "ana")


# --- stats ----------------------------------------------------------------------

static func stat(key: String) -> int:
	return int(get_v("stats", key, 0))


static func add_stat(key: String, n := 1) -> void:
	set_v("stats", key, stat(key) + n)


static func max_stat(key: String, v: int) -> void:
	if v > stat(key):
		set_v("stats", key, v)


# --- career ---------------------------------------------------------------------

## Rounds won in this venue's current run (0..Roster.ROUNDS.size()).
static func career_round(venue: String) -> int: return int(get_v("career", venue + "_round", 0))
static func career_won(venue: String) -> bool: return get_v("career", venue + "_won", false)


static func venue_unlocked(i: int) -> bool:
	return i == 0 or career_won(Roster.VENUES[i - 1].id)


# --- daily challenge --------------------------------------------------------------

static func today() -> String:
	return Time.get_date_string_from_system()


static func daily_best(date := "") -> int:
	return int(get_v("daily", date if date != "" else today(), 0))


# --- paddles, skills, shots, side, rating ------------------------------------------

static func paddle_id() -> String: return get_v("kit", "paddle", "club")


static func paddle_owned(id: String) -> bool:
	var u: String = Roster.paddle(id).unlock
	return u == "" or career_won(u)


static func skill(id: String) -> int: return int(get_v("skills", id, 0))


## Skill points: earned minus spent.
static func skill_points() -> int:
	var spent := 0
	for s in Roster.SKILLS:
		spent += skill(s[0])
	return stat("skill_points_earned") - spent


static func shot_unlocked(id: String) -> bool:
	return career_won(Roster.SHOTS[id].unlock) or get_v("debug", "all_shots", false)


## "left" (revés side) or "right" (drive side) of your team's half.
static func side() -> String: return get_v("team", "side", "left")


static func rating() -> int: return int(get_v("online", "rating", 1000))
