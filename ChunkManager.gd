# ChunkManager.gd (Thread-Safe Version)
extends Node3D

# --- Exports (Unchanged) ---
@export var player: CharacterBody3D
@export var chunk_scene: PackedScene
@export var render_distance: int = 4
@export var update_interval: float = 0.5
@export var lod_update_interval: float = 0.1

# --- Internal State ---
var active_chunks: Dictionary = {}
var pending_chunks: Dictionary = {}
var current_player_chunk_coords: Vector2i = Vector2i(9999, 9999)
var update_timer: float = 0.0
var lod_update_timer: float = 0.0
var effective_chunk_size_x: float
var effective_chunk_size_z: float

# --- NEW: Dictionary to hold references to running threads ---
var _active_threads: Dictionary = {}

# --- _ready, _process, get_chunk_coords_from_pos are UNCHANGED ---
func _ready():
	var default_chunk = chunk_scene.instantiate()
	effective_chunk_size_x = default_chunk.chunk_size_x * default_chunk.overall_scale
	effective_chunk_size_z = default_chunk.chunk_size_z * default_chunk.overall_scale
	default_chunk.queue_free()
	if effective_chunk_size_x <= 0 or effective_chunk_size_z <= 0:
		printerr("ChunkManager: Invalid chunk size or scale!")
		set_process(false); return
	update_chunks()

func _process(delta: float):
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		var new_coords = get_chunk_coords_from_pos(player.global_position)
		if new_coords != current_player_chunk_coords:
			update_chunks()
	lod_update_timer += delta
	if lod_update_timer >= lod_update_interval:
		lod_update_timer = 0.0
		var player_pos = player.global_position
		for chunk in active_chunks.values():
			if is_instance_valid(chunk):
				chunk.update_grass_lod(player_pos)

func get_chunk_coords_from_pos(pos: Vector3) -> Vector2i:
	return Vector2i( floori(pos.x / effective_chunk_size_x), floori(pos.z / effective_chunk_size_z) )

# --- update_chunks is UNCHANGED ---
func update_chunks():
	current_player_chunk_coords = get_chunk_coords_from_pos(player.global_position)
	var required: Dictionary = {}
	for x in range(current_player_chunk_coords.x - render_distance, current_player_chunk_coords.x + render_distance + 1):
		for z in range(current_player_chunk_coords.y - render_distance, current_player_chunk_coords.y + render_distance + 1):
			required[Vector2i(x, z)] = true
	for coord in active_chunks.keys().duplicate():
		if not required.has(coord): unload_chunk(coord)
	for coord in required.keys():
		if not active_chunks.has(coord) and not pending_chunks.has(coord):
			pending_chunks[coord] = true
			_start_chunk_generation_thread(coord)

# --- MODIFIED: _start_chunk_generation_thread ---
func _start_chunk_generation_thread(coord: Vector2i):
	var default_chunk = chunk_scene.instantiate()
	var thread_data = {
		"coords": coord,
		"chunk_size_x": default_chunk.chunk_size_x, "chunk_size_z": default_chunk.chunk_size_z,
		"vertices_x": default_chunk.vertices_x, "vertices_z": default_chunk.vertices_z,
		"overall_scale": default_chunk.overall_scale,
		"noise_continent": default_chunk.noise_continent, "continent_slope_scale": default_chunk.continent_slope_scale,
		"continent_min_height": default_chunk.continent_min_height, "continent_max_height": default_chunk.continent_max_height,
		"noise_mountain": default_chunk.noise_mountain, "mountain_scale": default_chunk.mountain_scale,
		"mountain_start_height": default_chunk.mountain_start_height, "mountain_fade_height": default_chunk.mountain_fade_height,
		"noise_valley": default_chunk.noise_valley, "valley_carve_scale": default_chunk.valley_carve_scale,
		"valley_apply_threshold": default_chunk.valley_apply_threshold,
		"noise_erosion": default_chunk.noise_erosion, "erosion_scale": default_chunk.erosion_scale,
		"grass_min_height": default_chunk.grass_min_height, "grass_max_height": default_chunk.grass_max_height,
		"grass_max_slope_normal_y": default_chunk.grass_max_slope_normal_y, "grass_density": default_chunk.grass_density,
		"grass_rotation_min_degrees": default_chunk.grass_rotation_min_degrees, "grass_rotation_max_degrees": default_chunk.grass_rotation_max_degrees,
		"grass_scale_min": default_chunk.grass_scale_min, "grass_scale_max": default_chunk.grass_scale_max,
		"tree_min_height": default_chunk.tree_min_height, "tree_max_height": default_chunk.tree_max_height,
		"tree_max_slope_normal_y": default_chunk.tree_max_slope_normal_y, "tree_density": default_chunk.tree_density,
		"tree_scale_min": default_chunk.tree_scale_min, "tree_scale_max": default_chunk.tree_scale_max,
	}
	default_chunk.queue_free()
	
	var generator = ChunkGeneratorThread.new()
	var thread = Thread.new()
	
	# NEW: Store references to the generator and thread objects so they don't get garbage collected.
	# We store them both because the signal connection is on the generator object.
	_active_threads[coord] = {
		"generator": generator,
		"thread": thread
	}
	
	generator.chunk_generated.connect(_on_chunk_generated, CONNECT_DEFERRED)
	thread.start(generator.run_generation.bind(thread_data))

# --- MODIFIED: _on_chunk_generated ---
func _on_chunk_generated(data_packet: Dictionary):
	var coord = data_packet.coords
	
	# NEW: Clean up the completed thread before doing anything else.
	if _active_threads.has(coord):
		var thread_obj = _active_threads[coord].thread
		thread_obj.wait_to_finish() # This is the crucial cleanup step.
		_active_threads.erase(coord) # Remove from the dictionary.

	if pending_chunks.has(coord): pending_chunks.erase(coord)
	
	var required_now = get_chunk_coords_from_pos(player.global_position)
	var dist_x = abs(coord.x - required_now.x)
	var dist_z = abs(coord.y - required_now.y)
	if dist_x > render_distance or dist_z > render_distance: return
		
	var chunk = chunk_scene.instantiate()
	add_child(chunk)
	chunk.chunk_coords = coord
	chunk.global_position.x = coord.x * effective_chunk_size_x
	chunk.global_position.z = coord.y * effective_chunk_size_z
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	
	chunk.apply_generated_data(data_packet)
	active_chunks[coord] = chunk

# --- unload_chunk is UNCHANGED ---
func unload_chunk(coord: Vector2i):
	if active_chunks.has(coord):
		var chunk_to_remove = active_chunks[coord]
		active_chunks.erase(coord)
		if is_instance_valid(chunk_to_remove):
			chunk_to_remove.queue_free()
