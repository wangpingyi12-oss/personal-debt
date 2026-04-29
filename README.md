# personal-debt

本项目是一个 iOS 17+ 的个人债务管理应用（SwiftUI + SwiftData），面向中国大陆场景，核心目标是帮助用户管理多笔债务并制定还款计划。

## 已实现的 MVP 骨架

- 债务、还款计划、还款记录、逾期事件、策略场景、订阅权益的数据模型
- 债务管理（新增/编辑/删除）
- 贷款还款计划自动生成（等额本息、等额本金、先息后本、到期还本付息）
- 单笔还款分配顺序：逾期费用 -> 逾期罚息 -> 利息 -> 本金
- 逾期事件新增与罚息计算
- 雪崩法、雪球法、均衡法策略对比（基础版）
- 首页统计、还款管理、策略页、设置页（隐私合规/反馈/订阅）

## 合规说明

- 本应用仅用于记账与测算，不构成投资建议或信贷建议。
- 默认本地存储，不做个人隐私数据采集。
- 计算规则为默认模板，用户需根据实际合同进行确认与修订。

## 本地运行

在 Xcode 中打开：

- `personal-debt.xcodeproj`

建议使用：

- iOS 17 或更高
- Xcode 15 或更高

## 文档站点发布（GitHub Pages）

- 文档源目录：`docs/`
- 已配置自动发布工作流：`.github/workflows/deploy-pages.yml`
- 目标页面（提审可直接使用）：
  - `https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-zh-CN.html`
  - `https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-en-US.html`
  - `https://wangpingyi12-oss.github.io/personal-debt/support-zh-CN.html`
  - `https://wangpingyi12-oss.github.io/personal-debt/support-en-US.html`

首次启用注意事项：

1. GitHub 仓库进入 `Settings > Pages`。
2. `Build and deployment` 选择 `Source: GitHub Actions`。
3. push 任意对 `docs/` 的改动或手动触发 `Deploy Docs to GitHub Pages`。

建议发布后校验：页面返回 200，且正文可打开显示。

## 最终上线收口（无迁移版本）

当前版本尚未上线，因此不做历史数据迁移；本版本不包含家庭共享能力，订阅来源统一按 App Store 购买处理。

### 1) 订阅全生命周期核验

- [ ] 订阅产品配置：`SubscriptionCatalogService.catalog` 的产品 ID 与 App Store Connect 保持一致（包月/包年）
- [ ] 本地调试配置：为调试 Scheme 绑定 `.storekit` 文件，确保离线与沙盒都可覆盖
- [ ] 生命周期日志核验：购买、恢复、续费、到期、退款/撤销、宽限期、扣费重试可正确落库到 `SubscriptionEntitlement` 与 `SubscriptionTransactionRecord`

### 2) Go / No-Go 阻断项

- [ ] 法务文案与入口：自动续费说明、隐私声明、订阅管理入口完整可达
- [ ] 功能门禁：策略中心仅对有效订阅状态（试用/生效/即将到期/宽限期）开放
- [ ] 发布元数据：截图、订阅说明、客服联系方式、隐私与条款链接、审核备注准备完整

### 3) 真机执行矩阵（按顺序）

建议顺序：StoreKit 本地配置 -> 沙盒账号真机 -> TestFlight 外测。

核心用例：

- [ ] 首次购买（月订阅/年订阅）
- [ ] 购买中断（`.pending`，如强认证或网络中断）
- [ ] 用户取消购买（`.userCancelled`）
- [ ] 恢复购买（同 Apple ID / 新设备）
- [ ] 自动续费成功
- [ ] 主动关闭自动续费后进入到期
- [ ] 宽限期（支付方式失效但仍有短期权益）
- [ ] 扣费重试期（权益降级与提示）
- [ ] 退款/撤销（权益回收）

通过标准：

- [ ] 订阅状态文案、门禁行为、按钮可用性一致
- [ ] 所有关键操作后，`校验并同步` 可恢复到正确状态
- [ ] 交易历史列表与当前权益快照时间线一致
