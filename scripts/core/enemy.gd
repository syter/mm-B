class_name Enemy
extends RefCounted

var element: Types.Element = Types.Element.NONE
var max_hp: float = 0.0
var hp: float = 0.0
var base_speed: float = 0.0
var bounty: int = 0
var is_elite: bool = false
## 大 boss。同时也算精英（表现层的金圈、漏怪惩罚都沿用精英那一套再加码）。
var is_boss: bool = false

## 沿路径走过的距离，抵达 TRACK_LENGTH 即漏怪
var distance: float = 0.0
var slow_timer: float = 0.0
var alive: bool = true

## 技能造成的状态。跟奖励的减速分开存，两者取较重的那个生效。
var burn_time: float = 0.0      ## 火：灼烧剩余时间
var burn_dps: float = 0.0
var burn_acc: float = 0.0       ## 跳伤累积器，每 0.2 秒结算一次
var root_time: float = 0.0      ## 木：缠绕，完全定身
var skill_slow_time: float = 0.0
var skill_slow_pct: float = 0.0

## 精英技能：被「浴火」加速
var haste_time: float = 0.0
var haste_pct: float = 0.0
## 精英自己用：已经放到第几个触发点了
var cast_index: int = 0
## 施法前摇剩余时间。> 0 期间完全不动，走完了技能才真的生效；
## 在这段时间里被打死的话这次施法就没了 —— 那是留给玩家的打断窗口。
var cast_time: float = 0.0
## 木精英挂的「死亡时分裂」。分出来的小怪不带这个标记，所以只会分裂一次。
var split_on_death: bool = false
## BOSS 专用：已经切换到第几个阶段
var phase: int = 0

## 是否被定身
func is_rooted() -> bool:
	return root_time > 0.0

func _init(element_: Types.Element, hp_: float, speed_: float, bounty_: int,
		elite: bool = false, boss: bool = false) -> void:
	element = element_
	max_hp = hp_
	hp = hp_
	base_speed = speed_
	bounty = bounty_
	is_elite = elite or boss
	is_boss = boss

func speed() -> float:
	return base_speed * (1.0 + (haste_pct if haste_time > 0.0 else 0.0))

func leak_cost() -> int:
	if is_boss:
		return Balance.LEAK_COST_BOSS
	return Balance.LEAK_COST_ELITE if is_elite else Balance.LEAK_COST_NORMAL

## 返回是否被这次伤害打死
func take_damage(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false
