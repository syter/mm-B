class_name Palette
extends RefCounted

## 表现层的样式令牌。所有颜色、圆角、边框、字体、贴图都集中在这里，
## 换一套视觉风格 = 换一个 preset，不用改 game.gd 一行绘制代码。
##
## 属性颜色是玩法的一部分 —— 玩家要能一眼认出怪是什么属性，
## 所以不管哪套风格，火/木/水 三色都必须保持足够好分辨。

enum Preset {
	CLASSIC,  ## 现在这套：深色扁平
	POLISH,   ## A：程序绘制强化（圆角、渐层、辉光、粒子），不依赖任何素材
	SCIFI,    ## D：科幻 HUD，Kenney 九宫格贴图 + 辉光
	PIXEL,    ## F：像素风，Fusion Pixel 中文字体 + 硬边框
}

## 默认风格。pixel 是选定的方向。
static var preset: Preset = Preset.PIXEL
static var _applied: bool = false

# ---- 颜色 ------------------------------------------------------------------
static var BG: Color = Color("#14171c")
static var PANEL: Color = Color("#1e232b")
static var PANEL_HI: Color = Color("#2a3039")
static var TRACK: Color = Color("#3b4557")
static var TRACK_EDGE: Color = Color("#222833")
static var TEXT: Color = Color("#e6e9ee")
static var DIM: Color = Color("#8b94a3")
static var ARROW: Color = Color("#5d6a80")
static var GOLD: Color = Color("#e8c05a")
static var STRONG: Color = Color("#ff9a4d")
static var CRIT: Color = Color("#d98cff")
static var LIFE: Color = Color("#e8563f")
static var OK: Color = Color("#57b85a")
static var SLOT: Color = Color("#232932")
static var SLOT_HI: Color = Color("#31394a")
static var SLOT_EDGE: Color = Color("#39414e")

static var FIRE: Color = Color("#e8563f")
static var WOOD: Color = Color("#57b85a")
static var WATER: Color = Color("#3d8fd1")
static var NONE: Color = Color("#8b94a3")

static var RARITY: Dictionary = {
	0: Color("#8b94a3"), 1: Color("#57b85a"),
	2: Color("#4f9ae8"), 3: Color("#f0a33c"),
}

# ---- 形状与质感 ------------------------------------------------------------
static var CORNER_RADIUS: int = 5
static var BORDER_WIDTH: int = 0
static var PANEL_RADIUS: int = 6
static var PANEL_BORDER: int = 2
## 贴图路径（空字符串＝用纯色 StyleBoxFlat）
static var BTN_TEX: String = ""
static var PANEL_TEX: String = ""
static var TEX_MARGIN: int = 20
## 中文字体路径。内嵌而不是用 SystemFont —— SystemFont 在这台机器上
## 会把「杀」这类常用字渲染成空白方块，而且打包发布后也没法依赖用户装了什么字体。
static var FONT_PATH: String = DEFAULT_FONT
const DEFAULT_FONT: String = "res://assets/fonts/NotoSansSC-Regular.otf"
static var FONT_SIZE_SCALE: float = 1.0
## 表现强度：弹道辉光、击杀粒子、扫描线
static var GLOW: float = 0.0
static var PARTICLES: bool = false
static var SCANLINE: float = 0.0
## 怪与塔的绘制形状：true = 圆形，false = 方块（没有精灵图时的退路）
static var ROUND_SHAPES: bool = true
## 战场底纹强度（0＝纯色）。一大片纯色背景会像个洞，
## 铺一层极淡的网格之后才有「地面」的感觉。
static var BG_PATTERN: float = 0.0
## 精灵图目录（空＝不用贴图，回退到程序绘制的圆形/方块）。
## 目录里要有 enemy_fire / enemy_wood / enemy_water / enemy_elite / tower 五张。
static var SPRITE_DIR: String = ""

static func apply(p: Preset) -> void:
	_applied = true
	preset = p
	_classic()
	match p:
		Preset.POLISH: _polish()
		Preset.SCIFI: _scifi()
		Preset.PIXEL: _pixel()

static func ensure_applied() -> void:
	if not _applied:
		apply(Preset.PIXEL)

static func preset_name() -> String:
	match preset:
		Preset.POLISH: return "polish"
		Preset.SCIFI: return "scifi"
		Preset.PIXEL: return "pixel"
		_: return "classic"

# ---- 各套 preset -----------------------------------------------------------

static func _classic() -> void:
	BG = Color("#14171c"); PANEL = Color("#1e232b"); PANEL_HI = Color("#2a3039")
	TRACK = Color("#3b4557"); TRACK_EDGE = Color("#222833"); ARROW = Color("#5d6a80")
	TEXT = Color("#e6e9ee"); DIM = Color("#8b94a3")
	GOLD = Color("#e8c05a"); STRONG = Color("#ff9a4d"); CRIT = Color("#d98cff")
	LIFE = Color("#e8563f"); OK = Color("#57b85a")
	SLOT = Color("#232932"); SLOT_HI = Color("#31394a"); SLOT_EDGE = Color("#39414e")
	FIRE = Color("#e8563f"); WOOD = Color("#57b85a")
	WATER = Color("#3d8fd1"); NONE = Color("#8b94a3")
	RARITY = {0: Color("#8b94a3"), 1: Color("#57b85a"),
		2: Color("#4f9ae8"), 3: Color("#f0a33c")}
	CORNER_RADIUS = 5; BORDER_WIDTH = 0; PANEL_RADIUS = 6; PANEL_BORDER = 2
	BTN_TEX = ""; PANEL_TEX = ""; FONT_PATH = DEFAULT_FONT; FONT_SIZE_SCALE = 1.0
	GLOW = 0.0; PARTICLES = false; SCANLINE = 0.0; ROUND_SHAPES = true
	SPRITE_DIR = ""; BG_PATTERN = 0.0

