class_name GreedyPlayer
extends RefCounted

## 脚本玩家，给平衡模拟用。不是游戏 AI，是「一个中等水平玩家」的替身——
## 用它扫出来的通关率当难度基准：它能稳过的配置，对人类就太简单了。
##
## mode:
##   "neutral"  只盖无属性塔，从不升级。用来验证「有没有不靠克制的歪路」。
##   "counter"  照下一波构成升级成克制属性，但从不拆塔。
##   "adaptive" 同上，另外会用掉手上的免费拆除名额，换掉下一波最没用的那座塔。
##   "fixed"    完全不看预告，三属性平均铺。用来测「看预告做选择」到底值不值钱。
##   "random"   随机选属性升级。用来测「选对属性」和「有属性就行」的差距。

var mode: String = "adaptive"
## 是否在波次进行中也建塔／升级（赏金即时到账，所以打到一半能补塔）。
## 默认开 —— 真人一定会这么玩，关掉的话量到的通关率偏低，
## 拿它当难度基准就会得出「游戏太难」的错误结论。关掉只用于 A/B 诊断。
var live: bool = true
## 诊断开关：分别关掉开局奖励／刷新，用来定位平衡变化是哪个机制造成的
var opening_rewards: bool = true
var use_reroll: bool = true
## 诊断统计
var stat_rerolls: int = 0
var stat_reroll_gold: int = 0
var stat_takes: int = 0

## 奖励偏好，越前面越优先
## 奖励评分。固定的偏好顺序模拟不了真人 —— 真人前期拿经济、后期拿输出，
## 而且会看场上缺什么。用一张死清单的话，AI 一刷新就永远刷到同一张常见 C 卡，
## 实测通关率会从 45% 崩到 1%。
func _score(rs: RunState, r: Reward) -> float:
	# 距离终局还有多远，1.0 = 刚开局，0.0 = 最后一波
	var early: float = clampf(
		float(Balance.TOTAL_WAVES - rs.wave_index) / float(Balance.TOTAL_WAVES), 0.0, 1.0)
	var base: float = 10.0
	# 认 family 不认 id —— 「淬火·火」的 id 是 damage_火，但它算的还是淬火那一档。
	# 这张表必须盖住奖励池里的每一格：漏掉的会掉到 base 10，
	# AI 不但永远不选，还会花钱把它刷掉。v1.1 加的那批卡就漏了整整一轮。
	match r.family:
		"crit": base = 100.0
		"counter": base = 92.0
		# 每 5 发 ×3（再领 ×5），摊平到每一发就是全局 +40% 伤害，比单属性加成划算
		"charge": base = 68.0
		"pierce": base = 62.0
		"true": base = 58.0
		# 连续命中同一只才叠满，塔越少越容易吃到
		"lock": base = 54.0
		"surge": base = 52.0
		"execute": base = 48.0
		"damage": base = 70.0 * _element_weight(rs, r.element)
		"rate": base = 66.0 * _element_weight(rs, r.element)
		"slow": base = 36.0
		"life": base = 32.0
		# 独尊要求场上只有一种属性。照克制铺塔的打法基本吃不到，所以得看场面给分，
		# 不能按 S 卡的面值算 —— 那会让 AI 拿一张永远不生效的加成。
		"mono": base = 88.0 if _is_mono(rs) else 4.0
		"relief": base = 18.0
		"neutral": base = 6.0
		# 以下几张的价值随波次递减：早期一块钱能滚成一座塔，后期只是一块钱
		"gold": base = 30.0 + 40.0 * early
		"interest": base = 20.0 + 60.0 * early
		"refine": base = 22.0 + 45.0 * early
		"killstreak": base = 18.0 + 30.0 * early
		"regen": base = 20.0 + 26.0 * early
	# 边际递减：同一张已经拿过越多次，再拿的价值越低。
	# 奖励是「同类加算、跨类相乘」，所以分散拿远比堆同一张强 ——
	# 少了这一项，AI 会一直刷新直到刷出它最爱的那张，亲手把 build 毁掉。
	return base / (1.0 + 0.35 * float(rs.taken.get(r.id, 0)))

