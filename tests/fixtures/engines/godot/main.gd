extends Node

const Suite = preload("res://suite.gd")

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    await Suite.run(get_tree())
