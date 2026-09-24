class_name Progress
extends RefCounted

## 跨局保留的进度，存在 user:// 下。目前只记一件事：哪几档难度通关过。
## 难度是一档一档解锁的 —— 三个档同时摆出来的话，新玩家很容易一上来就点地狱，
## 在第 4 波被打死然后再也不开了。

const SECTION: String = "progress"
const KEY_CLEARED: String = "cleared"

## 存档路径。测试会把它指到别的文件，免得跑一次测试就把玩家的进度冲掉。
static var save_path: String = "user://progress.cfg"

## 打通哪一档才解锁这一档。简单没有前置，永远开着。
const REQUIRES: Dictionary = {
	Balance.Difficulty.HARD: Balance.Difficulty.EASY,
	Balance.Difficulty.HELL: Balance.Difficulty.HARD,
}

const ORDER: Array[Balance.Difficulty] = [
	Balance.Difficulty.EASY, Balance.Difficulty.HARD, Balance.Difficulty.HELL,
]

static var _cleared: Dictionary = {}
static var _loaded: bool = false

# ---- 存取 ------------------------------------------------------------------

static func load_progress() -> void:
	_cleared = {}
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(save_path) != OK:
		# 第一次玩，没有存档很正常，不是错误
		return
	for v: int in cfg.get_value(SECTION, KEY_CLEARED, [] as Array):
		_cleared[v] = true

static func save_progress() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var ids: Array[int] = []
	for k: int in _cleared.keys():
		ids.append(k)
	ids.sort()
	cfg.set_value(SECTION, KEY_CLEARED, ids)
	cfg.save(save_path)

static func _ensure() -> void:
	if not _loaded:
		load_progress()

## 清空进度（测试用，也留给以后的「重置存档」入口）
static func reset() -> void:
	_cleared = {}
	_loaded = true

# ---- 查询 ------------------------------------------------------------------

static func is_cleared(d: Balance.Difficulty) -> bool:
	_ensure()
	return bool(_cleared.get(int(d), false))

static func is_unlocked(d: Balance.Difficulty) -> bool:
	if not REQUIRES.has(d):
		return true
	return is_cleared(REQUIRES[d])

## 打通 d 会解锁哪一档。它是最后一档的话就返回自己。
static func unlocks(d: Balance.Difficulty) -> Balance.Difficulty:
	for nxt: Balance.Difficulty in REQUIRES.keys():
		if REQUIRES[nxt] == d:
			return nxt
	return d

## 当前开放的最高难度，用来给标题页选一个合理的默认值
static func highest_unlocked() -> Balance.Difficulty:
	var best: Balance.Difficulty = Balance.Difficulty.EASY
	for d: Balance.Difficulty in ORDER:
		if is_unlocked(d):
			best = d
	return best

# ---- 写入 ------------------------------------------------------------------

## 记一次通关。返回 true 表示这是这一档的**首次**通关 ——
## UI 拿它决定要不要弹「解锁了困难」，重复通关不该每次都报一遍喜。
static func mark_cleared(d: Balance.Difficulty) -> bool:
	_ensure()
	if is_cleared(d):
		return false
	_cleared[int(d)] = true
	save_progress()
	return true
