extends Node
## Manages a `cloudflared` child process that creates an ephemeral
## Quick Tunnel (https://*.trycloudflare.com) proxying to a local WebSocket
## server. Used so players behind NAT/firewalls can host without port
## forwarding.
##
## Fully automatic: on first host attempt the binary is downloaded from
## the official Cloudflare GitHub release and cached under user://, so the
## player never has to install anything.
##
## Flow:
##   1. Caller invokes `await start_and_get_url(local_port)`.
##   2. We ensure cloudflared is available locally (cache or download).
##   3. We spawn `cloudflared tunnel --url http://localhost:<port>`.
##   4. A background Thread reads stderr line-by-line, searching for the
##      Quick Tunnel URL (e.g. `https://foo-bar-baz.trycloudflare.com`).
##   5. Once found, we convert https:// -> wss:// and return it.
##   6. `stop()` terminates the child process and joins the reader thread.

const URL_REGEX_PATTERN := "https://[a-z0-9-]+\\.trycloudflare\\.com"
const DEFAULT_STARTUP_TIMEOUT_SEC := 30.0
const DOWNLOAD_TIMEOUT_SEC := 120.0

const RELEASE_URL_WINDOWS := "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
const RELEASE_URL_MACOS := "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
const RELEASE_URL_LINUX := "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"

var _pid: int = -1
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _reader_thread: Thread = null
var _state_mutex: Mutex = Mutex.new()
var _captured_url: String = ""
var _capture_error: String = ""
var _captured_log: String = ""
var _stop_requested: bool = false
var _download_request: HTTPRequest = null


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## Spawn cloudflared and await the tunnel URL. Returns a Dictionary:
##   { "ok": bool, "url": String, "error": String, "log_tail": String }
## URL is in `wss://` form, ready to hand to WebSocketMultiplayerPeer.
func start_and_get_url(local_port: int, timeout_sec: float = DEFAULT_STARTUP_TIMEOUT_SEC) -> Dictionary:
	if _pid > 0:
		return {"ok": false, "url": "", "error": "Tunnel already running.", "log_tail": ""}

	var ensure_result: Dictionary = await _ensure_binary_available()
	if not bool(ensure_result.get("ok", false)):
		return {
			"ok": false,
			"url": "",
			"error": String(ensure_result.get("error", "Failed to acquire cloudflared binary.")),
			"log_tail": ""
		}
	var binary_path := String(ensure_result.get("path", ""))

	var args := PackedStringArray([
		"tunnel",
		"--url", "http://localhost:%d" % local_port,
		"--no-autoupdate"
	])
	var spawn := OS.execute_with_pipe(binary_path, args)
	if spawn.is_empty() or int(spawn.get("pid", -1)) <= 0:
		return {
			"ok": false,
			"url": "",
			"error": "Failed to launch cloudflared from %s." % binary_path,
			"log_tail": ""
		}

	_pid = int(spawn.get("pid", -1))
	_stdio = spawn.get("stdio", null)
	_stderr = spawn.get("stderr", null)
	_stop_requested = false
	_captured_url = ""
	_capture_error = ""
	_captured_log = ""

	_reader_thread = Thread.new()
	_reader_thread.start(_read_pipes_loop)

	var elapsed := 0.0
	var tree := get_tree()
	while elapsed < timeout_sec:
		await tree.create_timer(0.1).timeout
		elapsed += 0.1
		_state_mutex.lock()
		var url := _captured_url
		var err := _capture_error
		var log_tail := _captured_log
		_state_mutex.unlock()
		if not url.is_empty():
			var wss_url := url.replace("https://", "wss://")
			return {"ok": true, "url": wss_url, "error": "", "log_tail": log_tail}
		if not err.is_empty():
			stop()
			return {"ok": false, "url": "", "error": err, "log_tail": log_tail}
		if not is_running():
			stop()
			return {
				"ok": false,
				"url": "",
				"error": "cloudflared exited before publishing a tunnel URL.",
				"log_tail": log_tail
			}

	stop()
	return {
		"ok": false,
		"url": "",
		"error": "Tunnel startup timed out after %.1fs." % timeout_sec,
		"log_tail": _captured_log
	}


## Terminate the child process and join the reader thread.
func stop() -> void:
	_stop_requested = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _reader_thread != null and _reader_thread.is_started():
		_reader_thread.wait_to_finish()
	_reader_thread = null
	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null
	_pid = -1


## Runs on background thread. Tails stderr (cloudflared logs go to stderr)
## looking for the trycloudflare.com URL, then keeps draining until process exits.
func _read_pipes_loop() -> void:
	var regex := RegEx.new()
	regex.compile(URL_REGEX_PATTERN)
	var log_buffer := ""
	var captured := false

	while not _stop_requested:
		var line := ""
		if _stderr != null and not _stderr.eof_reached():
			line = _stderr.get_line()
		elif _stdio != null and not _stdio.eof_reached():
			line = _stdio.get_line()
		else:
			break

		if line.is_empty() and (_stderr == null or _stderr.eof_reached()) \
				and (_stdio == null or _stdio.eof_reached()):
			break

		if not line.is_empty():
			log_buffer += line + "\n"
			if log_buffer.length() > 4096:
				log_buffer = log_buffer.substr(log_buffer.length() - 4096, 4096)
			if not captured:
				var m := regex.search(line)
				if m != null:
					var found := m.get_string()
					_state_mutex.lock()
					_captured_url = found
					_captured_log = log_buffer
					_state_mutex.unlock()
					captured = true
			_state_mutex.lock()
			_captured_log = log_buffer
			_state_mutex.unlock()

	if not captured:
		_state_mutex.lock()
		if _capture_error.is_empty() and _captured_url.is_empty():
			_capture_error = "cloudflared closed its output pipes without publishing a URL."
		_state_mutex.unlock()


