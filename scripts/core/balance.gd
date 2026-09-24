class_name Balance
extends RefCounted

## 全部可调数值集中在这里。改平衡只动这个文件，规则代码不写魔法数字。
## 任何改动都要先跑 tests/sim/ 底下的模拟，结论写回 DESIGN.md。

# ---- 属性克制倍率 ----------------------------------------------------------
## 火 → 木 → 水 → 火
static var MULT_COUNTER: float = 3.0      ## 克制
static var MULT_SAME: float = 0.55        ## 同属性
## 被克制。跟 MULT_COUNTER 的比值就是「克制差距」，现在是 3.0 / 0.1667 = 18 倍。
## 比无属性（0.30）还低一截 —— 打错属性比不带属性更惨，这是故意的。
static var MULT_COUNTERED: float = 0.1667 ## 被克制（克制差距 18 倍）
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
## 免费拆除（全额返还）。按难度分两条线控制：
##
##   PER_WAVE  每波开始补几次（0 = 不按波补，整局定额一次性发下去）
##   TOTAL     整局最多用几次（-1 = 不限）
##
##   简单：每波 1 次，不限总量      —— 想怎么重组就怎么重组，专心学克制关系
##   困难：每波 1 次，整局上限 3    —— 能救三次，但得想清楚花在哪一波
##   地狱：整局就 1 次              —— 基本等于「盖下去就别想改了」
##
## 模拟实测：只有 60% 返还时，「拆掉用不上的塔」的通关率反而低于「从不拆塔」——
## 损耗吃掉了调整阵容的收益。免费拆除就是「看预告重组阵容」这条玩法的入场券，
## 所以它按难度收紧，而不是所有档位一刀切。
static var FREE_SELLS_PER_WAVE: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.HARD: 1,
	Difficulty.HELL: 0,
}
static var FREE_SELLS_TOTAL: Dictionary = {
	Difficulty.EASY: -1,
	Difficulty.HARD: 3,
	Difficulty.HELL: 1,
}
static var TOWER_BASE_DAMAGE: float = 10.0
static var TOWER_BASE_RATE: float = 1.2   ## 每秒攻击次数

# ---- 塔等级 ----------------------------------------------------------------
## 属性塔还能继续升级，每升一级多打一个目标（全额伤害）。
## 1 级打 1 个，4 级打 4 个 —— 等于 4 倍输出，所以价格必须陡。
static var MAX_TOWER_LEVEL: int = 4
## 升到第 n 级的价格 = UPGRADE_COST * LEVEL_COST_GROWTH^(n-1)，并取整到 10 的倍数
## → Lv2 120 / Lv3 240 / Lv4 480
##
## 加入「开局奖励 + 可刷新」之后，这条已经不是有效的难度旋钮了
## （4.0 → 95.3%、8.5 → 86.0%），因为玩家靠分散 build 和技能取胜，
## 等级不再是瓶颈。难度由 HP_GROWTH 控制。
##
## 2.6 → 2.0：赏金砍到 3+0.9n 之后，练到 Lv4 的 1620 金够盖三座新塔，
## 练级在数值上完全不成立，一条升级线就这么废掉了。
## 现在练满一座是 840，跟「多盖一座塔再升属性」处在同一个量级，才真的要比较。
static var LEVEL_COST_GROWTH: float = 2.0

# ---- 技能 ------------------------------------------------------------------
## 同属性塔达到这个数量就解锁该属性的技能
static var SKILL_REQUIRED_TOWERS: int = 3
## 冷却。一波约 25~35 秒，所以一波大概能放 1~2 次
static var SKILL_COOLDOWN: float = 18.0
## 技能伤害 = 这个 × 该属性所有塔的等级总和，再乘属性克制倍率。
## 挂钩等级总和而不是塔数，这样「练精一种属性」才有回报。
static var SKILL_DAMAGE_PER_LEVEL: float = 26.0
## 奖励强度的全局倍率。24 张卡一张张调太慢，用一个系数统一放大 ——
## 模拟器能直接扫它，找到目标通关率之后再决定要不要固化进各张卡。
static var REWARD_POWER: float = 1.0
## 火：灼烧。总伤害是技能伤害的这个比例，分摊在持续时间内每 0.2 秒跳一次
static var SKILL_BURN_RATIO: float = 0.6
static var SKILL_BURN_DURATION: float = 3.0
static var SKILL_BURN_TICK: float = 0.2
## 水：减速
static var SKILL_SLOW_PCT: float = 0.5
static var SKILL_SLOW_DURATION: float = 4.0
## 木：缠绕，完全定身
static var SKILL_ROOT_DURATION: float = 2.5

