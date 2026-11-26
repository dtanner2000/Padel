class_name Ads
extends Node
## AdMob (Poing Studios plugin, addons/admob): consent first (Google's UMP
## form, required in the UK/EU), then one interstitial between matches and an
## optional rewarded "double coins". Phones only; everywhere else every call is
## a no-op. Remove Ads (Store) switches interstitials off, not the rewarded one
## (that's always the player's choice).

## Google's test units until launch: real ads on your own phone break AdMob's
## rules. Flip to false for the App Store release build.
const USE_TEST_ADS := false

const IOS_INTERSTITIAL := "ca-app-pub-4925808836448571/5866076245"
const IOS_REWARDED := "ca-app-pub-4925808836448571/5319281339"
## Android (Google Play): fill in from AdMob > the Android app > Ad units. Empty = Google's
## test units (and the codemagic android-play check refuses a build without our app id).
const ANDROID_INTERSTITIAL := "ca-app-pub-4925808836448571/6306943845"
const ANDROID_REWARDED := "ca-app-pub-4925808836448571/6410438511"
const TEST_INTERSTITIAL_IOS := "ca-app-pub-3940256099942544/4411468910"
const TEST_REWARDED_IOS := "ca-app-pub-3940256099942544/1712485313"
const TEST_INTERSTITIAL_ANDROID := "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"

const MATCHES_BETWEEN := 2         # an interstitial at most every 2nd finished match
const MIN_GAP := 180.0             # and never within 3 minutes of the last one
const FREE_MATCHES := 2            # nobody sees an ad in their first two matches

## What the ads are doing, shown small in Settings so a real-ad build can be
## checked on a phone without tapping an ad.
static var status := "Ads: off on this device"
static var loaded := {"inter": false, "reward": false}

var _ready_sdk := false
var _inter: InterstitialAd
var _reward: RewardedAd
var _inter_loader: InterstitialAdLoader
var _reward_loader: RewardedAdLoader
var _since_ad := 0                 # finished matches since the last interstitial
var _last_ad_at := -1000.0


func _available() -> bool:
	return OS.get_name() in ["iOS", "Android"] and Engine.has_singleton("PoingGodotAdMob")


func _ready() -> void:
	if not _available():
		status = "Ads: off (no AdMob plugin in this build)" if OS.get_name() in ["iOS", "Android"] else status
		return
	status = "Ads: checking consent…"
	_inter_loader = InterstitialAdLoader.new()
	_reward_loader = RewardedAdLoader.new()
	var request := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(request, _consent_updated, func(e: FormError) -> void:
		status = "Ads: consent check failed (%s), starting anyway" % _err(e)
		_start_sdk())


func _consent_updated() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(func(form: ConsentForm) -> void:
			var st := UserMessagingPlatform.consent_information.get_consent_status()
			if st == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
				form.show(func(_e: FormError) -> void: _start_sdk())
			else:
				_start_sdk(),
			func(_e: FormError) -> void: _start_sdk())
	else:
		_start_sdk()


func _start_sdk() -> void:
	if _ready_sdk:
		return
	_ready_sdk = true
	status = "Ads: starting%s" % (" (test ads)" if USE_TEST_ADS else "")
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_s: InitializationStatus) -> void:
		status = "Ads: loading…"
		_load_interstitial()
		_load_rewarded()
	MobileAds.initialize(listener)


func _unit(kind: String) -> String:
	var ios := OS.get_name() == "iOS"
	var live := IOS_INTERSTITIAL if kind == "inter" else IOS_REWARDED
	if not ios:
		live = ANDROID_INTERSTITIAL if kind == "inter" else ANDROID_REWARDED
	if USE_TEST_ADS or live == "":
		if kind == "inter":
			return TEST_INTERSTITIAL_IOS if ios else TEST_INTERSTITIAL_ANDROID
		return TEST_REWARDED_IOS if ios else TEST_REWARDED_ANDROID
	return live


func _load_interstitial() -> void:
	if Profile.owns("remove_ads"):
		return
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_inter = ad
		_loaded("inter", true, "")
	cb.on_ad_failed_to_load = func(e: LoadAdError) -> void:
		_loaded("inter", false, _err(e))
		get_tree().create_timer(60.0).timeout.connect(_load_interstitial)
	_inter_loader.load(_unit("inter"), AdRequest.new(), cb)


func _load_rewarded() -> void:
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_reward = ad
		_loaded("reward", true, "")
	cb.on_ad_failed_to_load = func(e: LoadAdError) -> void:
		_loaded("reward", false, _err(e))
		get_tree().create_timer(60.0).timeout.connect(_load_rewarded)
	_reward_loader.load(_unit("reward"), AdRequest.new(), cb)


func _loaded(kind: String, ok: bool, err: String) -> void:
	loaded[kind] = ok
	var parts := []
	parts.append("between matches " + ("ready" if loaded.inter else "not loaded"))
	parts.append("double coins " + ("ready" if loaded.reward else "not loaded"))
	status = "Ads%s: %s" % [" (test)" if USE_TEST_ADS else "", ", ".join(parts)]
	if err != "":
		status += ". Last error: " + err + " (retrying every minute)"


static func _err(e: Object) -> String:
	if e == null:
		return "unknown"
	var code: Variant = e.get("code")
	var msg: Variant = e.get("message")
	return "%s %s" % [str(code) if code != null else "", str(msg) if msg != null else ""]


## A match just finished and the player is moving on: maybe show an
## interstitial first. `then` always runs (after the ad, or straight away).
func between_matches(then: Callable) -> void:
	_since_ad += 1
	var due := _inter != null and not Profile.owns("remove_ads") and _since_ad >= MATCHES_BETWEEN \
		and Time.get_ticks_msec() / 1000.0 - _last_ad_at >= MIN_GAP and Profile.stat("matches") >= FREE_MATCHES
	if not due:
		then.call()
		return
	var ad := _inter
	_inter = null
	_since_ad = 0
	_last_ad_at = Time.get_ticks_msec() / 1000.0
	var done := func() -> void:
		ad.destroy()
		_load_interstitial()
		then.call()
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = done
	fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: done.call()
	ad.full_screen_content_callback = fs
	ad.show()


func rewarded_ready() -> bool:
	return _reward != null


## The player chose to watch: on_reward runs only if they watched to the end.
func show_rewarded(on_reward: Callable, on_closed: Callable) -> void:
	if _reward == null:
		on_closed.call()
		return
	var ad := _reward
	_reward = null
	var earned := [false]
	var closed := func() -> void:
		ad.destroy()
		_load_rewarded()
		if earned[0]:
			on_reward.call()
		on_closed.call()
	var fs := FullScreenContentCallback.new()
	fs.on_ad_dismissed_full_screen_content = closed
	fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: closed.call()
	ad.full_screen_content_callback = fs
	var l := OnUserEarnedRewardListener.new()
	l.on_user_earned_reward = func(_item: RewardedItem) -> void: earned[0] = true
	ad.show(l)


## Remove Ads bought: drop any loaded interstitial.
func ads_removed() -> void:
	if _inter:
		_inter.destroy()
		_inter = null
