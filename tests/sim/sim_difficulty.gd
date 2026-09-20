extends SceneTree

## 三个难度档位各跑一遍，确认体感差距拉得开、而且歪路在每个档都走不通。
## 跑法：godot --headless --path . --script res://tests/sim/sim_difficulty.gd

const RUNS: int = 200

func _initialize() -> void:
	print("难度     HP成长 | 歪路   平均铺   照克制  拆塔重组 | 照克制平均阵亡波")
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		_run(d)
	Balance.reset()
	quit()

func _run(d: Balance.Difficulty) -> void:
	var out: Array[String] = []
	var death: float = 0.0
	for mode: String in ["neutral", "fixed", "counter", "adaptive"]:
		Balance.reset()
		Balance.apply_difficulty(d)
		var p: GreedyPlayer = GreedyPlayer.new(mode)
		var wins: int = 0
		var dsum: int = 0
		var losses: int = 0
		for s: int in RUNS:
			var rs: RunState = p.play(s * 7919 + 13)
			if rs.won:
				wins += 1
			else:
				losses += 1
				dsum += rs.wave_index
		out.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
		if mode == "counter":
			death = (float(dsum) / float(losses)) if losses > 0 else 0.0
	Balance.apply_difficulty(d)
	print("%-8s %6.2f | %s %s %s %s | %14.1f" % [
		Balance.difficulty_name(), Balance.HP_GROWTH,
		out[0], out[1], out[2], out[3], death])
