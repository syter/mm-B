extends Node2D

## 游戏主界面。表现层只读 RunState / Battle 的状态来画，不反向修改规则——
## 玩家的操作一律走 RunState 提供的方法（build_tower / upgrade_tower / sell_tower）。
##
## 版面是响应式的：stretch aspect 设成 expand，窗口比设计分辨率宽的时候
## 多出来的宽度是真的可用空间，写死 800 会在右边留一条没用的空白。

enum Phase { BUILD, BATTLE, REWARD, OVER, TITLE }

const HUD_H: float = 78.0
const SLOT_H: float = 104.0
const SLOT_GAP: float = 6.0
const BEAM_LIFE: float = 0.1
const LANES: int = 4
## 飘字存活时间与上限。4 倍速下命中极密集，不封顶会刷爆画面也拖帧。
const FLOAT_LIFE: float = 0.7
const MAX_FLOATERS: int = 48
## 同一位置、同类型的命中在这个时间窗内合并成一个数字
const MERGE_WINDOW: float = 0.2
const MERGE_RADIUS: float = 34.0
## 叠不下时往上错开一行的高度
const ROW_STEP: float = 20.0
const SKILL_FLASH_LIFE: float = 0.45
const SKILL_WAVE_LIFE: float = 0.7
const PARTICLE_LIFE: float = 0.55
const MAX_PARTICLES: int = 220
const SLOT_FLASH_LIFE: float = 0.09

# ---- 版面（_layout 按实际视口算出来）---------------------------------------
var vw: float = 800.0
var vh: float = 560.0
var slot_w: float = 94.0
var row_y: float = 428.0
var field_bottom: float = 420.0
var path_points: PackedVector2Array = PackedVector2Array()

# ---- 状态 ------------------------------------------------------------------
var run: RunState
var phase: Phase = Phase.BUILD
var speed_mult: float = 1.0
var selected_slot: int = -1
var reward_round: int = 0
var reward_choices: Array[Reward] = []
var beams: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
## 击杀赏金的飘字。飘在画面上方的金钱旁边，而不是怪身上——
## 伤害和收入是两回事，混在一起看就都看不清了。
var gold_floaters: Array[Dictionary] = []
var _prev_earned: int = 0
## 技能全屏特效
var skill_flash: Dictionary = {}
## 技能冲击波：从塔位往上扩散的环
var skill_wave: Dictionary = {}
## 击杀粒子
var particles: Array[Dictionary] = []
## 每个塔位的开火闪光剩余时间，用来做后座和枪口火光
var slot_flash: Dictionary = {}
var _last_skill_time: float = -1.0
## 截图工具用：固定种子，让不同风格拍出来的画面可比
var seed_override: int = -1
var last_result: Dictionary = {}

var sfx: SfxBank
var font: Font
## 精灵图。没有的话所有绘制自动退回程序画的圆形/方块。
var tex_enemy: Dictionary = {}
var tex_elite: Texture2D
var tex_boss: Texture2D
var tex_track: Texture2D
var tex_fence: Texture2D
## 「流动纹理」用的累加时间，让路面纹路往前滚，不用箭头也看得出方向
var flow_t: float = 0.0
var tex_tower: Texture2D
var tex_life: Texture2D
var tex_gold: Texture2D
var _cum: PackedFloat32Array = PackedFloat32Array()
var _path_len: float = 0.0
var _prev_leaked: int = 0

# ---- UI 节点 ---------------------------------------------------------------
var ui: Control
var lbl_wave: Label
var lbl_gold: Label
var lbl_lives: Label
var lbl_preview: Label
var lbl_hint: Label
var btn_start: Button
var btn_speed: Button
var btn_mute: Button
var btn_buffs: Button
var btn_skills: Dictionary = {}
## 技能按钮底部的冷却进度条。光有秒数玩家看不出它在动。
var skill_bars: Dictionary = {}
var btn_help: Button
var help_layer: Control
var help_box: Panel
var help_title: Label
var help_body: RichTextLabel
var log_layer: Control
var log_box: Panel
var log_title: Label
var log_body: RichTextLabel
var title_layer: Control
var title_name: Label
var title_sub: Label
## 标题页选的难度，开局时套到 Balance 上
var chosen_difficulty: Balance.Difficulty = Balance.Difficulty.EASY
var diff_buttons: Dictionary = {}
var title_diff_hint: Label
var buff_layer: Control
var buff_dim: ColorRect
var buff_box: Panel
var buff_title: Label
var buff_body: RichTextLabel
var slot_panel: Control
## 塔位操作按钮。战斗中买得起买不起会一直变，但**不能每帧重建按钮**——
## 按下去的那一瞬间按钮被 queue_free，pressed 信号就不会发出来，点击会失灵。
## 所以只在「选中的塔位／塔的状态」变了才重建，可否点击每帧只改 disabled。
var slot_buttons: Array[Dictionary] = []
var _slot_sig: String = ""
var reward_layer: Control
var reward_dim: ColorRect
var reward_box: Panel
var reward_bar: Button
var btn_reward_min: Button
var btn_reward_reroll: Button
## 奖励弹窗是否缩起来了。缩起来能看清场上的塔和下一波预告，
## 但阶段仍是 REWARD，所以什么都操作不了——必须选完才继续。
var reward_minimized: bool = false
## 这一轮三选一是不是「开局奖励」（第一波之前送的那三次）
var reward_is_opening: bool = false
var reward_title: Label
var reward_cards: Array[Dictionary] = []
var over_layer: Control
var over_dim: ColorRect
var over_title: Label
var over_detail: Label
var over_again: Button
var over_home: Button

func _ready() -> void:
	Balance.reset()
	# 命令行可以直接指定风格：godot --path . -- scifi
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		match args[0]:
			"polish": Palette.apply(Palette.Preset.POLISH)
			"scifi": Palette.apply(Palette.Preset.SCIFI)
			"pixel": Palette.apply(Palette.Preset.PIXEL)
			"classic": Palette.apply(Palette.Preset.CLASSIC)
	Palette.ensure_applied()
	font = Palette.make_font()
	_load_sprites()
	sfx = SfxBank.new()
	add_child(sfx)
	_layout()
	_build_ui()
	_position_ui()
	get_viewport().size_changed.connect(_on_resize)
	_reset_run()
	_show_title()

func _on_resize() -> void:
	_layout()
	_position_ui()
	_refresh()
	queue_redraw()

## 只重置状态，不决定阶段。标题页和「再来一局」各自决定接下来去哪。
## 精灵图是去饱和的，运行时用 modulate 乘上属性色 ——
## 属性颜色完全由代码控制，不会被素材本身的色偏带偏。
func _load_sprites() -> void:
	tex_enemy.clear()
	tex_elite = null
	tex_tower = null
	if Palette.SPRITE_DIR == "":
		return
	var names: Dictionary = {
		Types.Element.FIRE: "enemy_fire",
		Types.Element.WOOD: "enemy_wood",
		Types.Element.WATER: "enemy_water",
	}
	for e: Types.Element in names.keys():
		var path: String = "%s/%s.png" % [Palette.SPRITE_DIR, names[e]]
		if ResourceLoader.exists(path):
			tex_enemy[e] = load(path)
	var ep: String = "%s/enemy_elite.png" % Palette.SPRITE_DIR
	if ResourceLoader.exists(ep):
		tex_elite = load(ep)
	var bp: String = "%s/enemy_boss.png" % Palette.SPRITE_DIR
	if ResourceLoader.exists(bp):
		tex_boss = load(bp)
	var fl: String = "%s/track_floor.png" % Palette.SPRITE_DIR
	if ResourceLoader.exists(fl):
		tex_track = load(fl)
	var fe: String = "%s/track_fence.png" % Palette.SPRITE_DIR
	if ResourceLoader.exists(fe):
		tex_fence = load(fe)
	var tp: String = "%s/tower.png" % Palette.SPRITE_DIR
	if ResourceLoader.exists(tp):
		tex_tower = load(tp)
	for pair: Array in [["icon_life", "life"], ["icon_gold", "gold"]]:
		var ip: String = "%s/%s.png" % [Palette.SPRITE_DIR, pair[0]]
		if ResourceLoader.exists(ip):
			if pair[1] == "life":
				tex_life = load(ip)
			else:
				tex_gold = load(ip)

func _reset_run() -> void:
	run = RunState.new(seed_override if seed_override >= 0
		else int(Time.get_unix_time_from_system()))
	phase = Phase.BUILD
	selected_slot = -1
	speed_mult = 1.0
	beams.clear()
	floaters.clear()
	gold_floaters.clear()
	particles.clear()
	slot_flash.clear()
	skill_flash = {}
	skill_wave = {}
	_prev_earned = 0
	_last_skill_time = -1.0
	_prev_leaked = 0
	over_layer.visible = false
	reward_layer.visible = false
	buff_layer.visible = false
	help_layer.visible = false
	log_layer.visible = false
	reward_is_opening = false
	_refresh()

func _show_title() -> void:
	phase = Phase.TITLE
	title_layer.visible = true
	# 存档可能在这一局里解锁了新难度，而且选中的那档不一定还合法
	if not Progress.is_unlocked(chosen_difficulty):
		chosen_difficulty = Progress.highest_unlocked()
	_refresh_difficulty_buttons()
	_refresh()

## 从结算页回首页：整局清干净再显示标题，不然底下还留着上一局的残局
func _back_to_title() -> void:
	sfx.play("select", -18.0)
	_reset_run()
	_show_title()

## 开始游戏：先送三次奖励再打第一波。
## 开局就让玩家做三次选择，第一波之前手上已经有东西了，爽感前置。
func _start_game() -> void:
	Balance.apply_difficulty(chosen_difficulty)
	_reset_run()
	title_layer.visible = false
	reward_is_opening = true
	reward_round = 0
	run.begin_reward_phase()
	_next_reward_round()

# ---- 主循环 ----------------------------------------------------------------

func _process(delta: float) -> void:
	flow_t += delta
	for b: Dictionary in beams:
		b["life"] = float(b["life"]) - delta
	beams = beams.filter(func(b: Dictionary) -> bool: return float(b["life"]) > 0.0)
	for f: Dictionary in floaters:
		f["life"] = float(f["life"]) - delta
		f["pos"] = Vector2(f["pos"]) + Vector2(0, -34.0) * delta
	floaters = floaters.filter(func(f: Dictionary) -> bool: return float(f["life"]) > 0.0)
	for g: Dictionary in gold_floaters:
		g["life"] = float(g["life"]) - delta
	gold_floaters = gold_floaters.filter(func(g: Dictionary) -> bool: return float(g["life"]) > 0.0)
	if not skill_flash.is_empty():
		skill_flash["life"] = float(skill_flash["life"]) - delta
		if float(skill_flash["life"]) <= 0.0:
			skill_flash = {}
	if not skill_wave.is_empty():
		skill_wave["life"] = float(skill_wave["life"]) - delta
		if float(skill_wave["life"]) <= 0.0:
			skill_wave = {}
	for k: int in slot_flash.keys():
		slot_flash[k] = maxf(0.0, float(slot_flash[k]) - delta)
	_step_particles(delta)

	if phase == Phase.BATTLE and run.battle != null:
		var step: float = delta * speed_mult
		# 大步长会让命中判定失真，切成小步推进
		while step > 0.0:
			var dt: float = minf(step, Balance.SIM_STEP)
			# 一定要走 run.step_battle 而不是 run.battle.step —— 技能冷却是在
			# RunState 这一层递减的，直接戳 battle 会让冷却永远卡住不动。
			run.step_battle(dt)
			_collect_beams()
			step -= dt
			if run.battle.is_finished():
				break
		if run.battle != null and run.battle.leaked > _prev_leaked:
			_prev_leaked = run.battle.leaked
			sfx.play("leak", -6.0, 80)
		run.sync_gold()
		_refresh_hud()
		_refresh_slot_panel()
		_update_slot_buttons()
		# 命打光了就当场结束，不用等这波打完
		if run.battle.is_finished() or run.lives - run.battle.lives_lost <= 0:
			_finish_wave()
	queue_redraw()

