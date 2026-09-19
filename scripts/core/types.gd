class_name Types
extends RefCounted

## 属性与克制关系。火 → 木 → 水 → 火（猜拳）。

enum Element { NONE, FIRE, WOOD, WATER }

## 一次命中的效果等级。规则层只负责判定，怎么演（飘字、弹道、音效）是表现层的事。
enum Effect { WEAK, NORMAL, STRONG }

## 三种有属性的元素，供随机/遍历使用（不含 NONE）
const ELEMENTAL: Array[Element] = [Element.FIRE, Element.WOOD, Element.WATER]

const NAMES: Dictionary = {
	Element.NONE: "无",
	Element.FIRE: "火",
	Element.WOOD: "木",
	Element.WATER: "水",
}

## key 克 value
const COUNTERS: Dictionary = {
	Element.FIRE: Element.WOOD,
	Element.WOOD: Element.WATER,
	Element.WATER: Element.FIRE,
}

static func name_of(e: Element) -> String:
	return NAMES[e]

## 塔属性打怪属性的基础倍率（不含奖励修正）。
static func base_multiplier(attacker: Element, defender: Element) -> float:
	if attacker == Element.NONE:
		return 1.0 if defender == Element.NONE else Balance.MULT_NEUTRAL_ATK
	if defender == Element.NONE:
		return 1.0
	if COUNTERS[attacker] == defender:
		return Balance.MULT_COUNTER
	if COUNTERS[defender] == attacker:
		return Balance.MULT_COUNTERED
	return Balance.MULT_SAME

## 这一击算克制、普通、还是被克。
## 无属性塔打有属性怪也算 WEAK——它的倍率跟被克一样低，玩家该感受到同样的挫折。
static func effectiveness(attacker: Element, defender: Element) -> Effect:
	if defender == Element.NONE:
		return Effect.NORMAL
	if attacker == Element.NONE:
		return Effect.WEAK
	if COUNTERS[attacker] == defender:
		return Effect.STRONG
	if COUNTERS[defender] == attacker:
		return Effect.WEAK
	return Effect.NORMAL

## 返回克制 e 的属性（即「该用什么塔打它」）。
static func counter_of(e: Element) -> Element:
	for atk: Element in ELEMENTAL:
		if COUNTERS[atk] == e:
			return atk
	return Element.NONE
