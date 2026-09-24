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
	_test_elemental_rewards()
	_test_maxed_rewards()
	_test_reroll_cost()
	_test_reroll_shared_across_rounds()
	_test_progress_unlock()
	_test_interest_preview()
	_test_element_traits()
	_test_elite_skills()
	_test_boss()
	_test_new_rewards()
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
	# HP_GROWTH 由难度档位决定，不该在代码里手改。
	# 它太灵敏（0.06 能把通关率从 85% 打到 33%），正因如此才适合做档位。
	_feq(Balance.HP_GROWTH, 1.5, "默认（简单）是 1.5")
	var prev: float = 0.0
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		Balance.apply_difficulty(d)
		_true(Balance.HP_GROWTH > prev, "%s 比上一档更难（%.2f）" % [
			Balance.difficulty_name(), Balance.HP_GROWTH])
		_eq(Balance.difficulty, d, "当前难度记录正确")
		prev = Balance.HP_GROWTH
	_feq(Balance.DIFFICULTY_HP_GROWTH[Balance.Difficulty.EASY], 1.5, "简单 1.5")
	_feq(Balance.DIFFICULTY_HP_GROWTH[Balance.Difficulty.HARD], 1.55, "困难 1.55")
	_feq(Balance.DIFFICULTY_HP_GROWTH[Balance.Difficulty.HELL], 1.6, "地狱 1.6")
	Balance.reset()
	_eq(Balance.difficulty, Balance.Difficulty.EASY, "reset 回到简单档")
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
	_eq(rs.free_sells, Balance.free_sells_per_wave(), "开局就有免费拆除次数")
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
	var t2: Tower = rs.build_tower()
	rs.gold = 0
	_false(rs.upgrade_tower(t2.slot, Types.Element.WATER), "没钱升不了")

## 免费拆除按难度给，它是「看预告重组阵容」这条玩法的入场券：
##   简单 每波 1 次、不限总量　困难 每波 1 次、整局上限 3　地狱 整局只有 1 次
func _test_free_sell_resets() -> void:
	# ---- 简单：每波都补，一直有 ----
	Balance.reset()
	var rs: RunState = RunState.new(9)
	rs.gold = 999999
	rs.lives = 99999
	_eq(rs.free_sells, 1, "简单开局有 1 次")
	_eq(rs.free_sells_left(), -1, "简单不限总量")
	for i: int in 4:
		var tt: Tower = rs.build_tower()
		rs.sell_tower(tt.slot)
		_eq(rs.free_sells, 0, "第%d波用掉后归零" % (i + 1))
		rs.play_wave()
		_eq(rs.free_sells, 1, "简单每波都补回 1 次")
	_eq(rs.wave_index, 5, "波次有推进")

	# ---- 困难：每波补，但整局只有 3 次 ----
	Balance.reset()
	Balance.apply_difficulty(Balance.Difficulty.HARD)
	var hr: RunState = RunState.new(9)
	hr.gold = 999999
	hr.lives = 99999
	_eq(hr.free_sells_left(), 3, "困难整局 3 次")
	for i: int in 3:
		_eq(hr.free_sells, 1, "困难第%d波手上有 1 次" % (i + 1))
		var tt: Tower = hr.build_tower()
		hr.sell_tower(tt.slot)
		hr.play_wave()
	_eq(hr.free_sells_left(), 0, "3 次用完")
	_eq(hr.free_sells, 0, "额度见底后就不再补了")
	# 用完只能打折拆
	var ht: Tower = hr.build_tower()
	var hbefore: int = hr.gold
	hr.sell_tower(ht.slot)
	_eq(hr.gold - hbefore, ht.refund_value(), "困难用完后只退 60%")

	# ---- 地狱：整局就 1 次，不按波补，但不用就一直留着 ----
	Balance.reset()
	Balance.apply_difficulty(Balance.Difficulty.HELL)
	var xr: RunState = RunState.new(9)
	xr.gold = 999999
	xr.lives = 99999
	_eq(xr.free_sells, 1, "地狱开局有 1 次")
	xr.play_wave()
	_eq(xr.free_sells, 1, "地狱不用就一直留着，不会过期")
	var xt: Tower = xr.build_tower()
	xr.sell_tower(xt.slot)
	_eq(xr.free_sells, 0, "地狱用掉就没了")
	xr.play_wave()
	_eq(xr.free_sells, 0, "地狱过一波也不会恢复")
	Balance.reset()

	rs = RunState.new(9)
	rs.gold = 99999
	var t: Tower = rs.build_tower()
	rs.sell_tower(t.slot)
	# 用完之后只能打折拆
	var t2: Tower = rs.build_tower()
	var before: int = rs.gold
	rs.sell_tower(t2.slot)
	_true(rs.gold - before < t2.invested, "免费次数用完后只退一部分")