## 击杀粒子：小方块向上溅开再落下。像素风不用圆点，方块才对味。
func _step_particles(delta: float) -> void:
	for pt: Dictionary in particles:
		pt["life"] = float(pt["life"]) - delta
		var v: Vector2 = pt["vel"]
		v.y += 420.0 * delta
		pt["vel"] = v
		pt["pos"] = Vector2(pt["pos"]) + v * delta
	particles = particles.filter(
		func(pt: Dictionary) -> bool: return float(pt["life"]) > 0.0)

func _burst(pos: Vector2, color: Color, amount: int) -> void:
	if not Palette.PARTICLES:
		return
	for i: int in amount:
		if particles.size() >= MAX_PARTICLES:
			particles.remove_at(0)
		var ang: float = randf_range(-PI, 0.0)
		var spd: float = randf_range(55.0, 170.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": PARTICLE_LIFE * randf_range(0.6, 1.0),
			"color": color,
			"size": randf_range(2.0, 4.0),
		})

func _collect_beams() -> void:
	# 精英放技能：飘个技能名 + 全屏闪一下该属性的颜色。
	# 不给反馈的话玩家只会觉得「怪突然变快了」，不知道是被精英加了 buff。
	# 精英施法分两拍：前摇先报名字（怪站住不动），前摇走完才是真正的爆发。
	# 全挤在同一帧的话，玩家只看到「全场突然回满血」，来不及知道是谁干的。
	for ec: Dictionary in run.battle.last_elite_casts:
		var ecolor: Color = Palette.of(ec["element"])
		var epos: Vector2 = point_at(float(ec["dist"]))
		var is_boss: bool = bool(ec.get("boss", false))
		if bool(ec.get("windup", false)):
			while floaters.size() >= MAX_FLOATERS:
				floaters.remove_at(0)
			# 名字要撑过整段前摇，不然字还没读完技能就已经放完了
			floaters.append({
				"pos": epos + Vector2(0, -34.0), "dmg": 0, "key": -1,
				"text": String(ec["name"]), "color": ecolor,
				"size": 26 if is_boss else 21,
				"life": Balance.ELITE_CAST_WINDUP + FLOAT_LIFE,
			})
			_burst(epos, ecolor, 6)
			sfx.play("select", -14.0, 80)
			continue
		skill_flash = {"color": ecolor, "life": SKILL_FLASH_LIFE}
		_burst(epos, ecolor, 16)
		sfx.play("skill", -11.0, 120)

	var sk: Dictionary = run.battle.last_skill
	if not sk.is_empty() and float(sk["time"]) != _last_skill_time:
		_last_skill_time = float(sk["time"])
		var sc: Color = Palette.of(sk["element"])
		skill_flash = {"color": sc, "life": SKILL_FLASH_LIFE}
		# 冲击波从「放技能的那几座塔」中间升起，而不是凭空全屏染色
		skill_wave = {"color": sc, "life": SKILL_WAVE_LIFE,
			"origin": _element_origin(sk["element"])}
		sfx.play("skill", -6.0)
	for tk: Dictionary in run.battle.last_ticks:
		var tp: Vector2 = point_at(float(tk["dist"]))
		_add_floater(tp, int(tk["damage"]), Types.Effect.STRONG, false)
		if bool(tk.get("killed", false)):
			_burst(tp, Palette.of(tk["element"]), 14 if bool(tk.get("elite", false)) else 8)
	# 赏金变化 → 上方金钱旁飘一个 +N
	var earned: int = run.battle.gold_earned
	if earned > _prev_earned:
		_add_gold_floater(earned - _prev_earned)
		_prev_earned = earned
	for s: Dictionary in run.battle.last_shots:
		var to: Vector2 = point_at(float(s["dist"]))
		var eff: int = int(s["effect"])
		var crit: bool = bool(s["crit"])
		# slot < 0 是技能造成的伤害，没有发射点，不画弹道
		if int(s["slot"]) >= 0:
			beams.append({
				"from": _slot_muzzle(int(s["slot"])),
				"to": to,
				"crit": crit,
				"effect": eff,
				"life": BEAM_LIFE,
			})
		_add_floater(to, int(s["damage"]), eff, crit)
		if int(s["slot"]) >= 0:
			slot_flash[int(s["slot"])] = SLOT_FLASH_LIFE
		if bool(s["killed"]):
			_burst(to, Palette.of(s["element"]), 18 if bool(s.get("elite", false)) else 10)
		if bool(s["killed"]):
			sfx.play("kill", -11.0, 45)
		elif crit:
			sfx.play("crit", -15.0, 70)
		elif eff == Types.Effect.STRONG:
			sfx.play("strong", -19.0, 55)
		elif eff == Types.Effect.WEAK:
			sfx.play("weak", -17.0, 90)
		else:
			sfx.play("shoot", -21.0, 55)

## 伤害飘字。三档各有自己的文字标签和颜色——
## 这是玩家唯一能直接看到「打对没有」的地方，光靠数字大小和颜色不够，要把话说出来。
##
## 不加「+」号：那看起来像「获得」而不是「扣血」。
## 也绝对不用金色：跟 HUD 的「金 161」撞色，玩家会把伤害看成收钱。
func _add_floater(pos: Vector2, dmg: int, eff: int, crit: bool) -> void:
	# 只给数字，不给中文标签——颜色和字号已经把效果说清楚了，
	# 再加「克制」「无效」四个字只会让密集命中时的画面更挤。
	var color: Color = Palette.TEXT
	var size: int = 15
	match eff:
		Types.Effect.STRONG:
			color = Palette.STRONG
			size = 23
		Types.Effect.WEAK:
			color = Palette.DIM
			size = 12
	if crit:
		color = Palette.CRIT
		size = maxi(size, 24)
	var key: int = eff * 2 + (1 if crit else 0)

	# 同一只怪常在同一瞬间被好几座塔打中。不合并的话「克制 26」和「无效 3」
	# 会叠在同一个点上糊成乱码 —— 同类的直接累加成一个数字。
	for f: Dictionary in floaters:
		if int(f["key"]) == key \
				and float(f["life"]) > FLOAT_LIFE - MERGE_WINDOW \
				and Vector2(f["pos"]).distance_to(pos) < MERGE_RADIUS:
			f["dmg"] = int(f["dmg"]) + dmg
			f["text"] = str(int(f["dmg"]))
			f["life"] = FLOAT_LIFE
			return

	# 不同类的没法合并，就往上错开一行，别互相压著
	var p: Vector2 = pos + Vector2(0.0, -12.0)
	var tries: int = 0
	while tries < 5 and _floater_occupied(p):
		p.y -= ROW_STEP
		tries += 1

	while floaters.size() >= MAX_FLOATERS:
		floaters.remove_at(0)
	floaters.append({
		"pos": p, "dmg": dmg, "key": key,
		"text": str(dmg), "color": color, "size": size, "life": FLOAT_LIFE,
	})

## 赏金飘字：叠在上方金钱标签下面，往下排
func _add_gold_floater(amount: int) -> void:
	while gold_floaters.size() >= 6:
		gold_floaters.remove_at(0)
	gold_floaters.append({"text": "+%d" % amount, "life": 0.9})

func _floater_occupied(p: Vector2) -> bool:
	for f: Dictionary in floaters:
		var q: Vector2 = f["pos"]
		if absf(q.x - p.x) < 40.0 and absf(q.y - p.y) < ROW_STEP - 2.0:
			return true
	return false

# ---- 阶段切换 --------------------------------------------------------------

func _start_wave() -> void:
	if phase != Phase.BUILD:
		return
	selected_slot = -1
	slot_panel.visible = false
	_prev_leaked = 0
	_prev_earned = 0
	_last_skill_time = -1.0
	floaters.clear()
	gold_floaters.clear()
	particles.clear()
	slot_flash.clear()
	run.begin_wave()
	phase = Phase.BATTLE
	sfx.play("wave", -7.0)
	_refresh()

func _finish_wave() -> void:
	last_result = run.end_wave()
	beams.clear()
	floaters.clear()
	if run.finished:
		phase = Phase.OVER
		sfx.play("win" if run.won else "lose", -5.0)
		_show_over()
		return
	reward_round = 0
	run.begin_reward_phase()
	_next_reward_round()

func _next_reward_round() -> void:
	if reward_round >= Balance.REWARD_ROUNDS:
		phase = Phase.BUILD
		reward_is_opening = false
		reward_layer.visible = false
		_refresh()
		return
	phase = Phase.REWARD
	reward_choices = run.begin_reward_round()
	reward_round += 1
	reward_minimized = false
	# 进奖励阶段必须清掉塔位选取：那排操作按钮是真的 Button，
	# 不清的话弹窗缩起来（遮罩消失）时就能点到，等于偷跑。
	selected_slot = -1
	_refresh()
	_show_rewards()

func _on_reroll() -> void:
	var fresh: Array[Reward] = run.reroll_rewards()
	if fresh.is_empty():
		return
	reward_choices = fresh
	sfx.play("select", -16.0)
	_show_rewards()

func _toggle_reward_min() -> void:
	reward_minimized = not reward_minimized
	sfx.play("select", -18.0)
	_apply_reward_visibility()

func _apply_reward_visibility() -> void:
	var open: bool = not reward_minimized
	reward_dim.visible = open
	reward_box.visible = open
	reward_bar.visible = not open
	reward_bar.text = "%s %d / %d　·　点此展开" % [
		"开局奖励" if reward_is_opening else "奖励", reward_round, Balance.REWARD_ROUNDS]

func _pick_reward(i: int) -> void:
	if i < 0 or i >= reward_choices.size():
		return
	run.take_reward(reward_choices[i])
	sfx.play("reward", -9.0)
	_next_reward_round()

# ---- 玩家操作 --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.BUILD and phase != Phase.BATTLE:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var slot: int = _slot_at(event.position)
		selected_slot = -1 if slot == selected_slot else slot
		if selected_slot >= 0:
			sfx.play("select", -20.0)
		_refresh()

func _on_build() -> void:
	if selected_slot < 0 or run.tower_at(selected_slot) != null:
		return
	if run.gold < run.tower_cost(selected_slot):
		return
	run.build_tower()
	sfx.play("build", -10.0)
	_refresh()

func _on_upgrade(e: Types.Element) -> void:
	if selected_slot < 0:
		return
	if run.upgrade_tower(selected_slot, e):
		sfx.play("upgrade", -10.0)
	_refresh()

