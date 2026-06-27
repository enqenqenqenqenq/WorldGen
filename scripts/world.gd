extends Node3D
class_name WorldManager

@export var chunk_size: int = 16
@export var load_radius: int = 5

@export var max_ground_height: int = 14
@export var water_level: int = 3

@export var tile_grass: int = 0
@export var tile_dirt: int = 1
@export var tile_stone: int = 2
@export var tile_water: int = 3
@export var tile_sand: int = 4
@export var tile_tree: int = 5
@export var tile_rock: int = 6
@export var tile_leaves: int = 7
@export var tile_gravel: int = 8
@export var tile_mud: int = 9
@export var tile_snow: int = 10
@export var tile_ice: int = 11
@export var tile_clay: int = 12
@export var tile_cactus: int = 13
@export var tile_flower: int = 14

@onready var grid_map: GridMap = $GridMap

var seed: int = 0
var loaded_chunks := {}
var modified_blocks := {}
var current_center_chunk := Vector2i(999999, 999999)

var selected_block: int = 2
var noise_2d: FastNoiseLite
var noise_3d: FastNoiseLite

var base_biome_cache := {}
var height_cache := {}
var surface_zone_cache := {}
var near_water_cache := {}
var temperature_cache := {}


func _ready() -> void:
	selected_block = tile_stone


func setup(p_seed: int, p_modified_blocks: Dictionary) -> void:
	seed = p_seed
	modified_blocks = p_modified_blocks.duplicate(true)
	selected_block = tile_stone
	
	noise_2d = FastNoiseLite.new()
	noise_2d.noise_type = FastNoiseLite.TYPE_VALUE
	noise_2d.seed = p_seed
	
	noise_3d = FastNoiseLite.new()
	noise_3d.noise_type = FastNoiseLite.TYPE_VALUE
	noise_3d.seed = p_seed + 999
	
	_clear_generation_caches()
	clear_all_chunks()


func _clear_generation_caches() -> void:
	base_biome_cache.clear()
	height_cache.clear()
	surface_zone_cache.clear()
	near_water_cache.clear()
	temperature_cache.clear()


func clear_all_chunks() -> void:
	for cells in loaded_chunks.values():
		_clear_chunk_cells(cells)

	loaded_chunks.clear()
	current_center_chunk = Vector2i(999999, 999999)


func update_world(player_world_pos: Vector3) -> void:
	var center_chunk = _world_to_chunk(player_world_pos.x, player_world_pos.z)

	if center_chunk == current_center_chunk and loaded_chunks.size() > 0:
		return

	current_center_chunk = center_chunk

	var needed := {}

	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			var chunk_coord = Vector2i(center_chunk.x + dx, center_chunk.y + dz)
			needed[chunk_coord] = true

			if not loaded_chunks.has(chunk_coord):
				loaded_chunks[chunk_coord] = _generate_and_build_chunk(chunk_coord.x, chunk_coord.y)

	var to_remove := []

	for chunk_coord in loaded_chunks.keys():
		if not needed.has(chunk_coord):
			to_remove.append(chunk_coord)

	for chunk_coord in to_remove:
		_clear_chunk_cells(loaded_chunks[chunk_coord])
		loaded_chunks.erase(chunk_coord)


func pick_block(camera: Camera3D, max_distance: float = 8.0, step_size: float = 0.1) -> Dictionary:
	var screen_point = get_viewport().get_visible_rect().size / 2.0
	var origin = camera.project_ray_origin(screen_point)
	var direction = camera.project_ray_normal(screen_point)

	var last_cell = Vector3i(999999, 999999, 999999)
	var last_empty = null
	var steps = int(max_distance / step_size)

	for i in range(steps):
		var point = origin + direction * (i * step_size)
		var cell = grid_map.local_to_map(grid_map.to_local(point))

		if cell == last_cell:
			continue

		last_cell = cell

		var item = grid_map.get_cell_item(cell)
		if item == GridMap.INVALID_CELL_ITEM:
			last_empty = cell
		else:
			return {
				"hit": cell,
				"place": last_empty
			}

	return {}


