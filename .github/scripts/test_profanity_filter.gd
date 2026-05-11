extends MainLoop

const PROFANITY_FILTER_SCRIPT := preload("res://scripts/shared/profanity_filter.gd")

var test_cases = [
	{"name": "CleanName", "expected_profane": false},
	{"name": "Player123", "expected_profane": false},
	{"name": "TestUser", "expected_profane": false},
	{"name": "HelloWorld", "expected_profane": false},
	{"name": "fuck", "expected_profane": true},
	{"name": "shit", "expected_profane": true},
	{"name": "ass", "expected_profane": true},
	{"name": "bitch", "expected_profane": true},
	{"name": "damn", "expected_profane": true},
	{"name": "hell", "expected_profane": true},
	{"name": "", "expected_profane": false},
]

var results = []
var tests_completed = 0
var timeout_timer = 0.0
var root_node: Node = null

func _initialize() -> void:
	root_node = Node.new()
	print("[ProfanityFilterTest] Starting profanity filter tests...")
	print("[ProfanityFilterTest] Testing %d cases..." % test_cases.size())
	
	for test_case in test_cases:
		var filter = PROFANITY_FILTER_SCRIPT.new(root_node)
		if not filter.check_complete.is_connected(_on_check_complete):
			filter.check_complete.connect(_on_check_complete.bindv([test_case]))
		filter.check_profanity_async(test_case["name"])

func _process(delta: float) -> bool:
	timeout_timer += delta
	
	if tests_completed == test_cases.size():
		_print_summary()
		return true
	elif timeout_timer > 12.0:
		print("[ProfanityFilterTest] Test timeout!")
		return true
	return false

func _on_check_complete(is_profane: bool, test_case: Dictionary) -> void:
	var test_name = test_case["name"] if not test_case["name"].is_empty() else "(empty)"
	var expected = test_case["expected_profane"]
	var passed = is_profane == expected
	
	var status = "✓ PASS" if passed else "✗ FAIL"
	var result_msg = "%s | '%s' -> profane=%s (expected %s)" % [status, test_name, is_profane, expected]
	results.append(result_msg)
	print("[ProfanityFilterTest] %s" % result_msg)
	
	tests_completed += 1

func _print_summary() -> void:
	print("\n[ProfanityFilterTest] ===== TEST SUMMARY =====")
	var passed = results.filter(func(r): return r.begins_with("✓"))
	var failed = results.filter(func(r): return r.begins_with("✗"))
	print("[ProfanityFilterTest] Passed: %d/%d" % [passed.size(), test_cases.size()])
	if failed.size() > 0:
		print("[ProfanityFilterTest] Failed tests:")
		for fail in failed:
			print("[ProfanityFilterTest]   %s" % fail)
	else:
		print("[ProfanityFilterTest] All tests passed!")
	print("[ProfanityFilterTest] ========================")