func _on_level_up() -> void:
	if selected_slot < 0:
		return
	if run.level_up_tower(selected_slot):
		sfx.play("upgrade", -10.0)
	_refresh()

func _on_skill(e: Types.Element) -> void:
	if run.use_skill(e):
		_refresh()

func _on_sell() -> void:
	if selected_slot < 0:
		return
	if run.sell_tower(selected_slot):
		sfx.play("sell", -10.0)
	selected_slot = -1
	_refresh()

func _on_speed() -> void:
	speed_mult = 1.0 if speed_mult >= 4.0 else speed_mult * 2.0
	btn_speed.text = "%dx" % int(speed_mult)

func _on_mute() -> void:
	sfx.enabled = not sfx.enabled
	btn_mute.text = "♪" if sfx.enabled else "✕"

# ---- 绘制 ------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, vw, vh), Palette.BG)
	draw_rect(Rect2(0, 0, vw, HUD_H), Palette.PANEL)
	draw_rect(Rect2(0, field_bottom, vw, vh - field_bottom), Palette.PANEL)
	_draw_bg_pattern()
	_draw_hud_icons()
	_draw_track()
	_draw_slots()
	if phase == Phase.BATTLE and run.battle != null:
		_draw_enemies()
	_draw_beams()
	_draw_scanlines()
	_draw_skill_flash()
	_draw_skill_wave()
	_draw_particles()
	_draw_floaters()
	_draw_gold_floaters()

## 战场底纹。一大片纯色背景会像个洞，铺一层极淡的网格之后才有「地面」的感觉。
func _draw_bg_pattern() -> void:
	if Palette.BG_PATTERN <= 0.0:
		return
	var c: Color = Palette.TEXT
	c.a = Palette.BG_PATTERN * 0.5
	var step: float = 16.0
	var y: float = HUD_H
	while y < field_bottom:
		draw_rect(Rect2(0, y, vw, 1.0), c)
		y += step
	var x: float = 0.0
	while x < vw:
		draw_rect(Rect2(x, HUD_H, 1.0, field_bottom - HUD_H), c)
		x += step

## 金钱和生命用图标代替「金」「命」两个字。
## 数字旁边一颗心、一堆金币，比读字快，也更像游戏而不是表格。
func _draw_hud_icons() -> void:
	if phase == Phase.TITLE:
		return
	var sz: float = 20.0
	if tex_gold != null:
		draw_texture_rect(tex_gold, Rect2(216, 7, sz, sz), false, Palette.GOLD)
	if tex_life != null:
		draw_texture_rect(tex_life, Rect2(374, 7, sz, sz), false, Palette.LIFE)

const TRACK_HALF: float = 13.0
const FENCE_H: float = 9.0

func _draw_track() -> void:
	if tex_track != null:
		_draw_track_tiled()
	else:
		draw_polyline(path_points, Palette.TRACK_EDGE, 30.0)
		draw_polyline(path_points, Palette.TRACK, 24.0)
		for i: int in range(1, path_points.size() - 1):
			draw_circle(path_points[i], 15.0, Palette.TRACK_EDGE)
			draw_circle(path_points[i], 12.0, Palette.TRACK)
		_draw_seams()
	_draw_flow()
	_draw_spawn()
	_draw_goal()

## 贴图版赛道：路面铺沙地，两侧钉木栅栏。
## 赛道是轴对齐的蛇行折线，所以每一段都能直接算出矩形来平铺，
## 不用做曲线贴图那一套。
func _draw_track_tiled() -> void:
	# 分三趟画：先铺路面，再钉栅栏，最后在转角补一块路面。
	# 栅栏是沿着整段边缘铺的，到转角会横穿过去留下缺口 ——
	# 用转角补丁盖掉比逐段算裁剪简单得多，效果一样。
	_track_pass(true)
	_track_pass(false)
	for i: int in range(1, path_points.size() - 1):
		var c: Vector2 = path_points[i]
		draw_texture_rect(tex_track,
			Rect2(c - Vector2(TRACK_HALF, TRACK_HALF),
				Vector2(TRACK_HALF, TRACK_HALF) * 2.0),
			true, Palette.TRACK_TINT)

func _track_pass(floor_pass: bool) -> void:
	for i: int in range(1, path_points.size()):
		var a: Vector2 = path_points[i - 1]
		var b: Vector2 = path_points[i]
		if absf(a.y - b.y) < 0.5:
			var x0: float = minf(a.x, b.x)
			var w: float = absf(b.x - a.x)
			if floor_pass:
				draw_texture_rect(tex_track,
					Rect2(x0, a.y - TRACK_HALF, w, TRACK_HALF * 2.0),
					true, Palette.TRACK_TINT)
			elif tex_fence != null:
				draw_texture_rect(tex_fence,
					Rect2(x0, a.y - TRACK_HALF - FENCE_H, w, FENCE_H),
					true, Palette.FENCE_TINT)
				draw_texture_rect(tex_fence,
					Rect2(x0, a.y + TRACK_HALF, w, FENCE_H),
					true, Palette.FENCE_TINT)
		else:
			var y0: float = minf(a.y, b.y)
			var h: float = absf(b.y - a.y)
			if floor_pass:
				draw_texture_rect(tex_track,
					Rect2(a.x - TRACK_HALF, y0, TRACK_HALF * 2.0, h),
					true, Palette.TRACK_TINT)
			elif tex_fence != null:
				# 竖直段要把栅栏转 90°：旋转后局部的 +X 变世界的 +Y，
				# 局部的 +Y 变世界的 -X，所以原点要放在右边缘。
				_fence_rotated(Vector2(a.x - TRACK_HALF, y0), h)
				_fence_rotated(Vector2(a.x + TRACK_HALF + FENCE_H, y0), h)

func _fence_rotated(origin: Vector2, length: float) -> void:
	draw_set_transform(origin, PI * 0.5, Vector2.ONE)
	draw_texture_rect(tex_fence, Rect2(0, 0, length, FENCE_H),
		true, Palette.FENCE_TINT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 沿赛道铺出砖缝。纯色带子太平，加上横缝之后才像一条「路」。
func _draw_seams() -> void:
	var step: float = Balance.TRACK_LENGTH / 46.0
	var c: Color = Palette.TRACK_EDGE
	c.a = 0.55
	var d: float = step
	while d < Balance.TRACK_LENGTH:
		var a: Vector2 = point_at(d)
		var b: Vector2 = point_at(minf(d + 0.2, Balance.TRACK_LENGTH))
		var dir: Vector2 = (b - a).normalized()
		if dir.length_squared() > 0.1:
			var n: Vector2 = Vector2(-dir.y, dir.x) * 11.0
			draw_line(a - n, a + n, c, 2.0)
		d += step

## 流动纹理：一串顺着路往前滚的短条。
## 比那排静止的三角形好 —— 方向是「看出来」的而不是「读出来」的，
## 而且不用在路面上戳一堆箭头，路本身干净多了。
func _draw_flow() -> void:
	var step: float = Balance.TRACK_LENGTH / 30.0
	var offset: float = fmod(flow_t * 2.2, step)
	var c: Color = Palette.TEXT
	c.a = 0.16
	var d: float = offset
	while d < Balance.TRACK_LENGTH:
		var a: Vector2 = point_at(d)
		var b: Vector2 = point_at(minf(d + 0.28, Balance.TRACK_LENGTH))
		var dir: Vector2 = (b - a).normalized()
		if dir.length_squared() > 0.1:
			var n: Vector2 = Vector2(-dir.y, dir.x) * (TRACK_HALF - 3.0)
			draw_line(a - n, a + n, c, 2.0)
		d += step

## 起点闸门。绿色，跟终点的红色闸门对应 —— 一眼看出怪从哪来、往哪去。
func _draw_spawn() -> void:
	var start: Vector2 = path_points[0]
	var c: Color = Palette.OK
	for i: int in 5:
		var w: float = 14.0 if i % 2 == 0 else 10.0
		var cc: Color = c if i % 2 == 0 else c.darkened(0.25)
		draw_rect(Rect2(0, start.y - 18.0 + float(i) * 7.2, w, 7.0), cc)

## 终点：怪走到这里就扣命
func _draw_goal() -> void:
	var end: Vector2 = path_points[path_points.size() - 1]
	var c: Color = Palette.LIFE
	# 像素闸门：几块方砖叠起来，比一条色带有存在感
	for i: int in 5:
		var w: float = 14.0 if i % 2 == 0 else 10.0
		var cc: Color = c if i % 2 == 0 else c.darkened(0.25)
		draw_rect(Rect2(0, end.y - 18.0 + float(i) * 7.2, w, 7.0), cc)

func _draw_slots() -> void:
	var comp: Dictionary = _wave_comp()
	for i: int in Balance.MAX_TOWERS:
		var r: Rect2 = _slot_rect(i)
		var t: Tower = run.tower_at(i)
		var is_sel: bool = (i == selected_slot and phase == Phase.BUILD)
		draw_rect(r, Palette.SLOT_HI if is_sel else Palette.SLOT)
		draw_rect(r, Palette.GOLD if is_sel else Palette.SLOT_EDGE, false, 2.0)
		if t == null:
			var cost: int = run.tower_cost(i)
			var afford: bool = run.gold >= cost
			_text(Vector2(r.position.x, r.position.y + 48), r.size.x, "空位",
				16, Palette.DIM if afford else Palette.SLOT_EDGE)
			_text(Vector2(r.position.x, r.position.y + 74), r.size.x, "%d 金" % cost,
				15, Palette.GOLD if afford else Palette.SLOT_EDGE)
		else:
			var c: Color = Palette.of(t.element)
			# 开火瞬间整座塔往下沉一点，做出后座感
			var kick: float = float(slot_flash.get(i, 0.0)) / SLOT_FLASH_LIFE
			if tex_tower != null:
				var side: float = 36.0
				draw_texture_rect(tex_tower, Rect2(
					r.position + Vector2((r.size.x - side) * 0.5, 2.0 + kick * 3.0),
					Vector2(side, side)), false, c)
			else:
				var pad: float = 14.0
				draw_rect(Rect2(r.position + Vector2(pad, 10),
					Vector2(r.size.x - pad * 2.0, 34)), c)
			# draw_string 的 y 是基线不是顶端，等级点要排在基线之下才不会撞字
			_text(Vector2(r.position.x, r.position.y + 56), r.size.x,
				Types.name_of(t.element), 18, c)
			# 等级用点表示。一眼数得出来，比读「Lv3」快，也更像素风。
			if t.is_upgraded():
				_draw_level_pips(r, t.level, c)
			# 枪口火光
			if kick > 0.0:
				var mz: Vector2 = _slot_muzzle(i)
				var fc: Color = Palette.TEXT
				fc.a = kick
				var fs: float = 4.0 + 6.0 * kick
				draw_rect(Rect2(mz - Vector2(fs, fs) * 0.5, Vector2(fs, fs)), fc)
			# 这座塔对本波的平均倍率。无属性塔会显示刺眼的红色低倍率——
			# 这比写「可升级」三个字更能让玩家自己想去升级。
			var m: float = _avg_mult(t, comp)
			_text(Vector2(r.position.x, r.position.y + 92), r.size.x,
				"×%.2f" % m, 15, _mult_color(m))

## 等级点：亮点＝已有等级，暗点＝还能再练的空位
func _draw_level_pips(r: Rect2, level: int, c: Color) -> void:
	var n: int = Balance.MAX_TOWER_LEVEL
	var w: float = 7.0
	var gap: float = 4.0
	var total: float = float(n) * w + float(n - 1) * gap
	var x: float = r.position.x + (r.size.x - total) * 0.5
	var y: float = r.position.y + 64.0
	for i: int in n:
		var on: bool = i < level
		draw_rect(Rect2(x, y, w, w), c if on else Palette.SLOT_EDGE)
		if on:
			draw_rect(Rect2(x, y, w, w), Palette.BG, false, 1.0)
		x += w + gap

func _draw_enemies() -> void:
	for e: Enemy in run.battle.active:
		if not e.alive:
			continue
		var p: Vector2 = point_at(e.distance)
		var rad: float = 8.5
		if e.is_boss:
			rad = 22.0
		elif e.is_elite:
			rad = 14.0
		var c: Color = Palette.of(e.element)
		# 精英和 BOSS 各有自己的精灵图，轮廓跟杂兵完全不同 ——
		# 所以不用再画金圈红圈去标记，看一眼就知道这只不一样。
		var tex: Texture2D = tex_enemy.get(e.element, null)
		if e.is_boss and tex_boss != null:
			tex = tex_boss
		elif e.is_elite and tex_elite != null:
			tex = tex_elite
		if tex != null:
			var half: float = rad * 1.85
			draw_texture_rect(tex, Rect2(p - Vector2(half, half),
				Vector2(half, half) * 2.0), false, c)
		elif Palette.ROUND_SHAPES:
			draw_circle(p, rad + 2.0, Palette.BG)
			draw_circle(p, rad, c)
		else:
			draw_rect(Rect2(p - Vector2(rad + 2.0, rad + 2.0),
				Vector2(rad + 2.0, rad + 2.0) * 2.0), Palette.BG)
			draw_rect(Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), c)
		# 精灵图本身已经代表属性了，不再画额外的元素点 —— 那玩意儿小得像另一只怪
		var w: float = rad * 2.6
		var frac: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
		var bar: Vector2 = p + Vector2(-w * 0.5, -rad - 9.0)
		draw_rect(Rect2(bar, Vector2(w, 3.0)), Palette.BG)
		draw_rect(Rect2(bar, Vector2(w * frac, 3.0)),
			Palette.OK if frac > 0.3 else Palette.LIFE)

