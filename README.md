# SDGO画面监测助手

纯 AutoHotkey v2 的 SDGO 游戏画面监测工具。它只观察屏幕和窗口画面，不读取游戏内存、不注入游戏进程、不绕过反作弊。

## 当前版本目标

- 监测 `develop` 项目配置里指定的游戏进程，默认读取 `..\develop\Data\Settings.ini`。
- 当前版本监测 `gonline.exe` 的房间大厅与战斗 HUD，不做 OCR。
- 核心输出是左侧玩家列表的 12 个可见槽位：空位、房主、已准备、未准备，并用 `★我` 标出本机玩家。
- 进入战斗后自动切换为紧凑面板，显示 READY/进行中、HP 和 SHIELD 百分比。
- AHK v2 负责窗口定位、三档调度、像素检测、图片模板检测、区域变化检测、事件系统、Overlay 和中文日志。
- 不包含 Python Worker，不包含 Python 工具模块。

## 快速启动

1. 先通过 `develop` 项目或游戏启动器启动 SDGO，并进入房间大厅。
2. 双击 `run.bat`。
3. 工具会查找 `develop\Data\Settings.ini` 当前服务端配置中的 `GameExe`，通常是 `gonline.exe`。
4. 三档任务会启动：
   - Fast：默认 16ms。
   - Medium：默认 250ms，优先监测战斗 HUD，再按场景监测房间槽位和开始按钮。
   - Slow：默认 3000ms，主要监测房间场景锚点、战斗切换和异常变化。
5. Overlay 会按场景显示房间槽位或战斗 HUD，不会同时显示两套面板。
6. 日志写入 `logs/monitor-YYYYMMDD.log` 和 `logs/events-YYYYMMDD.jsonl`。

槽位检测只在游戏位于前台时运行。切换到其他窗口后会隐藏 Overlay 并保留稳定状态；返回游戏并完成 3 帧预热后自动恢复。

本人位置通过已占用行上下两条亮青边框识别，不使用 OCR。候选需连续 3 帧且至少持续 500ms 才确认；无法可靠区分时 Overlay 显示 `本人：待确认`。本人行格式为 `01号 房主 ★我`，槽位序号统一显示为 `01号` 至 `12号`。

修改 `.ahk`、`config\monitor.ini` 或 `config\elements.csv` 后，按全局快捷键 `Ctrl+Alt+F12` 完整重载助手。日志会记录快捷键触发、新会话 ID、代码版本和实际槽位区域。

`tools\demo_target.ahk` 只是开发测试窗口，启动主程序时不会自动运行。需要测试时可手动双击 `run_demo.bat`。

## 房间大厅关键画面识别项

默认 `config\elements.csv` 包含：

- `combat_hud`：联合检测 HP 框、比分框和雷达，并读取 HP、SHIELD 与 READY。
- `room_slots`：固定读取左侧玩家列表 12 个可见槽位。
- `start_button`：识别右下角 `+F5 开始` 按钮，辅助判断房间可操作状态。
- `room_scene_anchor`：识别房间大厅场景锚点，并直接控制房间检测的启用与暂停，避免在其他界面误判。
- `room_area_change`：记录玩家列表区域变化，辅助发现异常遮挡或状态刷新。

战斗场景至少需要三个 HUD 锚点中的两个。确认进入战斗后会立即暂停所有 `ROOM` 元素；退出后，`room_scene_anchor` 必须连续匹配 2 次才会恢复房间检测。锚点连续 2 次未匹配会暂停房间检测，槽位是否有人不再决定场景。HP 或 SHIELD 色条证据不足时显示 `--`，不会误报为 `0%`。

槽位状态枚举：

- `EMPTY`：空位。
- `MASTER`：房主。
- `READY`：已准备。
- `NOT_READY`：有人但未准备。
- `UNKNOWN`：未知状态。

## 配置目标游戏进程

编辑 `config\monitor.ini`：

```ini
[develop]
settings_path=..\develop\Data\Settings.ini

[window]
target_exe=
target_title=
reference_width=1040
reference_height=807
auto_launch_demo=false
```

`elements.csv` 的区域坐标以 `1040x807` 游戏窗口外框为基准，并按实际窗口尺寸缩放。
12 槽列表使用基准高度 `228px`，在 `2080x1614` 窗口中对应 `456px`，每个槽位高 `38px`。

### 双分辨率与模板档案

