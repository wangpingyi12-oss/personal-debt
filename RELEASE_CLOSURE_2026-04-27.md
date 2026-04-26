# 最终上线收口执行记录（2026-04-27）

## 目标

- 移除家庭共享相关对外呈现
- 按 1/2/3 完成上线收口（生命周期核验、Go/No-Go、真机测试执行准备）

## 代码与文档变更

1. `personal-debt/SubscriptionManagementView.swift`
   - 移除订阅卡片中的“家庭共享”状态标签显示。
   - 将“权益来源”文案统一为 `App Store 购买`（保留底层 `ownershipType` 落库字段，不影响审计链路）。

2. `README.md`
   - 删除家庭共享相关检查项与测试用例。
   - 清理重复段落。
   - 结构化为 1/2/3 三段最终收口清单：
     - 1) 订阅全生命周期核验
     - 2) Go / No-Go 阻断项
     - 3) 真机执行矩阵

## 按 1/2/3 执行结果

### 1) 生命周期核验（仓库侧）

- 已完成：代码路径确认购买、恢复、续费、到期、退款/撤销、宽限期、扣费重试的落库字段仍在。
- 已完成：家庭共享展示移除，不再作为发布验收项。
- 待真机：沙盒账号执行完整交易路径并截图留档。

### 2) Go / No-Go 阻断项（当前状态）

- 已完成：门禁与订阅生命周期相关 UI/服务层代码可编译并通过测试。
- 已完成：收口文档与上线检查项统一。
- 待人工：App Store Connect 元数据、法务文案、审核备注最终核对。

### 3) 真机测试执行（已完成模拟器基线）

- 已完成：单元测试通过（32/32）。
- 已完成：UI 冒烟测试通过（1/1）。
- 待真机：按 README 用例矩阵在真实设备执行并记录结果。

## 本次验证命令与结果

1. 单元测试
   - 命令：
     `xcodebuild test -project personal-debt.xcodeproj -scheme personal-debt -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' -only-testing:personal-debtTests -parallel-testing-enabled NO`
   - 结果：`TEST SUCCEEDED`（32 tests, 0 failures）

2. UI 冒烟测试
   - 命令：
     `xcodebuild test -project personal-debt.xcodeproj -scheme personal-debt -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' -only-testing:personal-debtUITests/personal_debtUITests/testMainTabsAndDebtEntryAreVisible -parallel-testing-enabled NO`
   - 结果：`TEST SUCCEEDED`（1 test, 0 failures）

## 结论

- “移除家庭共享”已完成（展示层和发布清单层）。
- “按 1/2/3 全部执行”已完成可自动化部分与仓库收口。
- 下一步仅剩真机与商店侧人工核验，可直接进入真机测试阶段。
