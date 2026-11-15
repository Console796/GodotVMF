class_name VMFStructure extends RefCounted

var solids: Array[VMFSolid] = [];
var entities: Array[VMFEntity] = [];

## Returns raw[key] as an Array, including the copies Hammer moves into "hidden" blocks
## when objects are hidden in the editor (they are still compiled).
static func collect(raw: Dictionary, key: String) -> Array:
	var result := [];
	for container in [raw] + as_array(raw.get("hidden", [])):
		if container is Dictionary:
			result.append_array(as_array(container.get(key, [])));
	return result;

static func as_array(value: Variant) -> Array:
	return value if value is Array else [value];

func _init(raw: Dictionary) -> void:
	for solid in collect(raw.world, "solid"):
		solids.append(VMFSolid.new(solid));

	for entity in collect(raw, "entity"):
		entities.append(VMFEntity.new(entity));

func _to_string() -> String:
	var line1 = "VMFStructure(solids=%d, entities=%d)\n" % [solids.size(), entities.size()]
	var line2 = "  Solids:\n"
	for solid in solids:
		line2 += "    %s\n" % solid;

	var line3 = "  Entities:\n"
	for entity in entities:
		line3 += "    %s\n" % entity;

	return line1 + line2 + line3;