func _exit_tree() -> void:
	stop()


## Ensure cloudflared is available locally. Returns { ok, path, error }.
## Resolution order:
##   1. Cached binary at user://cloudflared_bin/<name>
##   2. Binary shipped alongside the executable (res://-adjacent OS path)
##   3. cloudflared on system PATH
##   4. Download from official Cloudflare GitHub releases
func _ensure_binary_available() -> Dictionary:
	var info := _platform_binary_info()
	if info.is_empty():
		return {"ok": false, "path": "", "error": "Unsupported platform for automatic cloudflared download."}

	var cached_path := _cached_binary_path(info)
	if FileAccess.file_exists(cached_path):
		return {"ok": true, "path": ProjectSettings.globalize_path(cached_path), "error": ""}

	var shipped_path := _shipped_binary_path(info)
	if shipped_path != "" and FileAccess.file_exists(shipped_path):
		return {"ok": true, "path": shipped_path, "error": ""}

	var path_lookup := _which("cloudflared")
	if not path_lookup.is_empty():
		return {"ok": true, "path": path_lookup, "error": ""}

	print("[CloudflareTunnelHelper] cloudflared not found locally; downloading...")
	var download_result: Dictionary = await _download_binary(info, cached_path)
	if not bool(download_result.get("ok", false)):
		return download_result
	return {"ok": true, "path": ProjectSettings.globalize_path(cached_path), "error": ""}


func _platform_binary_info() -> Dictionary:
	var os_name := OS.get_name()
	match os_name:
		"Windows":
			return {"url": RELEASE_URL_WINDOWS, "filename": "cloudflared.exe", "needs_chmod": false}
		"macOS":
			return {"url": RELEASE_URL_MACOS, "filename": "cloudflared", "needs_chmod": true}
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return {"url": RELEASE_URL_LINUX, "filename": "cloudflared", "needs_chmod": true}
		_:
			return {}


func _cached_binary_path(info: Dictionary) -> String:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("cloudflared_bin"):
		dir.make_dir("cloudflared_bin")
	return "user://cloudflared_bin/%s" % String(info.get("filename", "cloudflared"))


func _shipped_binary_path(info: Dictionary) -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir.is_empty():
		return ""
	return "%s/%s" % [exe_dir, String(info.get("filename", "cloudflared"))]


func _which(name: String) -> String:
	var stdout: Array = []
	var lookup_cmd := "where" if OS.get_name() == "Windows" else "which"
	var exit_code := OS.execute(lookup_cmd, [name], stdout, false)
	if exit_code != 0 or stdout.is_empty():
		return ""
	var first_line := String(stdout[0]).strip_edges().split("\n")[0].strip_edges()
	return first_line


func _download_binary(info: Dictionary, dest_user_path: String) -> Dictionary:
	if _download_request != null:
		_download_request.queue_free()
		_download_request = null
	_download_request = HTTPRequest.new()
	_download_request.use_threads = true
	_download_request.timeout = DOWNLOAD_TIMEOUT_SEC
	add_child(_download_request)

	## macOS release ships as a .tgz; we'd need to unpack it. For now, surface a
	## clear error on that path — Windows/Linux work out-of-the-box.
	var url := String(info.get("url", ""))
	if url.ends_with(".tgz"):
		_download_request.queue_free()
		_download_request = null
		return {
			"ok": false,
			"path": "",
			"error": "Automatic cloudflared download isn't supported on this platform yet. Install manually via Homebrew: brew install cloudflared."
		}

	var dest_globalized := ProjectSettings.globalize_path(dest_user_path)
	_download_request.download_file = dest_user_path
	var request_err := _download_request.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if request_err != OK:
		_download_request.queue_free()
		_download_request = null
		return {"ok": false, "path": "", "error": "Failed to start cloudflared download: %s" % error_string(request_err)}

	var result: Array = await _download_request.request_completed
	var result_code := int(result[0])
	var response_code := int(result[1])
	_download_request.queue_free()
	_download_request = null

	if result_code != HTTPRequest.RESULT_SUCCESS:
		_remove_user_file(dest_user_path)
		return {"ok": false, "path": "", "error": "cloudflared download failed (result=%d)." % result_code}
	if response_code < 200 or response_code >= 300:
		_remove_user_file(dest_user_path)
		return {"ok": false, "path": "", "error": "cloudflared download HTTP %d." % response_code}
	if not FileAccess.file_exists(dest_user_path) or FileAccess.get_file_as_bytes(dest_user_path).is_empty():
		_remove_user_file(dest_user_path)
		return {"ok": false, "path": "", "error": "cloudflared download produced an empty file."}

	if bool(info.get("needs_chmod", false)):
		OS.execute("chmod", ["+x", dest_globalized], [], false)

	print("[CloudflareTunnelHelper] cloudflared downloaded to %s" % dest_globalized)
	return {"ok": true, "path": dest_globalized, "error": ""}


func _remove_user_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null:
		dir.remove(path.get_file())
