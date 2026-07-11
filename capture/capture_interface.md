# Capture Layer 接口说明

v1 为纯 AutoHotkey 实现，不引入 Python Worker。

统一接口：

```ahk
get_pixel(x, y)
capture_region(region)
capture()
```

## Fast

使用 `PixelGetColor` 和小区域采样，适合：

- 血条颜色
- Buff 亮灭
- 技能状态
- UI 颜色变化

## Medium

使用 AHK `ImageSearch` 和区域采样，适合：

- 图标识别
- 模板图片检测
- 简单区域变化检测

## Slow

用于低频状态确认和大区域变化扫描。

OCR、OpenCV、YOLO、特征点等能力保留到后续 Python Worker 版本。
