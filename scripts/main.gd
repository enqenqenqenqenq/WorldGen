extends Node3D

const START_POSITION := Vector3(8.0, 8.0, 8.0)
const DEFAULT_SEED := 123456789

@onready var world: WorldManager = $World
@onready var player: FreeFlyPlayer = $Player
@onready var database_manager: DatabaseManager = $DatabaseManager

@onready var debug_label: Label = $CanvasLayer/MarginContainer/VBoxContainer/DebugLabel
@onready var save_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/SaveButton
@onready var reload_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/ReloadButton
@onready var new_world_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/HBoxContainer/NewWorldButton

var world_id: int = -1
var world_seed: int = DEFAULT_SEED
var _last_checked_pos := Vector3(999999, 999999, 999999)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	save_button.pressed.connect(_on_save_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	new_world_button.pressed.connect(_on_new_world_button_pressed)

	save_button.text = "Save"
	reload_button.text = "Reload"
	new_world_button.text = "New World"

	database_manager.open_database()

	var world_row = database_manager.get_or_create_latest_world(DEFAULT_SEED)
	world_id = int(world_row["id"])
	world_seed = int(world_row["seed"])

	var loaded_mods = database_manager.load_modified_blocks(world_id)
	world.setup(world_seed, loaded_mods)

	var loaded_pos = database_manager.load_player_state(world_id)
	if loaded_pos == null:
		player.global_position = START_POSITION
	else:
		player.global_position = loaded_pos

	world.update_world(player.global_position)
	_update_debug_text()


func _process(_delta: float) -> void:
	_update_debug_text()
	
	var current_block_pos = player.global_position.floor()
	if current_block_pos != _last_checked_pos:
		_last_checked_pos = current_block_pos
		world.update_world(player.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				world.selected_block = world.tile_grass
			KEY_2:
				world.selected_block = world.tile_stone
			KEY_3:
				world.selected_block = world.tile_sand

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var result = world.pick_block(player.get_camera())
			if result.has("hit"):
				world.set_modified_cell(result["hit"], GridMap.INVALID_CELL_ITEM)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var result = world.pick_block(player.get_camera())
			if result.has("place") and result["place"] != null:
				world.set_modified_cell(result["place"], world.selected_block)


func _exit_tree() -> void:
	_save_current_world()


func _save_current_world() -> void:
	if world_id == -1:
		return

	database_manager.save_player_state(world_id, player.global_position)
	database_manager.save_modified_blocks(world_id, world.modified_blocks)


func _on_save_button_pressed() -> void:
	_save_current_world()


func _on_reload_button_pressed() -> void:
	var loaded_mods = database_manager.load_modified_blocks(world_id)
	world.setup(world_seed, loaded_mods)

	var loaded_pos = database_manager.load_player_state(world_id)
	if loaded_pos == null:
		player.global_position = START_POSITION
	else:
		player.global_position = loaded_pos

	world.update_world(player.global_position)


func _on_new_world_button_pressed() -> void:
	_save_current_world()

	var new_seed = int(Time.get_unix_time_from_system())
	var world_row = database_manager.create_world(new_seed)

	world_id = int(world_row["id"])
	world_seed = int(world_row["seed"])

	player.global_position = START_POSITION
	world.setup(world_seed, {})
	database_manager.save_player_state(world_id, player.global_position)
	world.update_world(player.global_position)


func _update_debug_text() -> void:
	var pos = player.global_position
	var chunk = world.get_current_chunk()
	var biome = world.get_biome_at_position(pos)

	debug_label.text = (
		"World ID: %d\n" +
		"Seed: %d\n" +
		"Position: %.2f, %.2f, %.2f\n" +
		"Chunk: %d, %d\n" +
		"Biome: %s\n" +
		"Loaded chunks: %d\n" +
		"Modified blocks: %d\n" +
		"Build block: %s\n\n" +
		"WASD - move\n" +
		"Space / Q - up / down\n" +
		"Shift - faster\n" +
		"Mouse - look\n" +
		"LMB - remove block\n" +
		"RMB - place block\n" +
		"1/2/3 - block select\n" +
		"Esc - release/capture mouse"
	) % [
		world_id,
		world_seed,
		pos.x, pos.y, pos.z,
		chunk.x, chunk.y,
		biome,
		world.get_loaded_chunk_count(),
		world.modified_blocks.size(),
		world.get_selected_block_name()
	]
