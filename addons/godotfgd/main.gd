@tool
class_name FGDGenerator extends EditorPlugin

var entity_template = "\n".join([
	"@{type} base({base}) {modificators} = {entity_name} : \"{description}\" [",
	"	spawnflags(Flags) = [",
	"{spawnflags}",
	"	]",
	"",
	"{properties}",
	"",
	"{outputs}",
	"",
	"{inputs}",
	"]"
]);

const FLAG_TEMPLATE = "		{flag_index} : \"{flag_name}\" : {value}";
const INPUT_TEMPLATE = "	input {input_name}({input_type}) : \"\"";
const SIGNAL_TEMPLATE = "	output {signal_name}({signal_type}) : \"\"";
const PROPERTY_TEMPLATE = "	{property_name}({property_type}) : \"{property_name_normalized}\" : {property_default} : \"{property_description}\"";
const BOOL_PROPERTY_TEMPLATE = "	{property_name}(choices) : \"{property_name_normalized}\" : {property_default} = [\
		\"0\" : \"No\"\
		\"1\" : \"Yes\"\
	]";

const CHOICES_TEMPLATE = "	{property_name}(choices) : \"{property_name_normalized}\" : {property_default} = [{choices}\
	]";

const QUOTE_WRAPPED = "\"{0}\"";

const TYPE_CHOICES = 1001;
const TYPE_DICTIONARY = {
	TYPE_NIL: "void",
	TYPE_FLOAT: "float",
	TYPE_INT: "integer",
	TYPE_BOOL: "choices",
	TYPE_STRING: "string",
	TYPE_OBJECT: "target_destination",
	TYPE_VECTOR3: "angle",
	TYPE_CHOICES: "choices",
};

## FGD files to @include ahead of the project's entities (res:// paths), e.g. an addon's own FGD.
## GodotVMF's base FGD always comes first.
const INCLUDES_SETTING = "godot_vmf/fgd/includes";
const BASE_FGD = "res://addons/godotfgd/godotvmf_base.fgd";
const HEADER = "// Written by the GodotVMF FGD generator from %s. Edits are overwritten.\n";

func get_aliases_scripts() -> Array:
	return VMFConfig.import.entity_aliases.values() \
		.map(func(alias): return load(alias)._bundled.variants[0].resource_path);

## The project's FGD: in the game folder beside gameinfo.txt (where Hammer and Apex look), named
## after the project.
static func output_path() -> String:
	var folder := VMFGameFolder.project_directory();
	if folder == "": folder = "res://";
	var name := str(ProjectSettings.get_setting("application/config/name", "")).to_snake_case();
	var unsafe := RegEx.create_from_string("[^a-z0-9_]+");
	name = unsafe.sub(name.to_lower(), "", true);
	return folder.path_join((name if name != "" else "game") + ".fgd");

const IO_TYPES = ["void", "integer", "float", "bool", "string", "color255", "vector", "target_destination", "ehandle"];

## An input's or output's FGD type from its first argument: none or a name starting with "_" is
## void; a name that is an FGD type is that type (func Open(float)); else the argument's static type;
## else string.
static func io_type(args: Array) -> String:
	if args.is_empty(): return "void";
	var name: String = args[0].name;
	if name.begins_with("_"): return "void";
	if IO_TYPES.has(name.to_lower()): return name.to_lower();
	match args[0].type:
		TYPE_INT: return "integer";
		TYPE_FLOAT: return "float";
		TYPE_BOOL: return "bool";
		TYPE_VECTOR3: return "vector";
		TYPE_COLOR: return "color255";
		TYPE_OBJECT: return "target_destination";
	return "string";

## path relative to folder, both res:// paths, as an @include wants it.
static func relative_path(folder: String, path: String) -> String:
	var from := folder.trim_prefix("res://").split("/", false);
	var to := path.trim_prefix("res://").split("/", false);
	var common := 0;
	while common < from.size() and common < to.size() - 1 and from[common] == to[common]:
		common += 1;
	var parts := PackedStringArray();
	for i in range(common, from.size()): parts.append("..");
	for i in range(common, to.size()): parts.append(to[i]);
	return "/".join(parts);

static func include_paths() -> PackedStringArray:
	var paths := PackedStringArray([BASE_FGD]);
	for path in PackedStringArray(ProjectSettings.get_setting(INCLUDES_SETTING, PackedStringArray())):
		if path == "" or paths.has(path): continue;
		if not FileAccess.file_exists(path):
			VMFLogger.warn("FGD include not found: " + path);
			continue;
		paths.append(path);
	return paths;

