extends SceneTree

## 平衡实验：「战斗中可建塔」让最强打法从 37% 冲到 50%，
## 这里扫 HP 成长，找回「最强打法约 40%、歪路仍 0%」的难度。
## 跑法：godot --headless --path . --script res://tests/sim/sim_recalibrate.gd

const RUNS: int = 300

func _initialize() -> void:
	print("HP成长 | 歪路  平均铺  照克制  拆塔重组(最强)")
	for hp: float in [1.505, 1.51, 1.515, 1.52]:
		var out: Array[String] = []
		for mode: String in ["neutral", "fixed", "counter", "adaptive"]:
			Balance.reset()
			Balance.HP_GROWTH = hp
			var p: GreedyPlayer = GreedyPlayer.new(mode)
			p.live = true
			var wins: int = 0
			for s: int in RUNS:
				if p.play(s * 7919 + 13).won:
					wins += 1
			out.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
		var best: float = out[3].to_float()
		var cheese: float = out[0].to_float()
		var mark: String = "  <== 目标" if best >= 35.0 and best <= 45.0 and cheese <= 2.0 else ""
		print("%6.3f | %s %s %s %s%s" % [hp, out[0], out[1], out[2], out[3], mark])
	Balance.reset()
	quit()