func set_modified_cell(cell: Vector3i, block_type: int) -> void:
	grid_map.set_cell_item(cell, block_type)
	modified_blocks[_coord_key(cell.x, cell.y, cell.z)] = block_type


func get_current_chunk() -> Vector2i:
	return current_center_chunk


func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()


func get_biome_at_position(world_pos: Vector3) -> String:
	var wx = floori(world_pos.x)
	var wz = floori(world_pos.z)

	var base_biome = _get_base_biome_cached(wx, wz)
	var height = _get_height_cached(wx, wz, base_biome)

	if height < water_level:
		var temperature = _get_temperature_cached(wx, wz, height)
		if temperature < 0.30:
			return "FrozenWater"
		return "Water"

	return _get_surface_zone_cached(wx, wz, base_biome, height)


func get_selected_block_name() -> String:
	if selected_block == tile_grass:
		return "Grass"
	if selected_block == tile_stone:
		return "Stone"
	if selected_block == tile_sand:
		return "Sand"
	return "Unknown"


func _generate_and_build_chunk(cx: int, cz: int) -> Array:
	var placed_cells: Array = []

	for lx in range(chunk_size):
		for lz in range(chunk_size):
			var wx = cx * chunk_size + lx
			var wz = cz * chunk_size + lz

			var base_biome = _get_base_biome_cached(wx, wz)
			var height = _get_height_cached(wx, wz, base_biome)
			var surface_zone = _get_surface_zone_cached(wx, wz, base_biome, height)

			_build_column(placed_cells, wx, wz, height, surface_zone)
			_place_surface_objects(placed_cells, wx, wz, height, surface_zone)

	_apply_chunk_modifications(cx, cz, placed_cells)

	return placed_cells


func _build_column(placed_cells: Array, wx: int, wz: int, height: int, surface_zone: String) -> void:
	var top_block = tile_grass
	var filler_block = tile_dirt

	match surface_zone:
		"Plains":
			top_block = tile_grass
			filler_block = tile_dirt
		"FlowerField":
			top_block = tile_grass
			filler_block = tile_dirt
		"MudBank":
			top_block = tile_mud
			filler_block = tile_dirt
		"ClayBank":
			top_block = tile_clay
			filler_block = tile_clay
		"Forest":
			top_block = tile_grass
			filler_block = tile_dirt
		"SparseForest":
			top_block = tile_grass
			filler_block = tile_dirt
		"Beach":
			top_block = tile_sand
			filler_block = tile_sand
		"Desert":
			top_block = tile_sand
			filler_block = tile_sand
		"Dunes":
			top_block = tile_sand
			filler_block = tile_sand
		"RockyDesert":
			top_block = tile_gravel
			filler_block = tile_sand
		"RockyField":
			top_block = tile_gravel
			filler_block = tile_stone
		"Ridge":
			top_block = tile_stone
			filler_block = tile_stone
		"SnowField":
			top_block = tile_snow
			filler_block = tile_dirt
		"FrozenShore":
			top_block = tile_snow
			filler_block = tile_clay

	for y in range(height + 1):
		var block_to_place = tile_stone
		var depth_from_surface = height - y

		if y == height:
			block_to_place = top_block
		elif depth_from_surface <= 2:
			block_to_place = filler_block
		else:
			block_to_place = tile_stone

			if _coord_random(wx + y * 17, wz, 1400, 0, 99) < 10:
				block_to_place = tile_gravel

		if [tile_stone, tile_gravel].has(block_to_place) and depth_from_surface > 2:
			if _is_cave(wx, y, wz):
				continue

		_place_cell(placed_cells, Vector3i(wx, y, wz), block_to_place)

	if height < water_level:
		var frozen = _is_frozen_surface(wx, wz, height)

		for y in range(height + 1, water_level + 1):
			var water_block = tile_water

			if frozen and y == water_level:
				water_block = tile_ice

			_place_cell(placed_cells, Vector3i(wx, y, wz), water_block)