Monitor v2.1.0 区分以下三个概念：

- **物理桌面分辨率**：Windows 主显示器当前输出的物理像素，例如 `1920x1080` 或 `2880x1800`；仅用于选择图片模板档案。
- **DPI 缩放**：Windows 的界面缩放比例，例如 100% 或 200%；不参与模板文件名和检测坐标计算。
- **游戏客户区**：不含标题栏和边框的游戏画面。战斗 HUD 以 `1024x768` 为基准按客户区宽高分别缩放；典型高 DPI 客户区约为 `2048x1536`。

房间槽位、开始按钮和房间锚点仍以 `1040x807` 游戏窗口外框为坐标基准。图片检测会按以下顺序解析模板：

1. `<模板名>_<主屏物理宽度>x<主屏物理高度>.png`
2. `elements.csv` 中配置的原始无后缀模板

因此，1920×1080 主屏优先使用 `*_1920x1080.png`；2880×1800 主屏在没有专用档案时安全回退原模板。游戏应运行在主显示器上，模板档案不会跟随副显示器上的游戏窗口。

`target_exe` 留空时，会按以下顺序读取：

1. `develop\Data\Settings.ini` 的 `[Game] ServerProfile`
2. 对应 `[Server.<Profile>]` 的 `GameExe`
3. `[General] GameExe`
4. 默认 `gonline.exe`

如果要临时覆盖目标进程，可直接写：

```ini
target_exe=gonline.exe
```

## 配置画面识别项

编辑 `config\elements.csv`。字段固定为：

```csv
id,enabled,lane,method,capture_type,region_x,region_y,region_w,region_h,template_path,color_hex,tolerance,threshold,debounce_ms,cooldown_ms,event_type,overlay,scene
```

常用字段说明：

- `lane`：`fast`、`medium`、`slow`。
- `method`：`color`、`image`、`change`、`room_slots`、`combat_hud`。
- `capture_type`：`pixel` 或 `region`。
- `region_x/y/w/h`：相对游戏窗口左上角的检测区域。
- `template_path`：图片模板路径，可引用 `..\develop\Data\Images\*.png`。
- `color_hex`：目标颜色，例如 `0xFFFFFF`。
- `tolerance`：颜色或图片搜索容差，0-255。
- `threshold`：变化检测阈值，0-1。
- `debounce_ms`：状态变化确认时间。
- `cooldown_ms`：同类事件冷却时间。
- `event_type`：`ANY`、`ON_APPEAR`、`ON_DISAPPEAR`、`ON_CHANGE`、`ON_STABLE`。
- `overlay`：是否显示覆盖层。
- `scene`：`ANY`、`ROOM` 或 `COMBAT`，用于场景切换时暂停不适用元素。

## 中文日志

普通日志使用中文：

```text
2026-07-08 12:00:00.016 [事件] 房间槽位 3 状态变化：未准备 → 已准备，耗时 3ms
```

JSONL 日志保留英文机器字段，同时提供中文字段：

```json
{"ts":"2026-07-08 12:00:00.016","id":"room_slots","event":"ON_CHANGE","event_zh":"变化","message_zh":"房间槽位 3 状态变化：未准备 → 已准备，耗时 3ms","matched":true,"score":1.000000,"slot_index":3,"state":"READY","state_zh":"已准备","previous_state":"NOT_READY","previous_state_zh":"未准备","latency_ms":3}
```

## 测试

语法检查：

```bat
"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" main.ahk --check
```

自检：

```bat
"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\smoke_test.ahk
```

模板档案与双尺寸目标/锁定检测：

```bat
"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\image_template_resolution_test.ahk
"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\combat_target_detector_test.ahk
```

使用战斗截图校准（第二个参数是截图内客户端顶部位置）：

```bat
"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\combat_screenshot_test.ahk screenshot.png 61
```

手动测试建议：

1. 启动游戏并进入房间大厅。
2. 启动本工具。
3. 确认 Overlay 显示 12 个槽位状态。
4. 改变玩家准备状态，确认中文日志出现“变化”事件。
5. 进入战斗，确认 `combat_anchor` 出现事件。

## 安全边界

本项目只监测屏幕像素和窗口区域，不读取游戏内存、不注入进程、不绕过反作弊。不同游戏对截图和覆盖层的兼容性不同，独占全屏模式不作为 v2.1.0 验收目标。
