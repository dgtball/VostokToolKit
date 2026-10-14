shader_type spatial;
render_mode unshaded, cull_disabled;

// Bot heat body. This is NOT a display shader: it paints a bot by emitting one
// of three PURE detector keys (VTKNVG.BOT_WARM_KEY / BOT_MID_KEY / BOT_COLD_KEY,
// mirrored here as the defaults below), picked by a pixel's height on the body.
// The NVG screen shader stays a pure exact-colour matcher, so the key it reads
// must stay a flat key colour -- a smooth blend between two keys would land
// between them and fall through to the world palette instead. The cooling
// therefore reads as a MOVING FRONT between flat zones, not a colour gradient.
//
// "cool" (0 -> 1, set per bot by VTKNVG.gd from the death timer) drives the
// front from just above the head down past the feet, so a body freezes at the
// extremities (head/arms, nearest the top) first and holds heat in the core.
uniform vec3 warmKey : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 midKey : source_color = vec3(1.0, 1.0, 0.0);
uniform vec3 coldKey : source_color = vec3(0.0, 0.7, 1.0);
uniform float cool : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float footY = 0.0;
uniform float bodyHeight = 1.8;
uniform float band = 0.28;

void fragment() {
	// VERTEX is view-space in the fragment stage; INV_VIEW_MATRIX brings it back
	// to world space. Read here (not per vertex) so the front is a crisp pixel
	// edge, and computed in world space so every mesh of the bot shares one
	// vertical scale no matter its own transform.
	float worldY = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float h = clamp((worldY - footY) / bodyHeight, 0.0, 1.0);
	// cool = 0: both fronts sit above the head (nothing cold). cool = 1: the
	// cold front has passed the feet (whole body cold).
	float coldFront = 1.35 - cool * 1.7;
	float midFront = coldFront - band;
	vec3 key = warmKey;
	if (h > coldFront) {
		key = coldKey;
	} else if (h > midFront) {
		key = midKey;
	}
	ALBEDO = key;
}