func _place_surface_objects(placed_cells: Array, wx: int, wz: int, height: int, surface_zone: String) -> void:
	if height < water_level:
		return

	if _should_place_tree(wx, wz, surface_zone):
		_place_tree(placed_cells, wx, wz, height)
		return

	if _should_place_cactus(wx, wz, surface_zone):
		_place_cactus(placed_cells, wx, wz, height)
		return

	if _should_place_rock_cluster(wx, wz, surface_zone):
		_place_boulder_cluster(placed_cells, wx, wz)
		return

	if _should_place_bush(wx, wz, surface_zone):
		_place_bush(placed_cells, wx, wz, height)
		return

	if _should_place_flower(wx, wz, surface_zone):
		_place_flower(placed_cells, wx, wz, height)


func _place_tree(placed_cells: Array, wx: int, wz: int, height: int) -> void:
	var trunk_height = 3 + _coord_random(wx, wz, 740, 0, 1)

	for i in range(1, trunk_height + 1):
		_place_cell(placed_cells, Vector3i(wx, height + i, wz), tile_tree)

	var top_y = height + trunk_height

	var leaves = [
		Vector3i(0, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
		Vector3i(0, 1, 0),
		Vector3i(1, -1, 0),
		Vector3i(-1, -1, 0),
		Vector3i(0, -1, 1),
		Vector3i(0, -1, -1)
	]

	for offset in leaves:
		_place_cell(placed_cells, Vector3i(wx + offset.x, top_y + offset.y, wz + offset.z), tile_leaves)


func _place_cactus(placed_cells: Array, wx: int, wz: int, height: int) -> void:
	var cactus_height = 2 + _coord_random(wx, wz, 760, 0, 2)

	for i in range(1, cactus_height + 1):
		_place_cell(placed_cells, Vector3i(wx, height + i, wz), tile_cactus)


func _place_bush(placed_cells: Array, wx: int, wz: int, height: int) -> void:
	_place_cell(placed_cells, Vector3i(wx, height + 1, wz), tile_leaves)


func _place_flower(placed_cells: Array, wx: int, wz: int, height: int) -> void:
	_place_cell(placed_cells, Vector3i(wx, height + 1, wz), tile_flower)


func _place_boulder_cluster(placed_cells: Array, wx: int, wz: int) -> void:
	var shapes = [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
	]

	var shape_index = _coord_random(wx, wz, 750, 0, shapes.size() - 1)
	var shape = shapes[shape_index]

	for offset in shape:
		var px = wx + offset.x
		var pz = wz + offset.y

		var base_biome = _get_base_biome_cached(px, pz)
		var h = _get_height_cached(px, pz, base_biome)

		if h < water_level:
			continue

		_place_cell(placed_cells, Vector3i(px, h + 1, pz), tile_rock)

		if offset == Vector2i(0, 0) or _coord_random(px, pz, 751, 0, 99) < 30:
			_place_cell(placed_cells, Vector3i(px, h + 2, pz), tile_rock)


func _should_place_tree(wx: int, wz: int, surface_zone: String) -> bool:
	var density = _value_noise_2d(float(wx), float(wz), 90.0, 700)

	match surface_zone:
		"Forest":
			if density < 0.45:
				return false
			var anchor = _cell_anchor_position(wx, wz, 5, 720)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 721, 0, 99) < 75

		"SparseForest":
			if density < 0.58:
				return false
			var anchor = _cell_anchor_position(wx, wz, 8, 722)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 723, 0, 99) < 65

		"Plains":
			if density < 0.83:
				return false
			var anchor = _cell_anchor_position(wx, wz, 14, 724)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 725, 0, 99) < 25

	return false


func _should_place_cactus(wx: int, wz: int, surface_zone: String) -> bool:
	var density = _value_noise_2d(float(wx), float(wz), 80.0, 730)

	if not ["Desert", "Dunes", "RockyDesert"].has(surface_zone):
		return false

	if density < 0.52:
		return false

	var anchor = _cell_anchor_position(wx, wz, 8, 731)
	if anchor != Vector2i(wx, wz):
		return false

	return _coord_random(wx, wz, 732, 0, 99) < 65


