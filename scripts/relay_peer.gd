class_name RelayPeer
extends MultiplayerPeerExtension
## Godot multiplayer transport that runs over the Padel relay server
## (server/relay.js) using a secure WebSocket. Once phones are paired, the
## host is peer 1 and guests are peers 2..4, and Godot's normal RPCs work
## exactly as they would over a direct connection. Every frame carries a slot
## byte: the target on the way out, the sender on the way in.
##
## WebSockets work through any home router or mobile network (no NAT or
## port-forwarding problems) and, using wss:// with a hostname, meet Apple's
## secure-transport and IPv6-only review requirements.

signal queued
signal room_created(code: String)
signal matched(is_host: bool, length: String, golden: bool, size: int)
signal relay_error(code: String, msg: String)
signal closed

const PROTOCOL := 3          # must match PROTOCOL in server/relay.js
const HOST_ID := 1

var _ws := WebSocketPeer.new()
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _socket_open := false
var _paired := false
var _is_host := false
var _my_id := 0
var _peers: Array[int] = []   # host: the guests; guest: [1]
var _pending: Array[String] = []
var _queue: Array = []        # [payload, channel, mode, from]
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _was_open := false


func open(url: String) -> Error:
	_ws.inbound_buffer_size = 256 * 1024
	_ws.outbound_buffer_size = 256 * 1024
	var err := _ws.connect_to_url(url)
	if err == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return err


func is_paired() -> bool:
	return _paired


func is_host() -> bool:
	return _is_host


func send_control(msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	if _socket_open:
		_ws.send_text(text)
	else:
		_pending.append(text)


# --- MultiplayerPeerExtension ---------------------------------------------------

func _poll() -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _socket_open:
			_socket_open = true
			_was_open = true
			_ws.send_text(JSON.stringify({"t": "hello", "v": PROTOCOL}))
			for text in _pending:
				_ws.send_text(text)
			_pending.clear()
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_on_control(pkt.get_string_from_utf8())
			elif _paired and pkt.size() >= 3:
				_queue.append([pkt.slice(3), pkt[1], pkt[2], pkt[0]])
	elif st == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was_paired := _paired
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		_socket_open = false
		_paired = false
		if was_paired:
			for id in _peers.duplicate():
				peer_disconnected.emit(id)
			_peers.clear()
		if not _was_open:
			relay_error.emit("offline", "Couldn't reach the game server. Check your internet connection.")
		closed.emit()


func _on_control(text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY:
		return
	match str(m.get("t", "")):
		"queued":
			queued.emit()
		"room":
			room_created.emit(str(m.get("code", "")))
		"matched":
			_is_host = bool(m.get("host", false))
			_my_id = int(m.get("id", 1 if _is_host else 2))
			_paired = true
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			matched.emit(_is_host, str(m.get("length", "quick")), bool(m.get("golden", true)), int(m.get("size", 2)))
			if not _is_host:
				_peers = [HOST_ID]
				peer_connected.emit(HOST_ID)
		"joined":
			var id := int(m.get("id", 0))
			if _is_host and id > 1 and not id in _peers:
				_peers.append(id)
				peer_connected.emit(id)
		"left":
			var id := int(m.get("id", 0))
			if id in _peers:
				_peers.erase(id)
				peer_disconnected.emit(id)
			if not _is_host and id == HOST_ID:
				_paired = false
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		"error":
			relay_error.emit(str(m.get("code", "")), str(m.get("msg", "Something went wrong.")))


func peers() -> Array[int]:
	return _peers


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front()[0]


func _get_packet_peer() -> int:
	return HOST_ID if _queue.is_empty() else _queue[0][3]


func _get_packet_channel() -> int:
	return 0 if _queue.is_empty() else _queue[0][1]


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE if _queue.is_empty() else _queue[0][2]


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if not _paired or not _socket_open:
		return ERR_UNCONFIGURED
	# 0 = everyone; a negative target means "everyone but that peer", which the
	# relay can't express, so it goes to everyone (receivers ignore stray RPCs)
	var to := _target if _target > 0 else 0
	if to > 0 and not to in _peers:
		return ERR_INVALID_PARAMETER
	var frame := PackedByteArray([to, _channel, _mode])
	frame.append_array(p_buffer)
	return _ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY)


func _get_max_packet_size() -> int:
	return 60 * 1024


func _set_target_peer(p_peer: int) -> void:
	_target = p_peer


func _get_unique_id() -> int:
	return _my_id if _my_id > 0 else (HOST_ID if _is_host else 2)


func _is_server() -> bool:
	return _is_host


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_mode = p_mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
	_close()


func _close() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close(1000, "bye")
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_socket_open = false
	_paired = false
	_peers.clear()
	_queue.clear()
