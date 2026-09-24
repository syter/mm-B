@warning_ignore_start("untyped_declaration")
class_name Reward
extends RefCounted

## 波间 3 选 1 的奖励池。所有奖励都可重复领取，效果累加（封顶逻辑在 Modifiers）。
## apply / status 的参数是 RunState，这里刻意不写型别标注，避免与 run_state.gd 形成循环依赖。

## 稀有度。同时决定卡片颜色和抽中的权重——
## S 如果和 C 一样常见，那个 S 就不值钱了。
enum Rarity { C, B, A, S }

const WEIGHTS: Dictionary = {
	Rarity.C: 100.0,
	Rarity.B: 55.0,
	Rarity.A: 28.0,
	Rarity.S: 9.0,
}

const RARITY_NAMES: Dictionary = {
	Rarity.C: "C", Rarity.B: "B", Rarity.A: "A", Rarity.S: "S",
}

var id: String = ""
var title: String = ""
var desc: String = ""
var rarity: Rarity = Rarity.C
## 非空 = 这是张「随机属性」卡：本体只是个壳，抽中时随机换成其中一张属性变体。
## 之所以不把火/木/水三张直接塞进池子，是那样会让这一档的权重凭空翻三倍，
## C 档一膨胀，后面 A/S 的相对出现率就全被压掉了。
var variants: Array[Reward] = []
## 属性变体用：它属于哪张壳卡（"damage" / "rate"）、发的是哪种属性。
## 评分和统计要认「这是淬火」，不能只认 "damage_火" 这个具体 id。
var family: String = ""
var element: Types.Element = Types.Element.NONE
var _apply: Callable
var _status: Callable

func _init(id_: String, rarity_: Rarity, title_: String, desc_: String,
		apply_: Callable, status_: Callable = Callable()) -> void:
	id = id_
	rarity = rarity_
	title = title_
	desc = desc_
	_apply = apply_
	_status = status_
	family = id_

func weight() -> float:
	return WEIGHTS[rarity]

func rarity_name() -> String:
	return RARITY_NAMES[rarity]

## 抽中这张卡时真正发出去的那一张。没有变体就是它自己。
func roll_variant(rng: RandomNumberGenerator) -> Reward:
	if variants.is_empty():
		return self
	return variants[rng.randi_range(0, variants.size() - 1)]

func apply(rs) -> void:
	_apply.call(rs)

## 卡片上的第三行：目前叠到多少、封顶多少、选了会变成什么。
## 没有这行的话，有封顶的奖励玩家根本不知道自己还差多少，堆到封顶了还在选。
func status(rs) -> String:
	if _status.is_null():
		return ""
	return String(_status.call(rs))

## 已经堆到封顶的奖励不该再出现在三选一里 —— 那等于白白浪费一格。
## 暴击不在此列：机率和倍率都不封顶，永远还有得涨。
func is_maxed(rs) -> bool:
	var m: Modifiers = rs.mods
	match id:
		"counter": return m.counter_bonus >= Modifiers.CAP_COUNTER_BONUS
		"relief":
			return Balance.MULT_COUNTERED + m.countered_relief >= Modifiers.CAP_COUNTERED
		"neutral":
			return Balance.MULT_NEUTRAL_ATK + m.neutral_boost >= Modifiers.CAP_NEUTRAL
		"slow": return m.slow_pct >= Modifiers.CAP_SLOW
		"interest": return m.interest_pct >= Modifiers.CAP_INTEREST
		"refine": return m.upgrade_discount >= Modifiers.CAP_UPGRADE_DISCOUNT
		"surge": return m.skill_cd_cut >= Modifiers.CAP_SKILL_CD
	return false

## 某些奖励有前置条件
func is_available(rs) -> bool:
	if is_maxed(rs):
		return false
	match id:
		"surge":
			# 技能还没解锁就别发技能类奖励了，那等于一张废牌
			for e: Types.Element in Types.ELEMENTAL:
				if rs.skill_unlocked(e):
					return true
			return false
	return true

static var _pool: Array[Reward] = []

static func pool() -> Array[Reward]:
	if _pool.is_empty():
		_build()
	return _pool

static func _cap(cur: float, cap: float, fmt: String) -> String:
	if cur >= cap - 0.0001:
		return "已封顶（" + fmt % cap + "）"
	return "目前 " + fmt % cur + " / 封顶 " + fmt % cap

## 「淬火」「急速」的属性变体。伤害 +15% / 攻速 +12%，只作用在这一种属性的塔上。
static func _tower_damage(e: Types.Element) -> Reward:
	var n: String = Types.name_of(e)
	return Reward.new("damage_" + n, Rarity.C, "淬火 · " + n, "%s属性塔伤害 +15%%" % n,
		func(rs) -> void: rs.mods.add_damage(e, 0.15 * Balance.REWARD_POWER),
		func(rs) -> String: return "%s塔目前 +%d%%" % [n, roundi(rs.mods.damage_bonus(e) * 100.0)])

