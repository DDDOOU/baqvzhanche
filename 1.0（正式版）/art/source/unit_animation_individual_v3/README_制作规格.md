# 单位动画 V3 制作规格（T-72B 基准）

## 固定输出

- 每个单位分别制作，不再从多人合集裁切，也不再由其他兵种换色派生。
- 移动图：128×128 PNG，4列×4行，每帧32×32。
- 攻击图：128×128 PNG，4列×4行，每帧32×32。
- 行方向固定为：东南、西南、西北、东北。
- 地面接触点固定为单帧坐标 `(16,29)`。
- 透明背景、近黑色1像素轮廓、6—8个主色、无抗锯齿、无平滑渐变、无细碎高分辨率纹理。
- T-72B 的移动与攻击图是唯一清晰度和像素颗粒基准，不重新生成。

## 通用生成提示词

```text
Production-ready 2.5D isometric pixel-art game sprite master. The referenced T-72B 128x128 sheet is the ONLY style authority for pixel density, chunky color clusters, near-black 1-pixel outline, camera angle, sprite scale, fixed bottom-center ground contact, exact 4x4 layout and direction order.

Transparent background. Exact 4 columns x 4 rows, no gutters, labels, grid, text, checkerboard or extras. Rows exactly southeast, southwest, northwest, northeast. Columns are four subtle movement frames. Keep the same unit identity, proportions, equipment and camera in all 16 cells. Each logical frame is 32x32; the subject fills the frame like the T-72B and touches the fixed ground contact at logical pixel (16,29). Use only 6-8 main colors. No antialiasing, blur, smooth gradients or high-resolution microtexture. The unit must remain immediately recognizable at native 32x32.

Unit-specific silhouette: [在这里填写兵种名称、关键武器、底盘/人数、阵营颜色与识别标记].
```

## 项目内重建

母版放入本目录，文件名为 `<单位id小写>_master.png`，然后运行：

```powershell
.\tools\rebuild_all_units_t72_quality.ps1
```

只重建一个单位：

```powershell
.\tools\rebuild_all_units_t72_quality.ps1 -UnitId M2_IFV
```

脚本会输出至 `assets/units/animated/all_units_v2/`，并始终恢复、保护已确认的 T-72B 原图。
