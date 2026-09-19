extends SceneTree

## 平衡实验：三种策略的通关率对比。
## 重点回答两个问题：
##   1. 属性克制有没有用？   → 看 neutral（只堆无属性）跟其他的差距
##   2. 「选哪个属性」有没有用？→ 看 fixed（不看预告平均铺）跟 counter（照预告建）的差距
##      如果 fixed ≈ counter，说明克制虽然重要，但玩家根本不需要动脑，
##      机制在体感上就是白给的 —— 这正是实际试玩时「感觉克制没意义」的来源。
## 跑法：godot --headless --path . --script res://tests/sim/sim_run.gd

const RUNS: int = 300

func _initialize() -> void:
	Balance.reset()
	print("=== 10 波完整模拟（%d 局）===\n" % RUNS)
	for mode: String in ["neutral", "random", "fixed", "counter", "adaptive"]:
		_batch(mode)
	quit()

const LABELS: Dictionary = {
	"neutral": "只堆无属性塔（歪路）",
	"random": "随机升属性，完全不看怪",
	"fixed": "三属性平均铺，不看预告",
	"counter": "照克制建塔，不拆塔",
	"adaptive": "照克制建塔 + 拆掉没用的",
}

func _batch(mode: String) -> void:
	var wins: int = 0
	var death_sum: int = 0
	var lives_sum: int = 0
	var p: GreedyPlayer = GreedyPlayer.new(mode)
	for s: int in RUNS:
		var rs: RunState = p.play(s * 7919 + 13)
		if rs.won:
			wins += 1
			lives_sum += rs.lives
		else:
			death_sum += rs.wave_index
	var losses: int = RUNS - wins
	print("%-26s 通关率 %5.1f%%   平均阵亡于第 %.1f 波   通关剩命 %.1f" % [
		LABELS[mode], 100.0 * float(wins) / float(RUNS),
		(float(death_sum) / float(losses)) if losses > 0 else 0.0,
		(float(lives_sum) / float(wins)) if wins > 0 else 0.0])
