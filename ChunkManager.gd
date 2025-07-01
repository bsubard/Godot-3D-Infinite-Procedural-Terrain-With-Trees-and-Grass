# ChunkManager.gd
extends Node3D

# --- Exports ---
@export var player: CharacterBody3D
@export var chunk_scene: PackedScene
@export var render_distance: int = 4
@export var update_interval: float = 0.5
@export var chunk_size_x: int = 32
@export var chunk_size_z: int = 32
@export var overall_scale: float = 10.0
@export var lod_update_interval: float = 0.1 # Update LOD 10 times per second

# --- Internal State ---
var active_chunks: Dictionary = {}
var current_player_chunk_coords: Vector2i = Vector2i(9999, 9999)
var update_timer: float = 0.0
var lod_update_timer: float = 0.0 # <-- NEW: Timer specifically for LOD updates

# Pre-calculate effective size for efficiency
var effective_chunk_size_x: float
var effective_chunk_size_z: float

func _ready():
	effective_chunk_size_x = chunk_size_x * overall_scale
	effective_chunk_size_z = chunk_size_z * overall_scale

	if effective_chunk_size_x <= 0 or effective_chunk_size_z <= 0:
		printerr("ChunkManager: Invalid overall_scale resulted in zero or negative effective chunk size!")
		effective_chunk_size_x = 1.0
		effective_chunk_size_z = 1.0
		set_process(false) # Stop processing if config is bad

	update_chunks() # Initial chunk load

# --- MODIFIED: _process() ---
func _process(delta: float) -> void:
	# --- Handle chunk loading/unloading based on its own interval ---
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0 # Reset timer
		
		var new_coords = get_chunk_coords_from_pos(player.global_position)
		if new_coords != current_player_chunk_coords:
			update_chunks()
			
	# --- NEW: Handle grass LOD updates based on its own, faster interval ---
	lod_update_timer += delta
	if lod_update_timer >= lod_update_interval:
		lod_update_timer = 0.0 # Reset timer
		
		var player_pos = player.global_position
		# Iterate through all currently active chunks
		for chunk in active_chunks.values():
			if is_instance_valid(chunk):
				# Call the function we created in Chunk.gd
				chunk.update_grass_lod(player_pos)

# --- UNCHANGED FUNCTIONS BELOW ---

func get_chunk_coords_from_pos(pos: Vector3) -> Vector2i:
	if effective_chunk_size_x == 0 or effective_chunk_size_z == 0:
		printerr("Cannot calculate chunk coords: Effective chunk size is zero.")
		return Vector2i(9999,9999)

	return Vector2i( floori(pos.x / effective_chunk_size_x), floori(pos.z / effective_chunk_size_z) )

func update_chunks() -> void:
	var new_coords = get_chunk_coords_from_pos(player.global_position)

	if new_coords == current_player_chunk_coords:
		return

	current_player_chunk_coords = new_coords

	var required: Dictionary = {}
	for x in range(current_player_chunk_coords.x - render_distance, current_player_chunk_coords.x + render_distance + 1):
		for z in range(current_player_chunk_coords.y - render_distance, current_player_chunk_coords.y + render_distance + 1):
			required[Vector2i(x, z)] = true

	for coord in active_chunks.keys().duplicate():
		if not required.has(coord):
			unload_chunk(coord)

	for coord in required.keys():
		if not active_chunks.has(coord):
			load_chunk(coord)

func load_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		printerr("Attempted to load chunk that is already active: ", coord)
		return

	var chunk = chunk_scene.instantiate()
	add_child(chunk)

	if chunk.has_method("initialize_chunk"):
		chunk.initialize_chunk(coord)
		active_chunks[coord] = chunk
	else:
		printerr("Instantiated chunk scene does not have 'initialize_chunk' method!")
		chunk.queue_free()

func unload_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		var chunk_to_remove = active_chunks[coord]
		active_chunks.erase(coord)

		if is_instance_valid(chunk_to_remove):
			chunk_to_remove.queue_free()
	else:
		printerr("Attempted to unload chunk that is not active: ", coord)
