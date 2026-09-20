# 塔防原型（暂定名）

塔防游戏，**Godot 4.7** + GDScript 开发。

>  玩法方向已定：**固定路径 + 属性克制**，一局 10 波，波间 3 次 3 选 1。
> 塔可练级（每级多一个攻击目标），同属性凑满 3 座解锁全屏技能。
> 规则、数值与平衡结论见 [`DESIGN.md`](DESIGN.md)。
> 核心规则层、模拟器、可玩的界面都已跑通，一局游戏能完整打完。

## 快速开始

需要 **Godot 4.7+**。

```bash
# 打开编辑器
godot --editor --path .

# 切换 UI 风格跑（classic / polish / scifi / pixel）
godot --path . -- scifi

# 把四种风格各截一套图（输出在 user:// 下）
for s in classic polish scifi pixel; do
  godot --path . --script res://tests/tools/capture.gd -- $s
done

# 跑回归测试（带断言）
godot --headless --path . --script res://tests/regression/test_core.gd      # 核心规则 65 条
godot --headless --path . --script res://tests/regression/test_ui_smoke.gd  # 界面冒烟 69 条

# 跑平衡模拟
godot --headless --path . --script res://tests/sim/sim_trace.gd     # 单局逐波明细
godot --headless --path . --script res://tests/sim/sim_curve.gd     # 难度曲线扫参数
godot --headless --path . --script res://tests/sim/sim_power.gd     # 塔等级/技能的平衡扫参数

# 截图（终端截不了屏，让游戏自己截各阶段画面）
godot --path . --script res://tests/tools/capture.gd
```

新增 `class_name` 之后要先 `godot --headless --path . --import` 注册全局类，
否则无头脚本会报 "Could not find type"。

## 目录

```
scripts/
├── core/     引擎无关的纯规则，可脱离 UI 单独跑
│   ├── balance.gd     全部可调数值，改平衡只动这个文件
│   ├── types.gd       属性与克制关系
│   ├── modifiers.gd   奖励叠加后的全局修正（含封顶）
│   ├── tower.gd       塔
│   ├── enemy.gd       怪物
│   ├── wave.gd        波次生成
│   ├── battle.gd      一波战斗的 tick 推进
│   ├── reward.gd      3 选 1 奖励池
│   └── run_state.gd   一局的完整状态
├── ai/       脚本玩家（平衡模拟用的「中等水平玩家」替身）
└── ui/       界面
    ├── palette.gd  配色与中文字型
    ├── sfx.gd      程序合成的音效，不依赖外部素材
    └── game.gd     主界面：绘制、输入、阶段切换
scenes/
└── main.tscn    主场景
tests/
├── regression/  带断言的回归测试，改坏了会红
├── sim/         一次性平衡实验，结论写回 DESIGN.md
└── tools/       开发工具（截图等）
```

## 工程约定

沿用姊妹项目 `mm-A` 验证过的那套，这几条是有教训的，不是照抄模板：

**1. 规则逻辑不依赖场景树**

核心规则全部继承 `RefCounted` 而非 `Node`，整套逻辑能脱离引擎和画面运行。
塔防的数值平衡（塔的 DPS 曲线、波次强度、经济曲线）必须靠批量模拟验证，
挂在场景树上就没法跑无头模拟了。

**2. 规则与表现分离，单向数据流**

UI 只读规则的结果，不反向修改规则状态。

**3. 模拟器先行**

任何平衡改动都先写个 `tests/sim_*.gd` 跑数据，**结论写回 DESIGN.md**，
再决定要不要改规则。参数不靠拍脑袋。

**4. 随机数由外部注入，固定种子**

调用方传 `RandomNumberGenerator` 进来，模拟器一律用固定种子。
可复现是排查玩家 bug 和做每日挑战的前提。

**5. 实验脚本和回归测试分开放**

`tests/regression/` 放带断言的回归测试，`tests/sim/` 放一次性平衡实验，
别像 mm-A 那样混到最后谁也分不清哪个还算数。

## 导出与分享

把游戏发给别人玩（Windows 单文件 / 网页版）见 [`DEPLOY.md`](DEPLOY.md)。

```bash
./build.sh          # Windows exe + 网页版，各自压成带版本号的 zip
./build.sh win      # 只打 Windows
```

脚本会先跑回归测试，没过就拒绝打包。

> `export_presets.cfg` 在 `.gitignore` 里（那个文件可能装签名密钥），
> 所以克隆下来之后要自己在编辑器里建导出预设，或者照 `DEPLOY.md` 配。

## 许可

暂未确定。