func _draw_beams() -> void:
	for b: Dictionary in beams:
		var a: float = clampf(float(b["life"]) / BEAM_LIFE, 0.0, 1.0)
		var eff: int = int(b.get("effect", Types.Effect.NORMAL))
		var c: Color = Palette.TEXT
		var w: float = 1.4
		match eff:
			Types.Effect.STRONG:
				c = Palette.STRONG
				w = 3.4
			Types.Effect.WEAK:
				c = Palette.DIM
				w = 0.8
		if bool(b["crit"]):
			c = Palette.CRIT
			w += 1.6
		c.a = a * 0.85
		if Palette.GLOW > 0.0:
			var halo: Color = c
			halo.a = a * 0.22 * Palette.GLOW
			draw_line(b["from"], b["to"], halo, w * 3.0)
		draw_line(b["from"], b["to"], c, w)
		# 命中点的小火花，让每一发都有「打到了」的反馈
		var spark: Color = c
		spark.a = a
		var ss: float = 3.0 + 3.0 * a
		draw_rect(Rect2(Vector2(b["to"]) - Vector2(ss, ss) * 0.5, Vector2(ss, ss)), spark)
		# 克制命中炸一圈光，让「打对了」在余光里也看得见
		if eff == Types.Effect.STRONG:
			var ring: Color = Palette.CRIT if bool(b["crit"]) else Palette.STRONG
			ring.a = a * 0.7
			draw_arc(b["to"], 5.0 + 13.0 * (1.0 - a), 0.0, TAU, 20, ring, 2.0)

## 扫描线：科幻风的 CRT 味道，纯代码叠一层横纹
func _draw_scanlines() -> void:
	if Palette.SCANLINE <= 0.0:
		return
	var c: Color = Palette.TEXT
	c.a = Palette.SCANLINE * 0.1
	var y: float = HUD_H
	while y < field_bottom:
		draw_rect(Rect2(0, y, vw, 1.0), c)
		y += 3.0

## 技能全屏特效：赛道区域整片染上属性颜色再淡出
func _draw_skill_flash() -> void:
	if skill_flash.is_empty():
		return
	var a: float = clampf(float(skill_flash["life"]) / SKILL_FLASH_LIFE, 0.0, 1.0)
	var c: Color = skill_flash["color"]
	# 压低一点，别把冲击波和粒子都盖掉
	c.a = a * 0.18
	draw_rect(Rect2(0, HUD_H, vw, field_bottom - HUD_H), c)

## 赏金飘字贴著上方的金钱标签往下排
func _draw_gold_floaters() -> void:
	var y: float = 30.0
	for g: Dictionary in gold_floaters:
		var a: float = clampf(float(g["life"]) / 0.9, 0.0, 1.0)
		var c: Color = Palette.GOLD
		c.a = minf(1.0, a * 1.8)
		draw_string(font, Vector2(302.0, y), String(g["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, 80.0, 15, c)
		y += 17.0

## 技能冲击波：从放技能的那几座塔中间升起的扩散环
func _draw_skill_wave() -> void:
	if skill_wave.is_empty():
		return
	var t: float = 1.0 - clampf(float(skill_wave["life"]) / SKILL_WAVE_LIFE, 0.0, 1.0)
	var origin: Vector2 = skill_wave["origin"]
	var base: Color = skill_wave["color"]
	for i: int in 3:
		var phase: float = clampf(t - float(i) * 0.12, 0.0, 1.0)
		if phase <= 0.0:
			continue
		var c: Color = base
		c.a = (1.0 - phase) * 0.55
		draw_arc(origin, phase * vw * 0.95, PI, TAU, 48, c, 3.0 - float(i) * 0.6)

## 击杀粒子。像素风用方块，不用圆点。
func _draw_particles() -> void:
	for pt: Dictionary in particles:
		var a: float = clampf(float(pt["life"]) / PARTICLE_LIFE, 0.0, 1.0)
		var c: Color = pt["color"]
		c.a = minf(1.0, a * 1.5)
		var sz: float = float(pt["size"])
		var pos: Vector2 = pt["pos"]
		if Palette.ROUND_SHAPES:
			draw_circle(pos, sz * 0.5, c)
		else:
			draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)

func _draw_floaters() -> void:
	for f: Dictionary in floaters:
		var a: float = clampf(float(f["life"]) / FLOAT_LIFE, 0.0, 1.0)
		var c: Color = f["color"]
		c.a = minf(1.0, a * 1.6)
		var p: Vector2 = f["pos"]
		_text(Vector2(p.x - 70.0, p.y), 140.0, String(f["text"]), int(f["size"]), c)

func _text(pos: Vector2, width: float, s: String, size: int, color: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)

## 当前（建造阶段＝下一波，战斗阶段＝本波）的怪物属性构成
func _wave_comp() -> Dictionary:
	var w: Wave = run.current_wave()
	return w.composition() if w != null else {}

## 一座塔对整波怪的平均倍率，按各属性数量加权
func _avg_mult(t: Tower, comp: Dictionary) -> float:
	var total: int = 0
	for c: int in comp.values():
		total += c
	if total == 0:
		return 1.0
	var sum: float = 0.0
	for e: Types.Element in comp.keys():
		sum += run.mods.multiplier(t.element, e) * float(comp[e]) / float(total)
	return sum

func _mult_color(m: float) -> Color:
	if m >= 1.5:
		return Palette.OK
	if m >= 0.8:
		return Palette.TEXT
	return Palette.LIFE

# ---- 版面计算 --------------------------------------------------------------

func _layout() -> void:
	var s: Vector2 = get_viewport_rect().size
	vw = maxf(s.x, 640.0)
	vh = maxf(s.y, 480.0)
	slot_w = (vw - SLOT_GAP * float(Balance.MAX_TOWERS + 1)) / float(Balance.MAX_TOWERS)
	row_y = vh - SLOT_H - 14.0
	field_bottom = row_y - 32.0
	_make_path()
	_measure_path()

## 蛇行赛道：左上进场，来回四趟，左下出场
func _make_path() -> void:
	var top: float = HUD_H + 34.0
	# 留够下边距：赛道半宽 13 + 栅栏 9 + 提示文字那一行
	var bot: float = field_bottom - 56.0
	var right: float = vw - 74.0
	var left: float = 104.0
	var ys: Array[float] = []
	for i: int in LANES:
		ys.append(lerpf(top, bot, float(i) / float(LANES - 1)))
	path_points = PackedVector2Array([
		Vector2(-40, ys[0]), Vector2(right, ys[0]),
		Vector2(right, ys[1]), Vector2(left, ys[1]),
		Vector2(left, ys[2]), Vector2(right, ys[2]),
		Vector2(right, ys[3]), Vector2(-40, ys[3]),
	])

func _measure_path() -> void:
	_cum.resize(path_points.size())
	_cum[0] = 0.0
	for i: int in range(1, path_points.size()):
		_cum[i] = _cum[i - 1] + path_points[i].distance_to(path_points[i - 1])
	_path_len = _cum[_cum.size() - 1]

## 规则层的行进距离（0~TRACK_LENGTH）换成画面座标
func point_at(dist: float) -> Vector2:
	var target: float = clampf(dist / Balance.TRACK_LENGTH, 0.0, 1.0) * _path_len
	for i: int in range(1, _cum.size()):
		if target <= _cum[i]:
			var seg: float = _cum[i] - _cum[i - 1]
			var t: float = 0.0 if is_zero_approx(seg) else (target - _cum[i - 1]) / seg
			return path_points[i - 1].lerp(path_points[i], t)
	return path_points[path_points.size() - 1]

func _slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_GAP + float(i) * (slot_w + SLOT_GAP), row_y, slot_w, SLOT_H)

## 某个属性所有塔的枪口中点，技能冲击波从这里升起
func _element_origin(e: Types.Element) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var n: int = 0
	for t: Tower in run.towers:
		if t.element == e:
			sum += _slot_muzzle(t.slot)
			n += 1
	if n == 0:
		return Vector2(vw * 0.5, row_y)
	return sum / float(n)

func _slot_muzzle(i: int) -> Vector2:
	var r: Rect2 = _slot_rect(i)
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + 6.0)

func _slot_at(pos: Vector2) -> int:
	for i: int in Balance.MAX_TOWERS:
		if _slot_rect(i).has_point(pos):
			return i
	return -1

# ---- 界面搭建 --------------------------------------------------------------

