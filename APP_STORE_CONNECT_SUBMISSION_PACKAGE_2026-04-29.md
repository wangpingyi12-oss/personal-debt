# 1) 提交并推送改动
cd /Users/mac/Desktop/debtmanager/personal-debt
git add .github/workflows/deploy-pages.yml README.md APP_STORE_CONNECT_SUBMISSION_PACKAGE_2026-04-29.md
git commit -m "chore: enable GitHub Pages deployment for docs"
git push# App Store Connect 提审填写包（personal-debt）

> 目标：一次性补齐“无法添加以供审核”页面提示的全部必填项。
> 适用前提：当前应用为本地债务管理工具，使用 StoreKit 订阅，无第三方广告/统计 SDK，无账号系统。

## 0. 先决条件（构建版本）

- 入口：`我的 App > personal-debt > iOS App > 版本 > 构建版本`
- 填写内容：选择一个状态为 `Processing Complete` 的构建。
- 校验结果：版本页面不再提示“你必须选择一个构建版本”。

---

## 1. 联系信息（必填）

- 入口：`我的 App > App 信息 > 联系信息`
- 建议填写（可直接替换占位符）：
  - 名字：`<你的姓名>`
  - 姓氏：`<你的姓氏>`
  - 电话：`+86 <11位手机号>`
  - 邮箱：`wangpingyi12@outlook.com`
- 校验结果：该模块无红色必填提示。

---

## 2. 类别（必填）

- 入口：`我的 App > App 信息 > 类别`
- 建议填写：
  - 主类别：`财务`
  - 副类别（可选）：`效率`（如果需要）
- 校验结果：版本页面不再提示“你必须为 App 选择主要类别”。

---

## 3. 年龄分级（必填）

- 入口：`我的 App > App 信息 > 年龄分级`
- 建议原则：本应用为债务记录和还款测算工具，无社交、无 UGC、无暴力/成人内容。
- 建议问卷答案：
  - 暴力/血腥：`无`
  - 成人/性暗示：`无`
  - 赌博：`无`
  - 酒精/烟草/药物：`无`
  - 恐怖题材：`无`
  - 粗俗语言：`无`
  - 模拟博彩：`无`
  - 医疗/治疗建议：`无`
  - 用户生成内容：`否`
  - 无限制网页访问：`否`
- 预期结果：通常会得到 `4+`（以系统最终计算为准）。
- 校验结果：版本页面不再提示“必须回答要求的年龄分级问题”。

---

## 4. 内容版权（必填）

- 入口：`我的 App > App 信息 > 内容版权`
- 可直接填写：

```text
2026 <你的个人名或公司名>
```

- 校验结果：版本页面不再提示“必须在 App 信息中设置内容版权信息”。

---

## 5. 隐私政策 URL（必填）

- 入口：`我的 App > App 信息 > 隐私政策 URL`（部分界面在隐私区域）
- 必须满足：公网可访问、HTTPS、无需登录。
- 推荐 URL（示例）：

```text
https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-zh-CN.html
https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-en-US.html
```

- 本仓库已提供可直接发布文件：
  - `docs/privacy-policy-zh-CN.html`
  - `docs/privacy-policy-en-US.html`
  - `docs/index.html`
  - 自动发布工作流：`.github/workflows/deploy-pages.yml`

- 首次发布提醒（若出现 404）：
  1. GitHub 仓库 `Settings > Pages` 中选择 `Source: GitHub Actions`
  2. 触发 `Deploy Docs to GitHub Pages` 工作流后再回到 App Store Connect 填写

- 技术支持 URL（可直接填写）：

```text
简体中文：https://wangpingyi12-oss.github.io/personal-debt/support-zh-CN.html
英语（美国）：https://wangpingyi12-oss.github.io/personal-debt/support-en-US.html
```

- 校验结果：版本页面不再提示“必须在 App 隐私页面输入隐私政策网址”。

---

## 6. App 隐私（必填）

- 入口：`我的 App > App 隐私 > 开始`
- 当前项目建议声明（基于现有代码）：
  - `是否收集任何来自此 App 的数据？` -> `否`
  - `是否用于跟踪？` -> `否`
- 说明：
  - 本地使用 SwiftData 和 UserDefaults 存储。
  - 订阅走 StoreKit，购买交易由 Apple 处理。
  - 未发现第三方广告/统计追踪 SDK。
- 校验结果：`App 隐私` 状态显示“已完成”。

---

## 7. 定价（必填）

- 入口：`我的 App > 定价与销售范围`
- 建议填写：
  - 价格：`免费（Tier 0）`
  - 销售范围：`中国大陆`（或按你的发布范围勾选）
  - 应用内购买：保留订阅项（月/年）
- 校验结果：版本页面不再提示“必须在定价中选择价格等级”。

---

## 8. 审核备注（建议一并填写）

- 入口：`我的 App > iOS App > 当前版本 > App 审核信息 > 备注`
- 可直接粘贴：

```text
感谢审核团队。

本应用为个人债务管理工具，主要功能包括：债务记录、还款计划测算、还款提醒、订阅解锁高级策略。

补充说明：
1) 无账号注册/登录，打开后可直接使用。
2) 无第三方广告与行为追踪 SDK。
3) 订阅功能使用 Apple StoreKit（产品：com.personaldebt.pro.monthly / com.personaldebt.pro.yearly）。
4) 若审核环境未返回订阅商品，请切换到可用的 App Store 沙盒环境后重试。

如需补充说明，请通过联系邮箱与我们沟通：wangpingyi12@outlook.com。
```

---

## 9. 最终提交前复核清单

- [ ] 已选中可用构建版本
- [ ] 联系信息完整
- [ ] 主类别已选
- [ ] 年龄分级已完成
- [ ] 版权已填写
- [ ] 隐私政策 URL 可访问
- [ ] App 隐私问卷已完成
- [ ] 定价已生效

完成以上后，返回版本页面点击“添加以供审核”。

---

## 10. 出口合规（减少后续重复填写）

- 当前工程已配置：`ITSAppUsesNonExemptEncryption = NO`
- 配置位置：`personal-debt.xcodeproj/project.pbxproj`
- 适用含义：App 未使用“非豁免加密”，通常后续新构建会减少或免去重复填写出口合规问卷。
- 注意：如果某个旧构建仍显示“缺少出口合规证明”，通常需要对该旧构建手动点一次“管理”；新上传构建会更容易自动带出该结论。
