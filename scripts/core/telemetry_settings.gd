extends RefCounted
class_name TelemetrySettings

const TELEMETRY_ENDPOINT_SETTING := "application/config/telemetry_upload_endpoint"
const TELEMETRY_API_KEY_SETTING := "application/config/telemetry_upload_api_key"

static func upload_endpoint() -> String:
	return String(ProjectSettings.get_setting(TELEMETRY_ENDPOINT_SETTING, "")).strip_edges()

static func upload_api_key() -> String:
	return String(ProjectSettings.get_setting(TELEMETRY_API_KEY_SETTING, "")).strip_edges()

static func rest_base_url() -> String:
	var endpoint := upload_endpoint()
	if endpoint.is_empty():
		return ""
	var marker := "/rest/v1/"
	var idx := endpoint.find(marker)
	if idx < 0:
		return ""
	return endpoint.substr(0, idx + marker.length() - 1)

static func rpc_url(rpc_name: String) -> String:
	var base := rest_base_url()
	if base.is_empty():
		return ""
	return "%s/rpc/%s" % [base.trim_suffix("/"), rpc_name.strip_edges()]