func _build_ui() -> void:
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 15

	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	add_child(ui)

	lbl_wave = _label(20, Palette.TEXT)
	lbl_gold = _label(20, Palette.GOLD)
	lbl_lives = _label(20, Palette.LIFE)
	lbl_preview = _label(14, Palette.DIM)
	lbl_hint = _label(14, Palette.DIM)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 技能按钮放 HUD 里，这样战斗中随时能按，也不会跟塔位操作按钮抢位置
	for e: Types.Element in Types.ELEMENTAL:
		var el: Types.Element = e
		var sb: Button = _button(Types.name_of(el), Palette.of(el),
			func() -> void: _on_skill(el))
		sb.add_theme_font_size_override("font_size", 14)
		btn_skills[el] = sb
		var bar: ColorRect = ColorRect.new()
		bar.color = Palette.TEXT
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sb.add_child(bar)
		skill_bars[el] = bar
	btn_mute = _button("♪", Palette.PANEL_HI, _on_mute)
	btn_speed = _button("1x", Palette.PANEL_HI, _on_speed)
	btn_start = _button("开始本波", Palette.OK, _start_wave)

	slot_panel = Control.new()
	slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.visible = false
	ui.add_child(slot_panel)

	_build_reward_layer()
	_build_over_layer()
	# 加成按钮和面板最后才加 —— 它们必须盖在奖励／结算遮罩之上，
	# 否则正在三选一的时候就没法回头查自己手上已经有什么加成了。
	btn_buffs = _button("加成", Palette.PANEL_HI, _on_buffs)
	btn_help = _button("?", Palette.PANEL_HI, _on_help)
	_build_buff_layer()
	_build_help_layer()
	_build_log_layer()
	_build_title_layer()

func _build_reward_layer() -> void:
	# 整层永远是 IGNORE，挡不挡点击交给 reward_dim 决定。
	# 缩起来的时候 dim 藏起来，点击就能穿透过去 —— 反正 REWARD 阶段
	# _unhandled_input 本来就不处理，玩家看得到场上状况但动不了。
	reward_layer = Control.new()
	reward_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_layer.visible = false
	ui.add_child(reward_layer)

	reward_dim = ColorRect.new()
	reward_dim.color = Color(0.04, 0.05, 0.07, 0.88)
	reward_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	reward_layer.add_child(reward_dim)

	reward_box = Panel.new()
	reward_box.add_theme_stylebox_override("panel", _panel_box())
	reward_layer.add_child(reward_box)

	# 刷新：第一次免费，之后越刷越贵
	btn_reward_reroll = Button.new()
	btn_reward_reroll.add_theme_font_size_override("font_size", 14)
	_style(btn_reward_reroll, Palette.PANEL_HI)
	btn_reward_reroll.pressed.connect(_on_reroll)
	reward_box.add_child(btn_reward_reroll)

	btn_reward_min = Button.new()
	btn_reward_min.text = "缩小"
	btn_reward_min.add_theme_font_size_override("font_size", 14)
	_style(btn_reward_min, Palette.PANEL_HI)
	btn_reward_min.pressed.connect(_toggle_reward_min)
	reward_box.add_child(btn_reward_min)

	# 缩起来之后留在画面上的横条，点它再展开
	reward_bar = Button.new()
	reward_bar.add_theme_font_size_override("font_size", 15)
	_style(reward_bar, Palette.OK)
	reward_bar.pressed.connect(_toggle_reward_min)
	reward_bar.visible = false
	reward_layer.add_child(reward_bar)

	reward_title = Label.new()
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_title.add_theme_font_size_override("font_size", 22)
	reward_title.add_theme_color_override("font_color", Palette.TEXT)
	reward_box.add_child(reward_title)

	# 卡片用「无文字的 Button + 子 Label」而不是带文字的 Button：
	# Button 的 size 不能小于文字撑出来的 minimum size，长描述会把卡片撑宽并互相重叠。
	for i: int in Balance.REWARD_CHOICES:
		var b: Button = Button.new()
		_style(b, Palette.PANEL_HI)
		b.pressed.connect(_pick_reward.bind(i))
		reward_box.add_child(b)

		# 稀有度色条：比一个孤零零的字母有分量得多，扫一眼就知道这张值不值
		var header: ColorRect = ColorRect.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(header)

		var rank: Label = Label.new()
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.add_theme_font_size_override("font_size", 15)
		rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(rank)

		var title: Label = Label.new()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 19)
		title.add_theme_color_override("font_color", Palette.TEXT)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(title)

		var desc: Label = Label.new()
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 14)
		desc.add_theme_color_override("font_color", Palette.TEXT)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)

		var status: Label = Label.new()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_font_size_override("font_size", 13)
		status.add_theme_color_override("font_color", Palette.DIM)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(status)

		reward_cards.append({"btn": b, "header": header, "rank": rank, "title": title,
			"desc": desc, "status": status})

func _build_over_layer() -> void:
	over_layer = Control.new()
	over_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	over_layer.visible = false
	ui.add_child(over_layer)

	over_dim = ColorRect.new()
	over_dim.color = Color(0.03, 0.04, 0.05, 0.92)
	over_layer.add_child(over_dim)

	over_title = Label.new()
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_title.add_theme_font_size_override("font_size", 36)
	over_layer.add_child(over_title)

	over_detail = Label.new()
	over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_detail.add_theme_font_size_override("font_size", 15)
	over_detail.add_theme_color_override("font_color", Palette.DIM)
	over_layer.add_child(over_detail)

	over_again = Button.new()
	over_again.text = "再来一局"
	_style(over_again, Palette.OK)
	over_again.pressed.connect(_start_game)
	over_layer.add_child(over_again)

	# 回首页才能换难度 —— 「再来一局」是直接用同一档重开
	over_home = Button.new()
	over_home.text = "返回首页"
	_style(over_home, Palette.PANEL_HI)
	over_home.pressed.connect(_back_to_title)
	over_layer.add_child(over_home)

## 通用的两栏资讯弹窗（加成面板、说明面板共用同一套结构）
func _build_info_panel(on_close: Callable, right_color: Color) -> Dictionary:
	var layer: Control = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	ui.add_child(layer)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			on_close.call())
	layer.add_child(dim)

	var box: Panel = Panel.new()
	box.add_theme_stylebox_override("panel", _panel_box())
	layer.add_child(box)

	var title: Label = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(title)

	# 单栏 + 滚动。两栏并排看着紧凑，但内容一多就直接溢出屏幕。
	# 用 RichTextLabel 而不是 Label：它自带滚动，而且支持 BBCode 上色 ——
	# 一整屏白字玩家根本不会读，关键信息必须能被扫到。
	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.scroll_active = true
	body.fit_content = false
	body.add_theme_font_override("normal_font", font)
	body.add_theme_font_override("bold_font", font)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_font_size_override("bold_font_size", 14)
	body.add_theme_color_override("default_color", right_color)
	box.add_child(body)

	var close: Button = Button.new()
	close.text = "关闭"
	_style(close, Palette.PANEL_HI)
	close.pressed.connect(on_close)
	close.name = "Close"
	box.add_child(close)

	return {"layer": layer, "dim": dim, "box": box,
		"title": title, "body": body, "close": close}

func _build_buff_layer() -> void:
	var d: Dictionary = _build_info_panel(_close_buffs, Palette.TEXT)
	buff_layer = d["layer"]
	buff_dim = d["dim"]
	buff_box = d["box"]
	buff_title = d["title"]
	buff_body = d["body"]

func _build_help_layer() -> void:
	var d: Dictionary = _build_info_panel(_close_help, Palette.TEXT)
	help_layer = d["layer"]
	help_box = d["box"]
	help_title = d["title"]
	help_body = d["body"]
	help_title.text = "游戏说明"
	help_body.text = _help_bbcode()

func _build_title_layer() -> void:
	# 盖在 buff/help 之前建立，这样说明面板能开在标题页之上
	title_layer = Control.new()
	title_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	title_layer.visible = false
	ui.add_child(title_layer)
	ui.move_child(title_layer, buff_layer.get_index())

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.95)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	title_layer.add_child(dim)
	dim.name = "Dim"

	title_name = Label.new()
	title_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_name.add_theme_font_size_override("font_size", 46)
	title_name.add_theme_color_override("font_color", Palette.TEXT)
	title_name.text = "属 性 塔 防"
	title_layer.add_child(title_name)

	title_sub = Label.new()
	title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_sub.add_theme_font_size_override("font_size", 16)
	title_sub.add_theme_color_override("font_color", Palette.DIM)
	title_sub.text = "火 → 木 → 水 → 火　·　十波怪　·　不靠克制打不过"
	title_layer.add_child(title_sub)

	# 难度选择。三个档只动 HP_GROWTH，但体感差距很明显。
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		var dd: Balance.Difficulty = d
		var b: Button = Button.new()
		b.text = Balance.DIFFICULTY_NAMES[dd]
		b.add_theme_font_size_override("font_size", 16)
		_style(b, Palette.PANEL_HI)
		b.pressed.connect(func() -> void: _choose_difficulty(dd))
		b.name = "D%d" % int(dd)
		title_layer.add_child(b)
		diff_buttons[dd] = b

	title_diff_hint = Label.new()
	title_diff_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_diff_hint.add_theme_font_size_override("font_size", 13)
	title_diff_hint.add_theme_color_override("font_color", Palette.DIM)
	title_layer.add_child(title_diff_hint)

	var specs: Array = [
		["开始游戏", Palette.OK, Callable(self, "_start_game")],
		["游戏说明", Palette.PANEL_HI, Callable(self, "_on_help")],
		["版本更新日志", Palette.PANEL_HI, Callable(self, "_on_log")],
		["退出游戏", Palette.PANEL_HI, Callable(self, "_on_quit")],
	]
	for i: int in specs.size():
		var b: Button = Button.new()
		b.text = specs[i][0]
		b.add_theme_font_size_override("font_size", 17)
		_style(b, specs[i][1])
		b.pressed.connect(specs[i][2])
		b.name = "T%d" % i
		title_layer.add_child(b)

func _choose_difficulty(d: Balance.Difficulty) -> void:
	if not Progress.is_unlocked(d):
		return
	chosen_difficulty = d
	sfx.play("select", -18.0)
	_refresh_difficulty_buttons()

func _refresh_difficulty_buttons() -> void:
	for d: Balance.Difficulty in diff_buttons.keys():
		var b: Button = diff_buttons[d]
		var unlocked: bool = Progress.is_unlocked(d)
		var on: bool = d == chosen_difficulty
		# 锁着的档位就是一颗点不动的灰按钮，不额外加字 —— 标题页已经够挤了
		b.disabled = not unlocked
		b.text = Balance.DIFFICULTY_NAMES[d]
		_style(b, Palette.OK if on else Palette.PANEL_HI,
			Palette.GOLD if on else Color(0, 0, 0, 0))
	var hints: Dictionary = {
		Balance.Difficulty.EASY: "怪物血量成长最慢，适合先摸清克制关系",
		Balance.Difficulty.HARD: "怪物血量成长更快，配错属性会立刻吃亏",
		Balance.Difficulty.HELL: "血量疯涨，不精打细算撑不到第 10 波",
	}
	title_diff_hint.text = String(hints[chosen_difficulty])

func _on_quit() -> void:
	get_tree().quit()

