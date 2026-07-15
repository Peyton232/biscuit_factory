shader_type spatial;
render_mode unshaded, blend_mix;

// The hovered entity's own current texture — HoverHighlight sets this
// (and outline_width_uv) fresh each time the hover target changes, so
// one shared material works for every Sprite3D regardless of its own
// native resolution. Godot's own per-fragment UV already accounts for
// hframes sub-framing (a Cat's walk-cycle frame), so no manual frame
// math is needed here.
// repeat_disable (clamp-to-edge) is load-bearing, not cosmetic: the
// neighbor samples below deliberately step outside [0,1] UV near a
// sprite's own edge, and a sprite's quad is sized to its full texture
// (including any fully-transparent padding around the drawn art, not
// just the visible silhouette) — with the default repeat sampler, an
// out-of-range sample wraps around to the texture's *opposite* edge
// instead of clamping, which can pick up unrelated opaque pixels there
// and draw a spurious "outline" fragment far from any real edge.
uniform sampler2D outline_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(1.0, 0.95, 0.4, 1.0);
// Separate X/Y sample offsets, not one shared value — a sprite frame's
// pixel width and height are rarely equal (a 92x23 Milk Source vs. a
// 89x123 Mixer), so a single UV delta derived from the frame's width
// alone under- or over-shoots the other axis by however much its aspect
// ratio differs from square. See HoverHighlight._apply_to().
uniform float outline_width_uv_x = 0.01;
uniform float outline_width_uv_y = 0.01;

// Manual billboard reconstruction — load-bearing, not cosmetic. Every
// hovered Sprite3D has billboard = BILLBOARD_ENABLED, which
// StandardMaterial3D implements by rotating the quad to face the
// camera every frame; that behavior is baked into the ENGINE's own
// generated shader code for that material, though, not exposed as a
// `render_mode` keyword a custom spatial shader can opt into (spatial
// shaders have no "billboard" render mode at all — only particle
// shaders do). material_overlay draws the SAME mesh geometry as the
// base material but through this completely separate ShaderMaterial,
// so without reconstructing the same rotation here by hand, the overlay
// renders as a flat, unrotated quad in the mesh's raw local space —
// from an angled camera that looks like a skewed/oversized triangle
// jutting off to one side instead of tracing the sprite's own
// silhouette (worse the taller/narrower the sprite, e.g. the Mixer).
// This is Godot's own standard "full billboard" vertex snippet: replace
// the rotation/scale part of MODELVIEW_MATRIX with the camera's own
// basis vectors (from INV_VIEW_MATRIX), keeping only the model's
// translation (MODEL_MATRIX[3]) and scale (via VIEW_MATRIX afterward),
// so the quad always faces the camera exactly like the base material's
// own billboard does.
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}


void fragment() {
	float center_alpha = texture(outline_texture, UV).a;
	if (center_alpha > 0.5) {
		// Inside the sprite's own silhouette — the base material already
		// draws here, so leave it alone rather than recoloring the whole
		// shape.
		discard;
	}
	float neighbor_alpha = 0.0;
	neighbor_alpha += texture(outline_texture, UV + vec2(outline_width_uv_x, 0.0)).a;
	neighbor_alpha += texture(outline_texture, UV - vec2(outline_width_uv_x, 0.0)).a;
	neighbor_alpha += texture(outline_texture, UV + vec2(0.0, outline_width_uv_y)).a;
	neighbor_alpha += texture(outline_texture, UV - vec2(0.0, outline_width_uv_y)).a;
	if (neighbor_alpha < 0.1) {
		// Not near an edge of the silhouette either — empty space.
		discard;
	}
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;
}
