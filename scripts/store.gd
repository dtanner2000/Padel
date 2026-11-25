class_name Store
extends Node
## In-app purchase: Remove Ads (£1.99, non-consumable) through StoreKit
## (GodotApplePlugins, fetched by the Codemagic iOS build). Elsewhere it's
## unavailable and the buttons say so.

signal changed(text: String)       # a status line for the Settings screen

const REMOVE_ADS := "com.davidtanner.padel.removeads"
const BONUS_COINS := 500

var _sk: Object = null             # StoreKitManager
var _product: Object = null        # StoreProduct
var price := ""                    # "£1.99" once the App Store has told us


func available() -> bool:
	return _sk != null


func _ready() -> void:
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
	if _sk == null:
		changed.emit("Purchases work on the iPhone build")
		return
	if _product == null:
		changed.emit("Can't reach the App Store right now")
		_sk.call("request_products", PackedStringArray([REMOVE_ADS]))
		return
	changed.emit("Opening the App Store…")
	_sk.call("purchase", _product)


func restore() -> void:
	if _sk == null:
		changed.emit("Purchases work on the iPhone build")
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
		var first := not Profile.owns("remove_ads")
		Profile.set_v("owned", "remove_ads", true)
		if first:
			Profile.add_stat("coins", BONUS_COINS)
		Profile.save()
		changed.emit("Ads removed. Thank you! +%d coins" % BONUS_COINS if first else "Ads removed")
	transaction.call("finish")
