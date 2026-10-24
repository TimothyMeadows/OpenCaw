extends RefCounted

static func _check(condition: bool, message: String, result: Dictionary) -> void:
    if condition:
        result["checks"] += 1
    else:
        result["status"] = "fail"
        result["failures"].append(message)
        push_error(message)

static func run(tree: SceneTree) -> void:
    var result := {"fixture": "opencaw-native-godot", "status": "pass", "checks": 0,
        "engineVersion": Engine.get_version_info()["string"], "failures": []}
    tree.root.set_meta("opencaw_fixture_exits", 0)
    var packed: PackedScene = load("res://actor.tscn")
    if packed == null:
        _check(false, "Actor scene failed to load", result)
    else:
        var actor = packed.instantiate()
        var reference := weakref(actor)
        tree.root.add_child(actor)
        await tree.process_frame
        _check(actor.entered == 1, "Actor did not enter once", result)
        _check(actor.readied == 1, "Actor was not ready once", result)
        actor.value = 19
        _check(actor.value == 19, "Actor state update failed", result)
        actor.queue_free()
        await tree.process_frame
        _check(reference.get_ref() == null, "Queued actor remained alive", result)
        _check(int(tree.root.get_meta("opencaw_fixture_exits")) == 1, "Exit callback count changed", result)
    if OS.get_environment("OPENCAW_FIXTURE_FORCE_FAILURE") == "1":
        _check(false, "Intentional failure verifies the harness exit status", result)
    var destination := OS.get_environment("OPENCAW_FIXTURE_REPORT")
    var file := FileAccess.open(destination, FileAccess.WRITE)
    if file == null:
        push_error("Fixture report could not be written")
        tree.quit(1)
        return
    file.store_string(JSON.stringify(result))
    file.close()
    tree.quit(0 if result["status"] == "pass" else 1)
