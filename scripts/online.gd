class_name Online
extends Node
## Online play through the relay server: random quick match, or a private
## game joined with a 4-letter code. Owns the RelayPeer until two phones are
## paired, then hands it to Godot's multiplayer so the match RPCs flow.

signal status(text: String)
signal room_code(code: String)
signal matched(is_host: bool, length: String, golden: bool, size: int)
signal failed(msg: String)

## The deployed relay. Must be wss:// with a hostname (Apple review uses
## IPv6-only networks, and both stores expect encrypted traffic).
const RELAY_URL := "wss://padel-relay.fly.dev"
## Online play on/off. Off until the relay is deployed: hides Play online from
## the menu, the online rows in Stats, and the two online achievements.
const ENABLED := false

var url := RELAY_URL
var peer: RelayPeer
var searching_since := -1.0   # seconds (engine time) a quick-match search began; -1 = not searching


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_active() -> bool:
	return peer != null


func search_seconds() -> float:
	if searching_since < 0.0:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - searching_since


func quick(length := "quick") -> void:
	if _start():
		status.emit("Connecting…")
		peer.send_control({"t": "quick", "length": length, "rating": Profile.rating()})


## size: 2 = you vs a friend (AI partners), 4 = doubles with up to four phones.
func create(length: String, golden: bool, size := 2) -> void:
	if _start():
		status.emit("Creating your game…")
		peer.send_control({"t": "create", "length": length, "golden": golden, "size": size})


## Host of a doubles room: stop taking players and play (AI fills the gaps).
func start_room() -> void:
	if peer:
		peer.send_control({"t": "start"})


func join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 4:
		failed.emit("Codes are 4 letters, like K7QF.")
		return
	if _start():
		status.emit("Joining %s…" % code)
		peer.send_control({"t": "join", "code": code})


func close() -> void:
	searching_since = -1.0
	if peer == null:
		return
	if multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	peer = null


func _start() -> bool:
	close()
	peer = RelayPeer.new()
	peer.queued.connect(func() -> void:
		searching_since = Time.get_ticks_msec() / 1000.0
		status.emit("Finding an opponent…"))
	peer.room_created.connect(func(code: String) -> void: room_code.emit(code))
	peer.matched.connect(_on_matched)
	peer.relay_error.connect(_on_error)
	var err := peer.open(url)
	if err != OK:
		peer = null
		failed.emit("Couldn't reach the game server (error %d)." % err)
		return false
	return true


func _on_error(code: String, msg: String) -> void:
	failed.emit(msg)
	if code in ["offline", "version", "expired"]:
		close()


func _on_matched(is_host: bool, length: String, golden: bool, size: int) -> void:
	searching_since = -1.0
	multiplayer.multiplayer_peer = peer
	matched.emit(is_host, length, golden, size)
	# RelayPeer then announces the other phones (peer_connected) as they arrive


func _process(_delta: float) -> void:
	# before pairing, nobody else polls the socket
	if peer and multiplayer.multiplayer_peer != peer:
		peer.poll()

