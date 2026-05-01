extends Node

signal state_changed
signal check_finished
signal download_finished(success: bool, message: String)

const UPDATE_FEED_SETTING := "application/config/update_feed_url"
const UPDATE_RELEASE_PAGE_SETTING := "application/config/update_release_page_url"
const DEFAULT_UPDATE_FEED_URL := "https://api.github.com/repos/Excellund/AbyssalDescent/releases/latest"
const DEFAULT_UPDATE_RELEASE_PAGE_URL := "https://github.com/Excellund/AbyssalDescent/releases/latest"
const UPDATE_DOWNLOAD_DIR := "user://updates"

var current_version: String = ""
var latest_version: String = ""
var download_url: String = ""
var release_page_url: String = ""
var update_available: bool = false
var check_in_progress: bool = false
var download_in_progress: bool = false
var check_enabled: bool = true
var action_enabled: bool = true
var force_prompt_mode: bool = false
var download_path: String = ""
var status_text: String = "Checking for updates..."
var detail_text: String = "Current version: unknown"

var _check_request: HTTPRequest
var _download_request: HTTPRequest

func initialize(version: String) -> void:
	current_version = version.strip_edges()
	release_page_url = _update_release_page_url()
	_ensure_requests()
	_set_status("Checking for updates...", "Current version: %s" % _display_current_version())

func configure_runtime_mode(is_editor_run: bool, force_prompt: bool) -> void:
	check_enabled = true
	action_enabled = not is_editor_run
	force_prompt_mode = is_editor_run and force_prompt

