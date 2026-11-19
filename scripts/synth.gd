class_name Synth
extends Node

## A tiny sound chip: everything you hear is generated from maths at startup.
##
## WHY SYNTHESISE INSTEAD OF SHIPPING WAVs
## ---------------------------------------
## Arcade sounds are short square-wave blips, and the original cabinet's audio
## is exactly that. Generating them means the repo holds no audio files at all,
## so there is nothing to license and nothing to lose in a bad merge. It also
## makes the pitch a tunable number rather than a sample.
##
## The sounds are built once and cached as AudioStreamWAV (16-bit mono PCM)
## because generating a buffer on every hop would stutter exactly when the game
## is busiest. A pool of players is round-robined so overlapping blips (a hop
## landing on a tile flip landing on an enemy death) do not cut each other off.

const RATE := 22050

## key -> waveform definition. `sweep` scales the frequency by the end of the
## tone (2.0 = one octave up, 0.5 = one octave down), which is what makes a
## fall sound like falling and a step sound like progress.
const SPECS := {
	"hop":    {"freq": 430.0, "dur": 0.09, "vol": 0.30, "sweep": 1.7, "wave": "square"},
	"step":   {"freq": 620.0, "dur": 0.07, "vol": 0.22, "sweep": 1.0, "wave": "square"},
	"revert": {"freq": 300.0, "dur": 0.12, "vol": 0.22, "sweep": 0.6, "wave": "saw"},
	"disc":   {"freq": 320.0, "dur": 0.45, "vol": 0.28, "sweep": 2.6, "wave": "square"},
	"death":  {"freq": 240.0, "dur": 0.55, "vol": 0.32, "sweep": 0.25, "wave": "square"},
	"fall":   {"freq": 180.0, "dur": 0.60, "vol": 0.28, "sweep": 0.2, "wave": "noise"},
	"squash": {"freq": 520.0, "dur": 0.10, "vol": 0.30, "sweep": 0.4, "wave": "square"},
	"level":  {"freq": 520.0, "dur": 0.60, "vol": 0.30, "sweep": 2.0, "wave": "saw"},
	"hatch":  {"freq": 700.0, "dur": 0.18, "vol": 0.26, "sweep": 0.5, "wave": "square"},
	"start":  {"freq": 440.0, "dur": 0.25, "vol": 0.26, "sweep": 1.5, "wave": "square"},
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.volume_db = -4.0
		add_child(player)
		_players.append(player)


## Stop everything on the way out. A playing AudioStreamPlayer keeps its
## AudioStreamPlaybackWAV alive inside the AudioServer, and Godot reports those
## as leaked objects at exit if the app quits mid-blip (which it always does).
func _exit_tree() -> void:
	for player in _players:
		player.stop()
		player.stream = null


func play(key: String) -> void:
	if not SPECS.has(key):
		return
	var stream: AudioStreamWAV = _stream_for(key)
	if stream == null:
		return
	# Round-robin rather than "find a free player": with six voices the oldest
	# one is almost always the right thing to steal, and this never scans.
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.play()


func _stream_for(key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = SPECS[key]
	var stream := _render(
		float(spec["freq"]),
		float(spec["dur"]),
		float(spec["vol"]),
		float(spec["sweep"]),
		String(spec["wave"])
	)
	_cache[key] = stream
	return stream


## Renders one blip: a swept oscillator with a 4 ms attack and a linear decay.
## The attack matters - a square wave starting at full amplitude clicks.
func _render(freq: float, duration: float, volume: float, sweep: float, wave: String) -> AudioStreamWAV:
	var frames := maxi(int(RATE * duration), 8)
	var data := PackedByteArray()
	data.resize(frames * 2)  # 16-bit mono: two bytes per frame

	# Phase is accumulated, not recomputed from t * f(t). Recomputing while the
	# frequency sweeps makes the *rate of change* of phase go as f0*(1 + 2k·p),
	# so a downward sweep with k > -0.5 decelerates through zero and bends back
	# up near the end. Accumulating keeps the sweep monotonic.
	var phase := 0.0
	for i in range(frames):
		var t := float(i) / RATE
		var progress := float(i) / float(frames)
		var f := freq * lerpf(1.0, sweep, progress)
		phase = fmod(phase + f / float(RATE), 1.0)
		var sample := 0.0
		match wave:
			"square":
				sample = 1.0 if phase < 0.5 else -1.0
			"saw":
				sample = phase * 2.0 - 1.0
			"noise":
				sample = randf_range(-1.0, 1.0)
			_:
				sample = sin(phase * TAU)
		var envelope := clampf(t / 0.004, 0.0, 1.0) * (1.0 - progress)
		var value := int(clampf(sample * envelope * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)  # little-endian, which AudioStreamWAV expects

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
