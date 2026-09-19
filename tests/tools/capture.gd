extends SceneTree

## 开发工具：跑起游戏、自动把各阶段的画面存成 PNG。
## 终端环境截不了屏，这是唯一能看到界面长什么样的办法。
## 跑法：godot --path . --script res://tests/tools/capture.gd
## 输出：user:// 底下的 shot_*.png（路径会印出来）

const OUT_DIR: String = "user://"
## 用固定种子，不同风格拍出来的画面才能一对一比较
const SHOT_SEED: int = 20260919
var style: String = "classic"

var game: Node2D
var frame: int = 0
var done: Array[String] = []
## root.get_texture() 拿到的是「上一帧」已经画完的画面，
## 所以改完状态必须等一帧再截，否则截到的是改之前的样子。
var pending: String = ""

func _initialize() -> void:
	# 跑法：godot --path . --script res://tests/tools/capture.gd -- <风格名>
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		style = args[0]
	match style:
		"polish": Palette.apply(Palette.Preset.POLISH)
		"scifi": Palette.apply(Palette.Preset.SCIFI)
		"pixel": Palette.apply(Palette.Preset.PIXEL)
		_: Palette.apply(Palette.Preset.CLASSIC)
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	game.seed_override = SHOT_SEED
	root.add_child(game)

func _process(_delta: float) -> bool:
	frame += 1
	# 前几帧等画面稳定
	if frame < 8:
		return false

	# 上一帧改了状态，这一帧画面才是新的，现在截
	if pending != "":
		_shot(pending)
		pending = ""
		return false

	# 标题页
	if not done.has("title"):
		pending = "title"
		return false
	if game.phase == 4:
		game._start_game()
		return false
	# 开局奖励：先截一张，再全部选掉
	if game.reward_is_opening:
		if not done.has("opening_reward"):
			pending = "opening_reward"
			return false
		game._pick_reward(0)
		return false

	if not done.has("build_empty"):
		pending = "build_empty"
		return false

	if not done.has("build_selected"):
		# 建两座塔，选中第一座让操作按钮露出来
		game.selected_slot = 0
		game._on_build()
		game.selected_slot = 1
		game._on_build()
		game.selected_slot = 0
		game._refresh()
		pending = "build_selected"
		return false

	if not done.has("build_upgraded"):
		# 升级成克制下一波的属性，再多盖几座
		var want: Types.Element = _counter_of_next()
		game._on_upgrade(want)
		for i: int in range(1, 5):
			game.selected_slot = i
			if game.run.tower_at(i) == null:
				game._on_build()
			game._on_upgrade(want if i % 2 == 0 else Types.COUNTERS[want])
		game.selected_slot = 2
		game._refresh()
		pending = "build_upgraded"
		return false

	if game.phase == 0:
		game.selected_slot = -1
		game._start_wave()
		return false

	if game.phase == 1 and not done.has("battle"):
		# 等怪走到一半再截，画面上东西多一点
		if game.run.battle != null and game.run.battle.time > 5.0:
			pending = "battle"
		return false

	# 战斗中选个塔位，确认操作按钮真的出得来
	if game.phase == 1 and not done.has("battle_build"):
		game.selected_slot = 1
		game._refresh()
		pending = "battle_build"
		return false

	if game.phase == 2 and not done.has("reward"):
		pending = "reward"
		return false

	# 奖励弹窗缩起来的样子：要能看到整个战场
	if game.phase == 2 and not done.has("reward_min"):
		game._toggle_reward_min()
		pending = "reward_min"
		return false

	# 选几个奖励，再把加成面板开起来 —— 要验证它能盖在奖励遮罩之上
	if game.phase == 2 and not done.has("buffs"):
		if game.reward_minimized:
			game._toggle_reward_min()
			return false
		if game.run.taken_count() < 2:
			game._pick_reward(0)
			return false
		game._on_buffs()
		pending = "buffs"
		return false

	# 说明面板
	if not done.has("help"):
		if game.help_layer.visible:
			pending = "help"
		else:
			game._on_help()
		return false

	# 技能特写：凑三座同属性塔才放得出来，专门拍一张
	if not done.has("skill"):
		# 前面开过的面板要先关掉，否则会盖住战场
		if game.help_layer.visible or game.buff_layer.visible:
			game._close_help()
			game._close_buffs()
			return false
		if game.phase == 1 and game.run.battle != null:
			var el: Types.Element = Types.Element.FIRE
			if not game.run.skill_unlocked(el):
				game.run.gold = 99999
				for i: int in Balance.SKILL_REQUIRED_TOWERS:
					if game.run.count_of(el) >= Balance.SKILL_REQUIRED_TOWERS:
						break
					var slot: int = game.run.free_slot()
					if slot < 0:
						break
					game.selected_slot = slot
					game._on_build()
					game._on_upgrade(el)
				game.selected_slot = -1
				game._refresh()
				return false
			if game.run.battle.active.is_empty():
				return false
			game._on_skill(el)
			pending = "skill"
			return false
		return false

	if done.size() >= 12:
		print("\n截图目录：%s" % ProjectSettings.globalize_path(OUT_DIR))
		return true
	return false

func _counter_of_next() -> Types.Element:
	var comp: Dictionary = game.run.current_wave().composition()
	var best: Types.Element = Types.Element.FIRE
	var most: int = -1
	for e: Types.Element in comp.keys():
		if int(comp[e]) > most:
			most = int(comp[e])
			best = Types.counter_of(e)
	return best

func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	var path: String = "%s%s_%d_%s.png" % [OUT_DIR, style, done.size() + 1, name]
	img.save_png(path)
	done.append(name)
	print("已截图 %s  (%dx%d)" % [name, img.get_width(), img.get_height()])
