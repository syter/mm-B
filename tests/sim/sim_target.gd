extends SceneTree

## 扫「大招伤害 × 奖励强度」，找能同时逼近
## 简单 80% / 困难 60% / 地狱 40% 的组合。
## 跑法：godot --headless --path . --script res://tests/sim/sim_target.gd

const RUNS: int = 100

func _initialize() -> void:
	print("大招/级 奖励×  |  简单   困难   地狱  | 歪路(地狱)")
	for skill: float in [26.0, 50.0, 80.0]:
		for power: float in [1.0, 1.35, 1.7]:
			_run(skill, power)
	Balance.reset()
	quit()

func _run(skill: float, power: float) -> void:
	var out: Array[String] = []
	var cheese: float = 0.0
	for d: Balance.Difficulty in [Balance.Difficulty.EASY,
			Balance.Difficulty.HARD, Balance.Difficulty.HELL]:
		Balance.reset()
		Balance.apply_difficulty(d)
		Balance.SKILL_DAMAGE_PER_LEVEL = skill
		Balance.REWARD_POWER = power
		var p: GreedyPlayer = GreedyPlayer.new("counter")
		var wins: int = 0
		for s: int in RUNS:
			if p.play(s * 7919 + 13).won:
				wins += 1
		out.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
		if d == Balance.Difficulty.HELL:
			var pn: GreedyPlayer = GreedyPlayer.new("neutral")
			var nw: int = 0
			for s2: int in 60:
				if pn.play(s2 * 7919 + 13).won:
					nw += 1
			cheese = 100.0 * float(nw) / 60.0
	print("%7.0f %5.2f  | %s %s %s | %8.1f%%" % [
		skill, power, out[0], out[1], out[2], cheese])
