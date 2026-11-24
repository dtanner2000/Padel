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
		"ambient_e": 0.45, "sun": 0.85, "lamps": 0.28, "rivals": [0.52, 0.58, 0.64], "partner": 0.72, "crowd": 0.5,
		"scene": "hall", "wind": 0.0},
	{"id": "regional", "name": "Regional Open", "sub": "Outdoors on a sunny afternoon",
		"court": Color("2f7d4e"), "apron": Color("2b4a33"), "bg": Color("8fc3e8"), "ambient": Color("dfe9f2"),
		"ambient_e": 0.75, "sun": 1.25, "lamps": 0.0, "rivals": [0.62, 0.67, 0.72], "partner": 0.76, "crowd": 0.65,
		"scene": "park", "wind": 0.7},
	{"id": "national", "name": "National Championship", "sub": "Sunset on the beach, clay-red court",
		"court": Color("b04a2f"), "apron": Color("4a2a22"), "bg": Color("e48a5a"), "ambient": Color("ffd2b0"),
		"ambient_e": 0.6, "sun": 1.0, "lamps": 0.12, "rivals": [0.7, 0.75, 0.8], "partner": 0.8, "crowd": 0.8,
		"scene": "beach", "wind": 1.1},
	{"id": "world", "name": "World Tour Finals", "sub": "Panoramic glass court, packed arena",
		"court": Color("5a3fa8"), "apron": Color("1a1430"), "bg": Color("07060f"), "ambient": Color("b9a8ff"),
		"ambient_e": 0.4, "sun": 0.7, "lamps": 0.42, "rivals": [0.78, 0.83, 0.9], "partner": 0.84, "crowd": 1.0,
		"scene": "arena", "wind": 0.0, "panoramic": true},
]

## Courts for quick play only (not in the career), open from the start.
const EXTRA_VENUES := [
	{"id": "rooftop", "name": "City Rooftop", "sub": "Yellow court above the city lights, breezy",
		"court": Color("d9b21f"), "apron": Color("2b2f36"), "bg": Color("0b1022"), "ambient": Color("aab8e8"),
		"ambient_e": 0.5, "sun": 0.6, "lamps": 0.32, "rivals": [0.68, 0.7, 0.72], "partner": 0.74, "crowd": 0.35,
		"scene": "rooftop", "wind": 1.4},
]

const COURT_COLOURS := {"blue": Color("1d64a6"), "green": Color("2f7d4e"), "red": Color("b04a2f"),
	"yellow": Color("d9b21f"), "purple": Color("5a3fa8"), "pink": Color("d05a8f")}


static func venue(id: String) -> Dictionary:
	for v in VENUES + EXTRA_VENUES:
		if v.id == id:
			return v
	return VENUES[0]


## Paddles. Real padel paddles trade control for power by shape: round
## (big sweet spot, forgiving), teardrop (balanced), diamond (power, smaller
## sweet spot). Effects apply to you offline only (online is even):
##   power  = m/s added to drives, smashes and víboras
##   touch  = timing-quality bonus (negative = a smaller sweet spot)
##   charge = SMASH charges this much faster
##   unlock = career title that unlocks it ("" = from the start)
const PADDLES := [
	{"id": "club", "name": "Club Round", "shape": "round", "face": Color("1a1d22"), "trim": Color("c6f432"),
		"power": 0.0, "touch": 0.0, "charge": 0.0, "unlock": "", "desc": "Your first paddle. Forgiving and honest."},
	{"id": "teardrop", "name": "Teardrop Pro", "shape": "teardrop", "face": Color("12324f"), "trim": Color("4fc3f7"),
		"power": 0.8, "touch": 0.02, "charge": 0.1, "unlock": "club", "desc": "Balanced: a little more of everything."},
	{"id": "diamond", "name": "Diamond Power", "shape": "diamond", "face": Color("3a0d12"), "trim": Color("ff5a4f"),
		"power": 2.2, "touch": -0.04, "charge": 0.25, "unlock": "regional", "desc": "Heavy hitter. Time it well or it flies."},
	{"id": "control", "name": "Carbon Control", "shape": "round", "face": Color("202020"), "trim": Color("e9e9e9"),
		"power": 0.4, "touch": 0.07, "charge": 0.1, "unlock": "national", "desc": "Huge sweet spot. Placement over pace."},
	{"id": "tour", "name": "Tour Diamond", "shape": "diamond", "face": Color("2b1a4d"), "trim": Color("ffd34d"),
		"power": 2.6, "touch": 0.0, "charge": 0.3, "unlock": "world", "desc": "The champions' paddle. Power without the penalty."},
]


static func paddle(id: String) -> Dictionary:
	for p in PADDLES:
		if p.id == id:
			return p
	return PADDLES[0]


## Player skills you level up offline with skill points (max level 5 each).
## Per level: power +0.35 m/s, speed +1.6 %, reach +3 cm, touch +0.012 timing.
const SKILLS := [
	["power", "Power", "Harder drives and smashes"],
	["speed", "Speed", "Quicker about the court"],
	["reach", "Reach", "Get to wider balls"],
	["touch", "Touch", "A bigger sweet spot"],
]
const SKILL_MAX := 5


## Signature shots and the career title that unlocks each.
const SHOTS := {
	"vibora": {"name": "Víbora", "unlock": "club",
		"how": "On a high ball, flick HIT sideways: a sliced overhead that skids low off the side glass."},
	"chiquita": {"name": "Chiquita", "unlock": "regional",
		"how": "Swipe HIT down: a soft dipping ball at the feet of players at the net."},
	"contrapared": {"name": "Contrapared", "unlock": "national",
		"how": "Beaten by a deep ball? Tap HIT as it passes you to play it into your own back glass and over the net."},
}


## Online rating tiers (Elo, everyone starts at 1000).
const TIERS := [[0, "Bronze"], [1050, "Silver"], [1150, "Gold"], [1300, "Platinum"], [1500, "Diamond"]]


static func tier(rating: int) -> String:
	var name := "Bronze"
	for t in TIERS:
		if rating >= t[0]:
			name = t[1]
	return name


## Cosmetics, bought with coins earned by playing. Looks only.
const HATS := [["", "None", 0], ["headband", "Headband", 80], ["visor", "Visor", 120], ["cap", "Cap", 150]]
const WRISTBAND_PRICE := 60
const PALETTE := [Color("f2f2f2"), Color("1a1d22"), Color("c6f432"), Color("ff5a4f"), Color("4fc3f7"),
	Color("ffd34d"), Color("b07cff"), Color("ff8fc7")]
## Paddle colourways over your paddle's shape: [id, name, face, trim, price].
const SKINS := [
	["", "Original", Color.BLACK, Color.BLACK, 0],
	["ice", "Ice", Color("dff3ff"), Color("4fc3f7"), 100],
	["lava", "Lava", Color("2a0a08"), Color("ff6a2a"), 100],
	["mint", "Mint", Color("10302a"), Color("6dffc2"), 100],
	["gold", "Gold", Color("1a1406"), Color("ffd34d"), 160],
	["neon", "Neon", Color("0c0c14"), Color("ff3df2"), 160],
]
