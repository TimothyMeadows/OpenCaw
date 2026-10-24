extends Node

var entered: int = 0
var readied: int = 0
var value: int = 7

func _enter_tree() -> void:
    entered += 1

func _ready() -> void:
    readied += 1

func _exit_tree() -> void:
    var root := get_tree().root
    root.set_meta("opencaw_fixture_exits", int(root.get_meta("opencaw_fixture_exits", 0)) + 1)
