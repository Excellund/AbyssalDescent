extends RefCounted

var resume_saved_run_requested: bool = false

func request_resume_saved_run() -> void:
	resume_saved_run_requested = true

func consume_resume_saved_run_request() -> bool:
	if not resume_saved_run_requested:
		return false
	resume_saved_run_requested = false
	return true

func clear_resume_saved_run_request() -> void:
	resume_saved_run_requested = false
