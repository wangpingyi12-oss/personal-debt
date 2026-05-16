# Logic Conflicts and Gaps

> Last updated: 2026-05-17
> Status legend: `open` / `in_progress` / `fixed` / `deferred`

## Closed items

1. **Strategy simulation cannot pay down debts that have no repayment plans** — `fixed`
   - Area: `personal-debt/Engines/StrategySimulationEngine.swift`
   - Resolution: debts with empty `plans` now apply allocated payments directly to `balance`, preserving strategy simulations for ad-hoc/manual debts.
   - Coverage: `CoreEngineTests.strategySimulationUsesSnapshotsWithoutMutatingInputs()` and strategy simulation tests cover no-plan repayment behavior.

2. **Subscription read-only mode is declared in UI copy but not enforced in write services** — `fixed`
   - Area: `SubscriptionStore`, debt write services, and analytics snapshot persistence.
   - Resolution: write services now depend on `WriteAccessAuthorizing` and call `requireWriteAccess()` before mutating or saving.
   - Coverage: `SubscriptionAccessTests.writeAccessGateRejectsDebtServiceWritesInReadOnlyMode()` verifies read-only rejection.

3. **Credit card system overdue penalty days appear to use `billingDate` instead of `dueDate`** — `fixed`
   - Area: `CreditCardDebtService.refreshSystemOverdue(...)`
   - Resolution: penalty days are now calculated from `statement.dueDate`, clamped at zero.
   - Coverage: `BusinessLoopServiceTests.creditCardSystemOverduePenaltyStartsFromDueDateAndRejectsZeroPayment()` verifies the due-date boundary and penalty amount.

4. **Credit card payment validation allows zero-amount records while loan / personal lending forbid them** — `fixed`
   - Area: `CreditCardDebtService.recordPayment/updatePayment`
   - Resolution: credit-card payments now require a positive amount, matching loan and personal lending write rules.
   - Coverage: `BusinessLoopServiceTests.creditCardSystemOverduePenaltyStartsFromDueDateAndRejectsZeroPayment()` verifies zero-amount rejection.

5. **Manual credit-card overdue records lack date-boundary validation** — `fixed`
   - Area: `CreditCardDebtService.createManualOverdue(...)`
   - Resolution: manual overdue records now reject `startDate > endDate` and `startDate < statement.dueDate`; existing active-record overlap behavior remains enforced.
   - Coverage: `BusinessLoopServiceTests.creditCardManualOverdueRejectsInvalidDateBoundaries()` verifies both date-boundary failures.

6. **Loan input validation can be tightened further** — `fixed`
   - Area: `LoanDebtService.validateDebtInput(...)`
   - Resolution: in-progress loans now reject `openingPrincipalForManagement > originalPrincipal` and `managementStartDate < startDate`.
   - Coverage: `BusinessLoopServiceTests.loanServiceRejectsInvalidInProgressBoundaries()` verifies both invalid boundaries.

## Deferred boundary

1. **Personal lending past-due semantics differ from `DebtStatus.overdue` and may confuse upper layers** — `deferred`
   - Area: `PersonalLendingPaymentEngine` and analytics consumers.
   - Boundary decision: current behavior is intentional. Personal lending remains contract-active while exposing unpaid due installments through engine/summary detail instead of forcing the whole debt into `DebtStatus.overdue`.
   - Coverage: `BusinessLoopServiceTests.personalLendingServiceKeepsPastDueOutOfOverdueState()` documents the distinction.

## Resolution notes

- Static conflict scan found no Git conflict markers. The remaining `fatalError` is the app startup guard for SwiftData `ModelContainer` creation failure.
- `xcodebuild build -project personal-debt.xcodeproj -scheme personal-debt -destination generic/platform=iOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO` succeeded.
- `xcodebuild build-for-testing -project personal-debt.xcodeproj -scheme personal-debt -destination generic/platform=iOS\ Simulator -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO` succeeded.
- Runtime `xcodebuild test` execution is blocked by the local CoreSimulator/app-launch environment with `NSMachErrorDomain Code=-308`; no test assertion failure was observed before simulator launch failed.
