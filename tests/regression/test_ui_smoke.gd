extends SceneTree

## 表现层冒烟测试：真的把主场景实例化，模拟点击打完一整局，抓运行时错误。
## 无头模式下 _draw 不会被调用，所以这里验的是状态机和界面刷新，不是画面。
## 跑法：godot --headless --path . --script res://tests/regression/test_ui_smoke.gd

## 这个测试本身的断言下限。测试函数被静默中止时总数会掉下来。
const MIN_ASSERTIONS: int = 60

var _passed: int = 0
var _failed: int = 0

var _game: Node2D

## SceneTree 的 root 在 _initialize() 阶段还没进树，这时 add_child 不会触发 _ready，
## 所以场景要挂上去、测试要等到第一帧才能跑。
func _initialize() -> void:
	# 冒烟测试可能真的通关，别让它去动玩家真正的解锁存档
	Progress.save_path = "user://test_smoke_progress.cfg"
	Progress.reset()
	var scene: PackedScene = load("res://scenes/main.tscn")
	_ok(scene != null, "主场景能载入")
	_game = scene.instantiate()
	root.add_child(_game)

func _process(_delta: float) -> bool:
	_run_test(_game)
	# 不清掉的话退出时会报一堆 ObjectDB leaked
	root.remove_child(_game)
	_game.free()
	return true

func _run_test(game: Node2D) -> void:
	_ok(game.run != null, "开局状态已建立")
	_eq(game.phase, 4, "一开始停在标题页")
	_ok(game.title_layer.visible, "标题页可见")
	_false(game.btn_start.visible, "标题页不显示游戏 HUD")
	game._start_game()
	_false(game.title_layer.visible, "开始后标题页收起")
	_eq(game.phase, 2, "开始游戏先进开局奖励，而不是直接建造")
	_ok(game.reward_is_opening, "标记为开局奖励")

	var waves_played: int = 0
	var guard: int = 0
	# 一局 10 波约 300 秒游戏时间，每次推进 0.1 秒，上限要留够
	while game.phase != 3 and guard < 6000:
		guard += 1
		match game.phase:
			0:  # BUILD
				_do_build(game)
				game._start_wave()
				_eq(game.phase, 1, "开始后进入战斗阶段")
			1:  # BATTLE
				game._process(0.1)
			2:  # REWARD
				_ok(game.reward_choices.size() > 0, "奖励有候选")
				# 刷新：第一次免费，之后越刷越贵
				if game.run.reroll_count == 0:
					_eq(game.run.reroll_cost(), 0, "第一次刷新免费")
					var g0: int = game.run.gold
					game._on_reroll()
					_eq(game.run.gold, g0, "免费刷新不扣钱")
					_eq(game.run.reroll_count, 1, "刷新次数 +1")
					_true(game.run.reroll_cost() > 0, "第二次刷新要花钱")
				_ok(game.reward_layer.visible, "奖励面板可见")
				# 奖励阶段不能留下可点的塔位操作按钮，否则弹窗缩起来时能偷跑
				_false(game.slot_panel.visible, "奖励阶段塔位操作面板已收起")
				_eq(game.selected_slot, -1, "奖励阶段没有选中的塔位")
				# 缩起来要能看到战场，但遮罩没了也不能操作
				game._toggle_reward_min()
				_ok(game.reward_minimized, "可以缩小")
				_false(game.reward_dim.visible, "缩小后遮罩消失，看得到战场")
				_ok(game.reward_bar.visible, "缩小后留下展开横条")
				_false(game.slot_panel.visible, "缩小后仍然不能操作塔位")
				game._toggle_reward_min()
				_false(game.reward_minimized, "可以再展开")
				_ok(game.reward_dim.visible, "展开后遮罩回来")
				game._pick_reward(0)
				if game.phase == 0:
					waves_played += 1

	_true(guard < 6000, "整局会结束，不会死循环")
	_eq(game.phase, 3, "最终进入结束阶段")
	_ok(game.over_layer.visible, "结算面板可见")
	_ok(game.over_home.visible, "结算页有「返回首页」")
	_true(game.run.finished, "规则层也标记为结束")
	_true(game.run.wave_index >= 1, "至少打了一波")
	print("  打完 %d 波，%s，剩命 %d" % [
		waves_played, "通关" if game.run.won else "失败", game.run.lives])

	_test_skill_cooldown_ticks(game)

	# 再开一局，确认能重来
	game._start_game()
	_eq(game.phase, 2, "重来后先给开局奖励")
	_eq(game.run.wave_index, 1, "重来后波次归一")
	_eq(game.run.gold, Balance.START_GOLD, "重来后金钱归初始")
	_false(game.over_layer.visible, "重来后结算面板隐藏")

	# 返回首页：要清干净残局并回到标题，而不是把上一局留在底下
	game._back_to_title()
	_eq(game.phase, 4, "返回首页回到标题阶段")
	_ok(game.title_layer.visible, "标题页重新可见")
	_false(game.over_layer.visible, "结算面板收起")
	_eq(game.run.wave_index, 1, "残局已清掉")

	# 难度解锁：没通关过就只有简单可选
	Progress.reset()
	game._refresh_difficulty_buttons()
	_false(game.diff_buttons[Balance.Difficulty.EASY].disabled, "简单一直可选")
	_ok(game.diff_buttons[Balance.Difficulty.HARD].disabled, "没通关简单时困难是锁的")
	game._choose_difficulty(Balance.Difficulty.HELL)
	_eq(int(game.chosen_difficulty), int(Balance.Difficulty.EASY), "点锁着的难度不生效")
	Progress.mark_cleared(Balance.Difficulty.EASY)
	game._refresh_difficulty_buttons()
	_false(game.diff_buttons[Balance.Difficulty.HARD].disabled, "通关简单后困难解锁")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))

	# 断言总数必须是固定的。GDScript 调用不存在的函数只会打一行错误然后
	# 中止当前函数，剩下的断言被静默跳过，总数照样显示「0 失败」——
	# 所以这里额外盯住总数，少了就说明中间有东西被吞了。
	_true(_passed + _failed >= MIN_ASSERTIONS,
		"断言总数 %d 不该少于 %d（少了说明有测试被静默中止）"
			% [_passed + _failed, MIN_ASSERTIONS])
	print("\n%d 通过, %d 失败" % [_passed, _failed])
	if _failed > 0:
		quit(1)

