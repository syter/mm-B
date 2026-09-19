class_name Modifiers
extends RefCounted

## 奖励叠加后的全局修正值。奖励可重复领取，所以这里全部是「累加」语义，
## 需要封顶的栏位在读取时 clamp，避免 27 次选择把倍率堆到爆。
##
## 每个有封顶的栏位都配一组 current/cap 读取函数，奖励卡片靠它显示
## 「目前 +0.50 / 封顶 +1.00」——没有这个玩家根本不知道自己还差多少。

var damage_pct: float = 0.0        ## 全体塔伤害 +N%（加算）
var rate_pct: float = 0.0          ## 全体塔攻速 +N%（加算）
var counter_bonus: float = 0.0     ## 克制倍率额外 +N
var countered_relief: float = 0.0  ## 被克制倍率额外 +N
var neutral_boost: float = 0.0     ## 无属性打有属性额外 +N
var crit_level: int = 0            ## 暴击等级，机率和倍率一起长
var true_damage: float = 0.0       ## 每次命中附加无视属性的固定伤害
var slow_pct: float = 0.0          ## 命中附带减速
var pierce_targets: int = 0        ## 穿透：在塔本身的目标数之外再多打几只（减伤）
var interest_pct: float = 0.0      ## 每波结束按存款给利息
var free_upgrades: int = 0         ## 免费升级券张数
var upgrade_discount: float = 0.0  ## 属性塔升级费用折扣
var skill_power: float = 0.0       ## 技能伤害 +N%
var skill_cd_cut: float = 0.0      ## 技能冷却缩减

const CAP_COUNTER_BONUS: float = 1.0
const CAP_COUNTERED: float = 0.7
const CAP_NEUTRAL: float = 0.9
const CAP_SLOW: float = 0.6
const CAP_INTEREST: float = 0.3
const CAP_UPGRADE_DISCOUNT: float = 0.6
const CAP_SKILL_CD: float = 0.5
const PIERCE_RATIO: float = 0.4
const SLOW_DURATION: float = 1.5

## 暴击阶梯：每领一次，机率和倍率同时涨。
## 固定 2 倍的暴击领到第三次就索然无味了，这样才会有「越堆越猛」的感觉。
const CRIT_CHANCE_BASE: float = 0.15
const CRIT_CHANCE_STEP: float = 0.10
const CAP_CRIT_CHANCE: float = 0.65
const CRIT_MULT_BASE: float = 2.0
const CRIT_MULT_STEP: float = 0.3

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
	return minf(CRIT_CHANCE_BASE + CRIT_CHANCE_STEP * float(level - 1), CAP_CRIT_CHANCE)

func crit_mult_at(level: int) -> float:
	if level <= 0:
		return 1.0
	return CRIT_MULT_BASE + CRIT_MULT_STEP * float(level - 1)

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
	if damage_pct > 0.0: parts.append("伤害 +%d%%" % roundi(damage_pct * 100.0))
	if rate_pct > 0.0: parts.append("攻速 +%d%%" % roundi(rate_pct * 100.0))
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
	if skill_power > 0.0: parts.append("技能伤害 +%d%%" % roundi(skill_power * 100.0))
	if skill_cd_cut > 0.0:
		parts.append("技能冷却 -%d%%" % roundi(effective_skill_cd_cut() * 100.0))
	if free_upgrades > 0: parts.append("免费升级券 ×%d" % free_upgrades)
	return parts