static func _tower_rate(e: Types.Element) -> Reward:
	var n: String = Types.name_of(e)
	return Reward.new("rate_" + n, Rarity.C, "急速 · " + n, "%s属性塔攻速 +12%%" % n,
		func(rs) -> void: rs.mods.add_rate(e, 0.12 * Balance.REWARD_POWER),
		func(rs) -> String: return "%s塔目前 +%d%%" % [n, roundi(rs.mods.rate_bonus(e) * 100.0)])

static func _build() -> void:
	# 壳卡本身永远不会被发出去，desc 只是给「这张卡是什么」留个说明
	var damage_card: Reward = Reward.new("damage", Rarity.C, "淬火",
		"随机一种属性塔伤害 +15%", func(_rs) -> void: pass)
	var rate_card: Reward = Reward.new("rate", Rarity.C, "急速",
		"随机一种属性塔攻速 +12%", func(_rs) -> void: pass)
	for e: Types.Element in Types.ELEMENTAL:
		damage_card.variants.append(_tower_damage(e))
		rate_card.variants.append(_tower_rate(e))
	for shell: Reward in [damage_card, rate_card]:
		for i: int in shell.variants.size():
			shell.variants[i].family = shell.id
			shell.variants[i].element = Types.ELEMENTAL[i]

	_pool = [
		# ---- C：基础数值，稳定但不惊艳，用来垫底 ----
		damage_card,
		rate_card,
		Reward.new("life", Rarity.C, "修补", "生命 +3",
			func(rs) -> void: rs.lives += 3,
			func(rs) -> String: return "目前 %d 命" % rs.lives),
		Reward.new("gold", Rarity.C, "赏金", "立刻获得金钱（随波次成长）",
			func(rs) -> void: rs.gold += roundi(float(60 + 20 * rs.wave_index) * Balance.REWARD_POWER),
			func(rs) -> String: return "这次给 %d 金" % (60 + 20 * rs.wave_index)),

		# ---- B：有针对性，能撑起特定打法 ----
		Reward.new("relief", Rarity.B, "韧性", "被克制时的伤害惩罚减轻 +0.10",
			func(rs) -> void: rs.mods.countered_relief += 0.10 * Balance.REWARD_POWER,
			func(rs) -> String: return _cap(
				Balance.MULT_COUNTERED + rs.mods.effective_relief(),
				Modifiers.CAP_COUNTERED, "%.2f")),
		Reward.new("neutral", Rarity.B, "本源", "无属性塔打有属性怪 +0.12",
			func(rs) -> void: rs.mods.neutral_boost += 0.12 * Balance.REWARD_POWER,
			func(rs) -> String: return _cap(
				Balance.MULT_NEUTRAL_ATK + rs.mods.effective_neutral(),
				Modifiers.CAP_NEUTRAL, "%.2f")),
		Reward.new("interest", Rarity.B, "利息", "每波结束时按当时的存款给 8%（钱留着不花才生息）",
			func(rs) -> void: rs.mods.interest_pct += 0.08 * Balance.REWARD_POWER,
			func(rs) -> String:
				# 光给百分比没用，玩家想知道的是「这一波结束到底进账多少」
				var now: float = rs.mods.effective_interest()
				var nxt: float = minf(now + 0.08, Modifiers.CAP_INTEREST)
				return "目前 %d%%（按存款 %d 金算 +%d）　→　选后 %d%%（+%d）" % [
					roundi(now * 100.0), rs.gold, floori(float(rs.gold) * now),
					roundi(nxt * 100.0), floori(float(rs.gold) * nxt)]),
		Reward.new("refine", Rarity.B, "精炼", "属性塔升级与练级费用 -20%",
			func(rs) -> void: rs.mods.upgrade_discount += 0.20 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 -%d%% / 封顶 -%d%%" % [
				roundi(rs.mods.effective_upgrade_discount() * 100.0),
				roundi(Modifiers.CAP_UPGRADE_DISCOUNT * 100.0)]),

		# ---- A：改变打法的强力牌 ----
		Reward.new("counter", Rarity.A, "锐利", "克制倍率 +0.25",
			func(rs) -> void: rs.mods.counter_bonus += 0.25 * Balance.REWARD_POWER,
			func(rs) -> String: return _cap(
				Balance.MULT_COUNTER + rs.mods.effective_counter_bonus(),
				Balance.MULT_COUNTER + Modifiers.CAP_COUNTER_BONUS, "×%.2f")),
		Reward.new("slow", Rarity.A, "凝滞", "命中附带 20% 减速，持续 1.5 秒",
			func(rs) -> void: rs.mods.slow_pct += 0.20 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 %d%% / 封顶 %d%%" % [
				roundi(rs.mods.effective_slow() * 100.0),
				roundi(Modifiers.CAP_SLOW * 100.0)]),
		Reward.new("pierce", Rarity.A, "穿透", "攻击额外打到后方 1 只，造成 40% 伤害",
			func(rs) -> void: rs.mods.pierce_targets += 1,
			func(rs) -> String: return "目前额外 %d 只" % rs.mods.pierce_targets),
		Reward.new("surge", Rarity.A, "蓄能", "技能冷却 -15%",
			func(rs) -> void: rs.mods.skill_cd_cut += 0.15 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前冷却 %.1f 秒 / 最低 %.1f 秒" % [
				rs.skill_cooldown(),
				Balance.SKILL_COOLDOWN * (1.0 - Modifiers.CAP_SKILL_CD)]),

		# ---- 后加的一批 ----
		Reward.new("regen", Rarity.C, "回春", "每波结束回复 1 点生命",
			func(rs) -> void: rs.mods.regen_per_wave += 1,
			func(rs) -> String: return "目前每波回 %d 点" % rs.mods.regen_per_wave),
		Reward.new("charge", Rarity.B, "蓄力", "每座塔的第 5 发攻击伤害翻倍再翻倍",
			func(rs) -> void: rs.mods.charge_level += 1,
			func(rs) -> String: return "目前那一发 ×%.1f　→　选后 ×%.1f" % [
				rs.mods.charge_multiplier(),
				1.0 + 2.0 * float(rs.mods.charge_level + 1)]),
		Reward.new("lock", Rarity.B, "锁定", "连续命中同一只怪，每次伤害 +8%",
			func(rs) -> void: rs.mods.lock_bonus += 0.08 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 +%d%%/层，最多叠 %d 层" % [
				roundi(rs.mods.lock_bonus * 100.0), Modifiers.CAP_LOCK_STACKS]),
		Reward.new("execute", Rarity.A, "处决", "对血量低于 25% 的怪，伤害 +80%",
			func(rs) -> void: rs.mods.execute_bonus += 0.8 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 +%d%%" % roundi(rs.mods.execute_bonus * 100.0)),
		Reward.new("killstreak", Rarity.A, "连杀", "本波不漏怪时，赏金逐只递增 3%",
			func(rs) -> void: rs.mods.killstreak_bonus += 0.03 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 +%d%%/只，最多 %d 只（漏怪清零）" % [
				roundi(rs.mods.killstreak_bonus * 100.0), Modifiers.CAP_KILLSTREAK]),
		Reward.new("mono", Rarity.S, "独尊", "场上只有一种属性的塔时，该属性伤害 +60%",
			func(rs) -> void: rs.mods.mono_bonus += 0.6 * Balance.REWARD_POWER,
			func(rs) -> String:
				var only: String = _mono_name(rs)
				return "目前 +%d%%　·　%s" % [roundi(rs.mods.mono_bonus * 100.0),
					("当前生效（%s）" % only) if only != "" else "当前没生效：场上不止一种属性"]),

		# ---- S：稀有，拿到就该兴奋 ----
		Reward.new("true", Rarity.S, "贯穿之刃", "每次命中附加 10 点无视属性伤害",
			func(rs) -> void: rs.mods.true_damage += 10.0 * Balance.REWARD_POWER,
			func(rs) -> String: return "目前 +%d" % roundi(rs.mods.true_damage)),
		Reward.new("crit", Rarity.S, "破绽", "暴击机率与暴击倍率同时提升",
			func(rs) -> void: rs.mods.crit_level += 1,
			func(rs) -> String:
				var m: Modifiers = rs.mods
				var nxt: int = m.crit_level + 1
				if m.crit_level == 0:
					return "选后 %d%% 机率 ×%.1f 伤害" % [
						roundi(m.crit_chance_at(1) * 100.0), m.crit_mult_at(1)]
				return "目前 %d%% ×%.1f　→　选后 %d%% ×%.1f" % [
					roundi(m.crit_chance_at(m.crit_level) * 100.0), m.crit_mult_at(m.crit_level),
					roundi(m.crit_chance_at(nxt) * 100.0), m.crit_mult_at(nxt)]),
	]

## 场上是不是只有一种属性的塔，给「独尊」的状态行用
static func _mono_name(rs) -> String:
	var found: int = -1
	for t: Tower in rs.towers:
		if not t.is_upgraded():
			continue
		if found < 0:
			found = int(t.element)
		elif found != int(t.element):
			return ""
	return "" if found < 0 else Types.name_of(found)

static func by_id(id_: String) -> Reward:
	for r: Reward in pool():
		if r.id == id_:
			return r
		for v: Reward in r.variants:
			if v.id == id_:
				return v
	return null
