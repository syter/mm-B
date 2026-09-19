extends SceneTree

## 平衡实验：校准到 60%。
##
## 练级涨价已经不是有效旋钮了（4.0 → 95.3%、8.5 → 86.0%）——
## 脚本玩家现在靠分散 build 和技能取胜，等级不再是瓶颈，
## 而且调太高只会让 Lv3/Lv4 变成没人碰得到的死内容。
## 改扫血量成长 × 每波数量成长这两个全局旋钮。
## 跑法：godot --headless --path . --script res://tests/sim/sim_power.gd

const RUNS: int = 200

func _initialize() -> void:
	print("HP成长 数量/波 | 歪路  照克制  拆塔重组 | 平均阵亡波")
	for hp: float in [1.55, 1.57, 1.59, 1.61]:
		_run(hp, 1.6)
	Balance.reset()
	quit()

func _run(hp: float, cnt: float) -> void:
	var out: Array[float] = []
	var death: float = 0.0
	for mode: String in ["neutral", "counter", "adaptive"]:
		Balance.reset()
		Balance.HP_GROWTH = hp
		Balance.COUNT_PER_WAVE = cnt
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
		out.append(100.0 * float(wins) / float(RUNS))
		if mode == "counter":
			death = (float(dsum) / float(losses)) if losses > 0 else 0.0
	var best: float = maxf(out[1], out[2])
	var mark: String = "  <== 目标" if best >= 56.0 and best <= 64.0 and out[0] <= 3.0 else ""
	print("%6.2f %7.1f | %5.1f%% %7.1f%% %9.1f%% | %9.1f%s" % [
		hp, cnt, out[0], out[1], out[2], death, mark])
