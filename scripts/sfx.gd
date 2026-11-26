class_name Sfx
extends Node
## Sound effects: a small pool of positional players for ball sounds, and a
## flat player for the crowd and UI. Muted through Profile's sound setting.

const SOUNDS := ["paddle", "smash", "floor", "glass", "mesh", "net", "squeak", "click", "ding", "buzz", "applause", "applause_big", "whoosh", "success", "unlock"]
const POOL := 10

static var instance: Sfx

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _flat: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _react: AudioStreamPlayer
var _reacts := {}            # "ooh" | "groan" -> [AudioStream]: assets/sfx/crowd_ooh*.ogg, crowd_groan*.ogg
var crowd_level := 0.6     # venue crowd size: 0.5 club .. 1.0 arena
var log_on := false        # main.gd records ball sounds for the replay
var log: Array = []        # [sound, pos, volume_db] since last read
var _duck: Tween


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SOUNDS:
		for ext in ["ogg", "wav"]:   # recorded clips are OGG; synthesised ones WAV
			var path := "res://assets/sfx/%s.%s" % [s, ext]
			if ResourceLoader.exists(path):
				_streams[s] = load(path)
				break
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_db = 3.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool.append(p)
	_flat = AudioStreamPlayer.new()
	add_child(_flat)
	_sting = AudioStreamPlayer.new()     # success / unlock: never cut off by a click
	add_child(_sting)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	_react = AudioStreamPlayer.new()
	add_child(_react)
	_load_voices()
	apply_settings()


func apply_settings() -> void:
	AudioServer.set_bus_mute(0, not Profile.sound())


## A sound at a point on court, slightly varied so repeats don't grate.
func at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	if log_on:
		log.append([sound, pos, volume_db])
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.global_position = pos
	p.volume_db = volume_db + randf_range(-1.5, 1.0)
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## Players' shouts after a big point: any assets/sfx/voice_*.ogg|wav, picked
## at random (none = silent).
var _voices: Array = []
var _last_voice := -1


func _load_voices() -> void:
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null:
		return
	var seen := {}
	for f in dir.get_files():
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not (f.ends_with(".ogg") or f.ends_with(".wav")) or seen.has(f):
			continue
		seen[f] = true
		for kind: String in ["voice", "crowd_ooh", "crowd_groan"]:
			if f.begins_with(kind):
				var r := load("res://assets/sfx/" + f)
				if r == null:
					continue
				if kind == "voice":
					_voices.append(r)
				else:
					var k: String = kind.trim_prefix("crowd_")
					if not _reacts.has(k):
						_reacts[k] = []
					_reacts[k].append(r)


func voice(pos: Vector3, volume_db := 0.0) -> void:
	if _voices.is_empty():
		return
	var i := randi() % _voices.size()
	if _voices.size() > 1 and i == _last_voice:
		i = (i + 1) % _voices.size()
	_last_voice = i
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _voices[i]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.97, 1.04)
	p.play()


func ui(sound := "click", volume_db := -4.0) -> void:
	if _streams.has(sound):
		var pl := _sting if sound in ["success", "unlock"] else _flat
		if pl == _sting and _sting.playing and _sting.stream == _streams["success"]:
			pl = _flat           # an achievement during the success jingle: both play
		pl.stream = _streams[sound]
		pl.volume_db = volume_db
		pl.pitch_scale = 1.0
		pl.play()


## Applause after a point: bigger for long rallies and big shots.
func crowd(big := false) -> void:
	var key := "applause_big" if big else "applause"
	if _streams.has(key):
		_crowd.stream = _streams[key]
		_crowd.volume_db = linear_to_db(clampf(crowd_level * (1.0 if big else 0.8), 0.05, 1.0)) - 4.2   # about 13 % quieter than first mixed
		_crowd.pitch_scale = randf_range(0.95, 1.05)
		if _duck and _duck.is_valid():
			_duck.kill()
		_crowd.play()


## The crowd reacting: "ooh" (a great get, a ball out of the court) or
## "groan" (a long rally thrown away). Louder in bigger venues; silent when
## the clips aren't there.
func react(kind: String) -> void:
	var list: Array = _reacts.get(kind, [])
	if list.is_empty():
		return
	_react.stream = list[randi() % list.size()]
	_react.volume_db = linear_to_db(clampf(crowd_level, 0.05, 1.0)) - 3.0
	_react.pitch_scale = randf_range(0.96, 1.04)
	_react.play()
	if kind == "groan" and _crowd.playing:
		duck_crowd(0.3)


## Fade the crowd out (a replay is starting).
func duck_crowd(secs := 0.5) -> void:
	if not _crowd.playing:
		return
	if _duck and _duck.is_valid():
		_duck.kill()
	_duck = create_tween()
	_duck.tween_property(_crowd, "volume_db", -40.0, secs)
	_duck.tween_callback(_crowd.stop)


static func play_ui(sound := "click") -> void:
	if instance:
		instance.ui(sound)
