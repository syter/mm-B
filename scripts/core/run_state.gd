class_name RunState
extends RefCounted

## 一局游戏的完整状态：10 波，波间 3 次 3 选 1。
## 纯规则层，不碰场景树；UI 只读不写。

var rng: RandomNumberGenerator
var gold: int = Balance.START_GOLD
var lives: int = Balance.START_LIVES
var towers: Array[Tower] = []
var mods: Modifiers = Modifiers.new()
var waves: Array[Wave] = []
## 下一波要打的波次（1 起算）
var wave_index: int = 1
var finished: bool = false
var won: bool = false
## 整局还剩几次免费拆除（全额返还）。用完就没了，不会每波恢复。
var free_sells: int = Balance.FREE_SELLS_PER_RUN
## 当前正在进行的战斗；BUILD/REWARD 阶段为 null
var battle: Battle = null
## 本波已经即时拨进金库的赏金，避免波末结算时重复计算
var _gold_synced: int = 0
## 每个奖励领了几次（id -> 次数）。奖励可重复领取，光看总加成看不出来源。
var taken: Dictionary = {}
## 各属性技能的剩余冷却（秒）。每波开始归零＝开场就能放。
var skill_cd: Dictionary = {}
## 本轮三选一已经刷新过几次。每轮重置，第一次免费、之后越刷越贵。
var reroll_count: int = 0

