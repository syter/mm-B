extends SceneTree

## 诊断：把「开局送三次奖励」和「奖励可刷新」分开量，
## 看通关率的变化到底是哪个机制造成的。
## 跑法：godot --headless --path . --script res://tests/sim/sim_diag.gd

const RUNS: int = 200

func _initialize() -> void:
	Balance.reset()
	print("开局奖励 刷新 | 通关率  阵亡波  剩命  结局金 | 领奖次数 刷新次数 刷新花费")
	for op: bool in [false, true]:
		for rr: bool in [false, true]:
			_run(op, rr)
	quit()

func _run(op: bool, rr: bool) -> void:
	var p: GreedyPlayer = GreedyPlayer.new("counter")
	p.opening_rewards = op
	p.use_reroll = rr
	var wins: int = 0
	var death: int = 0
	var losses: int = 0
	var lives: int = 0
	var gold: int = 0
	var rerolls: int = 0
	var rgold: int = 0
	var takes: int = 0
	for s: int in RUNS:
		var rs: RunState = p.play(s * 7919 + 13)
		rerolls += p.stat_rerolls
		rgold += p.stat_reroll_gold
		takes += p.stat_takes
		if rs.won:
			wins += 1
			lives += rs.lives
			gold += rs.gold
		else:
			losses += 1
			death += rs.wave_index
	print("%8s %4s | %5.1f%% %7.1f %5.1f %7.0f | %8.1f %8.1f %8.1f" % [
		"是" if op else "否", "是" if rr else "否",
		100.0 * float(wins) / float(RUNS),
		(float(death) / float(losses)) if losses > 0 else 0.0,
		(float(lives) / float(wins)) if wins > 0 else 0.0,
		(float(gold) / float(wins)) if wins > 0 else 0.0,
		float(takes) / float(RUNS),
		float(rerolls) / float(RUNS),
		float(rgold) / float(RUNS)])