func _should_place_bush(wx: int, wz: int, surface_zone: String) -> bool:
	var density = _value_noise_2d(float(wx), float(wz), 60.0, 740)

	match surface_zone:
		"Plains":
			if density < 0.54:
				return false
			var anchor = _cell_anchor_position(wx, wz, 7, 741)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 742, 0, 99) < 35

		"MudBank":
			if density < 0.44:
				return false
			var anchor = _cell_anchor_position(wx, wz, 6, 743)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 744, 0, 99) < 40

		"SparseForest":
			if density < 0.48:
				return false
			var anchor = _cell_anchor_position(wx, wz, 8, 745)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 746, 0, 99) < 35

	return false


func _should_place_flower(wx: int, wz: int, surface_zone: String) -> bool:
	var density = _value_noise_2d(float(wx), float(wz), 55.0, 750)

	match surface_zone:
		"FlowerField":
			if density < 0.38:
				return false
			var anchor = _cell_anchor_position(wx, wz, 4, 751)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 752, 0, 99) < 55

		"Plains":
			if density < 0.74:
				return false
			var anchor = _cell_anchor_position(wx, wz, 10, 753)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 754, 0, 99) < 28

	return false


func _should_place_rock_cluster(wx: int, wz: int, surface_zone: String) -> bool:
	var density = _value_noise_2d(float(wx), float(wz), 95.0, 760)

	match surface_zone:
		"RockyField":
			if density < 0.52:
				return false
			var anchor = _cell_anchor_position(wx, wz, 8, 761)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 762, 0, 99) < 80

		"Ridge":
			if density < 0.46:
				return false
			var anchor = _cell_anchor_position(wx, wz, 7, 763)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 764, 0, 99) < 82

		"RockyDesert":
			if density < 0.58:
				return false
			var anchor = _cell_anchor_position(wx, wz, 9, 765)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 766, 0, 99) < 75

		"FrozenShore":
			if density < 0.60:
				return false
			var anchor = _cell_anchor_position(wx, wz, 10, 767)
			if anchor != Vector2i(wx, wz):
				return false
			return _coord_random(wx, wz, 768, 0, 99) < 45

	return false


func _cell_anchor_position(wx: int, wz: int, cell_size: int, salt: int) -> Vector2i:
	var cell_x = floori(float(wx) / float(cell_size))
	var cell_z = floori(float(wz) / float(cell_size))

	var local_x = _coord_random(cell_x, cell_z, salt, 0, cell_size - 1)
	var local_z = _coord_random(cell_x, cell_z, salt + 1, 0, cell_size - 1)

	return Vector2i(
		cell_x * cell_size + local_x,
		cell_z * cell_size + local_z
	)


func _apply_chunk_modifications(cx: int, cz: int, placed_cells: Array) -> void:
	for key in modified_blocks.keys():
		var pos = _key_to_vec3i(key)
		var chunk_coord = _world_to_chunk(pos.x, pos.z)

		if chunk_coord.x == cx and chunk_coord.y == cz:
			var block_type = int(modified_blocks[key])
			grid_map.set_cell_item(pos, block_type)
			placed_cells.append(pos)


func _place_cell(placed_cells: Array, cell: Vector3i, tile_id: int) -> void:
	grid_map.set_cell_item(cell, tile_id)
	placed_cells.append(cell)


func _clear_chunk_cells(cells: Array) -> void:
	for cell in cells:
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


