extends SceneTree

## 平衡实验：第一波在不同开局配置下的表现。
## 用途是验证「必须靠克制才打得过」这条核心假设是否成立。
## 跑法：godot --headless --path . --script res://tests/sim/sim_wave1.gd

const SEED: int = 12345

func _initialize() -> void:
	var rs: RunState = RunState.new(SEED)
	var w: Wave = rs.waves[0]
	print("=== 第 1 波 ===")
	print("构成: %s  |  总血量 %.0f  |  单只 %.0f x%d" % [
		w.preview(), w.total_hp(), float(w.specs[0]["hp"]), w.specs.size()])
	var enemy_el: Types.Element = w.specs[0]["element"]
	var good: Types.Element = Types.counter_of(enemy_el)
	var bad: Types.Element = Types.COUNTERS[enemy_el]
	print("该用 %s 塔打（克制），最忌用 %s 塔（被克）\n" % [
		Types.name_of(good), Types.name_of(bad)])

	print("开局 %d 金：塔 %d / 升级 %d\n" % [
		Balance.START_GOLD, Balance.TOWER_COST, Balance.UPGRADE_COST])

	_try("3 座无属性塔（180金）", w, [Types.Element.NONE, Types.Element.NONE, Types.Element.NONE])
	_try("2 无属性 + 1 克制（175金）", w, [Types.Element.NONE, Types.Element.NONE, good])
	_try("1 无属性 + 1 克制 ... 买不起第三座", w, [Types.Element.NONE, good])
	_try("2 座克制塔（230金，超预算）", w, [good, good])
	_try("3 座克制塔（345金，超预算）", w, [good, good, good])
	_try("2 无属性 + 1 被克（反面教材）", w, [Types.Element.NONE, Types.Element.NONE, bad])
	quit()

func _try(label: String, w: Wave, elements: Array) -> void:
	var towers: Array[Tower] = []
	var cost: int = 0
	for i: int in elements.size():
		var t: Tower = Tower.new(i, Balance.TOWER_COST)
		cost += Balance.TOWER_COST
		if elements[i] != Types.Element.NONE:
			t.upgrade(elements[i], Balance.UPGRADE_COST)
			cost += Balance.UPGRADE_COST
		towers.append(t)
	var mods: Modifiers = Modifiers.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var b: Battle = Battle.new(w, towers, mods, rng)
	var r: Dictionary = b.run_to_end()
	var dps: float = 0.0
	for t: Tower in towers:
		dps += t.damage(mods) * t.rate(mods)
	print("%-32s 花费%3d  击杀%2d/%2d  漏%2d  扣命%2d  用时%5.1fs" % [
		label, cost, int(r["killed"]), w.specs.size(), int(r["leaked"]),
		int(r["lives_lost"]), float(r["duration"])])
