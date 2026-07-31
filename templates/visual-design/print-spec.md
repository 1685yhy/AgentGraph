---
agent: ui-designer
consumes: []
produces: print-specification
format: markdown
acceptance:
  - 包含尺寸/出血/安全区/色彩模式
  - 包含文件格式+命名规范
handoff_to: brand-guardian
---

# 印刷规格

## 通用规格
- 出血: 3mm (标准)
- 安全区: 距离边缘 ≥ 5mm
- 分辨率: ≥ 300 DPI
- 色彩模式: CMYK (印刷) / RGB (屏幕)

## 文件格式
- 交付: AI/EPS/PDF (矢量优先)
- 预览: JPG/PNG

## 命名规范
`[项目名]_[物料类型]_[尺寸]_[版本].[扩展名]`
例如: `brand_poster_A3_v2.pdf`
