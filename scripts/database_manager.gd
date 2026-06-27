extends Node
class_name DatabaseManager

var db: SQLite = null
var save_thread: Thread = null


func _ready() -> void:
	save_thread = Thread.new()


func _exit_tree() -> void:
	if save_thread and save_thread.is_started():
		save_thread.wait_to_finish()


func open_database() -> void:
	db = SQLite.new()
	db.path = "user://chunk_world.db"
	db.foreign_keys = true
	db.verbosity_level = 0

	var ok = db.open_db()
	if not ok:
		push_error("Could not open database: %s" % db.error_message)
		return

	_create_tables()


func _create_tables() -> void:
	db.query("""
		CREATE TABLE IF NOT EXISTS worlds (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			seed INTEGER NOT NULL,
			created_at TEXT DEFAULT CURRENT_TIMESTAMP
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS player_state (
			world_id INTEGER PRIMARY KEY,
			x REAL NOT NULL,
			y REAL NOT NULL,
			z REAL NOT NULL,
			FOREIGN KEY(world_id) REFERENCES worlds(id) ON DELETE CASCADE
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS modified_blocks (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			world_id INTEGER NOT NULL,
			x INTEGER NOT NULL,
			y INTEGER NOT NULL,
			z INTEGER NOT NULL,
			block_type INTEGER NOT NULL,
			UNIQUE(world_id, x, y, z),
			FOREIGN KEY(world_id) REFERENCES worlds(id) ON DELETE CASCADE
		);
	""")


func get_or_create_latest_world(default_seed: int) -> Dictionary:
	var row = get_latest_world()
	if row != null:
		return row
	return create_world(default_seed)


func get_latest_world():
	var ok = db.query("SELECT id, seed FROM worlds ORDER BY id DESC LIMIT 1;")
	if ok and db.query_result.size() > 0:
		return db.query_result[0]
	return null


func create_world(world_seed: int) -> Dictionary:
	var ok = db.query_with_bindings(
		"INSERT INTO worlds (seed) VALUES (?);",
		[world_seed]
	)
	if ok:
		return get_latest_world()
	return {"id": -1, "seed": world_seed}


func save_player_state(world_id: int, position: Vector3) -> void:
	db.query_with_bindings("""
		INSERT INTO player_state (world_id, x, y, z)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(world_id) DO UPDATE SET
			x = excluded.x,
			y = excluded.y,
			z = excluded.z;
	""", [world_id, position.x, position.y, position.z])


func load_player_state(world_id: int):
	var ok = db.query_with_bindings(
		"SELECT x, y, z FROM player_state WHERE world_id = ? LIMIT 1;",
		[world_id]
	)

	if ok and db.query_result.size() > 0:
		var row = db.query_result[0]
		return Vector3(
			float(row["x"]),
			float(row["y"]),
			float(row["z"])
		)
	return null


func load_modified_blocks(world_id: int) -> Dictionary:
	var result := {}
	var ok = db.query_with_bindings(
		"SELECT x, y, z, block_type FROM modified_blocks WHERE world_id = ?;",
		[world_id]
	)

	if not ok:
		return result

	for row in db.query_result:
		var key = _coord_key(
			int(row["x"]),
			int(row["y"]),
			int(row["z"])
		)
		result[key] = int(row["block_type"])

	return result


func save_modified_blocks(world_id: int, modified_blocks: Dictionary) -> void:
	if save_thread.is_started():
		save_thread.wait_to_finish()
	
	var data_to_save = {
		"world_id": world_id,
		"blocks": modified_blocks.duplicate()
	}
	
	save_thread.start(_async_save_task.bind(data_to_save))


func _async_save_task(data: Dictionary) -> void:
	var world_id = data["world_id"]
	var blocks = data["blocks"]
	
	db.query("BEGIN TRANSACTION;")
	
	db.query_with_bindings(
		"DELETE FROM modified_blocks WHERE world_id = ?;",
		[world_id]
	)

	for key in blocks.keys():
		var pos = _parse_key(key)
		var block_type = blocks[key]
		
		db.query_with_bindings("""
			INSERT INTO modified_blocks (world_id, x, y, z, block_type)
			VALUES (?, ?, ?, ?, ?);
		""", [world_id, pos.x, pos.y, pos.z, block_type])
	
	db.query("COMMIT;")


func _coord_key(x: int, y: int, z: int) -> String:
	return "%d:%d:%d" % [x, y, z]


func _parse_key(key: String) -> Vector3i:
	var parts = key.split(":")
	if parts.size() == 3:
		return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return Vector3i.ZERO