## 回归：技能冷却必须随著界面推进而减少。
## 曾经因为界面直接呼叫 battle.step() 而不是 run.step_battle()，
## 冷却卡在 18 秒永远不动，技能只能放一次。
func _test_skill_cooldown_ticks(game: Node2D) -> void:
	# _reset_run 只重置状态不改阶段，这里手动回到建造阶段
	game._reset_run()
	game.phase = 0
	var run: RunState = game.run
	run.gold = 999999
	for i: int in Balance.SKILL_REQUIRED_TOWERS:
		var t: Tower = run.build_tower()
		run.upgrade_tower(t.slot, Types.Element.FIRE)
	_true(run.skill_unlocked(Types.Element.FIRE), "凑满三座火塔解锁技能")
	game._start_wave()
	# 推进到场上有怪
	var guard: int = 0
	while run.battle.active.is_empty() and guard < 200:
		game._process(0.1)
		guard += 1
	_true(run.use_skill(Types.Element.FIRE), "放得出技能")
	var cd0: float = run.skill_remaining(Types.Element.FIRE)
	_true(cd0 > 0.0, "放完有冷却")
	game._process(0.5)
	var cd1: float = run.skill_remaining(Types.Element.FIRE)
	_true(cd1 < cd0, "界面推进一帧后冷却确实减少了（%.2f → %.2f）" % [cd0, cd1])
	# 推到冷却结束。注意：冷却只在战斗阶段走 —— 波次打完进了奖励阶段，
	# _process 就不再推进战斗，冷却会停在原地。所以这里要么等到冷却归零，
	# 要么等到这一波结束，两个都算正常。
	guard = 0
	while run.skill_remaining(Types.Element.FIRE) > 0.0 \
			and game.phase == 1 and guard < 400:
		game._process(0.2)
		guard += 1
	_true(guard < 400, "循环会结束，不会卡死")
	if game.phase == 1:
		_true(run.skill_remaining(Types.Element.FIRE) <= 0.0,
			"还在战斗中的话，冷却会走完，技能能再放")
	else:
		_true(true, "这一波在冷却走完前就打完了（冷却只在战斗中走）")

## 模拟玩家操作：有钱就把塔位填满，并升级成克制下一波的属性
func _do_build(game: Node2D) -> void:
	var run: RunState = game.run
	var comp: Dictionary = run.current_wave().composition()
	var want: Types.Element = Types.Element.FIRE
	var most: int = -1
	for e: Types.Element in comp.keys():
		if int(comp[e]) > most:
			most = int(comp[e])
			want = Types.counter_of(e)
	for i: int in Balance.MAX_TOWERS:
		game.selected_slot = i
		if run.tower_at(i) == null:
			game._on_build()
		var t: Tower = run.tower_at(i)
		if t != null and not t.is_upgraded():
			game._on_upgrade(want)
	game.selected_slot = -1
	game._refresh()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)

func _true(cond: bool, msg: String) -> void:
	_ok(cond, msg)

func _false(cond: bool, msg: String) -> void:
	_ok(not cond, msg)

func _eq(a: Variant, b: Variant, msg: String) -> void:
	_ok(a == b, "%s（%s != %s）" % [msg, str(a), str(b)])
