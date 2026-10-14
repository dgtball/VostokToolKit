shader_type canvas_item;

// NVG / thermal overlay. Replaces the vanilla NVG ColorRect shader (see
// VTKNVG.gd for why the swap is safe). The whole frame is read back through
// the false-colour thermal palette; bot heat, mines and the friendly Nomad
// marker are pulled out by comparing the screen against the *Key uniforms.
// Those keys are NOT the raw colours the entity materials emit -- the vanilla
// NVG world processing washes bright keys toward white before this shader ever
// sees them -- but the measured post-NVG values (VTKNVG.gd DET_*). The entity
// materials still emit BOT_WARM_KEY / BOT_MID_KEY / BOT_COLD_KEY
// (VTKBot.gdshader) plus MINE_KEY / MARKER_KEY. Keep both lists in lockstep
// with VTKNVG.gd. The *Color uniforms are the freely chosen substitution
// colours.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.47, 0.67, 0.51, 1.0);
uniform float noise : hint_range(0.0, 60.0, 1.0) = 4.0;
uniform float vignette : hint_range(0.0, 1.0, 0.1) = 0.1;
uniform float goggleSeparation : hint_range(0.0, 1.0, 0.1) = 0.4;
uniform float goggleSize : hint_range(0.0, 1.0, 0.1) = 0.8;
uniform float goggleAspect : hint_range(0.0, 2.0, 0.1) = 1.6;
uniform float goggleOutline : hint_range(0.0, 0.1, 0.01) = 0.05;

uniform bool thermalMode = false;
uniform float thermalDarken : hint_range(1.0, 4.0, 0.01) = 1.70;
uniform int worldPaletteMode = 0;
uniform bool markNomads = false;
// Final image brightness while NVG is on. Applied to the composited overlay, so
// unlike the old Environment.tonemap_white poke it is actually visible.
uniform float nvgWhite : hint_range(0.05, 1.0, 0.05) = 1.0;

uniform vec3 mineKey : source_color = vec3(0.0, 0.0, 1.0);
// Green is emitted only by the floating Nomad marker mesh (VTKNVG.MARKER_KEY),
// never by scenery, so the tight tolerance below cannot be tripped by foliage.
uniform vec3 markerKey : source_color = vec3(0.0, 1.0, 0.0);

// Bot heat: three keys on one body. VTKBot.gdshader emits warm at the feet,
// stepping through mid to cold up the body as a corpse cools; these uniforms
// carry the post-NVG (washed) values of those keys, so the detector matches the
// screen rather than the raw emitted colour. The warm/mid/cold *Color uniforms
// are the preset readout.
uniform vec3 warmKey : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 midKey : source_color = vec3(1.0, 1.0, 0.0);
uniform vec3 coldKey : source_color = vec3(0.0, 0.7, 1.0);

uniform vec3 warmColor : source_color = vec3(0.6, 0.48, 0.09);
uniform vec3 midColor : source_color = vec3(0.55, 0.45, 0.28);
uniform vec3 coldColor : source_color = vec3(0.28, 0.3, 0.4);

uniform vec3 mineColor : source_color = vec3(0.7, 0.1, 0.07);
uniform vec3 markerColor : source_color = vec3(0.2, 1.0, 0.2);

float Goggles(vec2 uv)
{
	vec2 centerUV = (uv * 2.0 - 1.0);
	centerUV.x *= goggleAspect;
	float G1Distance = length(centerUV - vec2(-goggleSeparation * goggleAspect, 0.0));
	float G2Distance = length(centerUV - vec2(goggleSeparation * goggleAspect, 0.0));
	return min(G1Distance, G2Distance);
}