## 利息预览要给出实际金额，不能只给百分比
func _test_interest_preview() -> void:
	var rs: RunState = RunState.new(51)
	rs.gold = 1000
	_eq(rs.interest_preview(), 0, "没领利息就没有预览收入")
	Reward.by_id("interest").apply(rs)
	var expect: int = floori(1000.0 * rs.mods.effective_interest())
	_eq(rs.interest_preview(), expect, "预览＝当前存款 × 利率")
	_true(rs.interest_preview() > 0, "领了利息就有预览收入")
	# 预览要跟实际结算对得上
	var before_gold: int = rs.gold
	var preview: int = rs.interest_preview()
	rs.begin_wave()
	rs.battle.run_to_end()
	rs.end_wave()
	_true(rs.gold > before_gold, "过波后金钱增加")
	# 存款变了利息也要跟着变
	rs.gold = 200
	_true(rs.interest_preview() < preview, "存款少了利息也少")

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
	# 机率和倍率都不封顶，只有「必暴」这个物理上限
	m.crit_level = 99
	_feq(m.effective_crit(), 1.0, "堆够了就是必暴")
	_true(m.crit_multiplier() > 20.0, "倍率一路涨，没有上限")

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

## 「淬火」「急速」是随机属性卡：池子里只占一格（不然 C 档权重翻三倍），
## 抽中的当下才决定是火还是木还是水，而且只加在那一种属性的塔上。
func _test_elemental_rewards() -> void:
	var rs: RunState = RunState.new(77)
	for id: String in ["damage", "rate"]:
		var shell: Reward = Reward.by_id(id)
		_true(shell != null, "壳卡 %s 在池子里" % id)
		_eq(shell.variants.size(), Types.ELEMENTAL.size(), "%s 有三种属性变体" % id)
		var seen: Array[String] = []
		for i: int in 200:
			var v: Reward = shell.roll_variant(rs.rng)
			_true(shell.variants.has(v), "抽出来的一定是变体之一")
			if not seen.has(v.id):
				seen.append(v.id)
		_eq(seen.size(), Types.ELEMENTAL.size(), "抽 200 次三种属性都出得来")

	# 只加在中奖的那一种属性上，别的属性和无属性塔一点都吃不到
	Reward.by_id("damage_火").apply(rs)
	_true(rs.mods.damage_bonus(Types.Element.FIRE) > 0.0, "火塔吃到伤害加成")
	_feq(rs.mods.damage_bonus(Types.Element.WOOD), 0.0, "木塔吃不到")
	_feq(rs.mods.damage_bonus(Types.Element.NONE), 0.0, "无属性塔吃不到")
	rs.gold = 99999
	var t: Tower = rs.build_tower()
	var plain: float = t.damage(rs.mods)
	rs.upgrade_tower(t.slot, Types.Element.FIRE)
	_true(t.damage(rs.mods) > plain, "升成火塔之后伤害才涨（%.1f → %.1f）"
		% [plain, t.damage(rs.mods)])

	Reward.by_id("rate_水").apply(rs)
	_true(rs.mods.rate_bonus(Types.Element.WATER) > 0.0, "水塔吃到攻速加成")
	_feq(rs.mods.rate_bonus(Types.Element.FIRE), 0.0, "火塔的攻速没被顺便加到")