# ---- 属性自带的特性 --------------------------------------------------------
## 三种属性不只是颜色不同，各自还有性格。查表而不是写死在怪物代码里 ——
## 以后加 boss 是在这张表的基础上再叠一层修正，不是改这里。
##
##   火：跑得快，但不抗打        → 优先处理，不然很快就漏
##   木：慢而厚                  → 有时间磨，但磨得久
##   水：死的时候给全场回血      → 不集中火力清掉就会拖成持久战
static var ELEMENT_SPEED_MULT: Dictionary = {
	Types.Element.FIRE: 1.28,
	Types.Element.WOOD: 0.78,
	Types.Element.WATER: 1.0,
}
static var ELEMENT_HP_MULT: Dictionary = {
	Types.Element.FIRE: 0.82,
	Types.Element.WOOD: 1.38,
	Types.Element.WATER: 1.0,
}
## 水属性怪死亡时，给场上所有活着的怪回复「死者最大血量」的这个比例
static var WATER_DEATH_HEAL: float = 0.05

# ---- 赛道与怪物 ------------------------------------------------------------
## 路径总长（抽象单位）。没有射程，塔打全场，所以路径只决定「怪能活多久」。
static var TRACK_LENGTH: float = 24.0
static var ENEMY_BASE_SPEED: float = 1.7  ## 单位/秒 → 约 14 秒走完
static var SPEED_GROWTH: float = 0.02     ## 每波累加

static var HP_BASE: float = 55.0
## ⚠️ 不要在代码里手改这个值 —— 它由难度档位决定，见 apply_difficulty()。
##
## 这条太灵敏了：0.06 的差距能把通关率从 85% 打到 33%，根本没法当微调旋钮用。
## 正因为灵敏，它反而特别适合做「档位」—— 三个档之间的体感差距足够明显。
## 想微调难度请用别的参数（COUNT_PER_WAVE / TOWER_BASE_DAMAGE / TRACK_LENGTH / 经济）。
static var HP_GROWTH: float = 1.5
static var COUNT_BASE: int = 6
## 第 n 波数量 = COUNT_BASE + n * COUNT_PER_WAVE。
## 难度不能只靠血量几何成长——那会让前 9 波全是白送、第 10 波变成一堵翻不过的墙。
## 让数量也跟著涨，压力才会平均分布在中后段。
static var COUNT_PER_WAVE: float = 1.6
static var SPAWN_INTERVAL: float = 0.75

## 击杀赏金 = round(BASE + PER_WAVE × 波次)，逐波 4 5 6 7 8 8 9 10 11 12。
## 原本是 6 + 2×波次，配上「连杀」之后一局能滚出 7000+ 金，
## 后半局钱根本花不完 —— 击杀在数值上变成纯粹的数字在涨，没有任何取舍。
##
## 一度砍到 3 + 0.6n，但那把「盖塔」本身也砍没了：模拟里一局只盖得起 3.6 座
## （满配 8），一半塔位整局空着，「照克制调属性」自然就赢不了「平均铺」——
## 连塔都盖不满，哪来的余裕调整。3 + 0.9n 是砍掉花不完的钱、又留住建设空间的位置。
##
## PER_WAVE 用小数是故意的：整数最小步长是 1，在这个量级上一步就是 20% 的差距。
static var BOUNTY_BASE: float = 3.0
static var BOUNTY_PER_WAVE: float = 0.9
static var WAVE_CLEAR_GOLD: int = 40

## 精英怪出现的波次。属性是随机抽的（三种里任选，不跟着本波的属性走），
## 但会写进下一波预告里，所以玩家来得及准备。
static var ELITE_WAVES: Array[int] = [4, 6, 8]
static var ELITE_HP_MULT: float = 6.0
static var ELITE_BOUNTY_MULT: float = 5.0
static var ELITE_SPEED_MULT: float = 0.65

