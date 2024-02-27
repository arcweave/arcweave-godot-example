extends CharacterBody3D

signal npc_approached(npc: CharacterBody3D)
signal npc_left(npc: CharacterBody3D)

@export var obj_id: String = ""

const WALK_SPEED = 1.8
const RUN_SPEED = 5.0
const JUMP_VELOCITY = 4.5
const PIVOT_FACTOR = 0.001

@onready var dummy: Node3D = $Dummy
@onready var animation_player: AnimationPlayer = $Dummy/AnimationPlayer
@onready var mesh: MeshInstance3D = $Dummy/Armature/Skeleton3D/Beta_Surface
@onready var cloud: Node3D = $Cloud
@onready var rain_drops: GPUParticles3D = $Cloud/GPUParticles3D


# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var near_npc: bool = false
var is_walking: bool = false
var is_pivotable: bool = true
var aw_name: String = ""



func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("walk"):
		is_walking = true
	if event.is_action_released("walk"):
		is_walking = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_pivotable:
		rotation.y += -event.relative.x * PIVOT_FACTOR
		dummy.rotate_y(event.relative.x * PIVOT_FACTOR)




func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump.
	if is_on_floor() and not near_npc:
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	
	var speed: float = RUN_SPEED
	var current_animation: String = "run"
	
	if is_walking:
		speed = WALK_SPEED
		current_animation = "walk"
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		animation_player.play(current_animation)
		dummy.look_at(position + direction)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		animation_player.play("idle")
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


func rain(yes: bool = true) -> void:
	rain_drops.emitting = yes
	cloud.visible = yes


func _on_area_3d_body_entered(body: Node3D) -> void:
	npc_approached.emit(body)
	near_npc = true


func _on_area_3d_body_exited(body: Node3D) -> void:
	npc_left.emit(body)
	near_npc = false