## A：不用任何外部素材，靠圆角、更深的背景对比、辉光和粒子把观感拉起来
static func _polish() -> void:
	BG = Color("#0d1014"); PANEL = Color("#181d25"); PANEL_HI = Color("#2b3442")
	TRACK = Color("#39455b"); TRACK_EDGE = Color("#161b23"); ARROW = Color("#6b7a94")
	TEXT = Color("#f2f5f9"); DIM = Color("#8e99ab")
	GOLD = Color("#f2c75c"); STRONG = Color("#ff9f52"); CRIT = Color("#c78cff")
	LIFE = Color("#f2604a"); OK = Color("#5fc765")
	SLOT = Color("#1c222c"); SLOT_HI = Color("#33405a"); SLOT_EDGE = Color("#3d4859")
	FIRE = Color("#f2604a"); WOOD = Color("#5fc765")
	WATER = Color("#46a0e6"); NONE = Color("#8e99ab")
	CORNER_RADIUS = 10; BORDER_WIDTH = 0; PANEL_RADIUS = 14; PANEL_BORDER = 2
	GLOW = 1.0; PARTICLES = true

## D：Kenney 九宫格贴图 + 冷色调 + 强辉光和扫描线
static func _scifi() -> void:
	BG = Color("#080d14"); PANEL = Color("#0e1823"); PANEL_HI = Color("#1b3348")
	TRACK = Color("#16324a"); TRACK_EDGE = Color("#0a1420"); ARROW = Color("#3fa9d9")
	TEXT = Color("#d6f0ff"); DIM = Color("#6d8ba3")
	GOLD = Color("#ffcf4d"); STRONG = Color("#ffa23d"); CRIT = Color("#e07cff")
	LIFE = Color("#ff4d6a"); OK = Color("#2fd6b0")
	SLOT = Color("#0d1c2a"); SLOT_HI = Color("#1d4a66"); SLOT_EDGE = Color("#2a5d7a")
	FIRE = Color("#ff5a45"); WOOD = Color("#3fe07a")
	WATER = Color("#35b6ff"); NONE = Color("#7d93a8")
	RARITY = {0: Color("#7d93a8"), 1: Color("#3fe07a"),
		2: Color("#35b6ff"), 3: Color("#ffbe3d")}
	CORNER_RADIUS = 0; BORDER_WIDTH = 0; PANEL_RADIUS = 0; PANEL_BORDER = 2
	BTN_TEX = "res://assets/ui/scifi/button.png"
	PANEL_TEX = "res://assets/ui/scifi/panel.png"
	TEX_MARGIN = 20
	GLOW = 1.4; PARTICLES = true; SCANLINE = 0.16

## F：像素风。中文像素字体是关键 —— 没有它整套风格根本立不住
static func _pixel() -> void:
	# 背景不能是纯黑 —— 原本 #1a1c2c 配上亮蓝面板，中间那块战场看着像个洞。
	# 把背景提亮、面板压暗，两边往中间靠，层次才连得上。
	BG = Color("#232741"); PANEL = Color("#2c3560"); PANEL_HI = Color("#44559e")
	TRACK = Color("#5f7392"); TRACK_EDGE = Color("#39415f"); ARROW = Color("#9db4c6")
	TEXT = Color("#f4f4f4"); DIM = Color("#94b0c2")
	GOLD = Color("#ffcd75"); STRONG = Color("#ef7d57"); CRIT = Color("#a7f070")
	LIFE = Color("#e2566c"); OK = Color("#38b764")
	SLOT = Color("#323c66"); SLOT_HI = Color("#4c5d8a"); SLOT_EDGE = Color("#5b6a9c")
	FIRE = Color("#ef7d57"); WOOD = Color("#38b764")
	WATER = Color("#41a6f6"); NONE = Color("#94b0c2")
	RARITY = {0: Color("#94b0c2"), 1: Color("#38b764"),
		2: Color("#41a6f6"), 3: Color("#ffcd75")}
	CORNER_RADIUS = 0; BORDER_WIDTH = 2; PANEL_RADIUS = 0; PANEL_BORDER = 3
	FONT_PATH = "res://assets/fonts/fusion-pixel-12px-zh_hans.otf"
	FONT_SIZE_SCALE = 1.05
	GLOW = 0.0; PARTICLES = true; ROUND_SHAPES = false
	SPRITE_DIR = "res://assets/sprites/pixel"
	BG_PATTERN = 0.07

# ---- 取值 ------------------------------------------------------------------

static func rarity(r: int) -> Color:
	return RARITY.get(r, RARITY[0])

static func of(e: Types.Element) -> Color:
	match e:
		Types.Element.FIRE: return FIRE
		Types.Element.WOOD: return WOOD
		Types.Element.WATER: return WATER
		_: return NONE

## 中文字体。Godot 内建字体没有中日韩字，不指定的话整个界面会是空白方块。
static func make_font() -> Font:
	if FONT_PATH != "" and ResourceLoader.exists(FONT_PATH):
		var ff: FontFile = load(FONT_PATH)
		if FONT_PATH.contains("fusion-pixel"):
			# 像素字体必须关掉抗锯齿和次像素定位，否则会糊成一团，
			# 整个像素风就立不住了
			ff = ff.duplicate()
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.hinting = TextServer.HINTING_NONE
		return ff
	var f: SystemFont = SystemFont.new()
	f.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Heiti SC",
		"Microsoft YaHei", "Noto Sans CJK SC", "Sans-Serif",
	])
	return f