## 大 boss 固定压轴在最后一波。比精英厚得多、慢得多，漏了基本等于输。
static var BOSS_WAVE: int = 10
static var BOSS_HP_MULT: float = 14.0
static var BOSS_BOUNTY_MULT: float = 12.0
static var BOSS_SPEED_MULT: float = 0.5

## 漏怪扣命
static var LEAK_COST_NORMAL: int = 1
static var LEAK_COST_ELITE: int = 5
static var LEAK_COST_BOSS: int = 10

# ---- 波次属性构成 ----------------------------------------------------------
## 第几波开始混入第 2 / 第 3 种属性
## 1~3 波：三种属性各来一波（顺序随机）—— 逼玩家把三种塔都造一遍
## 4~6 波：三种两两组合各来一波（顺序随机）
## 7~10 波：三色混战
static var WAVE_TWO_ELEMENTS: int = 4
static var WAVE_THREE_ELEMENTS: int = 7

# ---- 奖励 ------------------------------------------------------------------
## 每波结束给几次 3 选 1
static var REWARD_ROUNDS: int = 3
static var REWARD_CHOICES: int = 3

## 免费刷新的额度和补充节奏，按难度分：
##
##   简单：每次选择都补 1 次    —— 三张都不喜欢随时能洗
##   困难：每个奖励阶段 1 次    —— 3 次选择共享，得想清楚花在哪一次
##   地狱：没有免费刷新         —— 抽到什么就是什么，想换就掏钱
##
## 每次选择都送的话等于每波白送 3 次刷新，玩家总能把不喜欢的三张洗掉，
## 「这三张里挑一张」的取舍就不存在了 —— 所以它是按难度收紧的，不是一刀切。
static var REROLL_FREE_PER_ROUND: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.HARD: 0,
	Difficulty.HELL: 0,
}
static var REROLL_FREE_PER_PHASE: Dictionary = {
	Difficulty.EASY: 0,
	Difficulty.HARD: 1,
	Difficulty.HELL: 0,
}

## 付费刷新的价格：BASE × GROWTH^(已付费次数)，再乘一个随波次走的系数 ——
## 后期金流是前期的好几倍，不跟着涨就等于免费。
##
## 原本定的 1、2、3、4、5 块钱，对上百的金流基本等于白送：
## 玩家会一直刷到出 S 卡为止，三选一就失去意义了。
## 现在第 1 波是 20 / 40 / 90 / 190，第 10 波是 40 / 80 / 170 / 350。
static var REROLL_BASE_COST: int = 20
static var REROLL_COST_GROWTH: float = 2.1
static var REROLL_WAVE_SCALE: float = 0.1

# ---- 难度档位 --------------------------------------------------------------
## 三个档只动 HP_GROWTH 一个参数。它太灵敏，不适合微调，
## 但正因为灵敏，拿来做档位反而干净 —— 一个参数就能拉开明显的体感差距，
## 而且不会牵连经济、塔价这些玩家已经熟悉的数字。
enum Difficulty { EASY, HARD, HELL }

const DIFFICULTY_HP_GROWTH: Dictionary = {
	Difficulty.EASY: 1.5,
	Difficulty.HARD: 1.55,
	Difficulty.HELL: 1.6,
}

const DIFFICULTY_NAMES: Dictionary = {
	Difficulty.EASY: "简单",
	Difficulty.HARD: "困难",
	Difficulty.HELL: "地狱",
}

static var difficulty: Difficulty = Difficulty.EASY

static func apply_difficulty(d: Difficulty) -> void:
	difficulty = d
	HP_GROWTH = DIFFICULTY_HP_GROWTH[d]

static func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]

# ---- 精英技能 --------------------------------------------------------------
## 精英一出场就放一次，之后每走完一段路再放一次。
##
## 「转弯」这个概念在规则层是不存在的（赛道形状属于表现层），所以触发点用
## **赛道进度的百分比**来定 —— 改赛道形状也不会坏，模拟器也算得出来。
## 这几个数对应蛇行赛道上出场 + 四个拐弯的大致位置。
static var ELITE_CAST_POINTS: Array[float] = [0.0, 0.22, 0.44, 0.66, 0.85]