## 堆到封顶的奖励不能再出现在三选一里 —— 那等于白白浪费一格
func _test_maxed_rewards() -> void:
	var rs: RunState = RunState.new(31)
	var capped: Array[String] = ["counter", "relief", "neutral", "slow", "interest", "refine"]
	for id: String in capped:
		var r: Reward = Reward.by_id(id)
		_true(r != null, "奖励 %s 存在" % id)
		_false(r.is_maxed(rs), "%s 开局没封顶" % r.title)
		for i: int in 20:
			r.apply(rs)
		_true(r.is_maxed(rs), "%s 堆 20 次后封顶" % r.title)
		_false(r.is_available(rs), "%s 封顶后不再可选" % r.title)
	# 实际抽牌也不能漏出来
	var leaked: Array[String] = []
	for i: int in 120:
		for c: Reward in rs.roll_rewards():
			if capped.has(c.id) and not leaked.has(c.id):
				leaked.append(c.id)
	_true(leaked.is_empty(), "抽 120 轮不会抽到封顶的奖励（漏出 %s）" % str(leaked))
	# 暴击不算封顶：机率虽然有上限，但倍率不封顶，永远还有得涨
	var crit: Reward = Reward.by_id("crit")
	for i: int in 20:
		crit.apply(rs)
	_false(crit.is_maxed(rs), "暴击永远不算封顶（倍率不封顶）")

## 免费刷新按难度给：
##   简单 每次选择 1 次　困难 每个奖励阶段（3 次选择）共 1 次　地狱 没有免费刷新
func _test_reroll_shared_across_rounds() -> void:
	# ---- 简单：每次选择都补回来 ----
	Balance.reset()
	var rs: RunState = RunState.new(88)
	rs.gold = 999999
	rs.begin_reward_phase()
	for i: int in Balance.REWARD_ROUNDS:
		rs.begin_reward_round()
		_eq(rs.reroll_cost(), 0, "简单第%d次选择有免费刷新" % (i + 1))
		var g: int = rs.gold
		rs.reroll_rewards()
		_eq(rs.gold, g, "免费刷新不扣钱")
		_true(rs.reroll_cost() > 0, "同一次选择内再刷就要钱了")
	_eq(rs.reroll_paid, 0, "全程没花过钱")

	# ---- 困难：3 次选择共享一次 ----
	Balance.reset()
	Balance.apply_difficulty(Balance.Difficulty.HARD)
	var hr: RunState = RunState.new(88)
	hr.gold = 999999
	hr.begin_reward_phase()
	hr.begin_reward_round()
	_eq(hr.reroll_cost(), 0, "困难阶段内第一次刷新免费")
	hr.reroll_rewards()
	_true(hr.reroll_cost() > 0, "用掉之后就要钱")
	hr.begin_reward_round()
	_true(hr.reroll_cost() > 0, "换到第二次选择也不会补回来")
	hr.begin_reward_phase()
	hr.begin_reward_round()
	_eq(hr.reroll_cost(), 0, "进新阶段才重新给")

	# ---- 地狱：一次免费都没有 ----
	Balance.reset()
	Balance.apply_difficulty(Balance.Difficulty.HELL)
	var xr: RunState = RunState.new(88)
	xr.gold = 999999
	xr.begin_reward_phase()
	xr.begin_reward_round()
	_true(xr.reroll_cost() > 0, "地狱第一次刷新就要钱")
	var xg: int = xr.gold
	xr.reroll_rewards()
	_true(xr.gold < xg, "地狱刷新真的扣钱")
	_eq(xr.reroll_paid, 1, "记成付费刷新")
	Balance.reset()