## 说明文案。颜色从当前 preset 的调色板取，换风格也不会撞色。
##
## 一整屏白字玩家根本不会读 —— 所以文案要短，而且关键信息必须能被「扫」到：
## 小标题统一金色，属性词用各自的属性色，数值里「好的」绿、「坏的」红，
## 补充性的句子压成暗色，让眼睛自动跳过。
func _help_bbcode() -> String:
	var h: Callable = func(c: Color) -> String: return c.to_html(false)
	var fire: String = h.call(Palette.FIRE)
	var wood: String = h.call(Palette.WOOD)
	var water: String = h.call(Palette.WATER)
	var gold: String = h.call(Palette.GOLD)
	var ok: String = h.call(Palette.OK)
	var bad: String = h.call(Palette.LIFE)
	var hot: String = h.call(Palette.STRONG)
	var dim: String = h.call(Palette.DIM)
	var t: Array[String] = []

	t.append("[color=#%s]【目标】[/color]" % gold)
	t.append("撑过 10 波，生命归零就输。")
	t.append("[color=#%s]漏怪扣命：杂兵 1，精英 5，大BOSS 10。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【一局的节奏】[/color]" % gold)
	t.append("1~3 波　三种属性各来一波 [color=#%s]（三种塔都得造）[/color]" % dim)
	t.append("4~6 波　两两混合，[color=#%s]第 4、6 波有精英[/color]" % hot)
	t.append("7~9 波　三色混战，[color=#%s]第 8 波有精英[/color]" % hot)
	t.append("第 10 波　[color=#%s]大 BOSS[/color] 压轴" % bad)
	t.append("")
	t.append("[color=#%s]【精英会放技能】[/color]" % gold)
	t.append("出场时放一次，之后每走完一段路再放一次。")
	t.append("[color=#%s]简单 1 次 / 困难 2 次 / 地狱 3 次。[/color]" % dim)
	t.append("　[color=#%s]火 · 浴火[/color]　全场杂兵跑得更快" % fire)
	t.append("　[color=#%s]木 · 分裂[/color]　杂兵死时裂成两只半血的（只裂一次）" % wood)
	t.append("　[color=#%s]水 · 潮涌[/color]　全场杂兵血量[color=#%s]回满[/color]" % [water, bad])
	t.append("")
	t.append("[color=#%s]【大 BOSS】[/color]" % gold)
	t.append("[color=#%s]血量每掉一段就换一种属性[/color] —— 三种塔都得够强，" % hot)
	t.append("[color=#%s]只堆一种打不动它后面的形态。[/color]" % dim)
	t.append("每个触发点[color=#%s]召唤一批护卫[/color]，分散你的火力。" % hot)
	t.append("[color=#%s]死时裂成三只精英（火木水各一）[/color] ——" % bad)
	t.append("[color=#%s]别把技能和钱在本体身上一次打光。[/color]" % dim)
	t.append("[color=#%s]精英和 BOSS 的属性是单独随机的，不跟杂兵走 —— 看预告。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【属性克制 —— 最重要的一条】[/color]" % gold)
	t.append("[color=#%s]火[/color] → [color=#%s]木[/color] → [color=#%s]水[/color] → [color=#%s]火[/color]"
		% [fire, wood, water, fire])
	t.append("打对 [color=#%s]×2.6[/color]，打错 [color=#%s]×0.3[/color]，差 [color=#%s]8.7 倍[/color]。"
		% [ok, bad, hot])
	t.append("[color=#%s]怪的颜色就是它的属性。不靠克制基本打不过。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【三种怪的脾气】[/color]" % gold)
	t.append("[color=#%s]火[/color]　跑得快但不抗打 —— [color=#%s]不先处理很快就漏[/color]" % [fire, bad])
	t.append("[color=#%s]木[/color]　慢而厚 —— 有时间磨，但磨得久" % wood)
	t.append("[color=#%s]水[/color]　[color=#%s]死时给全场怪回血[/color] —— 不集中清掉会拖成持久战"
		% [water, bad])
	t.append("")
	t.append("[color=#%s]【塔位下的 ×倍率】[/color]" % gold)
	t.append("这座塔对[color=#%s]当前这波怪[/color]的实际伤害倍率。" % hot)
	t.append("[color=#%s]绿＝克制[/color]　白＝普通　[color=#%s]红＝几乎无效[/color]" % [ok, bad])
	t.append("[color=#%s]看到红色就该换属性或拆掉重建。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【塔】[/color]" % gold)
	t.append("没有射程，全部打得到。塔位越后面越贵（60 → 810）。")
	t.append("先建无属性塔，再升级成属性塔；[color=#%s]升级后不能改属性[/color]，只能拆掉重建。" % bad)
	t.append("[color=#%s]免费拆除[/color]（全额返还）按难度给：简单每波 1 次；困难每波 1 次、整局上限 3 次；地狱整局只有 1 次。之后只退 60%%。" % bad)
	t.append("属性塔可练级，每级多打一个目标。[color=#%s]塔位上的小方点＝当前等级。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【技能】[/color]" % gold)
	t.append("同属性凑满 [color=#%s]3 座塔[/color]解锁，冷却 18 秒，每波开场重置。" % hot)
	t.append("全屏 AOE，[color=#%s]伤害一样吃克制倍率[/color] —— 不是绕过克制的后门。" % bad)
	t.append("威力＝该属性所有塔的[color=#%s]等级总和[/color]，练精一种比铺满三种强。" % hot)
	t.append("　[color=#%s]火[/color] 灼烧　　[color=#%s]水[/color] 减速 50%%　　[color=#%s]木[/color] 定身"
		% [fire, water, wood])
	t.append("")
	t.append("[color=#%s]【奖励】[/color]" % gold)
	t.append("每波 3 次三选一，[color=#%s]开局额外送 3 次[/color]。" % ok)
	t.append("稀有度 [color=#%s]S[/color] > [color=#%s]A[/color] > [color=#%s]B[/color] > [color=#%s]C[/color]，S 最难抽到。"
		% [h.call(Palette.rarity(3)), h.call(Palette.rarity(2)),
			h.call(Palette.rarity(1)), h.call(Palette.rarity(0))])
	t.append("可重复领取、效果累加。[color=#%s]堆到封顶就不再出现。[/color]" % dim)
	t.append("免费刷新按难度给：简单[color=#%s]每次选择 1 次[/color]；困难[color=#%s]每轮 3 次选择共 1 次[/color]；地狱[color=#%s]没有免费刷新[/color]。之后越刷越贵。" % [ok, hot, bad])
	t.append("")
	t.append("[color=#%s]【利息】[/color]" % gold)
	t.append("每波结束按[color=#%s]当时手上的存款[/color]额外给钱，封顶 30%%。" % hot)
	t.append("[color=#%s]钱留着不花会生息，花光了这一波一分都没有。[/color]" % dim)
	t.append("[color=#%s]领了之后，HUD 上会直接写这一波能进账多少。[/color]" % dim)
	t.append("")
	t.append("[color=#%s]【其他】[/color]" % gold)
	t.append("[color=#%s]战斗中一样能建塔、升级、拆除[/color]，赏金即时到账。" % ok)
	t.append("[color=#%s]精英[/color]和[color=#%s]大BOSS[/color]的样子跟杂兵完全不同，看轮廓就认得出。"
		% [hot, bad])
	return "\n".join(t)

func _build_log_layer() -> void:
	var d: Dictionary = _build_info_panel(_close_log, Palette.TEXT)
	log_layer = d["layer"]
	log_box = d["box"]
	log_title = d["title"]
	log_body = d["body"]
	log_title.text = "版本更新日志"
	log_body.text = _changelog_bbcode()

func _on_log() -> void:
	if log_layer.visible:
		_close_log()
		return
	sfx.play("select", -18.0)
	log_body.text = _changelog_bbcode()
	log_layer.visible = true

func _close_log() -> void:
	log_layer.visible = false

## 更新日志。写给玩家看的，不是 commit log ——
## 只写「这一版你玩起来会有什么不同」，不写重构了哪个类。
func _changelog_bbcode() -> String:
	var h: Callable = func(c: Color) -> String: return c.to_html(false)
	var gold: String = h.call(Palette.GOLD)
	var dim: String = h.call(Palette.DIM)
	var ok: String = h.call(Palette.OK)
	var hot: String = h.call(Palette.STRONG)
	var bad: String = h.call(Palette.LIFE)
	var fire: String = h.call(Palette.FIRE)
	var wood: String = h.call(Palette.WOOD)
	var water: String = h.call(Palette.WATER)
	var t: Array[String] = []

	t.append("[color=#%s]v1.3[/color]" % gold)
	t.append("· [color=#%s]难度要一档一档解锁[/color]：通关简单才开困难，通关困难才开地狱" % hot)
	t.append("· 结算页多了[color=#%s]返回首页[/color]，不用重开游戏才能换难度" % ok)
	t.append("· [color=#%s]精英和 BOSS 放技能前会先停 0.5 秒[/color]，头上弹技能名" % hot)
	t.append("[color=#%s]  站着不动也照样挨打 —— 前摇结束前打死它，这次技能就没了[/color]" % dim)
	t.append("· [color=#%s]克制差距从 12 倍拉到 18 倍[/color]，打错属性更难受" % bad)
	t.append("· 奖励池大改：")
	t.append("[color=#%s]  淬火 / 急速改成「随机一种属性」，只加那一种塔，无属性塔吃不到[/color]" % dim)
	t.append("[color=#%s]  贯穿之刃升到 S 级、真伤 10 点；破绽改成 20%% 起步、每级 +15%% / +0.5 且不封顶[/color]" % dim)
	t.append("[color=#%s]  移除爆发、奠基、免费升级券、裂变[/color]" % dim)
	t.append("· 经济重调：")
	t.append("[color=#%s]  击杀赏金大幅下调（原本一局能剩几千金花不完）[/color]" % dim)
	t.append("[color=#%s]  塔位便宜一半：60/80/90/120/150/180/230/290[/color]" % dim)
	t.append("[color=#%s]  练级便宜一半：120/240/480[/color]" % dim)
	t.append("· [color=#%s]免费拆除、免费刷新都改成按难度给[/color]：" % hot)
	t.append("[color=#%s]  拆除　简单 每波 1 次 / 困难 每波 1 次但整局上限 3 / 地狱 整局 1 次[/color]" % dim)
	t.append("[color=#%s]  刷新　简单 每次选择 1 次 / 困难 每轮 3 次选择共 1 次 / 地狱 没有免费[/color]" % dim)
	t.append("")
	t.append("[color=#%s]v1.2[/color]" % gold)
	t.append("· 标题页可以选[color=#%s]难度[/color]了：简单 / 困难 / 地狱" % hot)
	t.append("· 加了这个[color=#%s]更新日志[/color]页" % hot)
	t.append("· [color=#%s]克制差距从 8.7 倍拉到 12 倍[/color]" % hot)
	t.append("[color=#%s]  打错属性现在比不带属性还惨。[/color]" % dim)
	t.append("· [color=#%s]精英会放技能了[/color]：" % hot)
	t.append("[color=#%s]  出场放一次，之后每走完一段路再放一次[/color]" % dim)
	t.append("[color=#%s]  简单 1 次 / 困难 2 次 / 地狱 3 次[/color]" % dim)
	t.append("　[color=#%s]火 · 浴火[/color]　全场杂兵跑得更快" % fire)
	t.append("　[color=#%s]木 · 分裂[/color]　杂兵死时裂成两只半血的" % wood)
	t.append("　[color=#%s]水 · 潮涌[/color]　全场杂兵血量回满" % water)
	t.append("· [color=#%s]大 BOSS 三件套[/color]：" % bad)
	t.append("[color=#%s]  血量每掉一段换一种属性 / 召唤护卫 / 死时裂成三只精英[/color]" % dim)
	t.append("· HUD 和结算页会标出当前难度")
	t.append("")
	t.append("[color=#%s]v1.1[/color]" % gold)
	t.append("· 奖励从 16 张加到 [color=#%s]24 张[/color]" % hot)
	t.append("[color=#%s]  新增处决、裂变、连杀、蓄力、锁定、奠基、回春、独尊[/color]" % dim)
	t.append("· 三种属性有了各自的脾气：")
	t.append("[color=#%s]  火跑得快但脆 / 木慢而厚 / 水死时给全场回血[/color]" % dim)
	t.append("· 一局的节奏重排：")
	t.append("[color=#%s]  1~3 波三种属性各来一波，4~6 波两两组合，7 波起三色混战[/color]" % dim)
	t.append("[color=#%s]  精英挪到 4/6/8 波，第 10 波换成大 BOSS[/color]" % dim)
	t.append("· 精英和 BOSS 的属性[color=#%s]单独随机[/color]，不跟本波杂兵走" % hot)
	t.append("· [color=#%s]堆到封顶的奖励不再出现[/color]在三选一里" % ok)
	t.append("· 刷新价格重做，不再是几块钱的白送")
	t.append("· 免费拆除从「每波一次」改成[color=#%s]整局一次[/color]" % hot)
	t.append("· 赛道重做：沙土路面、木栅栏、起点绿闸门 / 终点红闸门")
	t.append("· 杂兵 / 精英 / BOSS 各有自己的样子")
	t.append("· 说明面板改成单栏可滚动，关键信息上色")
	t.append("· 利息现在直接写「这一波结束能进账多少」")
	t.append("")
	t.append("[color=#%s]v1.0[/color]" % gold)
	t.append("· 完整的一局：10 波、火木水克制三角、波间三选一")
	t.append("· 塔可练级，同属性凑满 3 座解锁全屏技能")
	t.append("· 奖励分 S / A / B / C 稀有度，可刷新")
	t.append("· 像素风表现层，打击感、技能特效、击杀粒子")
	return "\n".join(t)

