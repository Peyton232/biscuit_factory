class_name HoverHighlight
extends Node
## Outlines whichever Cat or Building the mouse is currently over, so the
## player can see what a click would select/pick up before committing to
## it — "give it a slight outline effect so we know what we are about to
## click." Priority matches CatSelector/BuildingSelector's own click
## priority exactly (a cat wins over the building underneath it, e.g. a
## stationed cat): reuses `CatSelector.hovered_cat()` (same targeting
## logic and placer/held gating `_on_click()` itself uses) before falling
## back to the same `GridManager` occupancy check `BuildingSelector`'s own
## click handler uses — not a third copy of "what's under the cursor."
##
## Applies a small edge-detection outline shader (`hover_outline.gdshader`)
## via `material_overlay` directly on the hovered entity's own `Visual`
## Sprite3D, found by node name (the same "child literally named Visual"
## convention every Cat/Building scene already follows —
## `Building._ready()` itself looks it up the same way) rather than a
## duplicate sprite that would need to be kept positioned/scaled in sync
## every frame. `material_overlay` shares the exact same mesh/transform as
## whatever it's attached to, so there's nothing to desync.

@export var cat_selector: CatSelector
@export var grid_cursor: GridCursor
@export var grid_manager: GridManager
@export var placer: BuildingPlacer

const _OUTLINE_SHADER: Shader = preload("res://scenes/game_scene/factory/ui/hover_outline.gdshader")
## Outline ring thickness in WORLD METERS, not source-texture pixels —
## _apply_to() derives each entity's own pixel-space width from this by
## dividing out its Visual's pixel_size, so the ring reads as the same
## on-screen thickness for everything, regardless of native texture
## resolution. A fixed pixel count (the old approach) looked fine on
## buildings (~90-130px source art, pixel_size ~0.02) but was nearly
## invisible on cats — the walk-cycle sheet is a much higher-resolution
## 3000x3000-per-frame source with a correspondingly tiny pixel_size
## (0.00054), so the same "1.5px" ring rendered ~40x thinner in actual
## screen space. See decisions.md.
const _OUTLINE_WIDTH_METERS: float = 0.035
const _OUTLINE_COLOR: Color = Color(1.0, 0.95, 0.4)

var _material: ShaderMaterial
var _current: Sprite3D = null


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _OUTLINE_SHADER
	_material.set_shader_parameter("outline_color", _OUTLINE_COLOR)


func _process(_delta: float) -> void:
	var target: Sprite3D = _hovered_visual()
	if target == _current:
		return
	if _current != null:
		_current.material_overlay = null
	_current = target
	if _current != null:
		_apply_to(_current)


func _hovered_visual() -> Sprite3D:
	if placer.selected_definition() != null or placer.is_demolish_mode():
		return null
	var cat: Cat = cat_selector.hovered_cat()
	if cat != null:
		return cat.get_node_or_null("Visual") as Sprite3D
	if not grid_cursor.has_hover:
		return null
	var building: Building = grid_manager.get_cell_occupant(grid_cursor.hovered_cell) as Building
	if building != null:
		return building.get_node_or_null("Visual") as Sprite3D
	return null


func _apply_to(visual: Sprite3D) -> void:
	if visual.texture == null:
		_current = null
		return
	# X and Y computed separately, from this frame's own width/height in
	# source-texture pixels — a shared value assumed a square frame,
	# which most sprites in this project aren't (e.g. a 92x23 Milk Source
	# or an 89x123 Mixer), making the outline too thin on one axis and
	# too thick on the other instead of an even ring.
	var frame_width_px: float = visual.texture.get_width() / float(maxi(1, visual.hframes))
	var frame_height_px: float = visual.texture.get_height() / float(maxi(1, visual.vframes))
	# World-meters target converted to THIS entity's own source-pixel
	# terms via its pixel_size, then to UV — see _OUTLINE_WIDTH_METERS.
	var outline_width_px: float = _OUTLINE_WIDTH_METERS / visual.pixel_size
	_material.set_shader_parameter("outline_texture", visual.texture)
	_material.set_shader_parameter("outline_width_uv_x", outline_width_px / frame_width_px)
	_material.set_shader_parameter("outline_width_uv_y", outline_width_px / frame_height_px)
	visual.material_overlay = _material