## 施法前摇：精英/BOSS 走到触发点先停住，弹技能名，这段时间过完效果才生效。
## 没有前摇的话技能是「凭空发生」的 —— 全场突然加速、突然回满血，
## 玩家只看得到结果，来不及把它跟某只怪联系起来。
## 停住不动也给了一个窗口：在前摇结束前把它打死就能打断这次施法。
static var ELITE_CAST_WINDUP: float = 0.5

## 各难度实际会放几次（从上面的列表里取前 N 个）
## 原本是 1/3/5，但实测困难只有 3%、地狱 0/200 局 —— 不是难，是数学上不可能。
## 精英技能的压力不是线性叠加：一局有 4 场精英，5 次就是一局承受 20 次，
## 而「潮涌」是回满血，一次就把之前所有输出清零。
static var ELITE_CASTS_BY_DIFFICULTY: Dictionary = {
	Difficulty.EASY: 1,
	Difficulty.HARD: 2,
	Difficulty.HELL: 3,
}

## 火 · 浴火：全场杂兵加速，持续一段时间。火本来就快，这一下更难拦。
static var ELITE_FIRE_SPEED_PCT: float = 0.45
static var ELITE_FIRE_DURATION: float = 7.0
## 木 · 分裂：给全场杂兵挂上「死亡时分裂」。
## 只分裂一次 —— 分出来的小怪不再带这个效果，否则会指数爆炸。
## 已经带效果的怪再被挂一次也不会叠加（就是个布尔标记）。
static var ELITE_WOOD_SPLIT_COUNT: int = 2
static var ELITE_WOOD_SPLIT_HP: float = 0.5
## 分裂出来的小怪赏金也减半，不然「故意让它分裂」会变成刷钱套路
static var ELITE_WOOD_SPLIT_BOUNTY: float = 0.5
# ---- 大 BOSS ---------------------------------------------------------------
## 三段设计，每一段逼你用不同的方式打：
##   属性轮换 —— 血量每掉一段就换一种属性，逐个检验你三种塔够不够强，
##               而不是只看最强的那一种
##   召唤护卫 —— 每个触发点召一批当前属性的小怪，分散你的火力
##   死亡分裂 —— 死时裂成三只精英（火木水各一），别把资源在本体身上一次打光
static var BOSS_PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]
static var BOSS_SUMMON_COUNT: int = 3
## 召唤出来的小怪血量，按 boss 最大血量的比例算
static var BOSS_SUMMON_HP: float = 0.04
static var BOSS_SUMMON_BOUNTY: float = 0.06
## 死亡分裂出的三只精英，每只的血量（按 boss 最大血量的比例）
static var BOSS_DEATH_ELITE_HP: float = 0.10
static var BOSS_DEATH_ELITE_BOUNTY: float = 0.12

## 水 · 潮涌：全场杂兵血量回满。水的威胁就是拖时间，这一下直接把你的输出清零。
static var ELITE_WATER_HEAL_FULL: bool = true

## 当前难度每次选择补几次免费刷新（0 = 不按次补）
static func reroll_free_per_round() -> int:
	return int(REROLL_FREE_PER_ROUND.get(difficulty, 0))

## 当前难度每个奖励阶段给几次免费刷新
static func reroll_free_per_phase() -> int:
	return int(REROLL_FREE_PER_PHASE.get(difficulty, 0))

## 当前难度每波补几次免费拆除（0 = 不按波补）
static func free_sells_per_wave() -> int:
	return int(FREE_SELLS_PER_WAVE.get(difficulty, 0))

## 当前难度整局最多用几次免费拆除（-1 = 不限）
static func free_sells_total() -> int:
	return int(FREE_SELLS_TOTAL.get(difficulty, 1))

static func elite_casts() -> int:
	return int(ELITE_CASTS_BY_DIFFICULTY.get(difficulty, 1))

# ---- 模拟 ------------------------------------------------------------------
static var SIM_STEP: float = 0.05         ## 无头模拟步长（20Hz）

