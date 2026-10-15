class_name TestCase
extends RefCounted
## Base class for tests. Any method starting with "test_" is run by tests/run_tests.gd.

var failures: Array[String] = []


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		failures.append("expected true. " + message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if actual != expected:
		failures.append("expected %s, got %s. %s" % [expected, actual, message])


func assert_almost(actual: float, expected: float, tolerance := 0.0001, message := "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("expected %f (+/- %f), got %f. %s" % [expected, tolerance, actual, message])
