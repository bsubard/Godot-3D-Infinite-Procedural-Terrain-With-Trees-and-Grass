# ChunkManager.gd
# Manages the dynamic loading and unloading of terrain chunks based on player position.
# It also holds the global configuration for world generation features like paths.

extends Node3D

# --- Node & Scene References ---
@export var player: CharacterBody3D
@export var chunk_scene: PackedScene

# --- World Generation Parameters ---
@export var render_distance: int = 4
@export_range(1, 10, 1, "suffix:chunks") var load_trigger_distance: int = 2

# --- Performance & Timing ---
@export var update_interval: float = 0.5
@export var lod_update_interval: float = 0.1

# --- Chunk & Scale Configuration ---
@export var chunk_size_x: int = 32
@export var chunk_size_z: int = 32
@export var overall_scale: float = 10.0

# --- Path Generation ---
@export_group("Path Generation")
@export var noise_path: FastNoiseLite # Noise that defines the course of paths globally.

# --- Internal State ---
var active_chunks: Dictionary = {}
# Stores the center coordinate of the currently loaded grid of chunks.
var world_center_chunk_coords: Vector2i = Vector2i(9999, 9999)
var update_timer: float = 0.0
var lod_update_timer: float = 0.0

# Pre-calculated effective size for efficiency.
var effective_chunk_size_x: float
var effective_chunk_size_z: float


func _ready() -> void:
	# Ensure the trigger distance is logical to prevent constant reloading.
	if load_trigger_distance >= render_distance:
		printerr("ChunkManager: 'load_trigger_distance' should be less than 'render_distance'. Clamping value.")
		load_trigger_distance = max(1, render_distance - 1)

	effective_chunk_size_x = chunk_size_x * overall_scale
	effective_chunk_size_z = chunk_size_z * overall_scale

	if effective_chunk_size_x <= 0 or effective_chunk_size_z <= 0:
		printerr("ChunkManager: Invalid overall_scale resulted in zero or negative effective chunk size!")
		set_process(false)
		return

	# Initial chunk load, centering the world on the player's starting position.
	var player_chunk_pos = get_chunk_coords_from_pos(player.global_position)
	update_chunks(player_chunk_pos)


func _process(delta: float) -> void:
	# Handle chunk loading/unloading based on its own interval.
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0 # Reset timer.
		
		var player_chunk_pos = get_chunk_coords_from_pos(player.global_position)
		
		# Calculate the distance in chunks from the player to the center of the loaded world.
		# We use Chebyshev distance (the greater of the x or z distance) for square grids.
		var dist_x = abs(player_chunk_pos.x - world_center_chunk_coords.x)
		var dist_z = abs(player_chunk_pos.y - world_center_chunk_coords.y)
		
		# If the player has moved outside the "safe zone", trigger a world update.
		if max(dist_x, dist_z) > load_trigger_distance:
			# Pass the player's new position to re-center the world.
			update_chunks(player_chunk_pos)
			
	# Handle grass LOD updates based on its own, faster interval.
	lod_update_timer += delta
	if lod_update_timer >= lod_update_interval:
		lod_update_timer = 0.0 # Reset timer.
		
		var player_pos = player.global_position
		for chunk in active_chunks.values():
			if is_instance_valid(chunk):
				chunk.update_grass_lod(player_pos)


# Converts a world position Vector3 into a chunk coordinate Vector2i.
func get_chunk_coords_from_pos(pos: Vector3) -> Vector2i:
	if effective_chunk_size_x == 0 or effective_chunk_size_z == 0:
		return Vector2i.ZERO # Return a default value on error.
	
	var x = floori(pos.x / effective_chunk_size_x)
	var z = floori(pos.z / effective_chunk_size_z)
	return Vector2i(x, z)


# Re-evaluates which chunks should be loaded based on a new center coordinate.
func update_chunks(new_center_coords: Vector2i) -> void:
	# If the new center is the same as the old one, no work is needed.
	if new_center_coords == world_center_chunk_coords:
		return

	# Set the new center for the loaded world.
	world_center_chunk_coords = new_center_coords

	# Build a dictionary of all chunks that should be loaded around the new center.
	var required_chunks: Dictionary = {}
	for x in range(world_center_chunk_coords.x - render_distance, world_center_chunk_coords.x + render_distance + 1):
		for z in range(world_center_chunk_coords.y - render_distance, world_center_chunk_coords.y + render_distance + 1):
			required_chunks[Vector2i(x, z)] = true

	# Unload chunks: If an active chunk is not in the required list, unload it.
	for coord in active_chunks.keys().duplicate(): # Duplicate keys to safely modify the dictionary.
		if not required_chunks.has(coord):
			unload_chunk(coord)

	# Load chunks: If a required chunk is not in the active list, load it.
	for coord in required_chunks.keys():
		if not active_chunks.has(coord):
			load_chunk(coord)


# Instantiates and initializes a new chunk at the given coordinate.
func load_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		printerr("Attempted to load chunk that is already active: ", coord)
		return

	var chunk = chunk_scene.instantiate()
	add_child(chunk)

	if chunk.has_method("initialize_chunk"):
		# Provide the chunk its coordinates and the global path noise generator.
		chunk.initialize_chunk(coord, noise_path)
		active_chunks[coord] = chunk
	else:
		printerr("Instantiated chunk scene does not have 'initialize_chunk' method!")
		chunk.queue_free()


# Frees the chunk associated with the given coordinate.
func unload_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		var chunk_to_remove = active_chunks[coord]
		active_chunks.erase(coord)

		if is_instance_valid(chunk_to_remove):
			chunk_to_remove.queue_free()
	else:
		printerr("Attempted to unload chunk that is not active: ", coord)
