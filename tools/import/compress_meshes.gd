@tool
extends "res://tools/import/share_textures.gd"
## Post-import: share_textures.gd's texture sharing, and then the model's static
## surfaces stored with compressed vertices (#56).
##
## The glTF importer gives up vertex compression for a whole surface when one
## generated tangent is not exactly perpendicular to its normal, and the surface
## then stores 28 bytes a vertex instead of 16. tools/import/mesh_compress.gd has
## the reason, the rebuild and what it leaves alone; tools/mesh_compress_ab.gd
## measures what it costs (at worst 0.0015 % of a mesh's size in position, 0.53
## degrees of normal, 0.04 texel of UV on the 24 models it was first set on).
##
## Set on a model in its .import:
##   import_script/path="res://tools/import/compress_meshes.gd"
## then delete its .godot/imported entries and re-import.
## tests/mesh_compression_probe names every model that needs it.

const MeshCompress := preload("res://tools/import/mesh_compress.gd")

func _post_import(scene: Node) -> Object:
	super._post_import(scene)
	var done: int = MeshCompress.compress(scene)
	print("compress_meshes: %s: %d vertices now compressed" % [get_source_file().get_file(), done])
	return scene
