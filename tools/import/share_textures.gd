@tool
extends EditorScenePostImport
## Post-import: materials that sample the same picture share one texture (#56).
##
## With `gltf/embedded_image_handling=2` (embed as Basis Universal) Godot's glTF
## importer builds a new PortableCompressedTexture2D every time a material asks
## for an image, so a picture used by five materials is compressed and stored
## five times. The RONIN's model (robot-killer_model.glb) has 8 distinct pictures
## and imported 37 textures: 33.6 of its 40.8 MB of texture data were copies.
## Merging the images inside the GLB does not help (tried, twice: the .scn came
## back byte-identical), because the copies are made per material, not per image.
##
## This walks the imported scene and points every material slot at the first
## texture with the same compressed bytes. Lossless: same pixels, same format;
## an image used as both colour and normal map compresses differently and so
## stays two textures.
##
## Set on a model in its .glb.import:
##   import_script/path="res://tools/import/share_textures.gd"
## then delete its .godot/imported entries and re-import. tools/scene_weight.gd
## shows which models store copies; tests/shared_textures_probe keeps them out.

## The work is in texture_share.gd, a plain script the probe can load too (this
## class only exists in the editor).
const TextureShare := preload("res://tools/import/texture_share.gd")

func _post_import(scene: Node) -> Object:
	var first: Dictionary = {} ## content key -> Texture2D
	var merged: int = TextureShare.share(scene, first)
	print("share_textures: %s: %d texture(s) kept, %d copy slot(s) repointed" % [get_source_file().get_file(), first.size(), merged])
	return scene
