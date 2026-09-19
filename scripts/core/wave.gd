class_name Wave
extends RefCounted

## 一波怪的定义。只存「规格」不存怪物实例，
## 这样同一波可以用 build_enemies() 反复重建，模拟器能跑多次而不互相污染。

var index: int = 0
var specs: Array[Dictionary] = []   ## {time, element, hp, speed, bounty, elite}

func _init(index_: int) -> void:
	index = index_

## 第 index 波（1 起算）。属性构成由 rng 决定，种子固定即可复现。
static func generate(index_: int, rng: RandomNumberGenerator) -> Wave:
	var w: Wave = Wave.new(index_)
	var kinds: int = 1
	if index_ >= Balance.WAVE_THREE_ELEMENTS:
		kinds = 3
	elif index_ >= Balance.WAVE_TWO_ELEMENTS:
		kinds = 2

	var pool: Array[Types.Element] = Types.ELEMENTAL.duplicate()
	_shuffle(pool, rng)
	var used: Array[Types.Element] = pool.slice(0, kinds)

	var count: int = Balance.COUNT_BASE + roundi(float(index_) * Balance.COUNT_PER_WAVE)
	var hp: float = Balance.HP_BASE * pow(Balance.HP_GROWTH, float(index_ - 1))
	var speed: float = Balance.ENEMY_BASE_SPEED * (1.0 + Balance.SPEED_GROWTH * float(index_ - 1))
	var bounty: int = Balance.BOUNTY_BASE + Balance.BOUNTY_PER_WAVE * index_

	for i: int in count:
		w.specs.append({
			"time": float(i) * Balance.SPAWN_INTERVAL,
			"element": used[i % used.size()],
			"hp": hp,
			"speed": speed,
			"bounty": bounty,
			"elite": false,
		})

	if index_ in Balance.ELITE_WAVES:
		w.specs.append({
			"time": float(count) * Balance.SPAWN_INTERVAL,
			"element": used[rng.randi() % used.size()],
			"hp": hp * Balance.ELITE_HP_MULT,
			"speed": speed * Balance.ELITE_SPEED_MULT,
			"bounty": roundi(float(bounty) * Balance.ELITE_BOUNTY_MULT),
			"elite": true,
		})
	return w

func build_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for s: Dictionary in specs:
		out.append(Enemy.new(s["element"], s["hp"], s["speed"], s["bounty"], s["elite"]))
	return out

## 给「下一波预告」用：属性 -> 数量
func composition() -> Dictionary:
	var out: Dictionary = {}
	for s: Dictionary in specs:
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
	if index in Balance.ELITE_WAVES:
		parts.append("含精英")
	return " / ".join(parts)

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