vec3 ThermalPalette(float t)
{
	t = clamp(t, 0.0, 1.0);
	vec3 c0;
	vec3 c1;
	vec3 c2;
	vec3 c3;
	vec3 c4;
	if (worldPaletteMode == 1) {
		c0 = vec3(0.0, 0.0, 0.0);
		c1 = vec3(0.25, 0.25, 0.25);
		c2 = vec3(0.5, 0.5, 0.5);
		c3 = vec3(0.75, 0.75, 0.75);
		c4 = vec3(1.0, 1.0, 1.0);
	} else if (worldPaletteMode == 2) {
		t = pow(t, 0.4);
		c0 = vec3(0.7, 0.7, 0.7);
		c1 = vec3(0.55, 0.55, 0.55);
		c2 = vec3(0.4, 0.4, 0.4);
		c3 = vec3(0.2, 0.2, 0.2);
		c4 = vec3(0.0, 0.0, 0.0);
	} else if (worldPaletteMode == 3) {
		c0 = vec3(0.02, 0.01, 0.0);
		c1 = vec3(0.25, 0.12, 0.02);
		c2 = vec3(0.55, 0.30, 0.05);
		c3 = vec3(0.80, 0.58, 0.18);
		c4 = vec3(1.0, 0.92, 0.70);
	} else if (worldPaletteMode == 4) {
		c0 = vec3(0.0, 0.02, 0.02);
		c1 = vec3(0.05, 0.18, 0.12);
		c2 = vec3(0.10, 0.38, 0.22);
		c3 = vec3(0.35, 0.62, 0.30);
		c4 = vec3(0.80, 0.95, 0.65);
	} else if (worldPaletteMode == 5) {
		c0 = vec3(0.0, 0.01, 0.04);
		c1 = vec3(0.05, 0.12, 0.35);
		c2 = vec3(0.10, 0.30, 0.60);
		c3 = vec3(0.40, 0.65, 0.85);
		c4 = vec3(0.85, 0.95, 1.0);
	} else {
		c0 = vec3(0.0, 0.0, 0.03);
		c1 = vec3(0.30, 0.12, 0.45);
		c2 = vec3(0.55, 0.0, 0.08);
		c3 = vec3(0.9, 0.65, 0.0);
		c4 = vec3(1.0, 1.0, 0.8);
	}
	vec3 color = mix(c0, c1, smoothstep(0.0, 0.25, t));
	color = mix(color, c2, smoothstep(0.25, 0.5, t));
	color = mix(color, c3, smoothstep(0.5, 0.75, t));
	color = mix(color, c4, smoothstep(0.75, 1.0, t));
	return color;
}

void fragment()
{
	vec4 pixelColor = texture(screen_texture, SCREEN_UV);
	float goggleMask = smoothstep(goggleSize + vignette, goggleSize, Goggles(UV));
	float goggleRim = abs(Goggles(UV) - goggleSize);
	float goggleOutlines = 1.0 - smoothstep(0.0, goggleOutline, goggleRim);
	float x = (SCREEN_UV.x + 1.0) * (SCREEN_UV.y + 1.0) * (TIME * 10.0);
	vec4 noiseEffect = vec4(mod((mod(x, 13.0)) * (mod(x, 123.0)), 0.01) - 0.005) * noise;

	vec4 color;
	if (thermalMode) {
		// Pick whichever key is CLOSEST: with a wide tolerance two keys'
		// ranges can overlap on a single pixel, and an if/elif chain would
		// let an earlier check steal matches that belong to a later key.
		float dWarm = distance(pixelColor.rgb, warmKey);
		float dMid = distance(pixelColor.rgb, midKey);
		float dCold = distance(pixelColor.rgb, coldKey);
		float dMine = distance(pixelColor.rgb, mineKey);
		float dMark = distance(pixelColor.rgb, markerKey);
		// The Nomad marker key is very tight and only live while marking is on;
		// a loose match here would steal ordinary green foliage.
		if (!markNomads || dMark > 0.15) {
			dMark = 10.0;
		}
		float minD = min(min(dWarm, dMid), min(dCold, dMine));
		minD = min(minD, dMark);

		{
			float rawLuminance = dot(pixelColor.rgb, vec3(0.299, 0.587, 0.114));
			float luminance = clamp(rawLuminance * thermalDarken, 0.0, 1.0);
			vec3 backgroundColor = ThermalPalette(luminance) * 0.7;
			if (minD < 0.22) {
				vec3 subColor;
				if (minD == dMine) {
					subColor = mineColor;
				} else if (minD == dMark) {
					subColor = markerColor;
				} else {
				// Bot heat: the key says WHERE on the cooling ladder the
				// pixel sits, the preset says what that reads as. Only the
				// preset colour is scaled by the fixed glow strength, so the
				// world palette can never leak onto a bot.
				vec3 botColor = warmColor;
				if (minD == dMid) botColor = midColor;
				else if (minD == dCold) botColor = coldColor;
				subColor = botColor * 0.88;
				}
				color = vec4(subColor, pixelColor.a);
			} else {
				color = vec4(backgroundColor, pixelColor.a);
			}
		}
	} else {
		color = pixelColor * tint;
	}
	color.rgb *= nvgWhite;
	color += noiseEffect;
	color.rgb *= (1.0 + goggleOutlines);
	COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), color, goggleMask);
}