func request_check(is_manual: bool = false) -> void:
	_ensure_requests()
	if check_in_progress:
		return
	var feed_url := _update_feed_url()
	if feed_url.is_empty():
		update_available = false
		latest_version = ""
		download_url = ""
		_set_status("Automatic updates are not configured.", "Configure %s to enable auto update checks." % UPDATE_FEED_SETTING)
		emit_signal("check_finished")
		return
	check_in_progress = true
	_set_status("Checking for updates...", "Contacting release feed..." if is_manual else "Current version: %s" % _display_current_version())
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: AbyssalDescent-Updater"])
	var err := _check_request.request(feed_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		check_in_progress = false
		_set_status("Could not start update check.", "Request error: %d" % err)
		emit_signal("check_finished")

func request_download() -> bool:
	_ensure_requests()
	if download_in_progress:
		return false
	if not action_enabled:
		emit_signal("download_finished", false, "editor_disabled")
		return false
	if download_url.is_empty():
		return false
	var file_name := _file_name_from_url(download_url)
	if file_name.is_empty():
		_set_status("No installer asset available for this release.", "Opening release page instead is recommended.")
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DOWNLOAD_DIR))
	download_path = "%s/%s" % [UPDATE_DOWNLOAD_DIR, file_name]
	_download_request.download_file = download_path
	download_in_progress = true
	_set_status("Downloading update %s..." % _display_latest_version(), "The installer will open when download completes.")
	var err := _download_request.request(download_url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		download_in_progress = false
		_set_status("Update download failed to start.", "Request error: %d" % err)
		emit_signal("download_finished", false, "request_start_failed")
		return false
	return true

func should_prompt_for_update(skipped_version: String) -> bool:
	if force_prompt_mode:
		return true
	if not update_available:
		return false
	if latest_version.is_empty():
		return false
	return skipped_version.strip_edges() != latest_version

func open_release_page() -> void:
	if not action_enabled:
		return
	var page := release_page_url
	if page.is_empty():
		page = DEFAULT_UPDATE_RELEASE_PAGE_URL
	if not page.is_empty():
		OS.shell_open(page)

func launch_downloaded_installer() -> bool:
	if not action_enabled:
		return false
	if download_path.is_empty():
		return false
	if not FileAccess.file_exists(download_path):
		return false
	var absolute_path := ProjectSettings.globalize_path(download_path)
	var lower_path := absolute_path.to_lower()
	if OS.get_name() == "Windows" and lower_path.ends_with(".msi"):
		var install_dir := OS.get_executable_path().get_base_dir().replace("/", "\\")
		return OS.create_process("msiexec", PackedStringArray(["/i", absolute_path, "INSTALLDIR=" + install_dir + "\\", "/qb"])) >= 0
	if OS.get_name() == "Windows" and lower_path.ends_with(".zip"):
		return _launch_zip_update(absolute_path)
	if OS.get_name() == "Windows" and (lower_path.ends_with(".exe") or lower_path.ends_with(".bat")):
		return OS.create_process(absolute_path, PackedStringArray()) >= 0
	return OS.shell_open(absolute_path) == OK

func _launch_zip_update(zip_absolute_path: String) -> bool:
	var install_dir := OS.get_executable_path().get_base_dir().replace("/", "\\")
	var staging_dir := (ProjectSettings.globalize_path(UPDATE_DOWNLOAD_DIR) + "\\staging").replace("/", "\\")
	var exe_name := OS.get_executable_path().get_file()

	# Extract ZIP to staging directory
	var zip := ZIPReader.new()
	if zip.open(zip_absolute_path) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(staging_dir)
	for file_path in zip.get_files():
		var file_data := zip.read_file(file_path)
		var dest := staging_dir + "\\" + file_path.get_file()
		var f := FileAccess.open("user://updates/staging/" + file_path.get_file(), FileAccess.WRITE)
		if f != null:
			f.store_buffer(file_data)
			f.close()
	zip.close()

	# Write a batch script that waits for this process to exit, copies files, then relaunches
	var pid := OS.get_process_id()
	var batch_path := staging_dir + "\\apply_update.bat"
	var relaunch_path := install_dir + "\\" + exe_name
	var batch := FileAccess.open("user://updates/staging/apply_update.bat", FileAccess.WRITE)
	if batch == null:
		return false
	batch.store_string("@echo off\r\n")
	batch.store_string(":wait\r\n")
	batch.store_string("tasklist /FI \"PID eq %d\" 2>NUL | find \"%d\" >NUL\r\n" % [pid, pid])
	batch.store_string("if not errorlevel 1 (timeout /t 1 /nobreak >NUL && goto wait)\r\n")
	batch.store_string("xcopy /Y /E \"%s\\*\" \"%s\\\"\r\n" % [staging_dir, install_dir])
	batch.store_string("start \"\" \"%s\"\r\n" % relaunch_path)
	batch.store_string("rd /S /Q \"%s\"\r\n" % staging_dir)
	batch.store_string("del /F /Q \"%s\"\r\n" % zip_absolute_path)
	batch.close()

	return OS.create_process("cmd.exe", PackedStringArray(["/c", batch_path])) >= 0

func _ensure_requests() -> void:
	if _check_request == null:
		_check_request = HTTPRequest.new()
		_check_request.timeout = 8.0
		_check_request.request_completed.connect(_on_check_completed)
		add_child(_check_request)
	if _download_request == null:
		_download_request = HTTPRequest.new()
		_download_request.timeout = 60.0
		_download_request.request_completed.connect(_on_download_completed)
		add_child(_download_request)

func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	check_in_progress = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		update_available = false
		latest_version = ""
		download_url = ""
		_set_status("Update check failed.", "Network result %d, HTTP %d." % [result, response_code])
		emit_signal("check_finished")
		return
	var parsed_raw: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed_raw is Dictionary):
		update_available = false
		latest_version = ""
		download_url = ""
		_set_status("Update feed returned invalid data.", "Expected a JSON object response.")
		emit_signal("check_finished")
		return
	var payload := parsed_raw as Dictionary
	var resolved_latest := _resolve_latest_version(payload)
	var resolved_download := _resolve_download_url(payload)
	var resolved_release_page := _resolve_release_page_url(payload)
	if not resolved_release_page.is_empty():
		release_page_url = resolved_release_page
	latest_version = resolved_latest
	download_url = resolved_download
	if resolved_latest.is_empty():
		update_available = false
		_set_status("Release feed is missing version info.", "No tag_name/version field found in release response.")
		emit_signal("check_finished")
		return
	update_available = _compare_versions(current_version, latest_version) < 0
	if update_available:
		_set_status("New version available: %s" % latest_version, "Current version: %s" % _display_current_version())
	else:
		_set_status("You are up to date.", "Current version: %s" % _display_current_version())
	emit_signal("check_finished")

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	download_in_progress = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_set_status("Download failed.", "Network result %d, HTTP %d." % [result, response_code])
		emit_signal("download_finished", false, "download_failed")
		return
	if not FileAccess.file_exists(download_path):
		_set_status("Download finished but installer was not found.", "Open release page for manual install.")
		emit_signal("download_finished", false, "installer_missing")
		return
	_set_status("Download complete.", "Installer ready to launch.")
	emit_signal("download_finished", true, "ok")

