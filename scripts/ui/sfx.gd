class_name SfxBank
extends Node

## 音效库。所有音效在运行时用程序合成，**不依赖任何外部素材**——
## 没有下载、没有体积、没有授权问题，数值想调直接改参数。
##
## 要换成真素材：把同名文件丢进 res://assets/audio/ 即可自动覆盖，
## 例如 assets/audio/kill.wav。支援 .wav 和 .ogg。

const RATE: int = 22050
## 同时发声数。战斗时开火很密集，少了会互相打断。
const VOICES: int = 16
const OVERRIDE_DIR: String = "res://assets/audio"

var enabled: bool = true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last: Dictionary = {}

func _ready() -> void:
	for i: int in VOICES:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()

## min_gap_ms：同一个音效的最小间隔，用来挡住 4 倍速下密集开火糊成一片
func play(id: String, volume_db: float = -8.0, min_gap_ms: int = 0) -> void:
	if not enabled or not _streams.has(id):
		return
	var now: int = Time.get_ticks_msec()
	if min_gap_ms > 0 and now - int(_last.get(id, -999999)) < min_gap_ms:
		return
	_last[id] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]
	p.volume_db = volume_db
	p.play()

# ---- 音效定义 --------------------------------------------------------------

func _build() -> void:
	_def("select",  [_seg(0.035, 1200, 1200, "square", 0.0, 3.0)])
	_def("shoot",   [_seg(0.05,  880,  520, "square", 0.0, 3.2)])
	# 克制：清脆高频；被克：低频闷响带噪声。这两个是玩家分辨「打对没」的主要听觉线索。
	_def("strong",  [_seg(0.035, 2000, 1500, "square", 0.0, 2.4),
					 _seg(0.07,  2600, 1900, "sine",   0.0, 2.8)])
	_def("weak",    [_seg(0.09,   190,  115, "sine",   0.35, 2.6)])
	_def("kill",    [_seg(0.15,  420,   90, "saw",    0.12, 2.2)])
	_def("crit",    [_seg(0.12, 1500,  320, "square", 0.05, 2.0)])
	_def("build",   [_seg(0.06,  300,  520, "square", 0.0, 1.6),
					 _seg(0.09,  520,  720, "square", 0.0, 2.0)])
	_def("upgrade", [_seg(0.06,  440,  660, "sine", 0.0, 1.2),
					 _seg(0.06,  660,  880, "sine", 0.0, 1.2),
					 _seg(0.13,  880, 1100, "sine", 0.0, 1.8)])
	_def("sell",    [_seg(0.10,  620,  280, "square", 0.0, 1.8)])
	_def("wave",    [_seg(0.30,  130,  200, "saw", 0.06, 1.1)])
	# 技能：低频起手 + 上扬，要有「放大招」的份量
	_def("skill",   [_seg(0.10,  110,  260, "saw",  0.10, 0.9),
					 _seg(0.16,  330,  620, "square", 0.04, 1.1),
					 _seg(0.34,  700, 1200, "sine", 0.0, 1.4)])
	_def("leak",    [_seg(0.28,  210,   65, "saw", 0.28, 1.0)])
	_def("reward",  [_seg(0.08,  523,  523, "sine", 0.0, 1.0),
					 _seg(0.08,  659,  659, "sine", 0.0, 1.0),
					 _seg(0.20,  784,  784, "sine", 0.0, 1.4)])
	_def("win",     [_seg(0.11,  523,  523, "sine", 0.0, 1.0),
					 _seg(0.11,  659,  659, "sine", 0.0, 1.0),
					 _seg(0.11,  784,  784, "sine", 0.0, 1.0),
					 _seg(0.40, 1047, 1047, "sine", 0.0, 1.2)])
	_def("lose",    [_seg(0.18,  392,  392, "saw", 0.05, 1.0),
					 _seg(0.18,  330,  330, "saw", 0.05, 1.0),
					 _seg(0.48,  247,  247, "saw", 0.05, 1.2)])

func _seg(dur: float, f0: float, f1: float, shape: String,
		noise: float, decay: float) -> Dictionary:
	return {"dur": dur, "f0": f0, "f1": f1, "shape": shape,
		"noise": noise, "decay": decay}

## 有外部素材就用外部的，没有就合成
func _def(id: String, segments: Array) -> void:
	for ext: String in [".wav", ".ogg"]:
		var path: String = "%s/%s%s" % [OVERRIDE_DIR, id, ext]
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
			return
	_streams[id] = _synth(id, segments)

# ---- 合成 ------------------------------------------------------------------

func _synth(id: String, segments: Array) -> AudioStreamWAV:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id)
	for s: Dictionary in segments:
		_render(samples, s, rng)
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _render(out: PackedFloat32Array, s: Dictionary, rng: RandomNumberGenerator) -> void:
	var n: int = maxi(1, int(float(s["dur"]) * float(RATE)))
	var phase: float = 0.0
	var attack: float = 0.003 * float(RATE)
	for i: int in n:
		var t: float = float(i) / float(n)
		var f: float = lerpf(float(s["f0"]), float(s["f1"]), t)
		phase = fmod(phase + f / float(RATE), 1.0)
		var v: float = 0.0
		match String(s["shape"]):
			"square": v = 1.0 if phase < 0.5 else -1.0
			"saw": v = phase * 2.0 - 1.0
			"sine": v = sin(phase * TAU)
			_: v = rng.randf_range(-1.0, 1.0)
		var noise: float = float(s["noise"])
		if noise > 0.0:
			v = lerpf(v, rng.randf_range(-1.0, 1.0), noise)
		# 衰减包络 + 极短 attack，没有 attack 会有爆音
		var env: float = pow(1.0 - t, float(s["decay"]))
		env *= minf(1.0, float(i) / attack)
		out.append(v * env * 0.55)