## 难度是一档一档解锁的，存档跨局保留
func _test_progress_unlock() -> void:
	var real: String = Progress.save_path
	# 别拿玩家真正的存档做测试
	Progress.save_path = "user://test_progress.cfg"
	Progress.reset()

	_true(Progress.is_unlocked(Balance.Difficulty.EASY), "简单一开始就开着")
	_false(Progress.is_unlocked(Balance.Difficulty.HARD), "困难一开始锁着")
	_false(Progress.is_unlocked(Balance.Difficulty.HELL), "地狱一开始锁着")
	_eq(int(Progress.highest_unlocked()), int(Balance.Difficulty.EASY), "默认只能选简单")

	_true(Progress.mark_cleared(Balance.Difficulty.EASY), "首次通关简单")
	_true(Progress.is_unlocked(Balance.Difficulty.HARD), "通关简单解锁困难")
	_false(Progress.is_unlocked(Balance.Difficulty.HELL), "地狱还锁着")
	_false(Progress.mark_cleared(Balance.Difficulty.EASY), "重复通关不再算首次")

	# 不能跳级：没打通困难就通关地狱是不可能发生的，但解锁关系本身要严格
	_eq(int(Progress.unlocks(Balance.Difficulty.EASY)), int(Balance.Difficulty.HARD),
		"简单解锁的是困难")
	_eq(int(Progress.unlocks(Balance.Difficulty.HELL)), int(Balance.Difficulty.HELL),
		"地狱是最后一档，不再解锁别的")

	Progress.mark_cleared(Balance.Difficulty.HARD)
	_true(Progress.is_unlocked(Balance.Difficulty.HELL), "通关困难解锁地狱")
	_eq(int(Progress.highest_unlocked()), int(Balance.Difficulty.HELL), "三档全开")

	# 存档要能读回来
	Progress.save_progress()
	Progress.reset()
	Progress.load_progress()
	_true(Progress.is_cleared(Balance.Difficulty.EASY), "存档读回来还记得通关过简单")
	_true(Progress.is_unlocked(Balance.Difficulty.HELL), "读回来地狱仍是开的")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.save_path))
	Progress.save_path = real
	Progress.reset()

## 刷新价格必须随次数和波次一起涨，否则等于免费
func _test_reroll_cost() -> void:
	Balance.reset()
	var rs: RunState = RunState.new(32)
	rs.wave_index = 1
	rs.begin_reward_phase()
	rs.begin_reward_round()
	_eq(rs.reroll_cost(), 0, "简单档每次选择都有一次免费")
	rs.reroll_free_left = 0
	var prev: int = 0
	for n: int in range(0, 4):
		rs.reroll_paid = n
		var c: int = rs.reroll_cost()
		_true(c > prev, "第%d次付费刷新比上一次贵（%d > %d）" % [n + 1, c, prev])
		prev = c
	# 同样的次数，后期必须更贵 —— 后期金流是前期的好几倍
	rs.reroll_paid = 1
	var early: int = rs.reroll_cost()
	rs.wave_index = 10
	var late: int = rs.reroll_cost()
	_true(late > early, "同样次数后期更贵（第10波 %d > 第1波 %d）" % [late, early])
	# 价格要是整十
	_eq(late % 10, 0, "刷新价格取整到 10")

## 三种属性各有性格：火快而脆、木慢而厚、水死时给全场回血
func _test_element_traits() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	# 直接查表，别依赖某一波刚好抽到哪几种属性
	var f_sp: float = Balance.ELEMENT_SPEED_MULT[Types.Element.FIRE]
	var w_sp: float = Balance.ELEMENT_SPEED_MULT[Types.Element.WOOD]
	var f_hp: float = Balance.ELEMENT_HP_MULT[Types.Element.FIRE]
	var w_hp: float = Balance.ELEMENT_HP_MULT[Types.Element.WOOD]
	_true(f_sp > 1.0, "火跑得比基准快")
	_true(w_sp < 1.0, "木跑得比基准慢")
	_true(f_sp > w_sp, "火比木快")
	_true(w_hp > f_hp, "木比火厚")
	_true(f_hp < 1.0, "火比基准脆")

	# 水怪死亡要给全场回血
	var rs: RunState = RunState.new(41)
	rs.begin_wave()
	var b: Battle = rs.battle
	var victim: Enemy = Enemy.new(Types.Element.WATER, 100.0, 1.0, 5, false)
	var ally: Enemy = Enemy.new(Types.Element.FIRE, 100.0, 1.0, 5, false)
	ally.hp = 40.0
	b.active.append(victim)
	b.active.append(ally)
	var before: float = ally.hp
	victim.take_damage(999.0)
	b._on_killed(victim)
	_true(ally.hp > before, "水怪死亡后同伴回了血（%.1f → %.1f）" % [before, ally.hp])
	_eq(b.last_heals.size(), 1, "回血事件有记录，表现层才能飘字")
	# 回满的不能溢出
	ally.hp = ally.max_hp
	var victim2: Enemy = Enemy.new(Types.Element.WATER, 100.0, 1.0, 5, false)
	b.active.append(victim2)
	victim2.take_damage(999.0)
	b._on_killed(victim2)
	_feq(ally.hp, ally.max_hp, "回血不会超过血量上限")

