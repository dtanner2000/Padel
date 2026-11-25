extends SceneTree
## Codemagic, after the iOS export: link Google's AdMob + UMP Swift packages
## into the Xcode project. The AdMob plugin does this itself, but on Godot
## < 4.8 it defers the step, and a headless export quits before it runs.
## godot --headless --path . -s tools/admob_spm_patch.gd -- build/ios/Padel.xcodeproj/project.pbxproj
func _init() -> void:
	var path := OS.get_cmdline_user_args()[0]
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	var pkg := path.get_base_dir().get_base_dir().path_join("admob_spm/Package.swift")
	if not FileAccess.file_exists(pkg):
		printerr("AdMob SPM package missing: ", pkg)
		quit(1)
		return
	load("res://addons/admob/internal/services/pbxproj_service.gd").patch(path)
	var ok := FileAccess.get_file_as_string(path).contains("AD0000000000000000000001")
	print("AdMob SPM linked: ", ok)
	quit(0 if ok else 1)
