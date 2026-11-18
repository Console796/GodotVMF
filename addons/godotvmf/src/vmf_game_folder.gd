@tool
class_name VMFGameFolder extends RefCounted

## Makes the project usable as a level editor's game folder (Hammer, Apex): writes a minimal
## gameinfo.txt where godot_vmf/import/gameinfo_path points, so the editor finds the project's
## materials/, models/ and FGD there.
##
## Only a gameinfo.txt inside the project is written, and only when there is none yet or the
## existing one starts with MARKER. Remove that line to keep your own edits.

const MARKER = "// Written by GodotVMF. Remove this line to keep your edits.";
const WRITE_SETTING = "godot_vmf/game_folder/write_gameinfo";
const SEARCH_PATHS_SETTING = "godot_vmf/game_folder/extra_search_paths";

## The game folder as a path, from godot_vmf/import/gameinfo_path (a folder or its gameinfo.txt).
static func directory() -> String:
	var path: String = VMFConfig.gameinfo_path;
	if path.get_file().to_lower() == "gameinfo.txt":
		path = path.get_base_dir();
	return path;

## The game folder when it is inside the project, else "".
static func project_directory() -> String:
	var path := directory();
	return path if path.begins_with("res://") else "";

static func _quoted(text: String) -> String:
	# KeyValues strings can't hold a double quote; Windows separators become forward slashes.
	return "\"" + text.replace("\"", "'").replace("\\", "/") + "\"";

## gameinfo.txt for a game called game_name that mounts its own folder, then each of extra_paths
## (absolute folders, e.g. an installed Source game for its tool textures).
static func gameinfo_text(game_name: String, extra_paths: PackedStringArray) -> String:
	var lines := PackedStringArray([
		MARKER,
		"\"GameInfo\"",
		"{",
		"\tgame " + _quoted(game_name if game_name != "" else "Godot game"),
		"\tFileSystem",
		"\t{",
		"\t\tSearchPaths",
		"\t\t{",
		"\t\t\tgame+mod+default_write_path \"|gameinfo_path|.\"",
	]);
	for path in extra_paths:
		if path.strip_edges() == "": continue;
		lines.append("\t\t\tgame " + _quoted(path.strip_edges()));
	lines.append_array(["\t\t}", "\t}", "}", ""]);
	return "\n".join(lines);

## Writes or refreshes gameinfo.txt. OK when it is current, ERR_SKIP when it isn't ours to write.
static func update() -> Error:
	if not ProjectSettings.get_setting(WRITE_SETTING, true): return ERR_SKIP;
	var folder := project_directory();
	if folder == "": return ERR_SKIP;

	var path := folder.path_join("gameinfo.txt");
	var text := gameinfo_text(
		str(ProjectSettings.get_setting("application/config/name", "")),
		PackedStringArray(ProjectSettings.get_setting(SEARCH_PATHS_SETTING, PackedStringArray())));

	if FileAccess.file_exists(path):
		var existing := FileAccess.get_file_as_string(path);
		if not existing.begins_with(MARKER): return ERR_SKIP;
		if existing == text: return OK;

	DirAccess.make_dir_recursive_absolute(folder);
	var file := FileAccess.open(path, FileAccess.WRITE);
	if not file:
		VMFLogger.error("Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())]);
		return FileAccess.get_open_error();
	file.store_string(text);
	file.close();
	VMFLogger.log("Wrote " + path);
	return OK;

static func define_project_settings() -> void:
	if not ProjectSettings.has_setting(WRITE_SETTING):
		ProjectSettings.set_setting(WRITE_SETTING, true);
	ProjectSettings.set_initial_value(WRITE_SETTING, true);
	ProjectSettings.add_property_info({
		"name": WRITE_SETTING,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
	});

	if not ProjectSettings.has_setting(SEARCH_PATHS_SETTING):
		ProjectSettings.set_setting(SEARCH_PATHS_SETTING, PackedStringArray());
	ProjectSettings.set_initial_value(SEARCH_PATHS_SETTING, PackedStringArray());
	ProjectSettings.add_property_info({
		"name": SEARCH_PATHS_SETTING,
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_GLOBAL_DIR],
	});
