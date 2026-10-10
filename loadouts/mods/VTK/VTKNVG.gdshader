shader_type canvas_item;

// NVG / thermal overlay. Replaces the vanilla NVG ColorRect shader (see
// VTKNVG.gd for why the swap is safe). The whole frame is read back through
// the false-colour thermal palette; bots, mines and the friendly Nomad marker
// are pulled out, by key colours emitted by their own unshaded overlay meshes.
// Those keys are the DETECTOR: fixed by design and kept in lockstep with
// VTKNVG.HOT_KEY / HOT_FAR_KEY / DEAD_KEY / DEAD_FAR_KEY / MINE_KEY /
// MARKER_KEY and the overlay materials that emit them. The *Color uniforms are
// the freely chosen substitution colours.

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
uniform bool debugDetect = false;
uniform bool markNomads = false;

uniform vec3 mineKey : source_color = vec3(0.0, 0.0, 1.0);
// Green is emitted only by the floating Nomad marker mesh (VTKNVG.MARKER_KEY),
// never by scenery, so the tight tolerance below cannot be tripped by foliage.
uniform vec3 markerKey : source_color = vec3(0.0, 1.0, 0.0);

// Bot glow: two detectors per "heat" tier (near + far). Living bots emit the
// hot pair; a corpse keeps emitting it while still warm, then switches to the
// cool pair once DEATH_WARM_SECS pass and to the cold pair once DEATH_COOL_SECS
// pass (VTKNVG.gd) -- a stepped, readable "the body is cooling down" without
// per-bot shader state. The keys (magenta / cyan) are fixed the way they were
// proven; only *Color substitutions change with the Bot colour preset.
uniform vec3 hotKey : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 hotFarKey : source_color = vec3(0.6, 0.0, 0.6);
uniform vec3 deadKey : source_color = vec3(0.0, 0.7, 1.0);
uniform vec3 deadFarKey : source_color = vec3(0.0, 0.35, 0.5);
uniform float botHighlightOpacity : hint_range(0.0, 1.0, 0.01) = 0.85;

// Display colours, synced with BOT_PRESETS[0] (Amber) in VTKNVG.gd: the hot
// pair is full-strength warm, the cool pair is dim and the cold pair dimmer
// still, so a body visibly loses heat as the tiers advance.
uniform vec3 hotColor : source_color = vec3(1.0, 0.8, 0.15);
uniform vec3 hotFarColor : source_color = vec3(0.6, 0.48, 0.09);
uniform vec3 deadColor : source_color = vec3(0.55, 0.45, 0.28);
uniform vec3 deadFarColor : source_color = vec3(0.28, 0.3, 0.4);

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
		float dBot = distance(pixelColor.rgb, hotKey);
		float dBotFar = distance(pixelColor.rgb, hotFarKey);
		float dDead = distance(pixelColor.rgb, deadKey);
		float dDeadFar = distance(pixelColor.rgb, deadFarKey);
		float dMine = distance(pixelColor.rgb, mineKey);
		float dMark = distance(pixelColor.rgb, markerKey);
		// The Nomad marker key is very tight and only live while marking is on;
		// a loose match here would steal ordinary green foliage.
		if (!markNomads || dMark > 0.15) {
			dMark = 10.0;
		}
		float minD = min(min(dBot, dBotFar), min(dDead, dDeadFar));
		minD = min(min(minD, dMine), dMark);

		// The framebuffer can be read back only after shading, so a CPU probe
		// can never see the pre-shader frame. Let the shader report itself:
		// green where the detector fires, black where it misses.
		if (debugDetect) {
			color = vec4(minD < 0.4 ? vec3(0.0, 1.0, 0.0) : vec3(0.0), pixelColor.a);
		} else {
			float rawLuminance = dot(pixelColor.rgb, vec3(0.299, 0.587, 0.114));
			float luminance = clamp(rawLuminance * thermalDarken, 0.0, 1.0);
			vec3 backgroundColor = ThermalPalette(luminance) * 0.7;
			if (minD < 0.4) {
				vec3 subColor = backgroundColor;
				if (minD == dMine) {
					subColor = mineColor;
				} else if (minD == dMark) {
					subColor = markerColor;
				} else {
// Bot glow: living bots emit the hot tier; a corpse cools down
				// the ladder (hot -> dead -> deadFar) as DEATH_WARM_SECS and
				// DEATH_COOL_SECS pass in VTKNVG.gd. Fade toward the weather
				// background, not toward black, so a low opacity leaves a
				// readable heat readout on the palette.
					vec3 botColor = hotColor;
					if (minD == dBotFar) botColor = hotFarColor;
					else if (minD == dDead) botColor = deadColor;
					else if (minD == dDeadFar) botColor = deadFarColor;
					subColor = mix(backgroundColor, botColor, botHighlightOpacity);
				}
				color = vec4(subColor, pixelColor.a);
			} else {
				color = vec4(backgroundColor, pixelColor.a);
			}
		}
	} else {
		color = pixelColor * tint;
	}
	color += noiseEffect;
	color.rgb *= (1.0 + goggleOutlines);
	COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), color, goggleMask);
}
