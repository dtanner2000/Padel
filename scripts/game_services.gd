class_name GameServices
extends RefCounted
## Game Center on iOS, through the GodotApplePlugins GameCenter extension
## (fetched by the Codemagic iOS build, not kept in the repo). Everything is
## looked up by name, so the editor, desktop and Android builds run without it
## and every call here is simply a no-op there.
##
## Create these in App Store Connect → your app → Game Center with the SAME ids:
##   achievements: the ids in Awards.list()
##   leaderboards: the ids in BOARDS below (all "best score", high is better)

const BOARDS := {
	"daily_best": "Daily challenge: best goals",
	"longest_rally": "Longest rally",
	"online_rating": "Online rating",
}

static var _gc: Object = null          # GameCenterManager
static var _signed_in := false
static var _sent := {}                 # board -> last value sent this session


static func available() -> bool:
	return OS.get_name() == "iOS" and ClassDB.class_exists("GameCenterManager")


static func signed_in() -> bool:
	return _signed_in


## Call once at startup. iOS shows its own sign-in sheet if needed; after that
## every unlocked achievement and current best is sent and the current bests synced.
static func sign_in() -> void:
	if not available() or _gc != null:
		return
	_gc = ClassDB.instantiate("GameCenterManager")
	_gc.connect("authentication_result", func(ok: bool) -> void:
		_signed_in = ok
		if ok:
			_sync_all())
	_gc.connect("authentication_error", func(msg: String) -> void:
		print("Game Center: ", msg))
	_gc.call("authenticate")


static func achievement(id: String) -> void:
	if not available():
		return
	if not _signed_in:
		return   # sent on sign-in: _sync_all() reports everything unlocked
	var a: Object = ClassDB.instantiate("GKAchievement")
	a.set("identifier", id)
	a.set("percent_complete", 100.0)
	a.set("shows_completion_banner", true)
	ClassDB.class_call_static("GKAchievement", "report_achievement", [a], func(err: Variant) -> void:
		if err != null:
			print("Game Center achievement %s: %s" % [id, err]))


static func score(board: String, value: int) -> void:
	if not available() or value <= 0 or value == _sent.get(board, -1):
		return
	if not _signed_in:
		return   # sent on sign-in by _sync_all()
	_sent[board] = value
	ClassDB.class_call_static("GKLeaderboard", "load_leaderboards", PackedStringArray([board]), func(boards: Array, err: Variant) -> void:
		if err != null or boards.is_empty():
			print("Game Center board %s: %s" % [board, err])
			_sent.erase(board)
			return
		boards[0].call("submit_score", value, 0, _gc.get("local_player"), func(e: Variant) -> void:
			if e != null:
				print("Game Center score %s: %s" % [board, e])))


## The Game Center dashboard (leaderboards + achievements), over the game.
static func show_dashboard() -> void:
	if not _signed_in:
		return
	ClassDB.class_call_static("GKGameCenterViewController", "show_type", 4)   # DASHBOARD


static func _sync_all() -> void:
	# everything earned so far (re-reporting a finished achievement is harmless)
	for a in Awards.list():
		if Awards.unlocked(a[0]):
			achievement(a[0])
	submit_bests()


## Current bests to the leaderboards; unchanged values aren't re-sent.
static func submit_bests() -> void:
	score("daily_best", Profile.stat("daily_best"))
	score("longest_rally", Profile.stat("longest_rally"))
	if Profile.stat("online_matches") > 0:
		score("online_rating", Profile.rating())


## Apple's rating prompt (StoreKit plugin), after a win: on the first win,
## the third and the tenth, never twice in a day. iOS decides whether it
## actually shows (at most three times a year).
static func maybe_ask_review() -> void:
	if OS.get_name() != "iOS" or not ClassDB.class_exists("StoreKitManager"):
		return
	var wins := Profile.stat("wins")
	if not wins in [1, 3, 10, 25]:
		return
	var today := Profile.today()
	if Profile.get_v("review", "asked", "") == today:
		return
	Profile.set_v("review", "asked", today)
	Profile.save()
	var sk: Object = ClassDB.instantiate("StoreKitManager")
	sk.call("request_review")
