extends RefCounted
## Where the promo_* capture scripts write: a gitignored folder, never the
## tracked README stills in docs/screenshots/ (#272). A rerun used to recreate
## stills the README no longer shows, one careless `git add -A` from being
## committed unreferenced. To refresh a gallery still, copy its file from here
## over the tracked one; tools/check_screenshot_refs.py fails CI on a tracked
## still nothing references.

const DIR := "res://docs/screenshots/promo/"

static func save(img: Image, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR + name + ".png"
	img.save_png(path)
	return path
