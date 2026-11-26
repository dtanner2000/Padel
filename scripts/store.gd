class_name Store
extends Node
## In-app purchase: Remove Ads (£1.99, non-consumable). iOS: StoreKit
## (GodotApplePlugins, fetched by the Codemagic iOS build). Android: Google
## Play Billing (PlayBilling, addons/godot-iap). Elsewhere it's unavailable and
## the buttons say so. Same product id on both stores.

signal changed(text: String)       # a status line for the Settings screen

const REMOVE_ADS := "com.davidtanner.padel.removeads"
const BONUS_COINS := 500

var _sk: Object = null             # StoreKitManager
var _product: Object = null        # StoreProduct
var price := ""                    # "£1.99" once the store has told us
var _play: PlayBilling = null      # Android


func available() -> bool:
	return _sk != null or _play != null


func _ready() -> void:
	if OS.get_name() == "Android":
		_play = PlayBilling.new()
		add_child(_play)
		_play.granted.connect(func(id: String) -> void:
			if id == REMOVE_ADS:
				_grant())
		_play.status.connect(func(text: String) -> void:
			price = _play.prices.get(REMOVE_ADS, price)
			changed.emit(text))
		_play.start(PackedStringArray([REMOVE_ADS]))
		return
	if OS.get_name() != "iOS" or not ClassDB.class_exists("StoreKitManager"):
		return
	_sk = ClassDB.instantiate("StoreKitManager")
	_sk.connect("transaction_updated", _on_transaction)
	_sk.connect("purchase_completed", _on_purchase)
	_sk.connect("products_request_completed", _on_products)
	_sk.connect("restore_completed", _on_restore)
	_sk.call("start")
	_sk.call("fetch_current_entitlements")   # bought on another device / reinstall
	_sk.call("request_products", PackedStringArray([REMOVE_ADS]))


func _on_products(products: Array, _status: int) -> void:
	for p in products:
		if p and p.get("product_id") == REMOVE_ADS:
			_product = p
			price = str(p.get("display_price"))
			changed.emit("")


func buy() -> void:
	if _play:
		_play.buy(REMOVE_ADS)
		return
	if _sk == null:
		changed.emit("Purchases work in the App Store and Google Play versions")
		return
	if _product == null:
		changed.emit("Can't reach the App Store right now")
		_sk.call("request_products", PackedStringArray([REMOVE_ADS]))
		return
	changed.emit("Opening the App Store…")
	_sk.call("purchase", _product)


func restore() -> void:
	if _play:
		_play.restore()
		return
	if _sk == null:
		changed.emit("Purchases work in the App Store and Google Play versions")
		return
	changed.emit("Restoring…")
	_sk.call("restore_purchases")


func _on_purchase(transaction: Object, status: int, message: String) -> void:
	if transaction:
		_on_transaction(transaction)
	elif status != 0:
		changed.emit("" if "cancel" in message.to_lower() else message)


func _on_restore(status: int, message: String) -> void:
	_sk.call("fetch_current_entitlements")
	changed.emit("Purchases restored" if status == 0 else message)


func _on_transaction(transaction: Object) -> void:
	if transaction == null:
		return
	if transaction.get("product_id") == REMOVE_ADS and float(transaction.get("revocation_date")) <= 0.0:
		_grant()
	transaction.call("finish")


## Remove Ads owned (bought now, earlier or restored): the bonus coins only once.
func _grant() -> void:
	var first := not Profile.owns("remove_ads")
	Profile.set_v("owned", "remove_ads", true)
	if first:
		Profile.add_stat("coins", BONUS_COINS)
	Profile.save()
	changed.emit("Ads removed. Thank you! +%d coins" % BONUS_COINS if first else "Ads removed")
