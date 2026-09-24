class_name Modifiers
extends RefCounted

## 奖励叠加后的全局修正值。奖励可重复领取，所以这里全部是「累加」语义，
## 需要封顶的栏位在读取时 clamp，避免 27 次选择把倍率堆到爆。
##
## 每个有封顶的栏位都配一组 current/cap 读取函数，奖励卡片靠它显示
## 「目前 +0.50 / 封顶 +1.00」——没有这个玩家根本不知道自己还差多少。

## 属性塔的伤害 / 攻速加成（Types.Element -> +N%，加算）。
## 奖励只加在单一属性上，无属性塔一点也吃不到 ——
## 想拿数值就得先决定走哪条属性路线，「全塔通用 +N%」那种无脑加成没了。
var damage_by_element: Dictionary = {}
var rate_by_element: Dictionary = {}
var counter_bonus: float = 0.0     ## 克制倍率额外 +N
var countered_relief: float = 0.0  ## 被克制倍率额外 +N
var neutral_boost: float = 0.0     ## 无属性打有属性额外 +N
var crit_level: int = 0            ## 暴击等级，机率和倍率一起长
var true_damage: float = 0.0       ## 每次命中附加无视属性的固定伤害
var slow_pct: float = 0.0          ## 命中附带减速
var pierce_targets: int = 0        ## 穿透：在塔本身的目标数之外再多打几只（减伤）
var interest_pct: float = 0.0      ## 每波结束按存款给利息
var upgrade_discount: float = 0.0  ## 属性塔升级费用折扣
var skill_cd_cut: float = 0.0      ## 技能冷却缩减

# ---- 后加的一批 -----------------------------------------------------------
var execute_bonus: float = 0.0      ## 处决：对残血怪的额外伤害倍率
var regen_per_wave: int = 0         ## 回春：每波结束回几点生命
var charge_level: int = 0           ## 蓄力：每 N 发一次强化攻击
var lock_bonus: float = 0.0         ## 锁定：连续命中同一只怪，每次叠加
var killstreak_bonus: float = 0.0   ## 连杀：本波不漏怪时赏金逐只递增
var mono_bonus: float = 0.0         ## 独尊：场上只有一种属性的塔时的加成

const CAP_COUNTER_BONUS: float = 1.0
const CAP_COUNTERED: float = 0.7
const CAP_NEUTRAL: float = 0.9
const CAP_SLOW: float = 0.6
const CAP_INTEREST: float = 0.3
const CAP_UPGRADE_DISCOUNT: float = 0.6
const CAP_SKILL_CD: float = 0.5
const PIERCE_RATIO: float = 0.4
const SLOW_DURATION: float = 1.5

## 暴击阶梯：每领一次，机率和倍率同时涨，两边都不封顶。
## 固定 2 倍的暴击领到第三次就索然无味了，这样才会有「越堆越猛」的感觉。
## 机率只在 100% 处截断 —— 那不是平衡上的封顶，是「必暴」本来就是上限。
const CRIT_CHANCE_BASE: float = 0.20
const CRIT_CHANCE_STEP: float = 0.15
## 处决：血量低于这个比例才吃额外伤害
const EXECUTE_THRESHOLD: float = 0.25
## 蓄力：每几发攻击强化一次
const CHARGE_EVERY: int = 5
## 锁定 / 连杀的叠加上限，不封的话后期会失控。
## 连杀每层 3%、封 20 层 = 尾巴 ×1.6。原本每层 5%（封顶 ×2.0）时，
## 一个不漏怪的玩家拿两张就是 ×3.0，全局收入直接翻倍，赏金怎么调都没用。
const CAP_LOCK_STACKS: int = 10
const CAP_KILLSTREAK: int = 20

const CRIT_MULT_BASE: float = 2.0
const CRIT_MULT_STEP: float = 0.5

# ---- 克制倍率 --------------------------------------------------------------

## 塔属性打怪属性的最终倍率（含奖励修正）。
func multiplier(attacker: Types.Element, defender: Types.Element) -> float:
	var m: float = Types.base_multiplier(attacker, defender)
	if attacker == Types.Element.NONE:
		if defender != Types.Element.NONE:
			m = minf(m + neutral_boost, CAP_NEUTRAL)
	elif defender != Types.Element.NONE:
		if Types.COUNTERS[attacker] == defender:
			m += minf(counter_bonus, CAP_COUNTER_BONUS)
		elif Types.COUNTERS[defender] == attacker:
			m = minf(m + countered_relief, CAP_COUNTERED)
	return maxf(m, 0.0)

# ---- 每属性加成 ------------------------------------------------------------

func add_damage(e: Types.Element, v: float) -> void:
	damage_by_element[e] = damage_bonus(e) + v

func add_rate(e: Types.Element, v: float) -> void:
	rate_by_element[e] = rate_bonus(e) + v

func damage_bonus(e: Types.Element) -> float:
	return float(damage_by_element.get(e, 0.0))

