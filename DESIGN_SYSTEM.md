# WITRN K2 设计系统

## 设计理念

**极简工程美学** - 灰度为主，留白为王，颜色克制

### 核心原则

1. **灰度为主** - 90% 使用黑白灰色调
2. **留白为王** - 充足的呼吸空间，降低视觉压力
3. **颜色克制** - 只在警告和强调时使用颜色
4. **字重层次** - 用字体大小和粗细建立视觉层次
5. **折叠优先** - 次要信息可折叠，保持界面简洁

## 颜色系统

### 主色调
- **黑色**：主要文字（系统默认）
- **灰色**：次要文字（`.secondary`）
- **浅灰**：辅助文字（`.tertiary`）
- **背景**：`Color(nsColor: .controlBackgroundColor)` - 系统卡片背景

### 功能色（仅在必要时使用）
- **红色**：警告、错误（`.red`，背景 6% 不透明度）
- **绿色**：成功、确认（`.green`，背景 15% 不透明度）
- **蓝色**：强调按钮（`.accentColor`）

### 颜色使用规范
- ❌ 不再使用：蓝色电压、橙色电流、绿色功率的彩色区分
- ✅ 主读数：统一黑色，用分隔线区分
- ✅ 警告：红色文字 + 警告符号
- ✅ 成功状态：绿色圆点或勾选
- ✅ 按钮：灰色为主，蓝色强调主要操作

## 字体系统

### 字体层次
```
超大读数  .system(size: 42, design: .rounded)  ──  监控主读数
    ↓
大标题    .title3                             ──  页面标题、步骤标题
    ↓
标题      .headline                           ──  区块标题
    ↓
副标题    .subheadline                        ──  小标题
    ↓
正文      .callout                            ──  主要内容、按钮文字
    ↓
小字      .caption                            ──  辅助信息、提示
```

### 字重使用
- **Regular**：默认正文
- **Medium**：小标题强调
- **Semibold**：已弃用，改用 Medium
- **Monospaced**：数值、时间

## 布局系统

### 间距规范
```
卡片外边距    24pt    ──  页面边缘到卡片
卡片内边距    18-20pt ──  卡片内容边距
分组间距      24-32pt ──  主要功能分组
元素间距      16-20pt ──  相关元素组
紧凑间距      12-14pt ──  紧密相关的内容
```

### 卡片设计
```swift
// 标准卡片
.padding(20)
.background(Color(nsColor: .controlBackgroundColor))
.clipShape(RoundedRectangle(cornerRadius: 12))

// 警告卡片
Text("⚠ 警告信息")
    .font(.callout)
    .foregroundStyle(.red)
```

### 分隔设计
- **Divider**：用于分隔不同功能区
- **垂直 Divider**：用于并列元素（如读数卡片）
- **留白**：首选方式，用间距代替分隔线

## 图标系统

### 图标使用规范
❌ **不再使用的装饰性图标**：
- 不再给每个按钮添加图标
- 不再用图标区分文件操作类型
- 不再用彩色图标表示状态

✅ **保留的必要图标**：
- 折叠展开：`chevron.up` / `chevron.down`
- 步骤完成：`✓` 文字符号
- 警告：`⚠` 文字符号
- 状态指示：圆点、勾选（最小化图标）

### 按钮设计
```swift
// 主要按钮 - 纯文字
Button("开始记录") { }
    .buttonStyle(.borderedProminent)

// 次要按钮 - 纯文字
Button("读取") { }

// 菜单按钮 - 纯文字
Menu("操作") { }

// 特殊：撤销/重做用符号
Button("↶") { } // 撤销
Button("↷") { } // 重做
```

## 交互设计

### 折叠设计
所有次要信息默认折叠，提供展开/收起按钮：

```swift
Button {
    withAnimation(.easeInOut(duration: 0.2)) {
        expanded.toggle()
    }
} label: {
    HStack {
        Text(expanded ? "收起" : "展开")
            .font(.callout)
            .foregroundStyle(.secondary)
        Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
.buttonStyle(.plain)
.frame(maxWidth: .infinity, alignment: .center)
```

### 动画规范
- **折叠动画**：`easeInOut(duration: 0.2)`
- **过渡动画**：使用系统默认
- **避免**：闪烁、抖动、过度动效

## 组件规范

### 读数卡片（MonitorView）
```
┌────────────────────────────────────────┐
│ 电压      │  电流      │  功率        │
│           │            │              │
│ 5.1234 V  │  1.2345 A │  6.320 W     │
│  42pt圆角，全黑，用 Divider 分隔        │
│                                        │
│           [显示详细信息 ˅]              │
└────────────────────────────────────────┘
```

### 记录控制（MonitorRecordingControls）
```
┌────────────────────────────────────────┐
│ [开始记录]  100 样本 · 00:01:23  [操作]│
│                                        │
│              [记录设置 ˅]               │
└────────────────────────────────────────┘
```

### 步骤指示器（FirmwareView）
```
◯ 1  确认设备      ← 未完成（灰色圆圈）
◯ 2  选择固件
✓ 3  备份并升级    ← 已完成（绿色圆圈 + 勾）
```

### 状态指示（WorkspaceToolbar）
```
● 未保存   ← 橙色小圆点
● 已保存   ← 绿色小圆点
```

## 警告系统

### 警告层级
1. **错误** - 红色文字 + `⚠` 符号
2. **提示** - 灰色小字

### 警告样式
```swift
// 错误警告
Text("⚠ 采集仍在运行，请先断开")
    .font(.callout)
    .foregroundStyle(.red)

// 一般提示
Text("点击选择，拖动定位")
    .font(.caption)
    .foregroundStyle(.secondary)
```

## 响应式设计

### 窗口尺寸
- **最小宽度**：1100pt
- **最小高度**：720pt
- **侧边栏**：260pt 固定宽度

### 自适应
- 使用 `ViewThatFits` 在必要时切换布局
- 优先垂直堆叠而非水平挤压
- 保持最小触摸目标 44pt

## 设计检查清单

在添加新界面或修改现有界面时，检查：

- [ ] 是否只在必要时使用颜色？
- [ ] 是否有足够的留白（20pt+）？
- [ ] 按钮是否使用纯文字？
- [ ] 次要信息是否可折叠？
- [ ] 警告是否使用红色？
- [ ] 字体是否符合层次规范？
- [ ] 卡片圆角是否为 12pt？
- [ ] 是否避免了装饰性图标？

## 参考实现

所有设计规范已在以下文件中实现：
- `MonitorView.swift` - 监控界面
- `MonitorRecordingControls.swift` - 记录控制
- `FirmwareView.swift` - 固件升级
- `FirmwareCard.swift` - 固件卡片
- `WorkspaceToolbar.swift` - 工作区工具栏
- `PictureView.swift` - 表盘编辑器

---

**设计理念**：少即是多。通过克制的颜色使用、充足的留白和清晰的层次，打造专业、现代、易用的工程工具界面。
