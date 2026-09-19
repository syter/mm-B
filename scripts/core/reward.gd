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

func weight() -> float:
	return WEIGHTS[rarity]

func rarity_name() -> String:
	return RARITY_NAMES[rarity]

func apply(rs) -> void:
	_apply.call(rs)

## 卡片上的第三行：目前叠到多少、封顶多少、选了会变成什么。
## 没有这行的话，有封顶的奖励玩家根本不知道自己还差多少，堆到封顶了还在选。
func status(rs) -> String:
	if _status.is_null():
		return ""
	return String(_status.call(rs))

## 某些奖励有前置条件
func is_available(rs) -> bool:
	match id:
		"ticket":
			for t: Tower in rs.towers:
				if not t.is_upgraded():
					return true
			return false
		"burst", "surge":
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

static func _build() -> void:
	_pool = [
		# ---- C：基础数值，稳定但不惊艳，用来垫底 ----
		Reward.new("damage", Rarity.C, "淬火", "全体塔伤害 +12%",
			func(rs) -> void: rs.mods.damage_pct += 0.12,
			func(rs) -> String: return "目前 +%d%%" % roundi(rs.mods.damage_pct * 100.0)),
		Reward.new("rate", Rarity.C, "急速", "全体塔攻速 +10%",
			func(rs) -> void: rs.mods.rate_pct += 0.10,
			func(rs) -> String: return "目前 +%d%%" % roundi(rs.mods.rate_pct * 100.0)),
		Reward.new("life", Rarity.C, "修补", "生命 +3",
			func(rs) -> void: rs.lives += 3,
			func(rs) -> String: return "目前 %d 命" % rs.lives),
		Reward.new("gold", Rarity.C, "赏金", "立刻获得金钱（随波次成长）",
			func(rs) -> void: rs.gold += 60 + 20 * rs.wave_index,
			func(rs) -> String: return "这次给 %d 金" % (60 + 20 * rs.wave_index)),

		# ---- B：有针对性，能撑起特定打法 ----
		Reward.new("true", Rarity.B, "贯穿之刃", "每次命中附加 6 点无视属性伤害",
			func(rs) -> void: rs.mods.true_damage += 6.0,
			func(rs) -> String: return "目前 +%d" % roundi(rs.mods.true_damage)),
		Reward.new("relief", Rarity.B, "韧性", "被克制时的伤害惩罚减轻 +0.10",
			func(rs) -> void: rs.mods.countered_relief += 0.10,
			func(rs) -> String: return _cap(
				Balance.MULT_COUNTERED + rs.mods.effective_relief(),
				Modifiers.CAP_COUNTERED, "%.2f")),
		Reward.new("neutral", Rarity.B, "本源", "无属性塔打有属性怪 +0.12",
			func(rs) -> void: rs.mods.neutral_boost += 0.12,
			func(rs) -> String: return _cap(
				Balance.MULT_NEUTRAL_ATK + rs.mods.effective_neutral(),
				Modifiers.CAP_NEUTRAL, "%.2f")),
		Reward.new("interest", Rarity.B, "利息", "每波结束按存款给 8%",
			func(rs) -> void: rs.mods.interest_pct += 0.08,
			func(rs) -> String: return "目前 %d%% / 封顶 %d%%" % [
				roundi(rs.mods.effective_interest() * 100.0),
				roundi(Modifiers.CAP_INTEREST * 100.0)]),
		Reward.new("refine", Rarity.B, "精炼", "属性塔升级与练级费用 -20%",
			func(rs) -> void: rs.mods.upgrade_discount += 0.20,
			func(rs) -> String: return "目前 -%d%% / 封顶 -%d%%" % [
				roundi(rs.mods.effective_upgrade_discount() * 100.0),
				roundi(Modifiers.CAP_UPGRADE_DISCOUNT * 100.0)]),

		# ---- A：改变打法的强力牌 ----
		Reward.new("counter", Rarity.A, "锐利", "克制倍率 +0.25",
			func(rs) -> void: rs.mods.counter_bonus += 0.25,
			func(rs) -> String: return _cap(
				Balance.MULT_COUNTER + rs.mods.effective_counter_bonus(),
				Balance.MULT_COUNTER + Modifiers.CAP_COUNTER_BONUS, "×%.2f")),
		Reward.new("slow", Rarity.A, "凝滞", "命中附带 20% 减速，持续 1.5 秒",
			func(rs) -> void: rs.mods.slow_pct += 0.20,
			func(rs) -> String: return "目前 %d%% / 封顶 %d%%" % [
				roundi(rs.mods.effective_slow() * 100.0),
				roundi(Modifiers.CAP_SLOW * 100.0)]),
		Reward.new("pierce", Rarity.A, "穿透", "攻击额外打到后方 1 只，造成 40% 伤害",
			func(rs) -> void: rs.mods.pierce_targets += 1,
			func(rs) -> String: return "目前额外 %d 只" % rs.mods.pierce_targets),
		Reward.new("ticket", Rarity.A, "免费升级券", "免费把一座无属性塔升级成任意属性",
			func(rs) -> void: rs.mods.free_upgrades += 1,
			func(rs) -> String: return "手上 %d 张" % rs.mods.free_upgrades),
		Reward.new("surge", Rarity.A, "蓄能", "技能冷却 -15%",
			func(rs) -> void: rs.mods.skill_cd_cut += 0.15,
			func(rs) -> String: return "目前冷却 %.1f 秒 / 最低 %.1f 秒" % [
				rs.skill_cooldown(),
				Balance.SKILL_COOLDOWN * (1.0 - Modifiers.CAP_SKILL_CD)]),

		# ---- S：稀有，拿到就该兴奋 ----
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
		Reward.new("burst", Rarity.S, "爆发", "技能伤害 +25%",
			func(rs) -> void: rs.mods.skill_power += 0.25,
			func(rs) -> String: return "目前 +%d%%" % roundi(rs.mods.skill_power * 100.0)),
	]

static func by_id(id_: String) -> Reward:
	for r: Reward in pool():
		if r.id == id_:
			return r
	return null