func _world_to_chunk(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(
		floori(world_x / float(chunk_size)),
		floori(world_z / float(chunk_size))
	)


func _get_base_biome_cached(wx: int, wz: int) -> String:
	var key = _v2_key(Vector2i(wx, wz))

	if base_biome_cache.has(key):
		return base_biome_cache[key]

	var value = _get_base_biome(wx, wz)
	base_biome_cache[key] = value
	return value


func _get_height_cached(wx: int, wz: int, base_biome: String) -> int:
	var key = _v2_key(Vector2i(wx, wz))

	if height_cache.has(key):
		return height_cache[key]

	var value = _get_height(wx, wz, base_biome)
	height_cache[key] = value
	return value


func _get_surface_zone_cached(wx: int, wz: int, base_biome: String, height: int) -> String:
	var key = _v2_key(Vector2i(wx, wz))

	if surface_zone_cache.has(key):
		return surface_zone_cache[key]

	var value = _get_surface_zone(wx, wz, base_biome, height)
	surface_zone_cache[key] = value
	return value


func _get_temperature_cached(wx: int, wz: int, height: int) -> float:
	var key = _v2_key(Vector2i(wx, wz))

	if temperature_cache.has(key):
		return temperature_cache[key]

	var value = _get_temperature(wx, wz, height)
	temperature_cache[key] = value
	return value


func _is_near_water_cached(wx: int, wz: int) -> bool:
	var key = _v2_key(Vector2i(wx, wz))

	if near_water_cache.has(key):
		return near_water_cache[key]

	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var px = wx + dx
			var pz = wz + dz

			var biome = _get_base_biome_cached(px, pz)
			var h = _get_height_cached(px, pz, biome)

			if h <= water_level:
				near_water_cache[key] = true
				return true

	near_water_cache[key] = false
	return false


func _get_base_biome(wx: int, wz: int) -> String:
	var dryness = _value_noise_2d(float(wx), float(wz), 260.0, 100)
	var humidity = _value_noise_2d(float(wx), float(wz), 220.0, 101)
	var roughness = _value_noise_2d(float(wx), float(wz), 240.0, 102)

	if roughness > 0.76 and dryness > 0.42:
		return "Rocky"
	elif dryness > 0.68 and humidity < 0.45:
		return "Desert"
	elif humidity > 0.60:
		return "Forest"
	else:
		return "Plains"


func _get_surface_zone(wx: int, wz: int, base_biome: String, height: int) -> String:
	var near_water = _is_near_water_cached(wx, wz)
	var temperature = _get_temperature_cached(wx, wz, height)
	var micro = _value_noise_2d(float(wx), float(wz), 42.0, 200)
	var ridge = _ridge_noise_2d(float(wx), float(wz), 96.0, 201)

	if temperature < 0.28 and height >= water_level + 2:
		return "SnowField"

	if near_water and temperature < 0.32 and height <= water_level + 1:
		return "FrozenShore"

	match base_biome:
		"Plains":
			if near_water and micro < 0.34:
				return "MudBank"
			elif near_water and micro > 0.72:
				return "ClayBank"
			elif ridge > 0.58:
				return "Hills"
			elif micro > 0.70:
				return "FlowerField"
			else:
				return "Plains"

		"Forest":
			if ridge > 0.60:
				return "SparseForest"
			else:
				return "Forest"

		"Desert":
			if near_water and height <= water_level + 1:
				return "Beach"
			elif ridge > 0.60:
				return "Dunes"
			elif micro > 0.66:
				return "RockyDesert"
			else:
				return "Desert"

		"Rocky":
			if near_water and height <= water_level + 1:
				return "FrozenShore" if temperature < 0.32 else "Beach"
			elif ridge > 0.56:
				return "Ridge"
			else:
				return "RockyField"

	return "Plains"


func _get_temperature(wx: int, wz: int, height: int) -> float:
	var base_temp = _value_noise_2d(float(wx), float(wz), 320.0, 300)
	base_temp -= float(height) / float(max_ground_height + 2) * 0.38
	return clampf(base_temp, 0.0, 1.0)


func _is_frozen_surface(wx: int, wz: int, height: int) -> bool:
	var temperature = _get_temperature_cached(wx, wz, height)
	return temperature < 0.30


func _get_height(wx: int, wz: int, base_biome: String) -> int:
	var continent = _value_noise_2d(float(wx), float(wz), 420.0, 1) * 8.5
	var broad_land = _value_noise_2d(float(wx), float(wz), 220.0, 2) * 5.2
	var hills = _value_noise_2d(float(wx), float(wz), 72.0, 3) * 3.5
	var detail = _value_noise_2d(float(wx), float(wz), 24.0, 4) * 1.2
	var ridge = _ridge_noise_2d(float(wx), float(wz), 96.0, 5) * 4.0
	var basin = _value_noise_2d(float(wx), float(wz), 180.0, 6) * 2.0

	var height = continent + broad_land + hills + detail + ridge * 0.55 - basin - 4.5

	match base_biome:
		"Rocky":
			height += 1.6 + ridge * 0.8
		"Desert":
			height = lerpf(height, float(water_level) + 1.0, 0.22)
		"Forest":
			height += 0.4

	return clampi(int(round(height)), 0, max_ground_height)


func _ridge_noise_2d(x: float, z: float, cell_size: float, salt: int) -> float:
	var n = _value_noise_2d(x, z, cell_size, salt)
	var r = 1.0 - abs(n * 2.0 - 1.0)
	return pow(r, 2.5)


func _is_cave(wx: int, wy: int, wz: int) -> bool:
	if wy <= 1:
		return false
	if wy >= 8:
		return false

	var tunnel = _value_noise_3d(float(wx), float(wy), float(wz), 13.0, 900)
	var detail = _value_noise_3d(float(wx), float(wy), float(wz), 7.0, 901)
	var chamber = _value_noise_3d(float(wx), float(wy), float(wz), 22.0, 902)

	var cave_value = tunnel * 0.60 + detail * 0.20 + chamber * 0.20
	var depth_factor = 1.0 - (float(wy) / 8.0)

	return cave_value > (0.80 - depth_factor * 0.08)


func _value_noise_2d(x: float, z: float, cell_size: float, salt: int) -> float:
	noise_2d.frequency = 1.0 / cell_size
	var val = noise_2d.get_noise_2d(x + salt * 31.0, z + salt * 7.0)
	return (val + 1.0) / 2.0 

func _value_noise_3d(x: float, y: float, z: float, cell_size: float, salt: int) -> float:
	noise_3d.frequency = 1.0 / cell_size
	var val = noise_3d.get_noise_3d(x + salt * 17.0, y + salt * 13.0, z + salt * 3.0)
	return (val + 1.0) / 2.0 
	var grid_x = x / cell_size
	var grid_y = y / cell_size
	var grid_z = z / cell_size

	var x0 = floori(grid_x)
	var y0 = floori(grid_y)
	var z0 = floori(grid_z)

	var x1 = x0 + 1
	var y1 = y0 + 1
	var z1 = z0 + 1

	var tx = _smoothstep(grid_x - float(x0))
	var ty = _smoothstep(grid_y - float(y0))
	var tz = _smoothstep(grid_z - float(z0))

	var v000 = _hash01_3d(x0, y0, z0, salt)
	var v100 = _hash01_3d(x1, y0, z0, salt)
	var v010 = _hash01_3d(x0, y1, z0, salt)
	var v110 = _hash01_3d(x1, y1, z0, salt)

	var v001 = _hash01_3d(x0, y0, z1, salt)
	var v101 = _hash01_3d(x1, y0, z1, salt)
	var v011 = _hash01_3d(x0, y1, z1, salt)
	var v111 = _hash01_3d(x1, y1, z1, salt)

	var x00 = lerpf(v000, v100, tx)
	var x10 = lerpf(v010, v110, tx)
	var x01 = lerpf(v001, v101, tx)
	var x11 = lerpf(v011, v111, tx)

	var y0_mix = lerpf(x00, x10, ty)
	var y1_mix = lerpf(x01, x11, ty)

	return lerpf(y0_mix, y1_mix, tz)


func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _hash01(ix: int, iz: int, salt: int) -> float:
	var h = int(seed) * 73428767 + ix * 912931 + iz * 438289 + salt * 11939
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0

func _hash01_3d(ix: int, iy: int, iz: int, salt: int) -> float:
	var h = int(seed) * 73428767 + ix * 912931 + iy * 381721 + iz * 438289 + salt * 11939
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0

func _coord_random(a: int, b: int, salt: int, min_v: int, max_v: int) -> int:
	var h = int(seed) * 1000003 + a * 92837111 + b * 689287499 + salt * 283923481
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	var range_size = max_v - min_v + 1
	return min_v + (abs(h) % range_size)


func _v2_key(pos: Vector2i) -> String:
	return "%d:%d" % [pos.x, pos.y]


func _coord_key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]


func _key_to_vec3i(key: String) -> Vector3i:
	var parts = key.split(":")
	return Vector3i(
		parts[0].to_int(),
		parts[1].to_int(),
		parts[2].to_int()
	)