func _on_help() -> void:
	if help_layer.visible:
		_close_help()
		return
	sfx.play("select", -18.0)
	help_layer.visible = true

func _close_help() -> void:
	help_layer.visible = false

func _on_buffs() -> void:
	if buff_layer.visible:
		_close_buffs()
		return
	sfx.play("select", -18.0)
	_refresh_buff_panel()
	buff_layer.visible = true

func _close_buffs() -> void:
	buff_layer.visible = false

func _refresh_buff_panel() -> void:
	buff_title.text = "当前加成　·　已做过 %d 次选择" % run.taken_count()
	var rows: Array[String] = []
	for e: Dictionary in run.taken_list():
		rows.append("%s　×%d" % [e["title"], e["count"]])
	var lines2: Array[String] = run.mods.summary_lines()
	var gold: String = Palette.GOLD.to_html(false)
	var ok: String = Palette.OK.to_html(false)
	buff_body.text = "[color=#%s]【已领取的奖励】[/color]\n%s\n\n[color=#%s]【换算成实际效果】[/color]\n[color=#%s]%s[/color]" % [
		gold, "\n".join(rows) if not rows.is_empty() else "（还没领过）",
		gold, ok, "\n".join(lines2) if not lines2.is_empty() else "（无）"]

## 所有位置都按实际视口算。窗口一变就重新摆一次。
func _position_ui() -> void:
	ui.position = Vector2.ZERO
	ui.size = Vector2(vw, vh)

	lbl_wave.position = Vector2(16, 6)
	lbl_wave.size = Vector2(210, 28)
	# 有图标的时候文字往右让 26px，图标画在 _draw 里
	var icon_pad: float = 26.0 if tex_gold != null else 0.0
	# 图标画在 y 7..27（中心 17），数字得跟它对齐 ——
	# Label 默认顶对齐，不设 CENTER 的话数字会比图标低一截。
	lbl_gold.position = Vector2(216 + icon_pad, 5)
	lbl_gold.size = Vector2(120, 24)
	lbl_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_lives.position = Vector2(374 + icon_pad, 5)
	lbl_lives.size = Vector2(120, 24)
	lbl_lives.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_preview.position = Vector2(16, 46)
	lbl_preview.size = Vector2(440, 22)
	lbl_hint.position = Vector2(0, field_bottom - 26.0)
	lbl_hint.size = Vector2(vw, 20)

	btn_start.position = Vector2(vw - 116.0, 8)
	btn_start.size = Vector2(100, 32)
	btn_speed.position = Vector2(vw - 166.0, 8)
	btn_speed.size = Vector2(44, 32)
	btn_mute.position = Vector2(vw - 214.0, 8)
	btn_mute.size = Vector2(42, 32)
	btn_help.position = Vector2(vw - 352.0, 8)
	btn_help.size = Vector2(40, 32)
	btn_buffs.position = Vector2(vw - 306.0, 8)
	btn_buffs.size = Vector2(86, 32)
	# 技能按钮移到 HUD 第二行右侧，跟上面那排功能键分开
	var sx: float = vw - 250.0
	for e: Types.Element in Types.ELEMENTAL:
		var b: Button = btn_skills[e]
		b.position = Vector2(sx, 42)
		b.size = Vector2(76, 30)
		var bar: ColorRect = skill_bars[e]
		bar.position = Vector2(0, 26)
		bar.size = Vector2(76, 4)
		sx += 80.0

	_place_panel(buff_layer, buff_box, buff_title, buff_body, 560.0, 430.0)
	_place_panel(help_layer, help_box, help_title, help_body, 640.0, 9999.0)
	_place_panel(log_layer, log_box, log_title, log_body, 620.0, 9999.0)

	title_layer.size = Vector2(vw, vh)
	var tdim: ColorRect = title_layer.get_node_or_null("Dim")
	if tdim != null:
		tdim.position = Vector2.ZERO
		tdim.size = Vector2(vw, vh)
	title_name.position = Vector2(0, vh * 0.22)
	title_name.size = Vector2(vw, 60)
	title_sub.position = Vector2(0, vh * 0.22 + 68.0)
	title_sub.size = Vector2(vw, 24)

	# 难度按钮一排
	var dw: float = 96.0
	var dgap: float = 12.0
	var dtotal: float = dw * 3.0 + dgap * 2.0
	var dy: float = vh * 0.40
	var di: int = 0
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		var db: Button = diff_buttons.get(d, null)
		if db != null:
			db.position = Vector2((vw - dtotal) * 0.5 + float(di) * (dw + dgap), dy)
			db.size = Vector2(dw, 40)
		di += 1
	if title_diff_hint != null:
		title_diff_hint.position = Vector2(0, dy + 46.0)
		title_diff_hint.size = Vector2(vw, 20)

	for i: int in 4:
		var b: Button = title_layer.get_node_or_null("T%d" % i)
		if b != null:
			b.position = Vector2(vw * 0.5 - 90.0, vh * 0.54 + float(i) * 48.0)
			b.size = Vector2(180, 40)

	reward_layer.size = Vector2(vw, vh)
	reward_dim.position = Vector2.ZERO
	reward_dim.size = Vector2(vw, vh)

	var gap: float = 18.0
	var pad: float = 26.0
	var cw: float = minf(250.0, (vw - pad * 2.0 - gap * 2.0 - 20.0) / 3.0)
	var ch: float = 196.0
	var bw: float = cw * 3.0 + gap * 2.0 + pad * 2.0
	var bh: float = ch + 122.0
	reward_box.position = Vector2((vw - bw) * 0.5, (vh - bh) * 0.5)
	reward_box.size = Vector2(bw, bh)
	reward_title.position = Vector2(0, 20)
	reward_title.size = Vector2(bw, 30)
	btn_reward_min.position = Vector2(bw - 76.0, 16)
	btn_reward_min.size = Vector2(60, 30)
	btn_reward_reroll.position = Vector2(16, 16)
	btn_reward_reroll.size = Vector2(112, 30)
	reward_bar.position = Vector2(vw * 0.5 - 115.0, field_bottom - 48.0)
	reward_bar.size = Vector2(230, 38)
	var cy: float = 66.0
	for i: int in reward_cards.size():
		var b: Button = reward_cards[i]["btn"]
		b.position = Vector2(pad + float(i) * (cw + gap), cy)
		b.size = Vector2(cw, ch)
		var header: ColorRect = reward_cards[i]["header"]
		header.position = Vector2(0, 0)
		header.size = Vector2(cw, 26)
		var rank: Label = reward_cards[i]["rank"]
		rank.position = Vector2(0, 3)
		rank.size = Vector2(cw, 20)
		var title: Label = reward_cards[i]["title"]
		title.position = Vector2(0, 38)
		title.size = Vector2(cw, 26)
		var desc: Label = reward_cards[i]["desc"]
		desc.position = Vector2(14, 74)
		desc.size = Vector2(cw - 28.0, 62)
		var status: Label = reward_cards[i]["status"]
		status.position = Vector2(12, ch - 58.0)
		status.size = Vector2(cw - 24.0, 46)

	over_layer.size = Vector2(vw, vh)
	over_dim.position = Vector2.ZERO
	over_dim.size = Vector2(vw, vh)
	over_title.position = Vector2(0, vh * 0.30)
	over_title.size = Vector2(vw, 50)
	over_detail.position = Vector2(vw * 0.2, vh * 0.30 + 66.0)
	over_detail.size = Vector2(vw * 0.6, 80)
	over_again.position = Vector2(vw * 0.5 - 148.0, vh * 0.30 + 160.0)
	over_again.size = Vector2(140, 44)
	over_home.position = Vector2(vw * 0.5 + 8.0, vh * 0.30 + 160.0)
	over_home.size = Vector2(140, 44)

func _place_panel(layer: Control, box: Panel, title: Label,
		body: RichTextLabel, want_w: float, want_h: float) -> void:
	layer.size = Vector2(vw, vh)
	var dim: ColorRect = layer.get_child(0)
	dim.position = Vector2.ZERO
	dim.size = Vector2(vw, vh)
	var bw: float = minf(want_w, vw - 60.0)
	var bh: float = minf(want_h, vh - 32.0)
	box.position = Vector2((vw - bw) * 0.5, (vh - bh) * 0.5)
	box.size = Vector2(bw, bh)
	title.position = Vector2(0, 12)
	title.size = Vector2(bw, 26)
	body.position = Vector2(26, 46)
	body.size = Vector2(bw - 52.0, bh - 60.0)
	# 关闭放右上角而不是底部置中：底部那一排会吃掉整整一行高度，
	# 说明面板的内容本来就塞不下，能省则省。
	var close: Button = box.get_node_or_null("Close")
	if close != null:
		close.position = Vector2(bw - 68.0, 10)
		close.size = Vector2(54, 28)

# ---- 界面刷新 --------------------------------------------------------------

func _refresh() -> void:
	_refresh_hud()
	_refresh_slot_panel()

