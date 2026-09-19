class_name Battle
extends RefCounted

## 一波战斗的推进。纯 RefCounted，不碰场景树——UI 每帧读状态，无头模拟 while 回圈跑。
## 没有射程，所有塔都打得到全场，目标一律是「走得最前面的活怪」。

var towers: Array[Tower] = []
var mods: Modifiers
var active: Array[Enemy] = []
var rng: RandomNumberGenerator

var time: float = 0.0
var gold_earned: int = 0
var lives_lost: int = 0
var killed: int = 0
var leaked: int = 0
var damage_total: float = 0.0

## 本 step 内发生的开火，给表现层用：{slot, dist, crit, killed, damage, effect}
## 规则层不认识画面，只记录「谁打了走到哪里的怪」，怎么画是 UI 的事。
var last_shots: Array[Dictionary] = []
## 本 step 内的灼烧跳伤：{dist, damage, killed}
var last_ticks: Array[Dictionary] = []
## 最近一次施放的技能，给表现层放特效：{element, time}
var last_skill: Dictionary = {}

var _specs: Array[Dictionary] = []
var _next_spawn: int = 0

func _init(wave: Wave, towers_: Array[Tower], mods_: Modifiers, rng_: RandomNumberGenerator) -> void:
	_specs = wave.specs
	towers = towers_
	mods = mods_
	rng = rng_
	for t: Tower in towers:
		t.reset_for_wave()

func is_finished() -> bool:
	return _next_spawn >= _specs.size() and active.is_empty()

func step(dt: float) -> void:
	last_shots.clear()
	last_ticks.clear()
	time += dt
	_spawn()
	_advance(dt)
	_fire(dt)
	_cleanup()

## 一路跑到这波结束，返回统计。
func run_to_end() -> Dictionary:
	var guard: int = 0
	while not is_finished() and guard < 100000:
		step(Balance.SIM_STEP)
		guard += 1
	return {
		"killed": killed,
		"leaked": leaked,
		"lives_lost": lives_lost,
		"gold_earned": gold_earned,
		"damage": damage_total,
		"duration": time,
	}

func _spawn() -> void:
	while _next_spawn < _specs.size() and float(_specs[_next_spawn]["time"]) <= time:
		var s: Dictionary = _specs[_next_spawn]
		active.append(Enemy.new(s["element"], s["hp"], s["speed"], s["bounty"], s["elite"]))
		_next_spawn += 1

func _advance(dt: float) -> void:
	for e: Enemy in active:
		if not e.alive:
			continue
		_burn(e, dt)
		if not e.alive:
			continue
		var sp: float = e.speed()
		# 缠绕优先：定身期间完全不动
		if e.root_time > 0.0:
			e.root_time -= dt
			sp = 0.0
		else:
			# 奖励减速和技能减速取较重的那个，不叠加
			var slow: float = 0.0
			if e.slow_timer > 0.0:
				slow = maxf(slow, mods.effective_slow())
				e.slow_timer -= dt
			if e.skill_slow_time > 0.0:
				slow = maxf(slow, e.skill_slow_pct)
				e.skill_slow_time -= dt
			sp *= 1.0 - slow
		e.distance += sp * dt
		if e.distance >= Balance.TRACK_LENGTH:
			e.alive = false
			leaked += 1
			lives_lost += e.leak_cost()

## 灼烧每 0.2 秒结算一次，而不是逐帧扣血——跳字才看得清楚
func _burn(e: Enemy, dt: float) -> void:
	if e.burn_time <= 0.0:
		return
	e.burn_time -= dt
	e.burn_acc += dt
	while e.burn_acc >= Balance.SKILL_BURN_TICK and e.alive:
		e.burn_acc -= Balance.SKILL_BURN_TICK
		var d: float = e.burn_dps * Balance.SKILL_BURN_TICK
		var dealt: float = minf(d, e.hp)
		damage_total += dealt
		var died: bool = e.take_damage(d)
		if died:
			killed += 1
			gold_earned += e.bounty
		last_ticks.append({"dist": e.distance, "damage": roundi(dealt), "killed": died,
			"element": int(e.element), "elite": e.is_elite})

## 施放技能：全屏该属性 AOE，伤害同样吃属性克制，再附带各自的状态。
## 伤害由 RunState 算好传进来（它才知道塔的等级），Battle 只负责结算。
func cast_skill(element: Types.Element, power: float) -> void:
	last_skill = {"element": element, "time": time}
	for e: Enemy in active:
		if not e.alive:
			continue
		var dmg: float = power * mods.multiplier(element, e.element)
		var dealt: float = minf(dmg, e.hp)
		damage_total += dealt
		var died: bool = e.take_damage(dmg)
		if died:
			killed += 1
			gold_earned += e.bounty
		last_shots.append({
			"slot": -1, "dist": e.distance, "crit": false, "killed": died,
			"damage": roundi(dealt),
			"effect": int(Types.effectiveness(element, e.element)),
			"element": int(e.element), "elite": e.is_elite,
		})
		if died:
			continue
		match element:
			Types.Element.FIRE:
				e.burn_dps = power * Balance.SKILL_BURN_RATIO / Balance.SKILL_BURN_DURATION
				e.burn_time = Balance.SKILL_BURN_DURATION
				e.burn_acc = 0.0
			Types.Element.WATER:
				e.skill_slow_pct = Balance.SKILL_SLOW_PCT
				e.skill_slow_time = Balance.SKILL_SLOW_DURATION
			Types.Element.WOOD:
				e.root_time = Balance.SKILL_ROOT_DURATION

func _fire(dt: float) -> void:
	if active.is_empty():
		return
	# 走得最前面的排前面
	var queue: Array[Enemy] = active.filter(func(e: Enemy) -> bool: return e.alive)
	queue.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.distance > b.distance)
	for t: Tower in towers:
		t.cooldown -= dt
		if t.cooldown > 0.0:
			continue
		if queue.is_empty():
			t.cooldown = 0.0
			continue
		_shoot(t, queue)
		t.cooldown += 1.0 / t.rate(mods)

func _shoot(t: Tower, queue: Array[Enemy]) -> void:
	var base: float = t.damage(mods)
	var crit: bool = mods.effective_crit() > 0.0 and rng.randf() < mods.effective_crit()
	# 塔等级决定「全额伤害」的目标数，穿透在这之外再加减伤目标
	var full: int = t.targets()
	var chain: int = full + mods.pierce_targets
	var hit: int = 0
	for e: Enemy in queue:
		if not e.alive:
			continue
		if hit >= chain:
			break
		var dmg: float = base * mods.multiplier(t.element, e.element) + mods.true_damage
		if crit:
			dmg *= mods.crit_multiplier()
		if hit >= full:
			dmg *= Modifiers.PIERCE_RATIO
		if mods.effective_slow() > 0.0:
			e.slow_timer = Modifiers.SLOW_DURATION
		var dealt: float = minf(dmg, e.hp)
		t.damage_dealt += dealt
		damage_total += dealt
		var died: bool = e.take_damage(dmg)
		if died:
			t.kills += 1
			killed += 1
			gold_earned += e.bounty
		last_shots.append({
			"slot": t.slot, "dist": e.distance, "crit": crit, "killed": died,
			"damage": dealt, "effect": int(Types.effectiveness(t.element, e.element)),
			"element": int(e.element), "elite": e.is_elite,
		})
		hit += 1

func _cleanup() -> void:
	active = active.filter(func(e: Enemy) -> bool: return e.alive)