## 场上是不是只有一种属性的塔（「独尊」生效的条件）
func _is_mono(rs: RunState) -> bool:
	var found: int = -1
	for t: Tower in rs.towers:
		if not t.is_upgraded():
			continue
		if found < 0:
			found = int(t.element)
		elif found != int(t.element):
			return false
	return found >= 0

## 属性加成只作用在那一种属性的塔上，所以这张卡的价值约等于
## 「这种属性占了我多少火力」—— 铺三属性的话一张只加到三分之一的塔上，
## 不能再跟以前那种全场 +N% 同价。一座都没有就是张废牌。
func _element_weight(rs: RunState, e: Types.Element) -> float:
	if e == Types.Element.NONE:
		return 1.0
	var n: int = rs.count_of(e)
	if n <= 0:
		return 0.1
	return 0.1 + 1.1 * float(n) / float(maxi(rs.towers.size(), 1))

func _best_score(rs: RunState, choices: Array[Reward]) -> float:
	var best: float = -1.0
	for c: Reward in choices:
		best = maxf(best, _score(rs, c))
	return best

func _init(mode_: String = "adaptive") -> void:
	mode = mode_

## 跑完一整局，返回 RunState
func play(seed_value: int) -> RunState:
	var rs: RunState = RunState.new(seed_value)
	stat_rerolls = 0
	stat_reroll_gold = 0
	stat_takes = 0
	# 开局先送三次奖励，第一波之前手上就有东西
	if opening_rewards:
		reward_phase(rs)
	while not rs.finished:
		build_phase(rs)
		# 一律逐步推进，否则技能永远放不出来，量到的平衡是假的。
		# live 只控制「波次进行中要不要继续花钱」。
		_play_wave(rs)
		if rs.finished:
			break
		reward_phase(rs)
	return rs

## 逐步推进一波：技能一好就放，live 模式下每秒还会用刚赚的钱补塔。
## 波次进行中不拆塔——免费拆除名额留给建造阶段的属性重组更划算。
func _play_wave(rs: RunState) -> void:
	rs.begin_wave()
	var since: float = 0.0
	while not rs.battle.is_finished():
		rs.step_battle(Balance.SIM_STEP)
		_cast_skills(rs)
		since += Balance.SIM_STEP
		if since >= 1.0:
			since = 0.0
			if live:
				rs.sync_gold()
				_spend(rs)
	rs.sync_gold()
	rs.end_wave()

## 技能一就绪就放。场上没怪时不放，免得空砸。
func _cast_skills(rs: RunState) -> void:
	if rs.battle.active.is_empty():
		return
	for e: Types.Element in Types.ELEMENTAL:
		if rs.skill_ready(e):
			rs.use_skill(e)

## 只花钱，不拆塔
func _spend(rs: RunState) -> void:
	_buy(rs, rs.current_wave().composition())

func build_phase(rs: RunState) -> void:
	var comp: Dictionary = rs.current_wave().composition()
	if mode == "adaptive":
		_sell_useless(rs, comp)
	_buy(rs, comp)

## 花钱的顺序：先把手上的无属性塔升出来，再考虑加塔，最后才练级。
##
## 原本是「有钱就一直盖塔」，结果是一排升不起来的无属性塔 ——
## 它们打有属性怪只有 0.30 倍，等于把钱换成了一堆废塔位。
## 真人不会这么买，AI 这么买的话量到的通关率会明显偏低。
func _buy(rs: RunState, comp: Dictionary) -> void:
	if mode == "neutral":
		while rs.can_build():
			rs.build_tower()
		return
	_upgrade_all(rs, comp)
	# 加塔要留出升级费 —— 盖得起但升不起的塔不如不盖
	while rs.can_build() and rs.gold >= rs.next_tower_cost() + rs.upgrade_cost():
		if rs.build_tower() == null:
			break
		_upgrade_all(rs, comp)
	_level_up(rs, comp)

func _upgrade_all(rs: RunState, comp: Dictionary) -> void:
	for t: Tower in rs.towers:
		if t.is_upgraded():
			continue
		var want: Types.Element = _pick_element(rs, comp)
		if want == Types.Element.NONE:
			return
		if rs.gold < rs.upgrade_cost():
			return
		rs.upgrade_tower(t.slot, want)

