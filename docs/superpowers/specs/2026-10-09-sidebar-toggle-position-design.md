# 左侧导航按钮定位设计

日期：2026-10-09

## 目标

调整展开状态下左侧导航 sidebar 的收起按钮位置，使它位于窗口红绿灯所在的顶部横带内、仍属于 sidebar，并靠近 sidebar 与中间核心面板的分界线；按钮与红绿灯保持同一水平区域，但不要求彼此紧挨。视觉参考为用户提供的窗口顶部示意图。

## 范围

- 只调整 `ContentView.sidebarHeader` 中展开状态的 `NavigationSidebarToggle` 对齐方式。
- 保留顶部横带高度、红绿灯避让区域、`WITRN K2` 标题、维护菜单及 sidebar 列表内容。
- sidebar 收起后的工作区顶栏展开按钮、页面选择、连接栏、Store 和持久化状态不变。
- 不使用 worktree，不新增第三方依赖，不修改通信或业务逻辑。

## 方案与决策

采用顶部横带尾部对齐方案：将按钮放入占满 sidebar 顶部横带宽度的水平布局中，使用 sidebar 的 trailing 对齐，并保留约 18 pt 的右侧内边距。这样按钮会随 sidebar 宽度变化而保持靠近分界线，同时仍处于 sidebar 内；左侧红绿灯区域自然保持为空，不会与按钮重叠。

不采用固定横坐标，因为 sidebar 改变宽度后按钮会脱离右侧视觉锚点；不采用独立 overlay，因为它会增加与分割线和窄窗口调整区域发生重叠的风险。

## 组件与数据流

`ContentView.sidebarHeader` 继续负责顶部横带布局，`NavigationSidebarToggle` 继续负责点击和可访问性标签。按钮仍使用现有 `sidebarToggle` binding：点击只切换 `NavigationSplitViewVisibility`，不改变当前页面选择或任何 Store 状态。

垂直方向继续使用 `LayoutMetrics.titlebarHeight`，水平方向由 sidebar 自身可用宽度和固定 trailing inset 决定。`WorkspaceToolbar` 中收起后的入口不参与本次改动。

## 边界与验证

- 默认窗口：按钮出现在 sidebar 顶部横带右侧，和红绿灯同一水平区域。
- 调整 sidebar 宽度：按钮跟随 sidebar 右边界移动，并保留稳定的右侧间距。
- 收起 sidebar：按钮随 sidebar 一起消失，工作区顶栏仍保留展开按钮。
- 点击按钮：sidebar 展开/收起正常，当前页面和连接状态不变。
- 最低窗口尺寸：按钮仍在 sidebar 内，不遮挡标题、维护菜单或分割线。

验证方式为 Swift 编译、现有 Swift 测试，以及运行应用后的上述布局和交互检查；不启动真实设备写入。
