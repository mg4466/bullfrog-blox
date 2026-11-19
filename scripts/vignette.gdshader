shader_type canvas_item;

// Screen vignette: darkens the corners so the eye lands on the board.
//
// Drawn as a full-rect ColorRect in its own CanvasLayer below the HUD, because
// Environment has no vignette of its own and a screen-space pass is cheaper than
// adding a quad to the 3D scene.

uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.02, 1.0);
uniform float strength = 0.65;
uniform float inner = 0.32;
uniform float outer = 0.95;

void fragment() {
	vec2 p = SCREEN_UV - vec2(0.5);
	// Slightly wider than tall, so the corners darken evenly on a 16:10 window.
	p.x *= 1.06;
	float d = length(p);
	float amount = smoothstep(inner, outer, d) * strength;
	COLOR = vec4(edge_color.rgb, amount);
}