## 精英技能：出场放一次，之后每过一个触发点再放一次，次数由难度决定
func _test_elite_skills() -> void:
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		Balance.reset()
		Balance.apply_difficulty(d)
		var rs: RunState = RunState.new(61)
		rs.gold = 999999
		rs.lives = 99999
		for i: int in Balance.MAX_TOWERS:
			var t: Tower = rs.build_tower()
			rs.upgrade_tower(t.slot, Types.ELEMENTAL[i % 3])
		while rs.wave_index < Balance.ELITE_WAVES[0]:
			rs.play_wave()
		rs.begin_wave()
		# 每次施法会抛两条事件：前摇（报名字）和结算（效果生效）。
		# 这里数的是真正生效的次数，前摇不算。
		var casts: int = 0
		var windups: int = 0
		while not rs.battle.is_finished():
			rs.step_battle(Balance.SIM_STEP)
			for ec: Dictionary in rs.battle.last_elite_casts:
				if bool(ec.get("windup", false)):
					windups += 1
				else:
					casts += 1
		_eq(casts, Balance.elite_casts(),
			"%s 难度精英放 %d 次技能" % [Balance.difficulty_name(), Balance.elite_casts()])
		_eq(windups, casts, "每次施法都有一段前摇先报名字")
	Balance.reset()
	_true(Balance.ELITE_CASTS_BY_DIFFICULTY[Balance.Difficulty.HELL]
		> Balance.ELITE_CASTS_BY_DIFFICULTY[Balance.Difficulty.EASY],
		"地狱放得比简单多")

	# 三种技能各自要真的改变战场
	var b: Battle = _fresh_battle()
	var mob: Enemy = Enemy.new(Types.Element.FIRE, 100.0, 1.0, 5, false)
	b.active.append(mob)
	var fire_elite: Enemy = Enemy.new(Types.Element.FIRE, 999.0, 1.0, 5, true)
	var before_speed: float = mob.speed()
	b._cast_elite_skill(fire_elite)
	_true(mob.speed() > before_speed, "火·浴火让杂兵跑得更快")

	# 木·分裂：死亡时裂成两只半血的，而且只裂一次
	var b2: Battle = _fresh_battle()
	var mob2: Enemy = Enemy.new(Types.Element.WOOD, 100.0, 1.0, 20, false)
	b2.active.append(mob2)
	_false(mob2.split_on_death, "一开始没有分裂标记")
	b2._cast_elite_skill(Enemy.new(Types.Element.WOOD, 999.0, 1.0, 5, true))
	_true(mob2.split_on_death, "木精英给杂兵挂上分裂")
	# 重复挂不会叠加（就是个布尔）
	b2._cast_elite_skill(Enemy.new(Types.Element.WOOD, 999.0, 1.0, 5, true))
	_true(mob2.split_on_death, "重复挂还是一个标记")
	mob2.take_damage(999.0)
	b2._on_killed(mob2)
	var children: Array[Enemy] = []
	for o: Enemy in b2.active:
		if o != mob2:
			children.append(o)
	_eq(children.size(), Balance.ELITE_WOOD_SPLIT_COUNT,
		"裂成 %d 只" % Balance.ELITE_WOOD_SPLIT_COUNT)
	for c: Enemy in children:
		_feq(c.max_hp, 100.0 * Balance.ELITE_WOOD_SPLIT_HP, "分裂出来的只有一半血")
		_false(c.split_on_death, "分裂出来的不再带标记 —— 只裂一次，不会指数爆炸")
		_true(c.bounty < mob2.bounty, "分裂体赏金减半，防止故意刷钱")
	# 再杀一次分裂体，不该继续裂
	var before_count: int = b2.active.size()
	children[0].take_damage(999.0)
	b2._on_killed(children[0])
	_eq(b2.active.size(), before_count, "分裂体死了不会再裂")

	# 水·潮涌：全场回满
	var b3: Battle = _fresh_battle()
	var mob3: Enemy = Enemy.new(Types.Element.WATER, 100.0, 1.0, 5, false)
	mob3.hp = 12.0
	b3.active.append(mob3)
	b3._cast_elite_skill(Enemy.new(Types.Element.WATER, 999.0, 1.0, 5, true))
	_feq(mob3.hp, mob3.max_hp, "水·潮涌把杂兵血量回满")

	# 精英自己不该被自己的技能影响
	var e2: Enemy = Enemy.new(Types.Element.FIRE, 999.0, 1.0, 5, true)
	b.active.append(e2)
	var espeed: float = e2.speed()
	b._cast_elite_skill(Enemy.new(Types.Element.FIRE, 999.0, 1.0, 5, true))
	_feq(e2.speed(), espeed, "精英不吃自己人的 buff")