# ---- 塔的递增成本 ----------------------------------------------------------
## 第 n 座塔的价格 = TOWER_COST * TOWER_COST_GROWTH^n。
## 没有射程、塔位只有 8 个，如果塔很便宜，前三波就会填满、金钱从此失去意义。
## 让后面的塔越来越贵，「要不要开第 6 座」才会是一个真决策。
##
## 1.45 → 1.25：赏金砍完之后第 8 个塔位要 810，一局收入才 2183，
## 后面三个塔位等于不存在，「调整属性」连工具都没有。
## 现在八座共 1200（原本 2470），最贵的一座 290。
static var TOWER_COST_GROWTH: float = 1.25

## 把可调参数恢复成基准值（模拟扫参数后要复位，否则污染下一批）
## 所有玩家看得到的花费都过一次这个函数。
## 87 金、143 金这种数字在界面上很难读，取整到 10 的倍数之后
## 玩家一眼就能估算「我还差几座塔」。
static func round_cost(v: float) -> int:
	return maxi(10, roundi(v / 10.0) * 10)

static func reset() -> void:
	MULT_COUNTER = 3.0
	MULT_SAME = 0.55
	MULT_COUNTERED = 0.1667
	MULT_NEUTRAL_ATK = 0.30
	FREE_SELLS_PER_WAVE = {Difficulty.EASY: 1, Difficulty.HARD: 1, Difficulty.HELL: 0}
	FREE_SELLS_TOTAL = {Difficulty.EASY: -1, Difficulty.HARD: 3, Difficulty.HELL: 1}
	START_GOLD = 220
	START_LIVES = 20
	TOWER_COST = 60
	UPGRADE_COST = 60
	MAX_TOWER_LEVEL = 4
	LEVEL_COST_GROWTH = 2.0
	SKILL_REQUIRED_TOWERS = 3
	SKILL_COOLDOWN = 18.0
	SKILL_DAMAGE_PER_LEVEL = 26.0
	REWARD_POWER = 1.0
	SKILL_BURN_RATIO = 0.6
	SKILL_BURN_DURATION = 3.0
	SKILL_SLOW_PCT = 0.5
	SKILL_SLOW_DURATION = 4.0
	SKILL_ROOT_DURATION = 2.5
	TOWER_COST_GROWTH = 1.25
	TOWER_BASE_DAMAGE = 10.0
	TOWER_BASE_RATE = 1.2
	TRACK_LENGTH = 24.0
	ENEMY_BASE_SPEED = 1.7
	HP_BASE = 55.0
	difficulty = Difficulty.EASY
	HP_GROWTH = DIFFICULTY_HP_GROWTH[Difficulty.EASY]
	ELITE_CAST_POINTS = [0.0, 0.22, 0.44, 0.66, 0.85]
	ELITE_CAST_WINDUP = 0.5
	ELITE_CASTS_BY_DIFFICULTY = {
		Difficulty.EASY: 1, Difficulty.HARD: 2, Difficulty.HELL: 3,
	}
	ELITE_FIRE_SPEED_PCT = 0.45
	ELITE_FIRE_DURATION = 7.0
	ELITE_WOOD_SPLIT_COUNT = 2
	ELITE_WOOD_SPLIT_HP = 0.5
	ELITE_WOOD_SPLIT_BOUNTY = 0.5
	ELITE_WATER_HEAL_FULL = true
	BOSS_PHASE_THRESHOLDS = [0.66, 0.33]
	BOSS_SUMMON_COUNT = 3
	BOSS_SUMMON_HP = 0.04
	BOSS_SUMMON_BOUNTY = 0.06
	BOSS_DEATH_ELITE_HP = 0.10
	BOSS_DEATH_ELITE_BOUNTY = 0.12
	COUNT_BASE = 6
	COUNT_PER_WAVE = 1.6
	SPAWN_INTERVAL = 0.75
	BOUNTY_BASE = 3.0
	BOUNTY_PER_WAVE = 0.9
	WAVE_CLEAR_GOLD = 40
	REROLL_FREE_PER_ROUND = {Difficulty.EASY: 1, Difficulty.HARD: 0, Difficulty.HELL: 0}
	REROLL_FREE_PER_PHASE = {Difficulty.EASY: 0, Difficulty.HARD: 1, Difficulty.HELL: 0}
	REROLL_BASE_COST = 20
	REROLL_COST_GROWTH = 2.1
	REROLL_WAVE_SCALE = 0.1
