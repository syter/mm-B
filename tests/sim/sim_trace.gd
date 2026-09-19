extends SceneTree

## 逐波明细，用来定位「水分在哪」：每波的总血量 vs 我方总输出。
## 跑法：godot --headless --path . --script res://tests/sim/sim_trace.gd

const PRIORITY: Array[String] = [
	"counter", "damage", "rate", "crit", "true", "pierce",
	"gold", "interest", "slow", "life", "ticket", "relief", "neutral",
]

func _initialize() -> void:
	var rs: RunState = RunState.new(20260919)
	print("波  怪物构成            总血量   塔数 理论DPS  窗口s  可打出   击杀 漏 扣命  金  命")
	while not rs.finished:
		var w: Wave = rs.current_wave()
		_build(rs, w.composition())
		var dps: float = _dps(rs)
		var window: float = float(w.specs.size() - 1) * Balance.SPAWN_INTERVAL \
			+ Balance.TRACK_LENGTH / (Balance.ENEMY_BASE_SPEED * (1.0 + Balance.SPEED_GROWTH * float(w.index - 1)))
		var comp: String = w.preview()
		var r: Dictionary = rs.play_wave()
		print("%2d  %-20s %7.0f  %2d  %7.1f %6.1f %8.0f %5d %2d %4d %4d %3d" % [
			w.index, comp, w.total_hp(), rs.towers.size(), dps, window, dps * window,
			int(r["killed"]), int(r["leaked"]), int(r["lives_lost"]), rs.gold, rs.lives])
		if rs.finished:
			break
		_rewards(rs)
	print("\n结果：%s  剩命 %d  金 %d" % ["通关" if rs.won else "失败", rs.lives, rs.gold])
	print("最终加成：%s" % rs.mods.describe())
	quit()

## 理论 DPS：8 座塔打当前波次的平均倍率
func _dps(rs: RunState) -> float:
	var w: Wave = rs.current_wave()
	var comp: Dictionary = w.composition()
	var total: int = 0
	for c: int in comp.values():
		total += c
	var sum: float = 0.0
	for t: Tower in rs.towers:
		var avg: float = 0.0
		for e: Types.Element in comp.keys():
			avg += rs.mods.multiplier(t.element, e) * float(comp[e]) / float(total)
		sum += t.damage(rs.mods) * t.rate(rs.mods) * avg
	return sum

func _build(rs: RunState, comp: Dictionary) -> void:
	var useful: Array[Types.Element] = []
	for e: Types.Element in comp.keys():
		useful.append(Types.counter_of(e))
	for t: Tower in rs.towers.duplicate():
		if t.is_upgraded() and not useful.has(t.element):
			rs.sell_tower(t.slot)
	while rs.can_build():
		rs.build_tower()
	for t: Tower in rs.towers:
		if t.is_upgraded():
			continue
		var want: Types.Element = _wanted(rs, comp)
		if want == Types.Element.NONE:
			break
		if rs.mods.free_upgrades > 0 or rs.gold >= Balance.UPGRADE_COST:
			rs.upgrade_tower(t.slot, want)
		else:
			break

func _wanted(rs: RunState, comp: Dictionary) -> Types.Element:
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

func _rewards(rs: RunState) -> void:
	for i: int in Balance.REWARD_ROUNDS:
		var choices: Array[Reward] = rs.roll_rewards()
		if choices.is_empty():
			return
		var pick: Reward = choices[0]
		var best_rank: int = 99
		for c: Reward in choices:
			var rank: int = PRIORITY.find(c.id)
			if rank == -1:
				rank = 50
			if rank < best_rank:
				best_rank = rank
				pick = c
		rs.take_reward(pick)