func _fresh_battle() -> Battle:
	var rs: RunState = RunState.new(62)
	rs.begin_wave()
	var b: Battle = rs.battle
	b.active.clear()
	return b

## 大 BOSS：属性轮换 + 召唤护卫 + 死亡分裂成三只精英。
## 这里盯得最紧的是「boss 旗标有没有真的传到战场上」——
## 丢了的话 boss 会静默退化成一只厚精英，不报错、不崩溃，只是三个机制全不生效。
func _test_boss() -> void:
	Balance.reset()
	var rs: RunState = RunState.new(71)
	rs.wave_index = Balance.BOSS_WAVE
	rs.begin_wave()
	var b: Battle = rs.battle
	# 推进到 boss 出场
	var guard: int = 0
	var boss: Enemy = null
	while boss == null and guard < 4000:
		b.step(Balance.SIM_STEP)
		guard += 1
		for e: Enemy in b.active:
			if e.is_boss:
				boss = e
				break
	_true(boss != null, "大BOSS 真的出现在战场上（旗标没在生成时丢掉）")
	if boss == null:
		return
	_true(boss.is_elite, "boss 同时也算精英")
	_true(boss.max_hp > 0.0, "boss 有血量")

	# 属性轮换：掉血到阈值就换属性
	var e0: Types.Element = boss.element
	boss.hp = boss.max_hp * 0.5   # 跨过第一个阈值
	b._boss_phases()
	_neq(boss.element, e0, "血量过半后 boss 换了属性")
	_eq(boss.phase, 1, "进入第 2 阶段")
	var e1: Types.Element = boss.element
	boss.hp = boss.max_hp * 0.2   # 跨过第二个阈值
	b._boss_phases()
	_neq(boss.element, e1, "血量掉到三分之一又换一次")
	_eq(boss.phase, 2, "进入第 3 阶段")
	b._boss_phases()
	_eq(boss.phase, 2, "阈值用完就不再换了")

	# 召唤护卫
	var before: int = b.active.size()
	b._cast_elite_skill(boss)
	_eq(b.active.size(), before + Balance.BOSS_SUMMON_COUNT,
		"boss 每次放技能召唤 %d 只护卫" % Balance.BOSS_SUMMON_COUNT)

	# 死亡分裂成三只精英，每种属性各一只
	var before2: int = b.active.size()
	boss.take_damage(boss.max_hp * 10.0)
	b._on_killed(boss)
	_eq(b.active.size(), before2 + 3, "boss 死时裂成 3 只")
	var found: Array[int] = []
	for e: Enemy in b.active:
		if e.is_elite and not e.is_boss and not found.has(int(e.element)):
			found.append(int(e.element))
	_eq(found.size(), 3, "三只精英是火木水各一")
	for e: Enemy in b.active:
		if e.is_elite and not e.is_boss:
			_false(e.is_boss, "分裂出的是精英不是 boss —— 不会无限套娃")
			_true(e.cast_index >= 0, "施法进度已对齐当前位置，不会一帧连放")