func get_entity_scripts() -> Array:
	var folder: String = VMFConfig.import.entities_folder;
	var paths: Array = [];
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() == "gd": paths.append(folder.path_join(file));
	for path in get_aliases_scripts():
		if path.get_extension() == "gd" and not paths.has(path): paths.append(path);

	return paths \
		.map(func(path): return load(path)) \
		.filter(func(script):
			return script and get_prop_decorators(script, script.get_global_name()).has("entity"));

func compose_fgd(target: String) -> String:
	var text := HEADER % VMFConfig.import.entities_folder;
	for path in include_paths():
		text += "@include \"%s\"\n" % relative_path(target.get_base_dir(), path);
	for script in get_entity_scripts():
		text += "\n" + get_entity_description(script) + "\n";
	return text;

func recompose_fgd(_resources = null):
	var target := output_path();
	var text := compose_fgd(target);
	if FileAccess.file_exists(target) and FileAccess.get_file_as_string(target) == text: return;

	var fgd_file = FileAccess.open(target, FileAccess.WRITE);
	if not fgd_file:
		VMFLogger.error("Can't write %s: %s" % [target, error_string(FileAccess.get_open_error())]);
		return;
	fgd_file.store_string(text);
	fgd_file.close();
	VMFLogger.log("FGD recomposed: " + target);

func _enter_tree():
	if not ProjectSettings.has_setting(INCLUDES_SETTING):
		ProjectSettings.set_setting(INCLUDES_SETTING, PackedStringArray());
	ProjectSettings.set_initial_value(INCLUDES_SETTING, PackedStringArray());
	ProjectSettings.add_property_info({
		"name": INCLUDES_SETTING,
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:*.fgd" % [TYPE_STRING, PROPERTY_HINT_FILE],
	});

	get_editor_interface().get_resource_filesystem().sources_changed.connect(recompose_fgd);
	ProjectSettings.settings_changed.connect(recompose_fgd);
	recompose_fgd();

func _exit_tree():
	get_editor_interface().get_resource_filesystem().sources_changed.disconnect(recompose_fgd);
	ProjectSettings.settings_changed.disconnect(recompose_fgd);

func get_flags(script: Script):
	var index = 0;
	var flags = script.get_script_constant_map() \
		.keys() \
		.filter(func(n: String): return n.begins_with("FLAG_"));

	var base_flags = script.get_base_script().get_script_constant_map().keys() \
		.filter(func(n: String): return n.begins_with("FLAG_"));
	
	flags.append_array(base_flags);

	for flag in flags:
		var value = script[flag];
		var name = flag.replace("FLAG_", "").replace("_", " ").capitalize();
		var type = name.split(" ")[0];

		flags[index] = FLAG_TEMPLATE.format({
			"flag_index": value,
			"flag_name": name,
			"value": 0,
		});

		index += 1;
	
	return "\n".join(flags);

func get_inputs(script: Script):
	var inputs = script.get_script_method_list() \
	.filter(func(method):
		var is_pascal_cased = method.name == method.name.to_pascal_case();
		if is_pascal_cased: return true;

		return get_prop_decorators(script, method.name).has("exposed")
	) \
	.map(func(method):
		var type = io_type(method.args);

		var decorators = get_prop_decorators(script, method.name);
		var name = decorators.get("exposed", "");
		name = name if name != "" else method.name;
		name = name.replace("_", " ").capitalize().replace(" ", "");

		return INPUT_TEMPLATE.format({
			"input_name": name,
			"input_type": type,
		}));

	return "\n".join(inputs);

func get_outputs(script: Script):
	var outputs = script.get_script_signal_list().map(func(sig):
		var type = io_type(sig.args);

		return SIGNAL_TEMPLATE.format({
			"signal_name": sig.name,
			"signal_type": type,
		}));
	
	return "\n".join(outputs);

