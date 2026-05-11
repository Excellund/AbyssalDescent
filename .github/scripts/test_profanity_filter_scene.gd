extends Node

const PROFANITY_FILTER_SCRIPT := preload("res://scripts/shared/profanity_filter.gd")

var test_cases = [
	{"name": "Player123", "expected_profane": false},
	{"name": "fuck", "expected_profane": true},
]

var results = []
var tests_completed = 0

func _ready() -> void:
	print("[ProfanityFilterTest] Starting profanity filter tests...")
	print("[ProfanityFilterTest] Testing %d cases (API calls to vector.profanity.dev)..." % test_cases.size())
	
	for test_case in test_cases:
		var filter = PROFANITY_FILTER_SCRIPT.new(self)
		if not filter.check_complete.is_connected(_on_check_complete):
			filter.check_complete.connect(_on_check_complete.bindv([test_case]))
		filter.check_profanity_async(test_case["name"])

func _on_check_complete(is_profane: bool, test_case: Dictionary) -> void:
	var test_name = test_case["name"] if not test_case["name"].is_empty() else "(empty)"
	var expected = test_case["expected_profane"]
	var passed = is_profane == expected
	
	var status = "✓ PASS" if passed else "✗ FAIL"
	var result_msg = "%s | '%s' -> profane=%s (expected %s)" % [status, test_name, is_profane, expected]
	results.append(result_msg)
	print("[ProfanityFilterTest] %s" % result_msg)
	
	tests_completed += 1
	if tests_completed == test_cases.size():
		_print_summary()
		get_tree().quit()

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