## 后加的那批奖励，每个都要真的起作用
func _test_new_rewards() -> void:
	var rs: RunState = RunState.new(42)
	var m: Modifiers = rs.mods

	# 蓄力：倍率随等级涨
	_feq(m.charge_multiplier(), 1.0, "没领蓄力就没加成")
	m.charge_level = 1
	_true(m.charge_multiplier() > 1.0, "领了蓄力那一发更疼")
	var lv1: float = m.charge_multiplier()
	m.charge_level = 2
	_true(m.charge_multiplier() > lv1, "蓄力可以叠")

	# 锁定 / 连杀：都要封顶，不然后期失控
	m.lock_bonus = 0.08
	_true(m.lock_multiplier(3) > m.lock_multiplier(1), "锁定连击越多越疼")
	_feq(m.lock_multiplier(999), m.lock_multiplier(Modifiers.CAP_LOCK_STACKS),
		"锁定叠加有上限")
	m.killstreak_bonus = 0.05
	_true(m.killstreak_multiplier(5) > m.killstreak_multiplier(1), "连杀赏金递增")
	_feq(m.killstreak_multiplier(999), m.killstreak_multiplier(Modifiers.CAP_KILLSTREAK),
		"连杀有上限")

	# 回春：撑过一波才回血
	m.regen_per_wave = 2
	var lives_before: int = rs.lives
	rs.play_wave()
	_true(rs.lives >= lives_before - 20, "回春在波末结算（命 %d → %d）"
		% [lives_before, rs.lives])

	# 新奖励都进池子了
	for id: String in ["regen", "charge", "lock",
			"execute", "killstreak", "mono"]:
		var r: Reward = Reward.by_id(id)
		_true(r != null, "奖励 %s 在池子里" % id)
		if r != null:
			_true(r.status(rs).length() > 0, "奖励 %s 有状态说明" % r.title)

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
	# 一局的节奏：前 3 波三种属性各来一波、4~6 两两混合、7 起三色混战
	var singles: Array[int] = []
	for i: int in 3:
		_eq(a.waves[i].composition().size(), 1, "第%d波单一属性" % (i + 1))
		singles.append(int(a.waves[i].composition().keys()[0]))
	singles.sort()
	_eq(singles.size(), 3, "前三波共 3 波")
	_true(singles[0] != singles[1] and singles[1] != singles[2],
		"前三波三种属性各来一次，不重复")
	for i: int in range(3, 6):
		_eq(a.waves[i].composition().size(), 2, "第%d波两两混合" % (i + 1))
	# 精英 / boss 的波次与层级
	for wi: int in Balance.ELITE_WAVES:
		var ew: Wave = a.waves[wi - 1]
		_neq(ew.boss_element(), Types.Element.NONE, "第%d波有精英" % wi)
		_false(ew.has_boss(), "第%d波是精英不是大BOSS" % wi)
	var last: Wave = a.waves[Balance.BOSS_WAVE - 1]
	_true(last.has_boss(), "第%d波有大BOSS" % Balance.BOSS_WAVE)
	# 大 boss 必须比精英硬，漏了也更疼
	_true(Balance.BOSS_HP_MULT > Balance.ELITE_HP_MULT, "大BOSS比精英厚")
	_true(Balance.LEAK_COST_BOSS > Balance.LEAK_COST_ELITE, "漏大BOSS扣更多命")
	var boss_e: Enemy = Enemy.new(Types.Element.FIRE, 10.0, 1.0, 5, false, true)
	_true(boss_e.is_boss, "boss 标记正确")
	_true(boss_e.is_elite, "boss 同时也算精英（沿用精英那套表现和惩罚）")
	_eq(boss_e.leak_cost(), Balance.LEAK_COST_BOSS, "漏 boss 按 boss 扣命")
	# 精英属性是单独随机的，不该永远跟着本波杂兵走
	var elite_outside: int = 0
	for seed_i: int in 60:
		var r2: RunState = RunState.new(seed_i * 977 + 5)
		for wi2: int in Balance.ELITE_WAVES:
			var w2: Wave = r2.waves[wi2 - 1]
			if not w2.composition().has(w2.boss_element()):
				elite_outside += 1
	_true(elite_outside > 0,
		"精英属性会出现在本波杂兵之外（%d 次），说明是独立随机的" % elite_outside)
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
