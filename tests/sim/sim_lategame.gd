extends SceneTree

## 平衡实验：通关的局，最后三波到底是「打死怪」还是「靠命硬扛漏怪」？
## 如果击杀率很低却能赢，说明后期难度退化成了消耗战，属性克制失去意义。
## 跑法：godot --headless --path . --script res://tests/sim/sim_lategame.gd

const RUNS: int = 150

func _initialize() -> void:
	Balance.reset()
	print("通关局在各波的击杀率（杀掉的 / 总数）与扣命\n")
	print("波次   击杀率   平均扣命   平均塔数")
	var kills: Dictionary = {}
	var totals: Dictionary = {}
	var lost: Dictionary = {}
	var towers: Dictionary = {}
	var wins: int = 0
	for s: int in RUNS:
		var p: GreedyPlayer = GreedyPlayer.new("counter")
		var rs: RunState = RunState.new(s * 7919 + 13)
		var log: Array[Dictionary] = []
		while not rs.finished:
			p.build_phase(rs)
			var n: int = rs.current_wave().specs.size()
			var idx: int = rs.wave_index
			var tc: int = rs.towers.size()
			var r: Dictionary = rs.play_wave()
			log.append({"w": idx, "k": int(r["killed"]), "n": n,
				"l": int(r.get("lives_lost", 0)), "t": tc})
			if rs.finished:
				break
			p.reward_phase(rs)
		if not rs.won:
			continue
		wins += 1
		for e: Dictionary in log:
			var w: int = e["w"]
			kills[w] = int(kills.get(w, 0)) + int(e["k"])
			totals[w] = int(totals.get(w, 0)) + int(e["n"])
			lost[w] = int(lost.get(w, 0)) + int(e["l"])
			towers[w] = int(towers.get(w, 0)) + int(e["t"])
	for w: int in range(1, Balance.TOTAL_WAVES + 1):
		if not totals.has(w):
			continue
		print("%4d %7.0f%% %10.1f %10.1f" % [
			w, 100.0 * float(kills[w]) / float(totals[w]),
			float(lost[w]) / float(wins), float(towers[w]) / float(wins)])
	print("\n通关 %d / %d" % [wins, RUNS])
	quit()