func _set_status(status: String, detail: String) -> void:
	status_text = status
	detail_text = detail
	emit_signal("state_changed")

func _display_current_version() -> String:
	return current_version if not current_version.is_empty() else "unknown"

func _display_latest_version() -> String:
	return latest_version if not latest_version.is_empty() else "latest"

func _update_feed_url() -> String:
	return String(ProjectSettings.get_setting(UPDATE_FEED_SETTING, DEFAULT_UPDATE_FEED_URL)).strip_edges()

func _update_release_page_url() -> String:
	return String(ProjectSettings.get_setting(UPDATE_RELEASE_PAGE_SETTING, DEFAULT_UPDATE_RELEASE_PAGE_URL)).strip_edges()

func _resolve_latest_version(payload: Dictionary) -> String:
	if payload.has("latest_version"):
		return String(payload.get("latest_version", "")).strip_edges()
	if payload.has("version"):
		return String(payload.get("version", "")).strip_edges()
	if payload.has("tag_name"):
		return String(payload.get("tag_name", "")).strip_edges()
	if payload.has("name"):
		return String(payload.get("name", "")).strip_edges()
	return ""

func _resolve_download_url(payload: Dictionary) -> String:
	if payload.has("download_url"):
		return String(payload.get("download_url", "")).strip_edges()
	if payload.has("installer_url"):
		return String(payload.get("installer_url", "")).strip_edges()
	var assets := payload.get("assets", []) as Array
	if not assets.is_empty():
		return _pick_download_url_from_assets(assets)
	return ""

func _resolve_release_page_url(payload: Dictionary) -> String:
	if payload.has("release_page_url"):
		return String(payload.get("release_page_url", "")).strip_edges()
	if payload.has("html_url"):
		return String(payload.get("html_url", "")).strip_edges()
	return ""

func _pick_download_url_from_assets(assets: Array) -> String:
	var preferred_extensions := [".exe", ".msi", ".zip"]
	for extension in preferred_extensions:
		for asset_raw in assets:
			if not (asset_raw is Dictionary):
				continue
			var asset := asset_raw as Dictionary
			var url := String(asset.get("browser_download_url", "")).strip_edges()
			if url.to_lower().ends_with(extension):
				return url
	for asset_raw in assets:
		if not (asset_raw is Dictionary):
			continue
		var asset := asset_raw as Dictionary
		var fallback_url := String(asset.get("browser_download_url", "")).strip_edges()
		if not fallback_url.is_empty():
			return fallback_url
	return ""

func _version_tokens(version: String) -> Array[int]:
	var normalized := version.strip_edges().to_lower().trim_prefix("v")
	var token := ""
	var tokens: Array[int] = []
	for ch in normalized:
		if ch >= "0" and ch <= "9":
			token += ch
			continue
		if not token.is_empty():
			tokens.append(int(token))
			token = ""
	if not token.is_empty():
		tokens.append(int(token))
	if tokens.is_empty():
		tokens.append(0)
	return tokens

func _compare_versions(current: String, latest: String) -> int:
	var left := _version_tokens(current)
	var right := _version_tokens(latest)
	var count := maxi(left.size(), right.size())
	for i in range(count):
		var l := left[i] if i < left.size() else 0
		var r := right[i] if i < right.size() else 0
		if l < r:
			return -1
		if l > r:
			return 1
	return 0

func _file_name_from_url(url: String) -> String:
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return ""
	var path_only := trimmed
	var query_index := path_only.find("?")
	if query_index >= 0:
		path_only = path_only.substr(0, query_index)
	var slash_index := path_only.rfind("/")
	if slash_index < 0 or slash_index >= path_only.length() - 1:
		return ""
	return path_only.substr(slash_index + 1)
