# 怎么把游戏发给朋友

## 方案 A：Windows 单文件（朋友要下载 45MB）

`属性塔防-windows.zip` → 解压出一个 `属性塔防.exe`，**双击就能玩**，
不用装 Godot、不用装运行库，整个游戏（代码、素材、字体）都打包在里面了。

> **朋友第一次打开会被 Windows 拦。** 因为 exe 没有花钱买代码签名证书，
> SmartScreen 会弹「Windows 已保护你的电脑」。
> 让他点 **「更多信息」→「仍要运行」** 就行。
> 这是所有独立开发者的免签名程序都会遇到的，不是这个游戏有问题。

## 方案 B：网页版（朋友点个链接就能玩）

`属性塔防-web.zip` 是一个完整的网页版，**不挑系统**，手机也能开（虽然没适配触屏）。

最省事的托管方式是 **itch.io**（免费）：

1. 注册 itch.io → Dashboard → Create new project
2. **Kind of project** 选 `HTML`
3. 把 `属性塔防-web.zip` 整个上传，勾上 **This file will be played in the browser**
4. Embed options 里设成 **1280 × 720**，勾 Fullscreen button
5. Viewable 设成 Public（或者 Restricted 只发给有链接的人）
6. 发布，把链接甩给朋友

> 已经关掉了多线程支持，所以**不需要**服务器配 COOP/COEP 跨域隔离头 ——
> 丢到任何静态托管（itch.io / GitHub Pages / Vercel）都能跑。

## 推荐哪个

**发链接（方案 B）**。朋友不用下载、不用过 SmartScreen、Mac 用户也能玩。
Windows 版留给想离线玩或者网页卡的人。

## 重新导出

```bash
./build.sh          # 两个都打（约 15 秒）
./build.sh win      # 只打 Windows
./build.sh web      # 只打网页版
```

产物是 `build/属性塔防-v<版本>-windows.zip` 和 `-web.zip`，
版本号读 `project.godot` 里的 `config/version`，发新版改那一行就行。

脚本会**先跑一遍回归测试，没过就拒绝打包**（真要强行打加 `--skip-tests`）。
导出模板没装的话也会提前拦住，并告诉你去哪下、放哪。

需要先装导出模板（1.28GB，Godot 默认不带）：
从 https://github.com/godotengine/godot/releases/tag/4.7.2-stable
下载 `Godot_v4.7.2-stable_export_templates.tpz`，
解压到 `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`。
