extends CharacterBody3D

@export var obj_id: String = ""
@export var is_healthy: bool = true

@onready var animation_player: AnimationPlayer = $Dummy/AnimationPlayer

var aw_name: String = ""
var aw_colour: Color = Color(0,0,0)
var initial_facing_direction: float

func _ready() -> void:
	initial_facing_direction = rotation.y
	print(name + " is facing " + str(rotation.y))
