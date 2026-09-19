extends SceneTree

## 平衡实验（第二轮）：固定赛道 24（怪约 14 秒走完，视觉节奏舒服），
## 扫 HP 成长 × 塔基础伤害 × 无属性倍率，目标是把「只堆无属性塔」这条歪路压到 0。
## 跑法：godot --headless --path . --script res://tests/sim/sim_sweep2.gd

const RUNS: int = 150

func _initialize() -> void:
	print("HP成长 塔伤 无属性 | counter neutral adaptive | 阵亡波分布(5/6/7/8/9/10)")
	for hp_growth: float in [1.46, 1.50, 1.54]:
		for dmg: float in [9.0, 10.0, 11.0]:
			for neu: float in [0.30, 0.38, 0.45]:
				_run(hp_growth, dmg, neu)
	Balance.reset()
	quit()

func _run(hp_growth: float, dmg: float, neu: float) -> void:
	var rates: Array[String] = []
	var dist: Array[int] = [0, 0, 0, 0, 0, 0]
	for mode: String in ["counter", "neutral", "adaptive"]:
		Balance.reset()
		Balance.TRACK_LENGTH = 24.0
		Balance.HP_GROWTH = hp_growth
		Balance.TOWER_BASE_DAMAGE = dmg
		Balance.MULT_NEUTRAL_ATK = neu
		var wins: int = 0
		var p: GreedyPlayer = GreedyPlayer.new(mode)
		for s: int in RUNS:
			var rs: RunState = p.play(s * 7919 + 13)
			if rs.won:
				wins += 1
			elif mode == "counter":
				var w: int = clampi(rs.wave_index, 5, 10)
				dist[w - 5] += 1
		rates.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
	var cw: float = rates[0].to_float()
	var nw: float = rates[1].to_float()
	var mark: String = "  <== 目标" if cw >= 28.0 and cw <= 55.0 and nw <= 3.0 else ""
	print("%6.2f %4.0f %6.2f | %7s %7s %8s |  %2d/%2d/%2d/%2d/%2d/%2d%s" % [
		hp_growth, dmg, neu, rates[0], rates[1], rates[2],
		dist[0], dist[1], dist[2], dist[3], dist[4], dist[5], mark])
