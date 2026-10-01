class_name HoverHighlight
extends Node
## Outlines whichever Cat or Building the mouse is currently over, so the
## player can see what a click would select/pick up before committing to
## it — "give it a slight outline effect so we know what we are about to
## click." Priority matches CatSelector/BuildingSelector's own click
## priority exactly (a cat wins over the building underneath it, e.g. a
## stationed cat): reuses `CatSelector.hovered_cat()` (same targeting
## logic and placer/held gating `_on_click()` itself uses) before falling
## back to `BuildingSelector.hovered_building()` (likewise the exact
## targeting its own click handler uses) — not a third copy of "what's
## under the cursor." Both are screen-space sprite tests as of
## 2026-09-17, so the outline lands on exactly the pixels that are
## clickable; while buildings were still picked by ground cell, the
## outline and the click disagreed about a tall building's upper half.
##
## Applies a small edge-detection outline shader (`hover_outline.gdshader`)
## via `material_overlay` directly on the hovered entity's own `Visual`
## Sprite3D, found by node name (the same "child literally named Visual"
## convention every Cat/Building scene already follows —
## `Building._ready()` itself looks it up the same way) rather than a
## duplicate sprite that would need to be kept positioned/scaled in sync
## every frame. `material_overlay` shares the exact same mesh/transform as
## whatever it's attached to, so there's nothing to desync.
##
## **Ring color is per-entity, not one fixed color for everything (✅
## fixed — "color code the stations and outline cats in that color")** —
## a Cat's own role, or a ProcessingBuilding's required_role, both via the
## shared RoleColors table. Anything with no role of its own (ShippingBin,
## IngredientSource) keeps the original single yellow.
##
## Since a cat's hover target comes from `CatSelector.hovered_cat()`, the
## outline automatically follows that node's screen-space sprite picking
## (see its class doc) — hovering a cat's head highlights it exactly where
## clicking it would now select it, which is the "make it visually clear"
## half of the same request.

@export var cat_selector: CatSelector
@export var building_selector: BuildingSelector
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
## Fallback for anything with no Cat.Role of its own (ShippingBin,
## IngredientSource) — RoleColors only covers Cat/ProcessingBuilding roles.
const _OUTLINE_COLOR: Color = Color(1.0, 0.95, 0.4)

var _material: ShaderMaterial
var _current: Sprite3D = null


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _OUTLINE_SHADER


func _process(_delta: float) -> void:
	var target: Sprite3D = null
	var color: Color = _OUTLINE_COLOR
	if placer.selected_definition() == null and not placer.is_demolish_mode():
		var cat: Cat = cat_selector.hovered_cat()
		if cat != null:
			target = cat.visual()
			color = RoleColors.color_for(cat.role)
		else:
			var building: Building = building_selector.hovered_building()
			if building != null:
				target = building.get_node_or_null("Visual") as Sprite3D
				var processing: ProcessingBuilding = building as ProcessingBuilding
				if processing != null:
					color = RoleColors.color_for(processing.required_role)
	if target == _current:
		return
	if _current != null:
		_current.material_overlay = null
	_current = target
	if _current != null:
		_apply_to(_current, color)


## Ring color per entity (✅ fixed — "color code the stations and outline
## cats in that color"): a cat's own role, or a ProcessingBuilding's
## required_role — the same RoleColors table for both, so a Mixer's
## outline and a Mixer-role cat's outline read as the same color.
## Anything with no role (ShippingBin, IngredientSource) keeps the
## original single _OUTLINE_COLOR.
func _apply_to(visual: Sprite3D, color: Color) -> void:
	if visual.texture == null:
		_current = null
		return
	# World-meters target converted to THIS entity's own source-pixel
	# terms via its pixel_size, then to UV — see _OUTLINE_WIDTH_METERS.
	var outline_width_px: float = _OUTLINE_WIDTH_METERS / visual.pixel_size
	# **Divided by the WHOLE TEXTURE's dimensions, not one frame's (✅
	# fixed 2026-09-17).** The shader samples `outline_texture` — the
	# entire sheet — using Godot's own per-fragment UV, which already
	# maps into the current frame's sub-rect *of that sheet*. So a UV
	# delta is in sheet space: dividing by the frame width instead
	# multiplied the horizontal step by `hframes`. On the cat's 4-frame
	# 12000x3000 walk sheet that made the ring 259 source pixels wide
	# horizontally instead of 65, while the vertical stayed correct
	# (vframes = 1) — reported as "the highlight on cats extends a lot
	# farther left and right of the cat than just an outline". Every
	# single-frame sprite (the Mixer included, "you did great on the
	# mixer") was unaffected, since frame size and texture size are the
	# same thing there.
	#
	# X and Y still come out separately, which is the older fix this
	# replaces the arithmetic of, not the reasoning: a sprite's pixel
	# width and height are rarely equal (a 92x23 Milk Source vs an
	# 89x123 Mixer), so one shared UV delta over- or under-shoots one
	# axis by the aspect ratio.
	var texture_width_px: float = visual.texture.get_width()
	var texture_height_px: float = visual.texture.get_height()
	_material.set_shader_parameter("outline_texture", visual.texture)
	_material.set_shader_parameter("outline_color", color)
	_material.set_shader_parameter("outline_width_uv_x", outline_width_px / texture_width_px)
	_material.set_shader_parameter("outline_width_uv_y", outline_width_px / texture_height_px)
	visual.material_overlay = _material
