---
title: 欢迎使用 MD Viewer
author: MD Viewer Team
version: 1.2
tags: 指南 · Liquid Glass · Markdown
---

# 欢迎使用 **MD Viewer**

一款为 **iOS 26 Liquid Glass** 而生的 Markdown 阅读器。玻璃会折射背后的色彩，控件会随内容流动、聚合、形变——而文字，始终清晰可读。

> 好的界面不该抢走内容的注意力。它应该像玻璃一样：**存在，但不遮挡**。

---

## 三种打开方式

1. 点按资料库右上角的 **导入**，从「文件」App 里选择 `.md`
2. 在「文件」App 中长按文档 → **共享 → MD Viewer**
3. 通过 Finder / iTunes 文件共享，把文件放进 App 的 `Documents` 目录

支持 `md`、`markdown`、`mdown`、`mkd`、`txt` 等后缀，也支持 **YAML front matter**、GFM 表格与任务列表。

## 阅读体验

| 功能 | 说明 | 快捷键 / 位置 |
| :--- | :--- | :---: |
| 目录跳转 | 自动抽取 H1–H6 | 底部玻璃栏 |
| 全文搜索 | 命中高亮 + 逐个跳转 | 放大镜 |
| 排版调节 | 字号 / 行距 / 主题 | Aa 面板 |
| 分享与复制 | 原文、纯文本、代码块 | 右上角 |

- [x] 原生 SwiftUI 渲染，不依赖 WebView
- [x] 支持 `AttributedString` 级别的链接与行内样式
- [ ] 支持 Mermaid 图表（规划中）
- [ ] 支持导出 PDF（规划中）

## 一段代码

下面是本 App 里添加玻璃效果的核心代码：

```swift
GlassEffectContainer(spacing: 14) {
    Button("目录") { showOutline = true }
        .buttonStyle(.glass)
        .glassEffectID("outline", in: namespace)
}

Text(content)
    .glassEffect(
        .regular.tint(.indigo.opacity(0.14)).interactive(),
        in: .rect(cornerRadius: 22)
    )
```

也可以用 `UIGlassEffect` 在 UIKit 侧做同样的事：

```objectivec
UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
effect.tintColor = [UIColor systemIndigoColor];
UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
```

## 行内样式全家桶

**粗体**、*斜体*、***粗斜体***、`行内代码`、~~删除线~~、[外部链接](https://www.apple.com)、<https://swift.org>，以及换行  
这一行是硬换行后的结果。

> ### 引用里也可以有标题
>
> 甚至可以有列表：
>
> - 第一项
> - 第二项，**带粗体**
>
> > 还支持嵌套引用。

![界面示意图](assets/glass-preview.png)

---

*祝你阅读愉快。* —— 试试从资料库打开「Markdown 语法速查」。
