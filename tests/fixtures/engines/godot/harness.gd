extends SceneTree

const Suite = preload("res://suite.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    await Suite.run(self)
