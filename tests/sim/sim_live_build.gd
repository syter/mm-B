extends SceneTree

## 平衡实验：「战斗中也能建塔」这个改动对难度的冲击有多大。
##
## 赏金改成即时到账之后，玩家可以拿本波杀怪的钱当场补塔，
## 等于资源效率凭空提升一截。这里量的就是那一截有多厚。
## 跑法：godot --headless --path . --script res://tests/sim/sim_live_build.gd

const RUNS: int = 300

func _initialize() -> void:
	Balance.reset()
	print("=== 战斗中可建塔 对通关率的影响（%d 局）===\n" % RUNS)
	print("%-22s %10s %10s %8s" % ["打法", "只在波间建", "战斗中也建", "差值"])
	for mode: String in ["neutral", "fixed", "counter", "adaptive"]:
		var a: float = _rate(mode, false)
		var b: float = _rate(mode, true)
		print("%-22s %9.1f%% %9.1f%% %+7.1f" % [LABELS[mode], a, b, b - a])
	quit()

const LABELS: Dictionary = {
	"neutral": "只堆无属性塔",
	"fixed": "三属性平均铺",
	"counter": "照克制建塔",
	"adaptive": "照克制＋拆塔重组",
}

func _rate(mode: String, live: bool) -> float:
	var p: GreedyPlayer = GreedyPlayer.new(mode)
	p.live = live
	var wins: int = 0
	for s: int in RUNS:
		if p.play(s * 7919 + 13).won:
			wins += 1
	return 100.0 * float(wins) / float(RUNS)
