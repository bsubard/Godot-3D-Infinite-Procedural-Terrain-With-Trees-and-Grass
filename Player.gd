extends CharacterBody3D

# --- Player Movement ---
const SPEED = 10.0
const JUMP_VELOCITY = 5
const MAX_SPEED = 25.0  # Maximum movement speed
const MIN_SPEED = 2.0   # Minimum movement speed
var current_speed: float = SPEED
@onready var pivot: Node3D = $Node3D
@export var sensitivity = 0.25

# --- Camera Zoom (Hybrid TPV/FPV) ---
@export_group("Camera Zoom")
@export var zoom_speed: float = 0.5
# How far IN FRONT of the pivot the camera will go for FPV (use a negative value).
@export var max_zoom_in: float = -0.5 
# How far BEHIND the pivot the camera will go for TPV.
@export var max_zoom_out: float = 8.0
@export var default_zoom: float = 5.0
var current_zoom_level: float

# Optional: Reference to your player's mesh to hide it in FPV
@export var player_mesh: MeshInstance3D

# --- Underwater Effect ---
@export_group("Underwater Effect")
@export var water_level: float = -3.6
@export var underwater_fog_color: Color = Color(0.1, 0.4, 0.6)
@export var underwater_fog_density: float = 0.1

# --- Node References (Updated for new structure) ---
# The Camera3D is now deeper in the hierarchy.
@onready var camera: Camera3D = $Node3D/SpringArm3D/CameraMount/Camera3D
@onready var spring_arm: SpringArm3D = $Node3D/SpringArm3D
@export var world_environment: WorldEnvironment

# --- Original State Storage ---
var original_fog_color: Color
var original_fog_density: float

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_zoom_level = default_zoom
	current_speed = SPEED
	
	if world_environment and world_environment.environment:
		original_fog_color = world_environment.environment.fog_light_color
		original_fog_density = world_environment.environment.fog_density
	else:
		print_debug("Warning: WorldEnvironment or its Environment resource not found. Underwater effect will be disabled.")

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		pivot.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-90), deg_to_rad(45))
		
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom_level -= zoom_speed
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom_level += zoom_speed
			
		current_zoom_level = clamp(current_zoom_level, max_zoom_in, max_zoom_out)

func _physics_process(delta: float):
	# --- Player Movement Logic (unchanged) ---
	handle_movement(delta)
	
	# --- Camera Zoom Update Logic ---
	update_camera_zoom()
	
	# --- Underwater Effect Logic (unchanged) ---
	handle_underwater_effect()

# I've moved the logic into functions for better organization
func handle_movement(delta: float):
	if Input.is_action_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY
	
	# Speed control with page up/down
	if Input.is_action_pressed("ui_page_up"):
		current_speed = min(current_speed + 20.0 * delta, MAX_SPEED)
	elif Input.is_action_pressed("ui_page_down"):
		current_speed = max(current_speed - 20.0 * delta, MIN_SPEED)
	
	var direction = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S): direction += transform.basis.z
	if Input.is_key_pressed(KEY_A): direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D): direction += transform.basis.x
	
	direction.y = 0
	direction = direction.normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if Input.is_key_pressed(KEY_SHIFT):
		velocity.x *= 2
		velocity.z *= 2

	velocity.y -= 9.8 * delta * 2
	move_and_slide()

# --- THE WORKING HYBRID ZOOM FUNCTION ---
func update_camera_zoom():
	# If zoom is positive, we are in third-person view.
	if current_zoom_level > 0:
		# Set the SpringArm's length to control the TPV distance.
		spring_arm.spring_length = current_zoom_level
		# Ensure the camera is at the base position of its mount.
		camera.position.z = 0
		# Show the player mesh.
		if player_mesh:
			player_mesh.visible = true
			
	# If zoom is zero or negative, we are in first-person view.
	else:
		# Set the SpringArm's length to 0. This brings its child (the CameraMount)
		# right up to the pivot point.
		spring_arm.spring_length = 0
		# Now, we move the CAMERA forward from the CameraMount's position.
		# A negative Z value moves it forward. This works because the SpringArm
		# is no longer controlling the camera directly.
		camera.position.z = current_zoom_level
		# Hide the player mesh.
		if player_mesh:
			player_mesh.visible = false

func handle_underwater_effect():
	if world_environment and world_environment.environment:
		if camera.global_position.y < water_level:
			world_environment.environment.fog_light_color = underwater_fog_color
			world_environment.environment.fog_density = underwater_fog_density
		else:
			world_environment.environment.fog_light_color = original_fog_color
			world_environment.environment.fog_density = original_fog_density
