class_name MatchScore
extends RefCounted
## Padel scoring: 15/30/40, golden point at 40-40 (or advantage),
## sets to `games_per_set` won by 2, tie-break to 7 when level there,
## first to `sets_to_win` sets.

const POINT_NAMES := ["0", "15", "30", "40"]

var golden_point := true
var sets_to_win := 2
var games_per_set := 6     # 4 for a quick match
var points := [0, 0]
var games := [0, 0]
var sets := [0, 0]
var set_history: Array = []
var games_played := 0
var tiebreak := false
var winner := -1


static func create(p_games_per_set: int, p_sets_to_win: int, p_golden: bool) -> MatchScore:
	var s := MatchScore.new()
	s.games_per_set = p_games_per_set
	s.sets_to_win = p_sets_to_win
	s.golden_point = p_golden
	return s


func points_in_game() -> int:
	return points[0] + points[1]


## Returns "point", "game", "set" or "match".
func point_won(team: int) -> String:
	if winner != -1:
		return "match"
	var o := 1 - team
	points[team] += 1
	if tiebreak:
		if points[team] >= 7 and points[team] - points[o] >= 2:
			return _game_won(team)
		return "point"
	if points[team] >= 4:
		if golden_point or points[team] - points[o] >= 2:
			return _game_won(team)
		if points[team] == points[o]:
			points = [3, 3]   # back to deuce
	return "point"


func _game_won(team: int) -> String:
	var o := 1 - team
	var was_tiebreak := tiebreak
	games[team] += 1
	games_played += 1
	points = [0, 0]
	tiebreak = false
	if was_tiebreak or (games[team] >= games_per_set and games[team] - games[o] >= 2):
		sets[team] += 1
		set_history.append(games.duplicate())
		games = [0, 0]
		if sets[team] >= sets_to_win:
			winner = team
			return "match"
		return "set"
	if games[0] == games_per_set and games[1] == games_per_set:
		tiebreak = true
	return "game"


func point_text(team: int) -> String:
	if tiebreak:
		return str(points[team])
	var p: int = points[team]
	var o: int = points[1 - team]
	if not golden_point and p >= 3 and o >= 3:
		if p > o:
			return "AD"
		return "40"
	return POINT_NAMES[mini(p, 3)]


func is_golden_point() -> bool:
	return golden_point and not tiebreak and points[0] == 3 and points[1] == 3
