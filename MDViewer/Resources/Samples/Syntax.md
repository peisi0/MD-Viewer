# Markdown 语法速查

> 这份文档本身就是一份测试用例：MD Viewer 的解析器会逐行读取它，并渲染成本页你看到的样子。

## 1. 标题

```
# 一级标题
## 二级标题
### 三级标题
#### 四级标题
##### 五级标题
###### 六级标题
```

也可以用 Setext 写法：

```
标题一
=======
标题二
-------
```

## 2. 强调与行内

| 写法 | 效果 |
| :--- | :--- |
| `**text**` | **粗体** |
| `*text*` | *斜体* |
| `***text***` | ***粗斜体*** |
| `~~text~~` | ~~删除线~~ |
| `` `code` `` | `行内代码` |
| `[text](url)` | [链接](https://developer.apple.com) |

嵌套也支持：**粗体里带 *斜体* 和 `代码`**。转义字符：`\*不是斜体\*`。

## 3. 列表

### 无序列表

- 苹果
  - 富士
  - 嘎啦
    - 更深的层级
- 香蕉
- 樱桃

### 有序列表

1. 打开「文件」App
2. 选择 Markdown 文档
3. 点按共享
   1. 选择 MD Viewer
   2. 等待导入完成
4. 开始阅读

### 任务列表

- [x] 解析标题与段落
- [x] 解析 GFM 表格
- [x] 解析围栏代码块
- [ ] 解析 LaTeX 公式
- [ ] 解析脚注

## 4. 引用

> **设计原则**
>
> 玻璃材质应当 *折射* 内容，而不是 *覆盖* 内容。
>
> > 嵌套引用：可读性永远优先于视觉炫技。

## 5. 代码块

```python
def parse_markdown(source: str) -> list[Block]:
    lines = source.replace("\r\n", "\n").split("\n")
    return parse_blocks(lines)

if __name__ == "__main__":
    print(parse_markdown("# Hello"))
```

```json
{
  "name": "MD Viewer",
  "minOS": "iOS 26.0",
  "renderer": "SwiftUI + AttributedString",
  "glass": ["GlassEffectContainer", "glassEffectID", "GlassEffectTransition"]
}
```

```
纯文本代码块
没有语言标签时只显示「TEXT」
```

## 6. 表格

| 对齐方式 | 语法 | 说明 | 分数 |
| :--- | :---: | ---: | :---: |
| 左对齐 | `:---` | 最常用 | 9 |
| 居中 | `:---:` | 适合短文本 | 8 |
| 右对齐 | `---:` | 适合数字 | 7 |
| 默认 | `---` | 跟随语言方向 | 6 |

单元格里也可以有 **粗体**、`代码` 和 [链接](https://www.swift.org)。

## 7. 分割线

---

## 8. Front matter

文件开头的 `---` 区块会被解析成元数据卡片：

```yaml
---
title: 示例文档
author: Someone
tags: demo · guide
---
```

## 9. 链接

- 外部：[Apple Developer](https://developer.apple.com)
- 自动链接：<https://www.markdownguide.org>
- 页内锚点：[跳回顶部](#1-标题)

---

**小提示**：把任意 `.md` 文件拖进资料库，就能立刻看到它的渲染结果。
