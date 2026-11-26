class_name PlayBilling
extends Node
## Google Play Billing for Remove Ads, through the openiap godot-iap plugin
## (addons/godot-iap: an Android plugin AAR that registers the "GodotIap"
## engine singleton; the GodotIapPlugin autoload wraps it). Android only;
## iOS goes through StoreKit in store.gd.
##
## Ported from Jetpack Attack's IapBackend.gd, where every one of these rules
## was found on a device (its notes/IAP_PLAN.md and PLAY_PLAN.md):
## * talk to the plugin's `_raw` functions and await everything: the public
##   wrappers return coroutines and read results off them wrongly;
## * the purchase request needs the "google" payload with a LIST of skus;
## * the purchase itself arrives on `purchase_updated`, possibly much later
##   (a pending card payment) or at launch (bought on another device);
## * every purchase must be ACKNOWLEDGED (finish_transaction_dict, not
##   consumable) or Play refunds it automatically after three days;
## * a call that crosses to the native side can hang, so each has a timeout.

signal granted(product: String)          # owned: bought now, earlier, or restored
signal status(text: String)              # a line for the Settings screen

const PLUGIN := "GodotIapPlugin"
const CONNECT_TIMEOUT := 25.0
const QUERY_TIMEOUT := 30.0
const PURCHASE_TIMEOUT := 180.0

var products: PackedStringArray = []
var prices := {}                         # product id -> "£1.99"
var _iap: Node = null
var _ready_ok := false
var _connecting := false
var _waiting := ""                       # product being bought


static func supported() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton("GodotIap")


func start(ids: PackedStringArray) -> void:
	products = ids
	_iap = get_tree().root.get_node_or_null(PLUGIN)
	if _iap == null or not supported():
		print("[IAP] Play Billing not available (plugin %s, singleton %s)" % [_iap != null, Engine.has_singleton("GodotIap")])
		return
	_iap.purchase_updated.connect(_on_purchase_updated)
	_iap.purchase_error.connect(_on_purchase_error)
	await _connect()
	await _reconcile()
	await _fetch_prices()


func _connect() -> void:
	if _ready_ok or _connecting or _iap == null:
		return
	_connecting = true
	_ready_ok = _truthy(await _bridge("init_connection", [], CONNECT_TIMEOUT, false))
	_connecting = false
	print("[IAP] Play Billing connection: %s" % ("up" if _ready_ok else "FAILED"))


func _fetch_prices() -> void:
	if not _ready_ok:
		return
	var res = await _bridge("_fetch_products_raw", [{"skus": Array(products), "type": "in-app"}], QUERY_TIMEOUT, {})
	if not (res is Dictionary):
		return
	for p in res.get("products", []):
		if p is Dictionary:
			var id := String(p.get("id", p.get("productId", "")))
			var price := String(p.get("displayPrice", ""))
			if id != "" and price != "":
				prices[id] = price
	print("[IAP] prices: %s" % str(prices))
	status.emit("")


func buy(product: String) -> void:
	if _iap == null:
		status.emit("Purchases work in the Google Play version")
		return
	if not _ready_ok:
		await _connect()
		if _ready_ok:
			await _fetch_prices()
	if not _ready_ok:
		status.emit("Can't reach Google Play right now")
		return
	_waiting = product
	status.emit("Opening Google Play…")
	var res = await _bridge("_request_purchase_raw", [{
		"type": "in-app",
		"requestPurchase": {"apple": {"sku": product}, "google": {"skus": [product]}},
	}], PURCHASE_TIMEOUT, null)
	if _waiting != product:
		return                          # a signal already settled it
	if res is Dictionary and not _truthy(res):
		_waiting = ""
		status.emit("That didn't go through: %s" % String(res.get("error", "the store refused it")))


func restore() -> void:
	if _iap == null:
		status.emit("Purchases work in the Google Play version")
		return
	if not _ready_ok:
		await _connect()
	if not _ready_ok:
		status.emit("Can't reach Google Play right now")
		return
	status.emit("Restoring…")
	await _bridge("restore_purchases", [], QUERY_TIMEOUT, null)
	var n := await _reconcile()
	status.emit("Purchases restored" if n > 0 else "No purchases to restore on this Google account")


## Everything this Google account owns, granted again (and acknowledged, in
## case an earlier run never got to it). Returns how many.
func _reconcile() -> int:
	if not _ready_ok:
		return 0
	var raw = await _bridge("_get_available_purchases_raw", [null], QUERY_TIMEOUT, [])
	var n := 0
	if raw is Array:
		for p in raw:
			if p is Dictionary:
				var id := String(p.get("productId", p.get("id", "")))
				if id in products and _is_purchased(p):
					n += 1
					granted.emit(id)
					if not bool(p.get("isAcknowledgedAndroid", true)):
						await _bridge("finish_transaction_dict", [p, false], QUERY_TIMEOUT, null)
	return n


func _on_purchase_updated(purchase: Dictionary) -> void:
	var id := String(purchase.get("productId", purchase.get("id", "")))
	if id == "" or not (id in products):
		return
	if _waiting == id:
		_waiting = ""
	if not _is_purchased(purchase):
		status.emit("Payment pending: Remove Ads unlocks when it clears")
		return
	granted.emit(id)
	# acknowledge only after granting: a crash in between replays it rather than losing it
	await _bridge("finish_transaction_dict", [purchase, false], QUERY_TIMEOUT, null)


func _on_purchase_error(error: Dictionary) -> void:
	_waiting = ""
	var code := String(error.get("code", "unknown"))
	if code == "user-cancelled":
		status.emit("")
	elif code == "deferred-payment":
		status.emit("Payment pending: Remove Ads unlocks when it clears")
	else:
		status.emit("That didn't go through (%s). Nothing was charged." % code)


## A pending purchase (cash payment, slow card) is not owned yet.
static func _is_purchased(p: Dictionary) -> bool:
	var st := String(p.get("purchaseState", p.get("purchaseStateAndroid", "purchased"))).to_lower()
	return st in ["purchased", "1", ""]


# --- plugin boundary (see the header) ----------------------------------------

func _bridge(method: String, args: Array, secs: float, fallback):
	if _iap == null or not _iap.has_method(method):
		return fallback
	return await _await_or_timeout(_iap.callv(method, args), secs, fallback)


func _await_or_timeout(co, secs: float, fallback):
	var box := {"done": false, "value": fallback}
	_settle(co, box)
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while not bool(box["done"]) and Time.get_ticks_msec() < deadline:
		if not is_inside_tree():
			return box["value"]
		await get_tree().process_frame
	if not bool(box["done"]):
		push_warning("[IAP] store call timed out after %.0fs" % secs)
	return box["value"]


func _settle(co, box: Dictionary) -> void:
	if co is Signal or (co is Object and co.get_class() == "GDScriptFunctionState"):
		var v = await co
		box["done"] = true
		box["value"] = v
		return
	box["done"] = true
	box["value"] = co


static func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is Dictionary:
		return bool(v.get("success", false))
	return false
