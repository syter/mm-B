extends SceneTree

## 平衡实验（第三轮）：找一条「压力平均分布」的难度曲线。
##
## 上一轮的教训：只靠血量几何成长（HP_GROWTH 1.54）会让前 9 波击杀率 91~100%、
## 第 10 波掉到 59%，整局难度全压在最后一波，而且赢法是拿命硬扛漏怪而不是打得好。
##
## 这一轮同时看两个指标：
##   通关率        目标 25~45%
##   末波占比      第 10 波吃掉了全局多少比例的扣命，越低代表曲线越平滑，目标 < 45%
##
## 跑法：godot --headless --path . --script res://tests/sim/sim_curve.gd

const RUNS: int = 120

func _initialize() -> void:
	print("HP成长 数量/波 | counter neutral | 末波占比 首次扣命波 第5/7/9/10波击杀率")
	for hp_growth: float in [1.42, 1.46, 1.50]:
		for count_per: float in [1.0, 1.6, 2.2]:
			_run(hp_growth, count_per)
	Balance.reset()
	quit()

func _run(hp_growth: float, count_per: float) -> void:
	var rates: Array[String] = []
	var kill_at: Dictionary = {}
	var tot_at: Dictionary = {}
	var lost_at: Dictionary = {}
	var first_hit: float = 0.0
	var first_n: int = 0
	for mode: String in ["counter", "neutral"]:
		Balance.reset()
		Balance.TRACK_LENGTH = 24.0
		Balance.TOWER_BASE_DAMAGE = 10.0
		Balance.MULT_NEUTRAL_ATK = 0.30
		Balance.HP_GROWTH = hp_growth
		Balance.COUNT_PER_WAVE = count_per
		var wins: int = 0
		var p: GreedyPlayer = GreedyPlayer.new(mode)
		for s: int in RUNS:
			var rs: RunState = RunState.new(s * 7919 + 13)
			var first: int = 0
			while not rs.finished:
				p.build_phase(rs)
				var idx: int = rs.wave_index
				var n: int = rs.current_wave().specs.size()
				var r: Dictionary = rs.play_wave()
				if mode == "counter":
					kill_at[idx] = int(kill_at.get(idx, 0)) + int(r["killed"])
					tot_at[idx] = int(tot_at.get(idx, 0)) + n
					lost_at[idx] = int(lost_at.get(idx, 0)) + int(r.get("lives_lost", 0))
					if first == 0 and int(r.get("lives_lost", 0)) > 0:
						first = idx
				if rs.finished:
					break
				p.reward_phase(rs)
			if rs.won:
				wins += 1
			if mode == "counter" and first > 0:
				first_hit += float(first)
				first_n += 1
		rates.append("%5.1f%%" % (100.0 * float(wins) / float(RUNS)))
	var total_lost: int = 0
	for v: int in lost_at.values():
		total_lost += v
	var tail: float = 100.0 * float(lost_at.get(10, 0)) / maxf(float(total_lost), 1.0)
	var ks: Array[String] = []
	for w: int in [5, 7, 9, 10]:
		ks.append("%.0f%%" % (100.0 * float(kill_at.get(w, 0)) / maxf(float(tot_at.get(w, 1)), 1.0)))
	var cw: float = rates[0].to_float()
	var nw: float = rates[1].to_float()
	var mark: String = "  <== 目标" if cw >= 25.0 and cw <= 45.0 and nw <= 3.0 and tail < 45.0 else ""
	print("%6.2f %7.1f | %7s %7s | %7.0f%% %9.1f  %s%s" % [
		hp_growth, count_per, rates[0], rates[1], tail,
		(first_hit / float(first_n)) if first_n > 0 else 0.0, " / ".join(ks), mark])
