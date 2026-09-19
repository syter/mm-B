class_name Balance
extends RefCounted

## 全部可调数值集中在这里。改平衡只动这个文件，规则代码不写魔法数字。
## 任何改动都要先跑 tests/sim/ 底下的模拟，结论写回 DESIGN.md。

# ---- 属性克制倍率 ----------------------------------------------------------
## 火 → 木 → 水 → 火
static var MULT_COUNTER: float = 2.6      ## 克制
static var MULT_SAME: float = 0.55        ## 同属性
static var MULT_COUNTERED: float = 0.3    ## 被克制
static var MULT_NEUTRAL_ATK: float = 0.30 ## 无属性塔打有属性怪。压到 0.30 是为了堵死「只堆无属性塔」的歪路，
## 模拟实测 0.45 时该打法通关率 20%，0.30 时降到 0%。

# ---- 开局 ------------------------------------------------------------------
static var START_GOLD: int = 220
static var START_LIVES: int = 20
static var TOTAL_WAVES: int = 10
static var MAX_TOWERS: int = 8

# ---- 塔 --------------------------------------------------------------------
static var TOWER_COST: int = 60
static var UPGRADE_COST: int = 60
## 拆塔返还已投入金额的比例
static var REFUND_RATE: float = 0.6
## 每波免费拆除的次数，这几次全额返还。
## 模拟实测：只有 60% 返还时，「拆掉用不上的塔」的通关率反而低于「从不拆塔」——
## 损耗吃掉了调整阵容的收益。给每波一次免费拆除，才让「看预告重组阵容」成为真玩法。
static var FREE_SELLS_PER_WAVE: int = 1
static var TOWER_BASE_DAMAGE: float = 10.0
static var TOWER_BASE_RATE: float = 1.2   ## 每秒攻击次数

# ---- 塔等级 ----------------------------------------------------------------
## 属性塔还能继续升级，每升一级多打一个目标（全额伤害）。
## 1 级打 1 个，4 级打 4 个 —— 等于 4 倍输出，所以价格必须陡。
static var MAX_TOWER_LEVEL: int = 4
## 升到第 n 级的价格 = UPGRADE_COST * LEVEL_COST_GROWTH^(n-1)，并取整到 10 的倍数
## → Lv2 160 / Lv3 410 / Lv4 1050
##
## 加入「开局奖励 + 可刷新」之后，这条已经不是有效的难度旋钮了
## （4.0 → 95.3%、8.5 → 86.0%），因为玩家靠分散 build 和技能取胜，
## 等级不再是瓶颈。定在 2.6 纯粹是为了让 Lv4 真的练得到，
## 难度改由 HP_GROWTH 控制。
static var LEVEL_COST_GROWTH: float = 2.6

# ---- 技能 ------------------------------------------------------------------
## 同属性塔达到这个数量就解锁该属性的技能
static var SKILL_REQUIRED_TOWERS: int = 3
## 冷却。一波约 25~35 秒，所以一波大概能放 1~2 次
static var SKILL_COOLDOWN: float = 18.0
## 技能伤害 = 这个 × 该属性所有塔的等级总和，再乘属性克制倍率。
## 挂钩等级总和而不是塔数，这样「练精一种属性」才有回报。
static var SKILL_DAMAGE_PER_LEVEL: float = 26.0
## 火：灼烧。总伤害是技能伤害的这个比例，分摊在持续时间内每 0.2 秒跳一次
static var SKILL_BURN_RATIO: float = 0.6
static var SKILL_BURN_DURATION: float = 3.0
static var SKILL_BURN_TICK: float = 0.2
## 水：减速
static var SKILL_SLOW_PCT: float = 0.5
static var SKILL_SLOW_DURATION: float = 4.0
## 木：缠绕，完全定身
static var SKILL_ROOT_DURATION: float = 2.5

# ---- 赛道与怪物 ------------------------------------------------------------
## 路径总长（抽象单位）。没有射程，塔打全场，所以路径只决定「怪能活多久」。
static var TRACK_LENGTH: float = 24.0
static var ENEMY_BASE_SPEED: float = 1.7  ## 单位/秒 → 约 14 秒走完
static var SPEED_GROWTH: float = 0.02     ## 每波累加

