class_name Wave
extends RefCounted

## 一波怪的定义。只存「规格」不存怪物实例，
## 这样同一波可以用 build_enemies() 反复重建，模拟器能跑多次而不互相污染。

var index: int = 0
var specs: Array[Dictionary] = []   ## {time, element, hp, speed, bounty, elite}

func _init(index_: int) -> void:
	index = index_

## 一局的属性编排。开局一次算好，保证玩家一定会经历完整的教学曲线：
##   1~3 波   三种属性各来一波（顺序随机）—— 逼玩家把三种塔都造一遍
##   4~6 波   三种两两组合各来一波（顺序随机）—— 三种配对都吃一次
##   7~10 波  三色混战
## 顺序随机但覆盖完整，所以每局都不一样，又不会漏掉任何一种情况。
static func plan_elements(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var singles: Array[Types.Element] = Types.ELEMENTAL.duplicate()
	_shuffle(singles, rng)
	for e: Types.Element in singles:
		out.append([e] as Array[Types.Element])

	var pairs: Array = []
	for i: int in Types.ELEMENTAL.size():
		var a: Types.Element = Types.ELEMENTAL[i]
		var b: Types.Element = Types.ELEMENTAL[(i + 1) % Types.ELEMENTAL.size()]
		pairs.append([a, b] as Array[Types.Element])
	_shuffle(pairs, rng)
	for p: Array in pairs:
		var pp: Array[Types.Element] = p.duplicate()
		_shuffle(pp, rng)
		out.append(pp)

	while out.size() < Balance.TOTAL_WAVES:
		var all: Array[Types.Element] = Types.ELEMENTAL.duplicate()
		_shuffle(all, rng)
		out.append(all)
	return out

## 第 index 波（1 起算）。used 由 plan_elements 排好，种子固定即可复现。
static func generate(index_: int, rng: RandomNumberGenerator,
		used_in: Array = []) -> Wave:
	var w: Wave = Wave.new(index_)
	var used: Array[Types.Element] = []
	if used_in.is_empty():
		var kinds: int = 1
		if index_ >= Balance.WAVE_THREE_ELEMENTS:
			kinds = 3
		elif index_ >= Balance.WAVE_TWO_ELEMENTS:
			kinds = 2
		var pool: Array[Types.Element] = Types.ELEMENTAL.duplicate()
		_shuffle(pool, rng)
		used = pool.slice(0, kinds)
	else:
		used.assign(used_in)

	var count: int = Balance.COUNT_BASE + roundi(float(index_) * Balance.COUNT_PER_WAVE)
	var hp: float = Balance.HP_BASE * pow(Balance.HP_GROWTH, float(index_ - 1))
	var speed: float = Balance.ENEMY_BASE_SPEED * (1.0 + Balance.SPEED_GROWTH * float(index_ - 1))
	var bounty: int = Balance.BOUNTY_BASE + Balance.BOUNTY_PER_WAVE * index_

	for i: int in count:
		var el: Types.Element = used[i % used.size()]
		w.specs.append({
			"time": float(i) * Balance.SPAWN_INTERVAL,
			"element": el,
			# 属性自带的血量/速度修正。查表而不是写死，以后 boss 在这上面再叠。
			"hp": hp * float(Balance.ELEMENT_HP_MULT.get(el, 1.0)),
			"speed": speed * float(Balance.ELEMENT_SPEED_MULT.get(el, 1.0)),
			"bounty": bounty,
			"elite": false,
		})

	# 精英／boss 的属性是三种里随机抽的，不跟着本波的杂兵走 ——
	# 这样才会出现「杂兵是火木，精英却是水」这种要临时补塔的情况。
	# 预告里会写出来，所以玩家来得及准备。
	var boss: bool = index_ == Balance.BOSS_WAVE
	if boss or index_ in Balance.ELITE_WAVES:
		var bel: Types.Element = Types.ELEMENTAL[rng.randi() % Types.ELEMENTAL.size()]
		var hp_mult: float = Balance.BOSS_HP_MULT if boss else Balance.ELITE_HP_MULT
		var sp_mult: float = Balance.BOSS_SPEED_MULT if boss else Balance.ELITE_SPEED_MULT
		var bo_mult: float = Balance.BOSS_BOUNTY_MULT if boss else Balance.ELITE_BOUNTY_MULT
		w.specs.append({
			"time": float(count) * Balance.SPAWN_INTERVAL,
			"element": bel,
			"hp": hp * hp_mult * float(Balance.ELEMENT_HP_MULT.get(bel, 1.0)),
			"speed": speed * sp_mult * float(Balance.ELEMENT_SPEED_MULT.get(bel, 1.0)),
			"bounty": roundi(float(bounty) * bo_mult),
			"elite": true,
			"boss": boss,
		})
	return w

## 本波的精英／boss 是什么属性（没有就返回 NONE）
func boss_element() -> Types.Element:
	for sp: Dictionary in specs:
		if bool(sp.get("elite", false)):
			return sp["element"]
	return Types.Element.NONE

func has_boss() -> bool:
	for sp: Dictionary in specs:
		if bool(sp.get("boss", false)):
			return true
	return false

func build_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for s: Dictionary in specs:
		out.append(Enemy.new(s["element"], s["hp"], s["speed"], s["bounty"],
			bool(s.get("elite", false)), bool(s.get("boss", false))))
	return out

## 给「下一波预告」用：属性 -> 数量
func composition() -> Dictionary:
	var out: Dictionary = {}
	for s: Dictionary in specs:
		if bool(s.get("elite", false)):
			continue  # 精英单独在预告里写，别混进杂兵计数
		var e: Types.Element = s["element"]
		out[e] = int(out.get(e, 0)) + 1
	return out

func total_hp() -> float:
	var sum: float = 0.0
	for s: Dictionary in specs:
		sum += float(s["hp"])
	return sum

func preview() -> String:
	var parts: Array[String] = []
	for e: Types.Element in Types.ELEMENTAL:
		var c: int = int(composition().get(e, 0))
		if c > 0:
			parts.append("%s x%d" % [Types.name_of(e), c])
	var bel: Types.Element = boss_element()
	if bel != Types.Element.NONE:
		parts.append(("大BOSS %s" if has_boss() else "精英 %s") % Types.name_of(bel))
	return " / ".join(parts)

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