func _refresh_hud() -> void:
	var shown_lives: int = run.lives
	if run.battle != null:
		shown_lives -= run.battle.lives_lost
	lbl_wave.text = "第 %d / %d 波　%s" % [
		mini(run.wave_index, Balance.TOTAL_WAVES), Balance.TOTAL_WAVES,
		Balance.difficulty_name()]
	lbl_gold.text = str(run.gold) if tex_gold != null else "金 %d" % run.gold
	lbl_lives.text = str(maxi(shown_lives, 0)) if tex_life != null \
		else "命 %d" % maxi(shown_lives, 0)
	btn_buffs.text = "加成 %d" % run.taken_count()

	var w: Wave = run.current_wave()
	if phase == Phase.BATTLE and run.battle != null:
		lbl_preview.text = "本波 %s　　已杀 %d　漏 %d" % [
			w.preview(), run.battle.killed, run.battle.leaked]
	elif w != null:
		# 利息直接写在 HUD 上：「这笔钱花掉还是留着」是个高频决策，
		# 不该让玩家去翻奖励卡片才知道留着能生多少。
		var bits: Array[String] = ["下一波 %s" % w.preview()]
		if run.mods.effective_interest() > 0.0:
			bits.append("利息 +%d" % run.interest_preview())
		if run.free_sells > 0:
			# 整局有上限的档位要把「还剩几次」一起写出来，
			# 不然玩家以为每波都有，用到第四波才发现没了
			var left: int = run.free_sells_left()
			if left < 0:
				bits.append("免费拆除 %d 次" % run.free_sells)
			else:
				bits.append("免费拆除 %d 次（整局还剩 %d）" % [run.free_sells, left])
		lbl_preview.text = "　　".join(bits)
	else:
		lbl_preview.text = ""

	var in_game: bool = phase != Phase.TITLE
	lbl_wave.visible = in_game
	lbl_gold.visible = in_game
	lbl_lives.visible = in_game
	lbl_preview.visible = in_game
	btn_mute.visible = in_game
	btn_start.visible = phase == Phase.BUILD
	btn_speed.visible = phase == Phase.BATTLE
	btn_buffs.visible = in_game and phase != Phase.OVER
	btn_help.visible = in_game and phase != Phase.OVER
	_refresh_skill_buttons()
	if buff_layer.visible:
		_refresh_buff_panel()
	# 选中塔位时操作按钮会浮在这个位置，提示让位
	if phase == Phase.TITLE:
		lbl_hint.text = ""
	elif phase == Phase.BUILD and selected_slot < 0:
		lbl_hint.text = "塔位下的 ×倍率＝这座塔对下一波怪的实际伤害倍率（绿＝克制，红＝几乎无效）"
	elif phase == Phase.BATTLE and selected_slot < 0:
		lbl_hint.text = "战斗中一样可以建塔、升级、拆除　·　赏金即时到账"
	else:
		lbl_hint.text = ""

## 塔位状态的签名。只有它变了才值得重建按钮。
## 刻意不把金钱算进去——金钱每击杀都在变，算进去就等于每帧重建了。
func _slot_signature() -> String:
	if selected_slot < 0:
		return ""
	var t: Tower = run.tower_at(selected_slot)
	return "%d|%s|%d|%d|%d" % [
		selected_slot,
		"none" if t == null else str(int(t.element)),
		0 if t == null else t.level,
		run.free_sells, int(phase)]

## 技能按钮：没解锁就藏起来，冷却中显示剩余秒数
func _refresh_skill_buttons() -> void:
	for e: Types.Element in Types.ELEMENTAL:
		var b: Button = btn_skills[e]
		var unlocked: bool = run.skill_unlocked(e)
		b.visible = unlocked and phase != Phase.OVER and phase != Phase.TITLE
		if not unlocked:
			continue
		var cd: float = run.skill_remaining(e)
		var bar: ColorRect = skill_bars[e]
		if phase != Phase.BATTLE:
			b.text = "%s 技能" % Types.name_of(e)
			b.disabled = true
			bar.visible = false
		elif cd > 0.0:
			b.text = "%s 冷却 %ds" % [Types.name_of(e), ceili(cd)]
			b.disabled = true
			bar.visible = true
			bar.size = Vector2(76.0 * (1.0 - cd / maxf(run.skill_cooldown(), 0.001)), 4)
		else:
			b.text = "%s 放大招" % Types.name_of(e)
			b.disabled = false
			bar.visible = false

func _refresh_slot_panel() -> void:
	var sig: String = _slot_signature()
	if sig == _slot_sig and slot_panel.visible == (selected_slot >= 0):
		return
	_slot_sig = sig
	slot_buttons.clear()
	for c: Node in slot_panel.get_children():
		slot_panel.remove_child(c)
		c.queue_free()
	if (phase != Phase.BUILD and phase != Phase.BATTLE) or selected_slot < 0:
		slot_panel.visible = false
		slot_buttons.clear()
		_slot_sig = ""
		return
	slot_panel.visible = true

	var specs: Array[Dictionary] = []
	var t: Tower = run.tower_at(selected_slot)
	if t == null:
		var cost: int = run.tower_cost(selected_slot)
		specs.append({"text": "建塔 %d" % cost, "color": Palette.OK, "on": _on_build,
			"check": func() -> bool: return run.gold >= cost})
	else:
		if not t.is_upgraded():
			for e: Types.Element in Types.ELEMENTAL:
				specs.append({
					"text": "%s %d" % [Types.name_of(e), run.upgrade_cost()],
					"color": Palette.of(e), "on": _on_upgrade.bind(e),
					"check": func() -> bool: return run.gold >= run.upgrade_cost(),
				})
		if t.can_level_up():
			var lc: int = run.level_up_cost(selected_slot)
			specs.append({
				"text": "Lv%d  %d" % [t.level + 1, lc],
				"color": Palette.of(t.element), "on": _on_level_up,
				"check": func() -> bool: return run.gold >= lc,
			})
		specs.append({"text": "拆除 +%d" % run.sell_value(selected_slot),
			"color": Palette.PANEL_HI, "on": _on_sell,
			"check": func() -> bool: return true})

	var bw: float = 78.0
	var gap: float = 5.0
	var total: float = float(specs.size()) * bw + float(specs.size() - 1) * gap
	var center: float = _slot_rect(selected_slot).position.x + slot_w * 0.5
	var x: float = clampf(center - total * 0.5, 6.0, vw - 6.0 - total)
	for s: Dictionary in specs:
		var b: Button = Button.new()
		b.text = s["text"]
		b.position = Vector2(x, row_y - 46.0)
		b.size = Vector2(bw, 36)
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = not bool((s["check"] as Callable).call())
		_style(b, s["color"])
		b.pressed.connect(s["on"])
		slot_panel.add_child(b)
		slot_buttons.append({"btn": b, "ok": s["check"]})
		x += bw + gap

## 每帧刷新「买不买得起」，但不动按钮本身
func _update_slot_buttons() -> void:
	for e: Dictionary in slot_buttons:
		var b: Button = e["btn"]
		if is_instance_valid(b):
			b.disabled = not bool((e["ok"] as Callable).call())

func _show_rewards() -> void:
	reward_layer.visible = true
	_apply_reward_visibility()
	if reward_is_opening:
		reward_title.text = "开局奖励　·　%d / %d" % [reward_round, Balance.REWARD_ROUNDS]
	else:
		reward_title.text = "第 %d 波结束　·　奖励 %d / %d" % [
			run.wave_index - 1, reward_round, Balance.REWARD_ROUNDS]
	var rr_cost: int = run.reroll_cost()
	btn_reward_reroll.text = "刷新　免费" if rr_cost == 0 else "刷新　%d 金" % rr_cost
	btn_reward_reroll.disabled = not run.can_reroll()
	for i: int in reward_cards.size():
		var card: Dictionary = reward_cards[i]
		var vis: bool = i < reward_choices.size()
		card["btn"].visible = vis
		if vis:
			var r: Reward = reward_choices[i]
			var rc: Color = Palette.rarity(int(r.rarity))
			card["header"].color = rc
			card["rank"].text = "%s 级" % r.rarity_name()
			# 色条上的字要压得住底色，深色稀有度用亮字，亮色用暗字
			card["rank"].add_theme_color_override("font_color",
				Palette.BG if rc.get_luminance() > 0.45 else Palette.TEXT)
			card["title"].text = r.title
			card["desc"].text = r.desc
			card["status"].text = r.status(run)
			# 卡片底色往稀有度色偏一点，整张卡才有「档次感」
			_style(card["btn"], Palette.PANEL_HI.lerp(rc, 0.14), rc)
	_refresh_hud()

func _show_over() -> void:
	over_layer.visible = true
	over_title.text = ("通　关" if run.won else "失　败") + "　·　" + Balance.difficulty_name()
	over_title.add_theme_color_override("font_color",
		Palette.OK if run.won else Palette.LIFE)
	var line: String = "剩余生命 %d" % run.lives if run.won \
		else "撑到第 %d 波" % run.wave_index
	# 首次通关才报喜：重复通关每次都弹一遍「解锁了困难」很烦
	if run.won and Progress.mark_cleared(Balance.difficulty):
		var nxt: Balance.Difficulty = Progress.unlocks(Balance.difficulty)
		if nxt != Balance.difficulty:
			line += "　·　解锁了「%s」难度" % Balance.DIFFICULTY_NAMES[nxt]
	over_detail.text = "%s\n最终加成：%s" % [line, run.mods.describe()]

# ---- 小工具 ----------------------------------------------------------------

func _label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	ui.add_child(l)
	return l

func _button(text: String, color: Color, on: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	_style(b, color)
	b.pressed.connect(on)
	ui.add_child(b)
	return b

## 按钮样式。有贴图的 preset 走九宫格 + 颜色调变（一张灰底图能染出所有颜色），
## 没贴图的就用纯色 StyleBoxFlat。调用方不用管现在是哪一种。
func _style(b: Button, base: Color, border: Color = Color(0, 0, 0, 0)) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var c: Color = base
		match state:
			"hover": c = base.lightened(0.16)
			"pressed": c = base.darkened(0.18)
			"disabled": c = base.darkened(0.55)
		b.add_theme_stylebox_override(state, _box(c, border, state == "disabled"))
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_disabled_color", Palette.DIM)

func _box(c: Color, border: Color, dim: bool) -> StyleBox:
	if Palette.BTN_TEX != "" and ResourceLoader.exists(Palette.BTN_TEX):
		var st: StyleBoxTexture = StyleBoxTexture.new()
		st.texture = load(Palette.BTN_TEX)
		st.set_texture_margin_all(float(Palette.TEX_MARGIN))
		st.modulate_color = c
		return st
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(Palette.CORNER_RADIUS)
	if border.a > 0.0:
		sb.border_color = border if not dim else border.darkened(0.5)
		sb.set_border_width_all(3)
	elif Palette.BORDER_WIDTH > 0:
		sb.border_color = c.lightened(0.35)
		sb.set_border_width_all(Palette.BORDER_WIDTH)
	return sb

## 弹窗外框，同样支持贴图
func _panel_box() -> StyleBox:
	if Palette.PANEL_TEX != "" and ResourceLoader.exists(Palette.PANEL_TEX):
		var st: StyleBoxTexture = StyleBoxTexture.new()
		st.texture = load(Palette.PANEL_TEX)
		st.set_texture_margin_all(float(Palette.TEX_MARGIN))
		st.modulate_color = Palette.PANEL_HI
		return st
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL
	sb.border_color = Palette.SLOT_EDGE
	sb.set_border_width_all(Palette.PANEL_BORDER)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	return sb
