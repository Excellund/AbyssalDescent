extends RefCounted

func run_bootstrap(stages: Array[Callable]) -> void:
	for stage in stages:
		if stage.is_valid():
			stage.call()

func run_first_success(stages: Array[Callable]) -> bool:
	for stage in stages:
		if not stage.is_valid():
			continue
		if bool(stage.call()):
			return true
	return false
