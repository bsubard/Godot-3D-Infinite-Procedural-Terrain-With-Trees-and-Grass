extends CharacterBody3D

const SPEED = 10.0
const JUMP_VELOCITY = 5
@onready var pivot: Node3D = $Node3D
@export var sensitivity = 0.25
var is_mouse_input_enabled = true

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		pivot.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-90), deg_to_rad(45))
		
		
func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY
	
	var direction = Vector3.ZERO 

	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x

	direction.y = 0 
	direction = direction.normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	if Input.is_key_pressed(KEY_SHIFT):
		velocity.x *= 2
		velocity.z *= 2

	velocity.y -= 9.8 * delta * 2

	move_and_slide()