func _init(seed_value: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var plan: Array = Wave.plan_elements(rng)
	for i: int in range(1, Balance.TOTAL_WAVES + 1):
		waves.append(Wave.generate(i, rng, plan[i - 1]))

# ---- 查询 ------------------------------------------------------------------

func current_wave() -> Wave:
	if wave_index < 1 or wave_index > waves.size():
		return null
	return waves[wave_index - 1]

## 下一波预告（玩家在建塔阶段看得到）
func preview() -> String:
	var w: Wave = current_wave()
	return w.preview() if w != null else "—"

func used_slots() -> Array[int]:
	var out: Array[int] = []
	for t: Tower in towers:
		out.append(t.slot)
	return out

func free_slot() -> int:
	var used: Array[int] = used_slots()
	for i: int in Balance.MAX_TOWERS:
		if not used.has(i):
			return i
	return -1

func tower_at(slot: int) -> Tower:
	for t: Tower in towers:
		if t.slot == slot:
			return t
	return null

func count_of(element: Types.Element) -> int:
	var n: int = 0
	for t: Tower in towers:
		if t.element == element:
			n += 1
	return n

# ---- 建造 ------------------------------------------------------------------

## 第 slot 号塔位的价格。价格绑在塔位上而不是绑在「已有几座塔」上——
## 后者会让「拆掉早期的便宜塔、原位重建」要付最贵那一档的价，白亏几百块，
## 属性重组在数值上就不成立了。绑塔位的话，拆了原位重建刚好不赚不亏。
func tower_cost(slot: int) -> int:
	return Balance.round_cost(float(Balance.TOWER_COST) * pow(Balance.TOWER_COST_GROWTH, float(slot)))

## 下一座要盖的塔多少钱（塔位满了返回 -1）
func next_tower_cost() -> int:
	var slot: int = free_slot()
	if slot < 0:
		return -1
	var cost: int = tower_cost(slot)
	if mods.build_discount_charges > 0:
		cost = Balance.round_cost(float(cost) * 0.5)
	return cost

func can_build() -> bool:
	var slot: int = free_slot()
	return slot >= 0 and gold >= next_tower_cost()

func build_tower() -> Tower:
	if not can_build():
		return null
	var slot: int = free_slot()
	var cost: int = tower_cost(slot)
	# 奠基：攒着的半价券在这里花掉
	if mods.build_discount_charges > 0:
		mods.build_discount_charges -= 1
		cost = Balance.round_cost(float(cost) * 0.5)
	gold -= cost
	var t: Tower = Tower.new(slot, cost)
	towers.append(t)
	return t

## 升级费用（含「精炼」折扣）
func upgrade_cost() -> int:
	return Balance.round_cost(float(Balance.UPGRADE_COST) * (1.0 - mods.effective_upgrade_discount()))

## 练级到下一级的费用。Lv1→2 约 99、2→3 约 178、3→4 约 320。
func level_up_cost(slot: int) -> int:
	var t: Tower = tower_at(slot)
	if t == null or not t.can_level_up():
		return -1
	var base: float = float(Balance.UPGRADE_COST) * pow(Balance.LEVEL_COST_GROWTH, float(t.level))
	return Balance.round_cost(base * (1.0 - mods.effective_upgrade_discount()))

## 升级成属性塔。升过就不能再改属性，只能拆掉重建。
func upgrade_tower(slot: int, to: Types.Element) -> bool:
	var t: Tower = tower_at(slot)
	if t == null or t.is_upgraded() or to == Types.Element.NONE:
		return false
	if mods.free_upgrades > 0:
		mods.free_upgrades -= 1
		t.upgrade(to, 0)
		return true
	var cost: int = upgrade_cost()
	if gold < cost:
		return false
	gold -= cost
	t.upgrade(to, cost)
	return true

## 属性塔继续练级，每级多一个全额伤害的攻击目标
func level_up_tower(slot: int) -> bool:
	var t: Tower = tower_at(slot)
	if t == null or not t.can_level_up():
		return false
	var cost: int = level_up_cost(slot)
	if gold < cost:
		return false
	gold -= cost
	t.level_up(cost)
	return true

# ---- 技能 ------------------------------------------------------------------

## 该属性有几座塔
func towers_of(e: Types.Element) -> int:
	return count_of(e)

## 该属性所有塔的等级总和。技能威力挂钩这个，所以「练精一种属性」有回报。
func element_levels(e: Types.Element) -> int:
	var n: int = 0
	for t: Tower in towers:
		if t.element == e:
			n += t.level
	return n

func skill_unlocked(e: Types.Element) -> bool:
	return count_of(e) >= Balance.SKILL_REQUIRED_TOWERS

func skill_remaining(e: Types.Element) -> float:
	return maxf(float(skill_cd.get(e, 0.0)), 0.0)

func skill_ready(e: Types.Element) -> bool:
	return battle != null and skill_unlocked(e) and skill_remaining(e) <= 0.0

## 技能伤害（还没乘属性克制倍率，那一步在 Battle 里做）
func skill_damage(e: Types.Element) -> float:
	return Balance.SKILL_DAMAGE_PER_LEVEL * float(element_levels(e)) * (1.0 + mods.skill_power)

func skill_cooldown() -> float:
	return Balance.SKILL_COOLDOWN * (1.0 - mods.effective_skill_cd_cut())

func use_skill(e: Types.Element) -> bool:
	if not skill_ready(e):
		return false
	battle.cast_skill(e, skill_damage(e))
	skill_cd[e] = skill_cooldown()
	return true

## 拆塔。整局前 FREE_SELLS_PER_RUN 次全额返还，之后按 REFUND_RATE 打折。
func sell_tower(slot: int) -> bool:
	var t: Tower = tower_at(slot)
	if t == null:
		return false
	if free_sells > 0:
		free_sells -= 1
		gold += t.invested
	else:
		gold += t.refund_value()
	towers.erase(t)
	return true

## 这次拆除能拿回多少（UI 显示用）
func sell_value(slot: int) -> int:
	var t: Tower = tower_at(slot)
	if t == null:
		return 0
	return t.invested if free_sells > 0 else t.refund_value()

# ---- 推进 ------------------------------------------------------------------

## 开始当前这一波，返回可逐帧 step 的 Battle。UI 用这个。
func begin_wave() -> Battle:
	var w: Wave = current_wave()
	if w == null or finished:
		return null
	battle = Battle.new(w, towers, mods, rng)
	_gold_synced = 0
	# 每波开场技能都是就绪的，不用背著上一波的冷却
	for el: Types.Element in Types.ELEMENTAL:
		skill_cd[el] = 0.0
	return battle

## 推进战斗一小步。技能冷却也跟著走，所以 UI 和模拟器都该走这个入口，
## 而不是直接 battle.step()。
func step_battle(dt: float) -> void:
	if battle == null:
		return
	battle.step(dt)
	for el: Types.Element in Types.ELEMENTAL:
		skill_cd[el] = maxf(0.0, float(skill_cd.get(el, 0.0)) - dt)

## 把战斗中已经赚到的赏金即时拨进金库。
## 不这样做的话，波次进行中的金钱只是个显示数字，玩家看得到却花不了，
## 「打到一半补一座塔」就无从谈起。
func sync_gold() -> void:
	if battle == null:
		return
	gold += battle.gold_earned - _gold_synced
	_gold_synced = battle.gold_earned

## 结算已经打完的那一波。
func end_wave() -> Dictionary:
	if battle == null:
		return {}
	var result: Dictionary = {
		"killed": battle.killed,
		"leaked": battle.leaked,
		"lives_lost": battle.lives_lost,
		"gold_earned": battle.gold_earned,
		"damage": battle.damage_total,
		"duration": battle.time,
	}
	battle = null
	return _settle(result)

## 一口气打完当前这一波（无头模拟用），返回统计。
func play_wave() -> Dictionary:
	if begin_wave() == null:
		return {}
	var guard: int = 0
	while not battle.is_finished() and guard < 100000:
		step_battle(Balance.SIM_STEP)
		guard += 1
	return end_wave()

func _settle(result: Dictionary) -> Dictionary:
	# 已经即时拨过的部分不能再算一次
	gold += int(result["gold_earned"]) - _gold_synced
	_gold_synced = 0
	lives -= int(result["lives_lost"])

	if lives <= 0:
		lives = 0
		finished = true
		won = false
		result["over"] = true
		return result

	# 回春：撑过这一波才回血，不能靠它把已经归零的命救回来
	if mods.regen_per_wave > 0:
		lives += mods.regen_per_wave
	gold += Balance.WAVE_CLEAR_GOLD
	var interest: int = floori(float(gold) * mods.effective_interest())
	gold += interest
	result["interest"] = interest

	wave_index += 1
	if wave_index > Balance.TOTAL_WAVES:
		finished = true
		won = true
	result["over"] = finished
	return result

# ---- 奖励 ------------------------------------------------------------------

## 开一轮新的三选一（刷新次数归零）
func begin_reward_round() -> Array[Reward]:
	reroll_count = 0
	return roll_rewards()

## 按当前存款算，这一波结束能拿到多少利息。
## 玩家要决定「这笔钱是现在花掉还是留着生息」，没有这个数字就只能瞎猜。
func interest_preview() -> int:
	return floori(float(gold) * mods.effective_interest())

## 这次刷新要多少钱。每轮头 REROLL_FREE_PER_ROUND 次免费，
## 之后指数递增，并随波次放大 —— 后期金流是前期好几倍，不跟着涨就等于免费。
func reroll_cost() -> int:
	var paid: int = reroll_count - Balance.REROLL_FREE_PER_ROUND
	if paid < 0:
		return 0
	var base: float = float(Balance.REROLL_BASE_COST) \
		* pow(Balance.REROLL_COST_GROWTH, float(paid))
	var wave_scale: float = 1.0 + Balance.REROLL_WAVE_SCALE * float(wave_index - 1)
	return Balance.round_cost(base * wave_scale)

func can_reroll() -> bool:
	return gold >= reroll_cost()

func reroll_rewards() -> Array[Reward]:
	if not can_reroll():
		return []
	gold -= reroll_cost()
	reroll_count += 1
	return roll_rewards()

## 抽一轮 3 选 1。稀有度同时决定卡片颜色和抽中的权重——
## S 如果和 C 一样常见，那个 S 就不值钱了。
func roll_rewards(k: int = Balance.REWARD_CHOICES) -> Array[Reward]:
	var candidates: Array[Reward] = Reward.pool().filter(
		func(r: Reward) -> bool: return r.is_available(self))
	var out: Array[Reward] = []
	while out.size() < k and candidates.size() > 0:
		var total: float = 0.0
		for r: Reward in candidates:
			total += r.weight()
		var roll: float = rng.randf() * total
		var idx: int = candidates.size() - 1
		for i: int in candidates.size():
			roll -= candidates[i].weight()
			if roll <= 0.0:
				idx = i
				break
		out.append(candidates[idx])
		candidates.remove_at(idx)
	return out

func take_reward(r: Reward) -> void:
	taken[r.id] = int(taken.get(r.id, 0)) + 1
	r.apply(self)

## 已领取的奖励，按次数由多到少：[{id, title, count}]
func taken_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in taken.keys():
		var r: Reward = Reward.by_id(id)
		out.append({
			"id": id,
			"title": r.title if r != null else id,
			"count": int(taken[id]),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		return String(a["title"]) < String(b["title"]))
	return out

## 总共领了几次奖励
func taken_count() -> int:
	var n: int = 0
	for c: int in taken.values():
		n += c
	return n

func status() -> String:
	var by_el: Array[String] = []
	for e: Types.Element in [Types.Element.NONE] + Types.ELEMENTAL:
		var c: int = count_of(e)
		if c > 0:
			by_el.append("%s%d" % [Types.name_of(e), c])
	return "波%d 金%d 命%d 塔[%s]" % [wave_index, gold, lives, "/".join(by_el)]
