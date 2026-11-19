shader_type sky;

// A smooth vertical gradient with a warm band low on the horizon.
//
// ProceduralSkyMaterial draws a hard line where the ground hemisphere meets the
// sky, which on a mostly-empty screen reads as a seam across the middle of the
// monitor. This shader blends three colours with smoothsteps instead, so the
// backdrop has depth without any visible edge.

uniform vec4 top_color : source_color = vec4(0.012, 0.010, 0.038, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.105, 0.055, 0.215, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.014, 0.010, 0.034, 1.0);
// A soft pool of violet centred on the board, so the pyramid looks set into the
// background rather than pasted onto it. This used to be a giant additive plane
// in the 3D scene, which was a mistake: a plane that big sits between the camera
// and the board and blends over *everything*, turning the whole frame violet.
// A sky is infinitely far away, so it can only ever be behind.
uniform vec4 glow_color : source_color = vec4(0.22, 0.12, 0.45, 1.0);
uniform float glow_strength = 0.55;
// Direction from the camera towards the board centre, in world space.
uniform vec3 glow_direction = vec3(0.0, -0.3, -1.0);

void sky() {
	float height = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 colour = mix(bottom_color.rgb, horizon_color.rgb,
		smoothstep(0.30, 0.52, height));
	colour = mix(colour, top_color.rgb, smoothstep(0.55, 0.98, height));

	// Alignment with the board direction: 1.0 straight at it, falling off
	// smoothly away from it.
	float align = max(dot(normalize(EYEDIR), normalize(glow_direction)), 0.0);
	colour += glow_color.rgb * pow(align, 6.0) * glow_strength;

	COLOR = colour;
}
