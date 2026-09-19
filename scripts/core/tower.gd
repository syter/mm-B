class_name Tower
extends RefCounted

## 塔。没有射程——全部盖在底部，打得到全场任何怪。
## 只有两种状态：无属性，或已升级成三属性之一。升级后不可再改属性，只能拆掉重建。

var slot: int = -1
var element: Types.Element = Types.Element.NONE
## 0 = 还是无属性塔；升级成属性塔后为 1，之后每升一级多打一个目标
var level: int = 0
## 已投入的金额，拆塔按 REFUND_RATE 返还
var invested: int = 0
var cooldown: float = 0.0

## 本局统计，给模拟器看的
var damage_dealt: float = 0.0
var kills: int = 0

func _init(slot_index: int, cost: int = Balance.TOWER_COST) -> void:
	slot = slot_index
	invested = cost

func is_upgraded() -> bool:
	return element != Types.Element.NONE

func upgrade(to: Types.Element, cost: int) -> void:
	element = to
	level = 1
	invested += cost

## 继续练级：每级多一个全额伤害的攻击目标
func level_up(cost: int) -> void:
	level += 1
	invested += cost

func can_level_up() -> bool:
	return is_upgraded() and level < Balance.MAX_TOWER_LEVEL

## 同时能打几个目标（全额伤害）。穿透奖励是在这之外再加的减伤目标。
func targets() -> int:
	return maxi(level, 1)

func refund_value() -> int:
	return Balance.round_cost(float(invested) * Balance.REFUND_RATE)

func damage(mods: Modifiers) -> float:
	return Balance.TOWER_BASE_DAMAGE * (1.0 + mods.damage_pct)

func rate(mods: Modifiers) -> float:
	return Balance.TOWER_BASE_RATE * (1.0 + mods.rate_pct)

func reset_for_wave() -> void:
	cooldown = 0.0

func label() -> String:
	if not is_upgraded():
		return "#%d 无属性塔" % slot
	return "#%d %s塔 Lv%d" % [slot, Types.name_of(element), level]
