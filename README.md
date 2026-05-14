# personal-debt

该仓库现已精简为一个 **iOS 17+ SwiftUI / StoreKit 示例工程**，仅保留以下能力：

- 订阅套餐展示、购买、恢复购买与权益同步
- 隐私政策、Apple 条款、Apple 隐私政策等法务外链入口
- 支持页面与联系邮箱入口

其余与债务管理、还款计划、策略分析、提醒通知、统计展示相关的页面、模型、服务和测试均已移除。

## 当前保留的主要文件

- `personal-debt/personal_debtApp.swift`：最小应用入口
- `personal-debt/ContentView.swift`：仅保留订阅 / 法务隐私 / 支持入口导航
- `personal-debt/SubscriptionManagementView.swift`：订阅中心页面
- `personal-debt/SubscriptionServices.swift`：StoreKit 商品加载、购买、恢复与权益状态解析
- `personal-debt/Item.swift`：最小订阅状态模型
- `personal-debt/AppLinks.swift`：隐私、条款、支持相关外链集中定义
- `personal-debt/UIComponents.swift`：精简后的共享 UI 组件

## 外链文档

项目文档站点仍保留以下页面：

- `https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-zh-CN.html`
- `https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-en-US.html`
- `https://wangpingyi12-oss.github.io/personal-debt/support-zh-CN.html`
- `https://wangpingyi12-oss.github.io/personal-debt/support-en-US.html`

## 本地打开

在 Xcode 中打开：

- `personal-debt.xcodeproj`

建议环境：

- iOS 17 或更高
- Xcode 15 或更高
