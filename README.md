# personal-debt

该仓库当前为 **iOS 17+ SwiftUI + SwiftData** 的本地优先债务管理应用，保留并复用订阅能力（StoreKit）。

## 当前能力范围（V1）

- 本地优先（SwiftData）
- 三类债务：信用卡 / 贷款 / 个人借贷
- 基础 CRUD、流水与逾期记录、状态重算
- 策略模拟：雪崩 / 雪球 / 均衡（最长 360 个月）
- 总览与统计页（真实数据与模拟数据隔离）
- 规则页（本地提醒规则）
- 设置页保留订阅中心、隐私政策、条款、支持入口

## 导航结构

- 总览
- 债务
- 策略
- 统计
- 规则
- 设置

## 关键目录

- `/home/runner/work/personal-debt/personal-debt/personal-debt/Models`
  - `CreditCard` / `Loan` / `PersonalLending` / `Strategy` / `Analysis` / `Rules` / `Shared`
- `/home/runner/work/personal-debt/personal-debt/personal-debt/Services/Calculation`
- `/home/runner/work/personal-debt/personal-debt/personal-debt/Repositories`
- `/home/runner/work/personal-debt/personal-debt/personal-debt/ViewModels`
- `/home/runner/work/personal-debt/personal-debt/personal-debt/Views`

## 订阅与法务入口

- 设置页中的 `订阅中心`
- 设置页中的隐私政策、Apple 条款与支持链接

## 本地打开

在 Xcode 中打开：

- `personal-debt.xcodeproj`

建议环境：

- iOS 17 或更高
- Xcode 15 或更高
