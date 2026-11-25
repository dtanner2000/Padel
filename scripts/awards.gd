class_name Awards
extends RefCounted
## Achievements: checked against the saved profile after anything notable.
## Each pays coins, and unlocks go to Game Center on iOS (see report()).

const COINS := 50

## id, title, description, test(ctx) where ctx has "drills" (training drills done).
static func list() -> Array:
	if Online.ENABLED:
		return _all()
	return _all().filter(func(a: Array) -> bool: return not a[0] in ["online_win", "gold_tier"])


static func _all() -> Array:
	return [
		["first_win", "First win", "Win a match", func(_c: Dictionary) -> bool: return Profile.stat("wins") >= 1],
		["ten_wins", "Regular", "Win 10 matches", func(_c: Dictionary) -> bool: return Profile.stat("wins") >= 10],
		["rally_20", "Rally builder", "Play a 20-shot rally", func(_c: Dictionary) -> bool: return Profile.stat("longest_rally") >= 20],
		["rally_40", "Marathon point", "Play a 40-shot rally", func(_c: Dictionary) -> bool: return Profile.stat("longest_rally") >= 40],
		["power_5", "Por tres", "Hit 5 power smashes", func(_c: Dictionary) -> bool: return Profile.stat("power_smashes") >= 5],
		["bajada_10", "Off the glass", "Hit 10 bajadas", func(_c: Dictionary) -> bool: return Profile.stat("bajadas") >= 10],
		["perfect_50", "Sweet spot", "50 perfect hits", func(_c: Dictionary) -> bool: return Profile.stat("perfect") >= 50],
		["slice_50", "Backspin", "Hit 50 slices", func(_c: Dictionary) -> bool: return Profile.stat("slices") >= 50],
		["vibora_10", "Snake bite", "Hit 10 víboras", func(_c: Dictionary) -> bool: return Profile.stat("vibora") >= 10],
		["chiquita_10", "Soft hands", "Hit 10 chiquitas", func(_c: Dictionary) -> bool: return Profile.stat("chiquita") >= 10],
		["contrapared_5", "Escape artist", "Hit 5 contraparedes", func(_c: Dictionary) -> bool: return Profile.stat("contrapared") >= 5],
		["title_club", "Club champion", "Win Club Night", func(_c: Dictionary) -> bool: return Profile.career_won("club")],
		["title_regional", "Regional champion", "Win the Regional Open", func(_c: Dictionary) -> bool: return Profile.career_won("regional")],
		["title_national", "National champion", "Win the National Championship", func(_c: Dictionary) -> bool: return Profile.career_won("national")],
		["title_world", "World champion", "Win the World Tour Finals", func(_c: Dictionary) -> bool: return Profile.career_won("world")],
		["drills_all", "Student of the game", "Complete every training drill", func(c: Dictionary) -> bool: return c.get("drills", 0) >= c.get("drills_total", 99)],
		["daily_5", "On target", "Score 5 in a daily challenge", func(_c: Dictionary) -> bool: return Profile.stat("daily_best") >= 5],
		["daily_10", "Sharpshooter", "Score 10 in a daily challenge", func(_c: Dictionary) -> bool: return Profile.stat("daily_best") >= 10],
		["dejada_10", "Feather touch", "Hit 10 dejadas", func(_c: Dictionary) -> bool: return Profile.stat("dejada") >= 10],
		["globo_10", "Over the top", "Hit 10 globos", func(_c: Dictionary) -> bool: return Profile.stat("globo") >= 10],
		["por_cuatro_1", "Por cuatro", "Smash one out over the side wall", func(_c: Dictionary) -> bool: return Profile.stat("por_cuatro") >= 1],
		["combo_5", "Better together", "Finish 5 partner combos", func(_c: Dictionary) -> bool: return Profile.stat("combos") >= 5],
		["online_win", "Worldwide", "Win an online match", func(_c: Dictionary) -> bool: return Profile.stat("online_wins") >= 1],
		["gold_tier", "Gold", "Reach Gold online (1150)", func(_c: Dictionary) -> bool: return Profile.rating() >= 1150],
		["maxed", "Maxed out", "Take any skill to level 5", func(_c: Dictionary) -> bool:
			for s in Roster.SKILLS:
				if Profile.skill(s[0]) >= Roster.SKILL_MAX:
					return true
			return false],
	]


static func unlocked(id: String) -> bool:
	return Profile.get_v("awards", id, false)


## Unlock anything newly earned; returns their titles (and pays the coins).
static func check(ctx: Dictionary) -> Array:
	var fresh: Array = []
	for a in list():
		if unlocked(a[0]):
			continue
		if (a[3] as Callable).call(ctx):
			Profile.set_v("awards", a[0], true)
			Profile.add_stat("coins", COINS)
			fresh.append(a[1])
			report(a[0])
	if not fresh.is_empty():
		Profile.save()
	return fresh


## Game Center (GameServices) / Play Games, when their plugins are in the build.
## Create the achievements in App Store Connect / Play Console with these same ids.
static func report(id: String) -> void:
	GameServices.achievement(id)
	if Engine.has_singleton("GodotPlayGameServices"):
		Engine.get_singleton("GodotPlayGameServices").call("achievementsUnlock", id, true)
