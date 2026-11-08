---
title: Liquid Glass 设计说明
subtitle: MD Viewer 的界面是怎么搭出来的
---

# Liquid Glass 设计说明

MD Viewer 使用 **iOS 26 原生玻璃 API**，而不是一张张半透明图片。这意味着玻璃会实时折射背后的颜色、随环境明暗自适应，并在控件聚合时产生形变过渡。

## 材质层级

| 层级 | API | 用途 |
| :--- | :--- | :--- |
| 背景 | `MeshGradient` | 提供可被折射的色彩 |
| 容器 | `GlassEffectContainer` | 让相邻玻璃共享高光与间距 |
| 控件 | `.glassEffect(_:in:)` | 按钮、卡片、工具栏 |
| 按钮 | `.buttonStyle(.glass)` / `.glassProminent` | 按压时的弹性反馈 |
| 形变 | `.glassEffectID(_:in:)` + `Namespace` | 面板展开 / 收起的 morph |

```swift
@Namespace private var glass

GlassEffectContainer(spacing: 16) {
    if expanded {
        AppearancePanel()
            .glassEffect(.regular.tint(.indigo.opacity(0.12)).interactive(),
                         in: .rect(cornerRadius: 28))
            .glassEffectID("appearance", in: glass)
    } else {
        Button { withAnimation(.bouncy) { expanded = true } } label: {
            Label("排版", systemImage: "textformat.size")
        }
        .buttonStyle(.glass)
        .glassEffectID("appearance", in: glass)
    }
}
```

> `GlassEffectContainer` 里的玻璃元素会互相「感知」：靠得足够近时自动合并边缘高光，这是单独加 `blur` 永远做不出来的效果。

## 为什么不用 WebView

- [x] 原生 `AttributedString` 让 **Dynamic Type**、文本选择、链接跳转全部免费获得
- [x] 代码块可以单独放复制按钮，表格可以横向滚动
- [x] 深色模式、无障碍对比度由系统统一管理
- [x] 渲染结果与系统控件共享同一套玻璃材质栈
- [ ] 代价：需要自己实现 Markdown 解析器

解析器是一个 **两阶段流水线**：

1. 逐行扫描，产出 `MarkdownBlock` 序列（标题、段落、列表、引用、代码块、表格）
2. 行内扫描，把 `**粗体**`、`[链接]()` 等转成 `InlineNode`，再折叠成 `AttributedString`

```
source.md ──▶ BlockParser ──▶ [MarkdownBlock]
                                   │
                                   ▼
                            InlineParser ──▶ AttributedString ──▶ Text()
```

## 用到的系统框架

- **SwiftUI** — 界面、导航、玻璃材质、MeshGradient
- **UniformTypeIdentifiers** — `.md` 文档类型声明与文件导入
- **Foundation** — `AttributedString`、`FileManager`、`Codable` 持久化
- **UIKit** — `UIPasteboard`、`UIFontMetrics`、`UIImpactFeedbackGenerator`
- **Observation** — `@Observable` 资料库状态

---

*版本 1.0 · 需要 iOS 26 或更高版本*