func rate_bonus(e: Types.Element) -> float:
	return float(rate_by_element.get(e, 0.0))

# ---- 封顶后的实际值 --------------------------------------------------------

func effective_counter_bonus() -> float:
	return minf(counter_bonus, CAP_COUNTER_BONUS)

func effective_relief() -> float:
	return minf(countered_relief, CAP_COUNTERED - Balance.MULT_COUNTERED)

func effective_neutral() -> float:
	return minf(neutral_boost, CAP_NEUTRAL - Balance.MULT_NEUTRAL_ATK)

func effective_slow() -> float:
	return minf(slow_pct, CAP_SLOW)

func effective_interest() -> float:
	return minf(interest_pct, CAP_INTEREST)

func effective_upgrade_discount() -> float:
	return minf(upgrade_discount, CAP_UPGRADE_DISCOUNT)

func effective_skill_cd_cut() -> float:
	return minf(skill_cd_cut, CAP_SKILL_CD)

## 第 level 级暴击的机率（level 0 = 没领过）
func crit_chance_at(level: int) -> float:
	if level <= 0:
		return 0.0
	return minf(CRIT_CHANCE_BASE + CRIT_CHANCE_STEP * float(level - 1), 1.0)

func crit_mult_at(level: int) -> float:
	if level <= 0:
		return 1.0
	return CRIT_MULT_BASE + CRIT_MULT_STEP * float(level - 1)

## 蓄力那一发的伤害倍率（没领过就是 1）
func charge_multiplier() -> float:
	return 1.0 if charge_level <= 0 else 1.0 + 2.0 * float(charge_level)

## 连续命中同一只怪第 n 次的伤害加成
func lock_multiplier(streak: int) -> float:
	if lock_bonus <= 0.0:
		return 1.0
	return 1.0 + lock_bonus * float(mini(streak, CAP_LOCK_STACKS))

## 本波连杀第 n 只的赏金倍率
func killstreak_multiplier(streak: int) -> float:
	if killstreak_bonus <= 0.0:
		return 1.0
	return 1.0 + killstreak_bonus * float(mini(streak, CAP_KILLSTREAK))

func effective_crit() -> float:
	return crit_chance_at(crit_level)

func crit_multiplier() -> float:
	return crit_mult_at(crit_level)

# ---- 显示 ------------------------------------------------------------------

func describe() -> String:
	var lines: Array[String] = summary_lines()
	return ", ".join(lines) if not lines.is_empty() else "（无）"

## 逐条列出当前生效的加成，给加成面板一行一条地显示
func summary_lines() -> Array[String]:
	var parts: Array[String] = []
	for e: Types.Element in Types.ELEMENTAL:
		var d: float = damage_bonus(e)
		if d > 0.0: parts.append("%s塔伤害 +%d%%" % [Types.name_of(e), roundi(d * 100.0)])
	for e: Types.Element in Types.ELEMENTAL:
		var r: float = rate_bonus(e)
		if r > 0.0: parts.append("%s塔攻速 +%d%%" % [Types.name_of(e), roundi(r * 100.0)])
	if counter_bonus > 0.0: parts.append("克制倍率 +%.2f" % effective_counter_bonus())
	if countered_relief > 0.0: parts.append("被克减免 +%.2f" % effective_relief())
	if neutral_boost > 0.0: parts.append("无属性 +%.2f" % effective_neutral())
	if crit_level > 0:
		parts.append("暴击 %d%% ×%.1f" % [roundi(effective_crit() * 100.0), crit_multiplier()])
	if true_damage > 0.0: parts.append("真伤 +%d" % roundi(true_damage))
	if slow_pct > 0.0: parts.append("减速 %d%%" % roundi(effective_slow() * 100.0))
	if pierce_targets > 0: parts.append("穿透 ×%d" % pierce_targets)
	if interest_pct > 0.0: parts.append("利息 %d%%" % roundi(effective_interest() * 100.0))
	if upgrade_discount > 0.0:
		parts.append("升级折扣 -%d%%" % roundi(effective_upgrade_discount() * 100.0))
	if skill_cd_cut > 0.0:
		parts.append("技能冷却 -%d%%" % roundi(effective_skill_cd_cut() * 100.0))
	if execute_bonus > 0.0: parts.append("残血处决 +%d%%" % roundi(execute_bonus * 100.0))
	if regen_per_wave > 0: parts.append("每波回血 +%d" % regen_per_wave)
	if charge_level > 0: parts.append("蓄力 ×%.1f" % charge_multiplier())
	if lock_bonus > 0.0: parts.append("锁定 +%d%%/层" % roundi(lock_bonus * 100.0))
	if killstreak_bonus > 0.0: parts.append("连杀 +%d%%/只" % roundi(killstreak_bonus * 100.0))
	if mono_bonus > 0.0: parts.append("独尊 +%d%%" % roundi(mono_bonus * 100.0))
	return parts
