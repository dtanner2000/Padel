class_name Roster
extends RefCounted
## Characters you can play as or partner with, and the career venues.

## style changes how the AI plays them and gives a small edge when you play
## as them offline: power = harder drives and smashes, touch = cleaner timing,
## speed = quicker about the court, all-round = a bit of everything.
const CHARACTERS := [
	{"id": "dani", "name": "DANI", "style": "All-rounder", "desc": "No weak side. Solid from the back and at the net.",
		"skin": Color("e3b48c"), "hair": Color("3a2a20")},
	{"id": "ana", "name": "ANA", "style": "Touch", "desc": "Lobs, slices and clean timing. Hard to hurry.",
		"skin": Color("d9a47c"), "hair": Color("5a3a26")},
	{"id": "marco", "name": "MARCO", "style": "Power", "desc": "Big smashes and heavy drives.",
		"skin": Color("e0b48e"), "hair": Color("3b2b22")},
	{"id": "leo", "name": "LEO", "style": "Speed", "desc": "Covers every corner. Gets to balls others can't.",
		"skin": Color("8d5a3c"), "hair": Color("1e1a18")},
]


static func character(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c.id == id:
			return c
	return CHARACTERS[0]


## Your team and the rivals: [me, partner, rival1, rival2] ids.
static func lineup(me: String, partner: String) -> Array:
	if partner == me:
		partner = "ana" if me != "ana" else "dani"
	var out := [me, partner]
	for c in CHARACTERS:
		if not c.id in out:
			out.append(c.id)
	return out


const ROUNDS := ["Quarter-final", "Semi-final", "Final"]

## Career venues, in unlock order. rivals = AI skill per round (before the
## difficulty setting), partner = your partner's skill there.
const VENUES := [
	{"id": "club", "name": "Club Night", "sub": "Your local club, under the lights",
		"court": Color("1d64a6"), "apron": Color("13263d"), "bg": Color("0c1a2e"), "ambient": Color("9fb6d6"),
		"ambient_e": 0.45, "sun": 0.85, "lamps": 0.28, "rivals": [0.52, 0.58, 0.64], "partner": 0.72, "crowd": 0.5},
	{"id": "regional", "name": "Regional Open", "sub": "Outdoors on a sunny afternoon",
		"court": Color("2f7d4e"), "apron": Color("2b4a33"), "bg": Color("8fc3e8"), "ambient": Color("dfe9f2"),
		"ambient_e": 0.75, "sun": 1.25, "lamps": 0.0, "rivals": [0.62, 0.67, 0.72], "partner": 0.76, "crowd": 0.65},
	{"id": "national", "name": "National Championship", "sub": "Sunset on the clay-red court",
		"court": Color("b04a2f"), "apron": Color("4a2a22"), "bg": Color("e48a5a"), "ambient": Color("ffd2b0"),
		"ambient_e": 0.6, "sun": 1.0, "lamps": 0.12, "rivals": [0.7, 0.75, 0.8], "partner": 0.8, "crowd": 0.8},
	{"id": "world", "name": "World Tour Finals", "sub": "Centre court, packed arena",
		"court": Color("5a3fa8"), "apron": Color("1a1430"), "bg": Color("07060f"), "ambient": Color("b9a8ff"),
		"ambient_e": 0.4, "sun": 0.7, "lamps": 0.42, "rivals": [0.78, 0.83, 0.9], "partner": 0.84, "crowd": 1.0},
]


static func venue(id: String) -> Dictionary:
	for v in VENUES:
		if v.id == id:
			return v
	return VENUES[0]
