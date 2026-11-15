class_name VMFEntity extends RefCounted

var id: int = -1;
var data: Dictionary = {};
var has_solid: bool = false;
var solids: Array[VMFSolid] = [];
var vmf: String = "";
var classname: String = "";
var targetname: String;
var parentname: String;
var angles: Vector3 = Vector3.ZERO;
var origin: Vector3 = Vector3.ZERO;

func _init(raw: Dictionary) -> void:
	id = int(raw.get("id", -1));
	classname = raw.get("classname", "");
	data = raw;
	angles = raw.get("angles", Vector3.ZERO);
	origin = raw.get("origin", Vector3.ZERO);

	# A brush entity with several solids parses as an Array; hidden ones sit in "hidden".
	for solid in VMFStructure.collect(raw, "solid"):
		if solid is Dictionary:
			solids.append(VMFSolid.new(solid));
	has_solid = not solids.is_empty();

func _to_string() -> String:
	return "VMFEntity(id=%d, has_solid=%s, solids=%d)" % [id, has_solid, solids.size()];