static var HP_BASE: float = 55.0
static var HP_GROWTH: float = 1.585
static var COUNT_BASE: int = 6
## 第 n 波数量 = COUNT_BASE + n * COUNT_PER_WAVE。
## 难度不能只靠血量几何成长——那会让前 9 波全是白送、第 10 波变成一堵翻不过的墙。
## 让数量也跟著涨，压力才会平均分布在中后段。
static var COUNT_PER_WAVE: float = 1.6
static var SPAWN_INTERVAL: float = 0.75

static var BOUNTY_BASE: int = 6
static var BOUNTY_PER_WAVE: int = 2
static var WAVE_CLEAR_GOLD: int = 40

## 精英怪出现的波次
static var ELITE_WAVES: Array[int] = [5, 10]
static var ELITE_HP_MULT: float = 6.0
static var ELITE_BOUNTY_MULT: float = 5.0
static var ELITE_SPEED_MULT: float = 0.65

## 漏怪扣命
static var LEAK_COST_NORMAL: int = 1
static var LEAK_COST_ELITE: int = 5

# ---- 波次属性构成 ----------------------------------------------------------
## 第几波开始混入第 2 / 第 3 种属性
static var WAVE_TWO_ELEMENTS: int = 3
static var WAVE_THREE_ELEMENTS: int = 7

# ---- 奖励 ------------------------------------------------------------------
## 每波结束给几次 3 选 1
static var REWARD_ROUNDS: int = 3
static var REWARD_CHOICES: int = 3

# ---- 模拟 ------------------------------------------------------------------
static var SIM_STEP: float = 0.05         ## 无头模拟步长（20Hz）

# ---- 塔的递增成本 ----------------------------------------------------------
## 第 n 座塔的价格 = TOWER_COST * TOWER_COST_GROWTH^n。
## 没有射程、塔位只有 8 个，如果塔很便宜，前三波就会填满、金钱从此失去意义。
## 让后面的塔越来越贵，「要不要开第 6 座」才会是一个真决策。
static var TOWER_COST_GROWTH: float = 1.45

## 把可调参数恢复成基准值（模拟扫参数后要复位，否则污染下一批）
## 所有玩家看得到的花费都过一次这个函数。
## 87 金、143 金这种数字在界面上很难读，取整到 10 的倍数之后
## 玩家一眼就能估算「我还差几座塔」。
static func round_cost(v: float) -> int:
	return maxi(10, roundi(v / 10.0) * 10)

static func reset() -> void:
	MULT_COUNTER = 2.6
	MULT_SAME = 0.55
	MULT_COUNTERED = 0.3
	MULT_NEUTRAL_ATK = 0.30
	START_GOLD = 220
	START_LIVES = 20
	TOWER_COST = 60
	UPGRADE_COST = 60
	MAX_TOWER_LEVEL = 4
	LEVEL_COST_GROWTH = 2.6
	SKILL_REQUIRED_TOWERS = 3
	SKILL_COOLDOWN = 18.0
	SKILL_DAMAGE_PER_LEVEL = 26.0
	SKILL_BURN_RATIO = 0.6
	SKILL_BURN_DURATION = 3.0
	SKILL_SLOW_PCT = 0.5
	SKILL_SLOW_DURATION = 4.0
	SKILL_ROOT_DURATION = 2.5
	TOWER_COST_GROWTH = 1.45
	TOWER_BASE_DAMAGE = 10.0
	TOWER_BASE_RATE = 1.2
	TRACK_LENGTH = 24.0
	ENEMY_BASE_SPEED = 1.7
	HP_BASE = 55.0
	HP_GROWTH = 1.585
	COUNT_BASE = 6
	COUNT_PER_WAVE = 1.6
	SPAWN_INTERVAL = 0.75
	BOUNTY_BASE = 6
	BOUNTY_PER_WAVE = 2
	WAVE_CLEAR_GOLD = 40
