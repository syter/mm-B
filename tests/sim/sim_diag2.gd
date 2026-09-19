extends SceneTree

## 诊断：同一个种子，开/关刷新，印出实际领到的奖励。
## 跑法：godot --headless --path . --script res://tests/sim/sim_diag2.gd

func _initialize() -> void:
	Balance.reset()
	for rr: bool in [false, true]:
		var rs: RunState = RunState.new(777)
		var p: GreedyPlayer = GreedyPlayer.new("counter")
		p.use_reroll = rr
		print("\n=== 刷新：%s ===" % ("开" if rr else "关"))
		for round_i: int in 6:
			var before: int = rs.taken_count()
			var choices: Array[Reward] = rs.begin_reward_round()
			var names: Array[String] = []
			for c: Reward in choices:
				names.append("%s(%s)" % [c.title, c.rarity_name()])
			print("  抽到: %s" % " / ".join(names))
			p.reward_phase_single(rs, choices)
			print("    → 领了 %d 个，金 %d" % [rs.taken_count() - before, rs.gold])
	quit()
