extends SceneTree

## 核心规则的回归测试（带断言，改坏了会红）。
## 跟 tests/sim/ 底下的一次性平衡实验严格分开：这里的每一条都必须永远为真。
## 跑法：godot --headless --path . --script res://tests/regression/test_core.gd

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	Balance.reset()
	_test_counter_table()
	_test_multiplier()
	_test_modifier_caps()
	_test_tower_economy()
	_test_upgrade_rules()
	_test_free_sell_resets()
	_test_live_gold()
	_test_crit_ladder()
	_test_tower_levels()
	_test_skills()
	_test_reward_pool()
	_test_wave_determinism()
	_test_battle_leaks()
	_test_elite_leak_cost()
	print("\n%d 通过, %d 失败" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# ---- 属性克制 --------------------------------------------------------------

func _test_counter_table() -> void:
	_eq(Types.COUNTERS[Types.Element.FIRE], Types.Element.WOOD, "火克木")
	_eq(Types.COUNTERS[Types.Element.WOOD], Types.Element.WATER, "木克水")
	_eq(Types.COUNTERS[Types.Element.WATER], Types.Element.FIRE, "水克火")
	# 三角必须闭环：每种属性都恰好被一种属性克制
	for e: Types.Element in Types.ELEMENTAL:
		_neq(Types.counter_of(e), Types.Element.NONE, "%s 有克制者" % Types.name_of(e))
		_neq(Types.counter_of(e), e, "%s 不自我克制" % Types.name_of(e))

func _test_multiplier() -> void:
	var f: Types.Element = Types.Element.FIRE
	var w: Types.Element = Types.Element.WOOD
	var a: Types.Element = Types.Element.WATER
	_feq(Types.base_multiplier(f, w), Balance.MULT_COUNTER, "火打木＝克制")
	_feq(Types.base_multiplier(w, f), Balance.MULT_COUNTERED, "木打火＝被克")
	_feq(Types.base_multiplier(f, f), Balance.MULT_SAME, "同属性")
	_feq(Types.base_multiplier(Types.Element.NONE, f), Balance.MULT_NEUTRAL_ATK, "无属性打有属性")
	# 核心假设：打对属性至少要比打错强 5 倍，否则玩家不会在意克制
	var ratio: float = Balance.MULT_COUNTER / Balance.MULT_COUNTERED
	_true(ratio >= 5.0, "克制/被克 倍率差 >= 5x（实际 %.1fx）" % ratio)
	# 效果等级：表现层靠它决定飘字颜色、弹道粗细和音效，判错了反馈就是骗人的
	_eq(Types.effectiveness(f, w), Types.Effect.STRONG, "火打木＝STRONG")
	_eq(Types.effectiveness(w, f), Types.Effect.WEAK, "木打火＝WEAK")
	_eq(Types.effectiveness(f, f), Types.Effect.NORMAL, "同属性＝NORMAL")
	_eq(Types.effectiveness(Types.Element.NONE, f), Types.Effect.WEAK, "无属性打有属性＝WEAK")
	_eq(Types.effectiveness(f, Types.Element.NONE), Types.Effect.NORMAL, "打无属性怪＝NORMAL")
	# 等级必须和倍率一致，否则画面演的和实际打的对不上
	for atk: Types.Element in [Types.Element.NONE] + Types.ELEMENTAL:
		for de: Types.Element in Types.ELEMENTAL:
			var mult: float = Types.base_multiplier(atk, de)
			var eff: Types.Effect = Types.effectiveness(atk, de)
			if eff == Types.Effect.STRONG:
				_true(mult > 1.0, "STRONG 的倍率必须 >1（%s打%s）" % [
					Types.name_of(atk), Types.name_of(de)])
			elif eff == Types.Effect.WEAK:
				_true(mult < 0.5, "WEAK 的倍率必须 <0.5（%s打%s）" % [
					Types.name_of(atk), Types.name_of(de)])

func _test_modifier_caps() -> void:
	var m: Modifiers = Modifiers.new()
	m.counter_bonus = 99.0
	m.countered_relief = 99.0
	m.neutral_boost = 99.0
	m.slow_pct = 99.0
	m.interest_pct = 99.0
	_feq(m.multiplier(Types.Element.FIRE, Types.Element.WOOD),
		Balance.MULT_COUNTER + Modifiers.CAP_COUNTER_BONUS, "克制加成封顶")
	_feq(m.multiplier(Types.Element.WOOD, Types.Element.FIRE),
		Modifiers.CAP_COUNTERED, "被克减免封顶")
	_feq(m.multiplier(Types.Element.NONE, Types.Element.FIRE),
		Modifiers.CAP_NEUTRAL, "无属性加成封顶")
	_feq(m.effective_slow(), Modifiers.CAP_SLOW, "减速封顶")
	_feq(m.effective_interest(), Modifiers.CAP_INTEREST, "利息封顶")

# ---- 经济 ------------------------------------------------------------------

func _test_tower_economy() -> void:
	var rs: RunState = RunState.new(1)
	var first: int = rs.next_tower_cost()
	_eq(first, Balance.TOWER_COST, "第一座塔是基础价")
	rs.gold = 99999
	rs.build_tower()
	_true(rs.next_tower_cost() > first, "第二座塔更贵")
	# 塔位上限
	while rs.can_build():
		rs.build_tower()
	_eq(rs.towers.size(), Balance.MAX_TOWERS, "塔位上限 %d" % Balance.MAX_TOWERS)
	_eq(rs.free_slot(), -1, "满了就没有空位")
	# 每波第一次拆除免费（全额返还）
	_eq(rs.free_sells, Balance.FREE_SELLS_PER_WAVE, "开局就有免费拆除次数")
	var t: Tower = rs.towers[0]
	var before: int = rs.gold
	_eq(rs.sell_value(t.slot), t.invested, "免费拆除全额返还")
	rs.sell_tower(t.slot)
	_eq(rs.gold - before, t.invested, "免费拆除确实拿回全额")
	_eq(rs.free_sells, 0, "免费次数用掉了")
	# 用完之后打折
	var t2: Tower = rs.towers[0]
	before = rs.gold
	var expect: int = t2.refund_value()
	_eq(rs.sell_value(t2.slot), expect, "免费次数用完后按 %d%% 返还" % roundi(Balance.REFUND_RATE * 100.0))
	rs.sell_tower(t2.slot)
	_eq(rs.gold - before, expect, "打折返还金额正确")
	_true(expect < t2.invested, "打折返还必定小于投入")

func _test_upgrade_rules() -> void:
	var rs: RunState = RunState.new(2)
	rs.gold = 99999
	var t: Tower = rs.build_tower()
	_true(rs.upgrade_tower(t.slot, Types.Element.FIRE), "无属性可升级")
	_eq(t.element, Types.Element.FIRE, "升级后是火塔")
	# 这是玩法的硬规则：升过就不能改属性，只能拆掉重建
	_false(rs.upgrade_tower(t.slot, Types.Element.WATER), "火塔不能改成水塔")
	_eq(t.element, Types.Element.FIRE, "改属性失败后仍是火塔")
	# 免费升级券
	var t2: Tower = rs.build_tower()
	rs.gold = 0
	_false(rs.upgrade_tower(t2.slot, Types.Element.WATER), "没钱升不了")
	rs.mods.free_upgrades = 1
	_true(rs.upgrade_tower(t2.slot, Types.Element.WATER), "有券就能免费升")
	_eq(rs.mods.free_upgrades, 0, "券用掉了")
	_eq(rs.gold, 0, "用券不花钱")

## 免费拆除次数每波重置，否则整局只能免费拆一次
func _test_free_sell_resets() -> void:
	var rs: RunState = RunState.new(9)
	rs.gold = 99999
	var t: Tower = rs.build_tower()
	rs.sell_tower(t.slot)
	_eq(rs.free_sells, 0, "用掉后归零")
	rs.play_wave()
	_eq(rs.free_sells, Balance.FREE_SELLS_PER_WAVE, "过一波后恢复")
	_eq(rs.wave_index, 2, "波次有推进")

## 战斗中即时拨款：能当场花掉，而且波末结算不能再算一次
func _test_live_gold() -> void:
	var rs: RunState = RunState.new(11)
	rs.gold = 99999
	for i: int in 4:
		var t: Tower = rs.build_tower()
		rs.upgrade_tower(t.slot, Types.counter_of(rs.waves[0].specs[0]["element"]))
	rs.gold = 0
	rs.begin_wave()
	# 推到有怪被打死为止
	var guard: int = 0
	while rs.battle.gold_earned == 0 and guard < 20000:
		rs.battle.step(Balance.SIM_STEP)
		guard += 1
	_true(rs.battle.gold_earned > 0, "战斗中有赚到赏金")
	_eq(rs.gold, 0, "没 sync 之前金库还是空的")
	rs.sync_gold()
	_eq(rs.gold, rs.battle.gold_earned, "sync 之后赏金进了金库")
	# 重复 sync 不该再加
	var after: int = rs.gold
	rs.sync_gold()
	_eq(rs.gold, after, "重复 sync 不会重复加钱")

	# 当场花掉一部分，再打完整波，结算不能把已拨的钱再算一次
	var earned_before: int = rs.battle.gold_earned
	rs.gold += 100000
	var built: Tower = rs.build_tower()
	_true(built != null, "战斗中可以建塔")
	_true(rs.towers.has(built), "新塔进了塔列表")
	_true(rs.battle.towers.has(built), "新塔当场加入战斗，不用等下一波")
	var gold_mid: int = rs.gold
	rs.battle.run_to_end()
	var total_earned: int = rs.battle.gold_earned
	var r: Dictionary = rs.end_wave()
	_true(total_earned >= earned_before, "赏金只增不减")
	_eq(rs.gold, gold_mid + (total_earned - earned_before) + Balance.WAVE_CLEAR_GOLD,
		"波末只补上还没拨的部分，不重复计算")
	_true(int(r["gold_earned"]) == total_earned, "统计里仍是本波赏金总额")

## 暴击是阶梯式的：每领一次，机率和倍率必须同时变强
func _test_crit_ladder() -> void:
	var m: Modifiers = Modifiers.new()
	_feq(m.effective_crit(), 0.0, "没领过就不会暴击")
	_feq(m.crit_multiplier(), 1.0, "没领过倍率是 1")
	var prev_c: float = 0.0
	var prev_m: float = 1.0
	for lv: int in range(1, 7):
		m.crit_level = lv
		_true(m.effective_crit() >= prev_c, "第%d级机率不低于前一级" % lv)
		_true(m.crit_multiplier() > prev_m, "第%d级倍率严格变高" % lv)
		prev_c = m.effective_crit()
		prev_m = m.crit_multiplier()
	m.crit_level = 99
	_true(m.effective_crit() <= Modifiers.CAP_CRIT_CHANCE, "暴击机率有封顶")

## 属性塔可以继续练级，每级多一个全额目标
func _test_tower_levels() -> void:
	var rs: RunState = RunState.new(21)
	rs.gold = 999999
	var t: Tower = rs.build_tower()
	_eq(t.level, 0, "无属性塔等级 0")
	_eq(t.targets(), 1, "无属性塔打 1 个目标")
	_false(t.can_level_up(), "无属性塔不能练级")
	rs.upgrade_tower(t.slot, Types.Element.FIRE)
	_eq(t.level, 1, "升成属性塔后 Lv1")
	var prev_cost: int = 0
	while t.can_level_up():
		var c: int = rs.level_up_cost(t.slot)
		_true(c > prev_cost, "练级费用递增（Lv%d 要 %d）" % [t.level + 1, c])
		prev_cost = c
		var lv: int = t.level
		_true(rs.level_up_tower(t.slot), "有钱就能练级")
		_eq(t.level, lv + 1, "等级 +1")
		_eq(t.targets(), t.level, "目标数等于等级")
	_eq(t.level, Balance.MAX_TOWER_LEVEL, "练到上限 Lv%d" % Balance.MAX_TOWER_LEVEL)
	_false(rs.level_up_tower(t.slot), "到顶就不能再练")

## 技能：三座同属性塔解锁，有冷却，伤害吃克制
func _test_skills() -> void:
	var rs: RunState = RunState.new(22)
	rs.gold = 999999
	_false(rs.skill_unlocked(Types.Element.FIRE), "开局没技能")
	for i: int in Balance.SKILL_REQUIRED_TOWERS:
		var t: Tower = rs.build_tower()
		rs.upgrade_tower(t.slot, Types.Element.FIRE)
	_true(rs.skill_unlocked(Types.Element.FIRE), "凑满 %d 座火塔就解锁" % Balance.SKILL_REQUIRED_TOWERS)
	_false(rs.skill_unlocked(Types.Element.WATER), "别的属性没解锁")
	_eq(rs.element_levels(Types.Element.FIRE), Balance.SKILL_REQUIRED_TOWERS, "等级总和")
	_true(rs.skill_damage(Types.Element.FIRE) > 0.0, "技能有伤害")
	# 练级之后技能变强
	var before: float = rs.skill_damage(Types.Element.FIRE)
	rs.level_up_tower(rs.towers[0].slot)
	_true(rs.skill_damage(Types.Element.FIRE) > before, "塔练级后技能威力提升")

	_false(rs.skill_ready(Types.Element.FIRE), "没在战斗中就放不了")
	rs.begin_wave()
	_true(rs.skill_ready(Types.Element.FIRE), "开波时技能是就绪的")
	var hp_before: float = 0.0
	# 先推进到场上有怪
	while rs.battle.active.is_empty():
		rs.step_battle(Balance.SIM_STEP)
	for e: Enemy in rs.battle.active:
		hp_before += e.hp
	_true(rs.use_skill(Types.Element.FIRE), "放得出技能")
	var hp_after: float = 0.0
	for e: Enemy in rs.battle.active:
		hp_after += e.hp
	_true(hp_after < hp_before, "技能是全屏伤害，场上所有怪都掉血")
	_false(rs.skill_ready(Types.Element.FIRE), "放完进冷却")
	_true(rs.skill_remaining(Types.Element.FIRE) > 0.0, "冷却大于 0")
	_false(rs.use_skill(Types.Element.FIRE), "冷却中放不了")
	# 冷却会随战斗推进而减少
	var cd0: float = rs.skill_remaining(Types.Element.FIRE)
	rs.step_battle(0.5)
	_true(rs.skill_remaining(Types.Element.FIRE) < cd0, "冷却随时间减少")

## 奖励池：稀有度权重、封顶显示、不能有负面效果的专精
func _test_reward_pool() -> void:
	var pool: Array[Reward] = Reward.pool()
	_true(pool.size() >= 12, "奖励池够大（%d 个）" % pool.size())
	var by_rarity: Dictionary = {}
	for r: Reward in pool:
		by_rarity[r.rarity] = int(by_rarity.get(r.rarity, 0)) + 1
		_false(r.id.begins_with("spec_"), "专精已移除（%s）" % r.id)
	for rr: int in [Reward.Rarity.C, Reward.Rarity.B, Reward.Rarity.A, Reward.Rarity.S]:
		_true(int(by_rarity.get(rr, 0)) > 0, "每个稀有度都有奖励")
	# 越稀有越难抽到
	_true(Reward.WEIGHTS[Reward.Rarity.S] < Reward.WEIGHTS[Reward.Rarity.A], "S 比 A 稀有")
	_true(Reward.WEIGHTS[Reward.Rarity.A] < Reward.WEIGHTS[Reward.Rarity.B], "A 比 B 稀有")
	_true(Reward.WEIGHTS[Reward.Rarity.B] < Reward.WEIGHTS[Reward.Rarity.C], "B 比 C 稀有")
	# 有封顶的奖励一定要能显示当前值，否则玩家不知道还差多少
	var rs: RunState = RunState.new(23)
	for id: String in ["counter", "relief", "neutral", "slow", "interest", "refine", "crit"]:
		var r: Reward = Reward.by_id(id)
		_true(r != null, "奖励 %s 存在" % id)
		_true(r.status(rs).length() > 0, "奖励 %s 有状态说明" % id)

# ---- 波次与战斗 ------------------------------------------------------------

func _test_wave_determinism() -> void:
	var a: RunState = RunState.new(4242)
	var b: RunState = RunState.new(4242)
	for i: int in Balance.TOTAL_WAVES:
		_eq(a.waves[i].preview(), b.waves[i].preview(), "同种子第%d波构成一致" % (i + 1))
	var c: RunState = RunState.new(4243)
	var same: bool = true
	for i: int in Balance.TOTAL_WAVES:
		if a.waves[i].preview() != c.waves[i].preview():
			same = false
	_false(same, "不同种子构成应该有差异")
	# 波次构成规则
	_eq(a.waves[0].composition().size(), 1, "第1波单一属性")
	_eq(a.waves[Balance.WAVE_THREE_ELEMENTS - 1].composition().size(), 3,
		"第%d波起三属性混合" % Balance.WAVE_THREE_ELEMENTS)

func _test_battle_leaks() -> void:
	var rs: RunState = RunState.new(7)
	var w: Wave = rs.waves[0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var empty: Array[Tower] = []
	var b: Battle = Battle.new(w, empty, Modifiers.new(), rng)
	var r: Dictionary = b.run_to_end()
	_eq(int(r["killed"]), 0, "没有塔就杀不死怪")
	_eq(int(r["leaked"]), w.specs.size(), "没有塔就全漏")
	_eq(int(r["gold_earned"]), 0, "没杀死就没赏金")
	_true(b.is_finished(), "战斗一定会结束（不会死循环）")

func _test_elite_leak_cost() -> void:
	var normal: Enemy = Enemy.new(Types.Element.FIRE, 10.0, 1.0, 5, false)
	var elite: Enemy = Enemy.new(Types.Element.FIRE, 10.0, 1.0, 5, true)
	_eq(normal.leak_cost(), Balance.LEAK_COST_NORMAL, "杂兵漏掉扣 1 命")
	_eq(elite.leak_cost(), Balance.LEAK_COST_ELITE, "精英漏掉扣得更多")
	_true(elite.leak_cost() > normal.leak_cost(), "精英惩罚必定更重")
	# 击杀判定
	_false(normal.take_damage(5.0), "半血不死")
	_true(normal.take_damage(5.0), "打光血就死")
	_false(normal.take_damage(5.0), "死了不能再死（避免重复计赏金）")

# ---- 断言工具 --------------------------------------------------------------

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

func _neq(a: Variant, b: Variant, msg: String) -> void:
	_ok(a != b, "%s（两者都是 %s）" % [msg, str(a)])

func _feq(a: float, b: float, msg: String) -> void:
	_ok(absf(a - b) < 0.0001, "%s（%.4f != %.4f）" % [msg, a, b])
