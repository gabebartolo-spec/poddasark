extends SceneTree
## Headless test runner. Runs every tests/test_*.gd file.
##   godot --headless --path . -s tests/run_tests.gd
## Exits with code 1 if any test fails.

const TEST_DIR := "res://tests/"


func _init() -> void:
	var passed := 0
	var failed := 0
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load(TEST_DIR + file)
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.call(name)
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for failure in test.failures:
					printerr("FAIL %s::%s: %s" % [file, name, failure])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