## 塔位满了、属性也配好了，多出来的钱拿去练级。
## 优先练「对下一波倍率最高」的塔——练级加的是全额伤害目标，倍率越高越划算。
func _level_up(rs: RunState, comp: Dictionary) -> void:
	while true:
		var best: Tower = null
		var best_mult: float = 0.0
		for t: Tower in rs.towers:
			if not t.can_level_up():
				continue
			var cost: int = rs.level_up_cost(t.slot)
			if cost < 0 or rs.gold < cost:
				continue
			var m: float = _avg_mult(rs, t, comp)
			if m > best_mult:
				best_mult = m
				best = t
		if best == null:
			return
		if not rs.level_up_tower(best.slot):
			return

func _avg_mult(rs: RunState, t: Tower, comp: Dictionary) -> float:
	var total: int = 0
	for c: int in comp.values():
		total += c
	if total == 0:
		return 1.0
	var sum: float = 0.0
	for e: Types.Element in comp.keys():
		sum += rs.mods.multiplier(t.element, e) * float(comp[e]) / float(total)
	return sum

func reward_phase(rs: RunState) -> void:
	rs.begin_reward_phase()
	for i: int in Balance.REWARD_ROUNDS:
		var choices: Array[Reward] = rs.begin_reward_round()
		reward_phase_single(rs, choices)

## 拆出来单独一轮，方便诊断脚本逐轮观察
func reward_phase_single(rs: RunState, choices_in: Array[Reward]) -> void:
		var choices: Array[Reward] = choices_in
		if choices.is_empty():
			return
		# 只在「三张全是废牌」时才刷。门槛设太松的话，AI 会一直刷到
		# 最常见的那张高优先 C 卡为止，等于永远只拿同一种奖励。
		var tries: int = 0
		while use_reroll and tries < 4 and rs.can_reroll() \
				and rs.reroll_cost() <= maxi(2, rs.gold / 15) \
				and _best_score(rs, choices) < 45.0:
			var cost: int = rs.reroll_cost()
			var fresh: Array[Reward] = rs.reroll_rewards()
			if fresh.is_empty():
				break
			stat_rerolls += 1
			stat_reroll_gold += cost
			choices = fresh
			tries += 1
		var pick: Reward = choices[0]
		var best: float = -1.0
		for c: Reward in choices:
			var sc: float = _score(rs, c)
			if sc > best:
				best = sc
				pick = c
		stat_takes += 1
		rs.take_reward(pick)

## 拆掉下一波用不上的塔——但只用免费名额，超出就不拆。
## 付费拆除要亏 40%，模拟实测那样拆反而不如完全不拆。
func _sell_useless(rs: RunState, comp: Dictionary) -> void:
	var useful: Array[Types.Element] = []
	for e: Types.Element in comp.keys():
		useful.append(Types.counter_of(e))
	while rs.free_sells > 0:
		var worst: Tower = null
		for t: Tower in rs.towers:
			if t.is_upgraded() and not useful.has(t.element):
				# 塔价绑塔位，拆哪座重建都不赚不亏，就先拆最便宜的
				if worst == null or t.invested < worst.invested:
					worst = t
		if worst == null:
			return
		rs.sell_tower(worst.slot)

## 按模式决定这座塔升成什么属性
func _pick_element(rs: RunState, comp: Dictionary) -> Types.Element:
	match mode:
		"fixed":
			# 不看预告，就照 火/木/水 轮流铺，铺成均匀的三色阵
			return Types.ELEMENTAL[rs.towers.size() % Types.ELEMENTAL.size()]
		"random":
			return Types.ELEMENTAL[rs.rng.randi() % Types.ELEMENTAL.size()]
		_:
			return wanted(rs, comp)

## 缺口最大的克制属性
func wanted(rs: RunState, comp: Dictionary) -> Types.Element:
	var total: int = 0
	for c: int in comp.values():
		total += c
	if total == 0:
		return Types.Element.NONE
	var best: Types.Element = Types.Element.NONE
	var best_gap: float = -999.0
	for e: Types.Element in comp.keys():
		var counter: Types.Element = Types.counter_of(e)
		var gap: float = float(comp[e]) / float(total) * float(Balance.MAX_TOWERS) - float(rs.count_of(counter))
		if gap > best_gap:
			best_gap = gap
			best = counter
	return best