func get_properties(script: Script):
	var properties = script.get_script_property_list() \
	.filter(func(prop): 
		return get_prop_decorators(script, prop.name).has("exposed");
	) \
	.map(func(prop): 
		var default_value = get_prop_default_value(script, prop.name);
		var description = get_prop_description(script, prop.name);
		var template = PROPERTY_TEMPLATE;
		var decorators = get_prop_decorators(script, prop.name);
		var prop_name_normalized = decorators.get("exposed", "");
		prop_name_normalized = prop_name_normalized if prop_name_normalized != "" else prop.name.replace("_", " ").capitalize();

		match prop.type:
			TYPE_BOOL:
				default_value = "1" if default_value == "true" else "0";
				template = BOOL_PROPERTY_TEMPLATE;
			TYPE_VECTOR3:
				var scr = GDScript.new();
				scr.set_source_code("static func eval(): return " + default_value);
				scr.reload();
				default_value = str(scr.eval()).replace("(", "").replace(")", "").replace(",", "");
			TYPE_INT:
				prop.type = TYPE_CHOICES if prop.class_name != "" else prop.type;

		var choices := "";

		if prop.type == TYPE_CHOICES:
			template = CHOICES_TEMPLATE;

			var enum_name = prop.class_name.split(".")[1];
			var values = script[enum_name];

			for choice_name in values.keys():
				var choice_value = values.get(choice_name);

				choices += "\n\t\t" + QUOTE_WRAPPED.format([choice_value]) + " : " + QUOTE_WRAPPED.format([choice_name.capitalize()]);

			var selected_key = default_value.split('.')[1];
			default_value = values.get(selected_key);

		if prop.type != TYPE_INT && prop.type != TYPE_CHOICES && prop.type != TYPE_STRING:
			default_value = QUOTE_WRAPPED.format([default_value]);

		var type_to_output = decorators.get("type", TYPE_DICTIONARY[prop.type] if prop.type in TYPE_DICTIONARY else "void");

		return template.format({
			"property_name": prop.name,
			"property_name_normalized": prop_name_normalized,
			"property_type": type_to_output,
			"property_default": default_value,
			"property_description": description,
			"choices": choices,
		}));

	properties.append(BOOL_PROPERTY_TEMPLATE.format({
		"property_name": "StartDisabled",
		"property_name_normalized": "Start Disabled",
		"property_type": "choices",
		"property_default": "0",
		"property_description": "If enabled, entity will be disabled on spawn",
	}));

	return "\n".join(properties);

func get_entity_description(script: Script):
	var class_decorator = get_prop_decorators(script, script.get_global_name());

	return entity_template.format({
		entity_name 	= script.get_global_name(),
		spawnflags 		= get_flags(script),
		inputs 			= get_inputs(script),
		outputs 		= get_outputs(script),
		properties 		= get_properties(script),
		type 			= class_decorator.entity,
		base 			= class_decorator.get("base", "Targetname, Origin"),
		description 	= get_prop_description(script, script.get_global_name()),
		modificators 	= class_decorator.get("appearance", ""),
	}).replace("\r\r", "\n");

func get_property_line_index(script: Script, property_name: String):
	if not is_instance_valid(script): return -1;

	var source = script.source_code.split("\n");
	var line_index = 0;

	for line in source:
		var property_pattern = "var " + property_name;
		var is_property = line.begins_with(property_pattern) or (line.contains(property_pattern) and line.contains("@export"));
		var is_method = line.begins_with("func " + property_name);
		var is_class = line.begins_with("class_name " + property_name);

		if not is_property and not is_method and not is_class:
			line_index += 1;
			continue;

		return line_index;

	return -1;

func get_prop_default_value(script: Script, property_name: String):
	if not is_instance_valid(script): return "";

	var source = script.source_code.split("\n");
	var line_index = get_property_line_index(script, property_name);
	if line_index == -1: return get_prop_default_value(script.get_base_script(), property_name);

	var line = source[line_index];
	line = line.replace("\n", "").replace(";", "").replace("\r", "");

	var value = line.split("=")[1] if line.contains("=") else "";
	value = value.trim_prefix(" ").trim_suffix(" ").replace(":", "");

	return value;

func get_prop_decorators(script: Script, property_name: String):
	if not is_instance_valid(script): return {};

	var description = get_prop_description(script, property_name, false);
	var decorators = {};

	var lines = description.split("\n");
	for line in lines:
		line = line.trim_prefix(" ").trim_suffix(" ");
		if not line.begins_with("@"): continue;

		var name = line.split(" ")[0].trim_prefix("@");
		var value = line.split("@" + name)[1].trim_prefix(" ").trim_suffix(" ");

		if name in decorators:
			decorators[name] += "\n" + value;
		else:
			decorators[name] = value;

	return decorators;

func get_prop_description(script: Script, property_name: String, no_decorators = true):
	if not is_instance_valid(script): return "";

	var source = script.source_code.replace("\r\n", "\n").split("\n");

	var description = "";
	var line_index = get_property_line_index(script, property_name);

	if line_index == -1:
		return get_prop_description(script.get_base_script(), property_name, no_decorators);

	line_index -= 1;
	var comment_line = source[line_index];

	while comment_line.begins_with("##"):
		comment_line = comment_line.trim_prefix("##").trim_prefix(" ").trim_suffix(" ").replace("\n", "").replace("\r", "");

		if no_decorators and comment_line.begins_with("@"):
			line_index -= 1;
			comment_line = source[line_index];
			continue;

		description = comment_line + "\n" + description;
		line_index -= 1;
		comment_line = source[line_index];

	return description.trim_suffix("\n");
