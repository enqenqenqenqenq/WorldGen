extends Node3D
class_name FreeFlyPlayer

@export var move_speed: float = 10.0
@export var fast_speed: float = 20.0
@export var mouse_sensitivity: float = 0.0025

@onready var camera: Camera3D = $Camera3D

var pitch: float = 0.0


func _ready() -> void:
	camera.current = true
	pitch = camera.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		camera.rotation.x = pitch


func _process(delta: float) -> void:
	var move_x := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var move_z := Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	var move_y := 0.0

	if Input.is_action_pressed("move_up"):
		move_y += 1.0
	if Input.is_action_pressed("move_down"):
		move_y -= 1.0

	var local_dir := Vector3(move_x, 0.0, move_z)
	if local_dir.length() > 1.0:
		local_dir = local_dir.normalized()

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x

	var velocity := right * local_dir.x + forward * local_dir.z
	velocity.y = move_y

	if velocity.length() > 0.0:
		velocity = velocity.normalized()

	var speed := fast_speed if Input.is_action_pressed("move_fast") else move_speed
	global_position += velocity * speed * delta


func get_camera() -> Camera3D:
	return camera
