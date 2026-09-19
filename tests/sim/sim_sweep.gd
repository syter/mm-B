extends SceneTree

## 平衡实验：扫 赛道长度 × HP 成长 × 塔基础伤害，找难度落在目标区间的组合。
##
## 目标（脚本玩家 GreedyPlayer 的通关率）：
##   counter  照克制建塔，中等水平玩家的替身   30~55%
##   neutral  只堆无属性塔，不靠克制的歪路     0~5%（必须堵死）
##
## 跑法：godot --headless --path . --script res://tests/sim/sim_sweep.gd

const RUNS: int = 100

func _initialize() -> void:
	print("赛道 HP成长 塔伤 | counter neutral adaptive | 平均阵亡波")
	for track: float in [14.0, 18.0, 24.0]:
		for hp_growth: float in [1.34, 1.42, 1.50]:
			for dmg: float in [9.0, 11.0, 14.0]:
				_run(track, hp_growth, dmg)
	Balance.reset()
	quit()

func _run(track: float, hp_growth: float, dmg: float) -> void:
	var rates: Array[String] = []
	var death: float = 0.0
	for mode: String in ["counter", "neutral", "adaptive"]:
		Balance.reset()
		Balance.TRACK_LENGTH = track
		Balance.HP_GROWTH = hp_growth
		Balance.TOWER_BASE_DAMAGE = dmg
		var wins: int = 0
		var death_sum: int = 0
		var deaths: int = 0
		var p: GreedyPlayer = GreedyPlayer.new(mode)
		for s: int in RUNS:
			var rs: RunState = p.play(s * 7919 + 13)
			if rs.won:
				wins += 1
			else:
				deaths += 1
				death_sum += rs.wave_index
		rates.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
		if mode == "counter":
			death = (float(death_sum) / float(deaths)) if deaths > 0 else 0.0
	var mark: String = ""
	var cw: float = rates[0].to_float()
	var nw: float = rates[1].to_float()
	if cw >= 25.0 and cw <= 60.0 and nw <= 8.0:
		mark = "  <== 目标区间"
	print("%4.0f %6.2f %4.0f | %7s %7s %8s |  %8.1f%s" % [
		track, hp_growth, dmg, rates[0], rates[1], rates[2], death, mark])
