import SwiftUI
import SwiftData

struct RulesDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rules: [ReminderRule]

    var body: some View {
        NavigationStack {
            List {
                if rules.isEmpty {
                    Text("暂无提醒规则，点击右上角新增。")
                } else {
                    ForEach(rules.filter { $0.isValid }) { rule in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rule.title).font(.headline)
                            Text("还款日前 \(rule.daysBeforeDue) 天提醒")
                            Text("账单日后 \(rule.triggerAfterStatementDay) 天检查")
                            Toggle("启用", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { newValue in
                                    rule.isEnabled = newValue
                                    try? modelContext.save()
                                }
                            ))
                        }
                    }
                    .onDelete(perform: deleteRule)
                }
            }
            .navigationTitle("规则")
            .toolbar {
                Button("新增") {
                    modelContext.insert(ReminderRule(title: "默认提醒规则"))
                    try? modelContext.save()
                }
            }
        }
    }

    private func deleteRule(at offsets: IndexSet) {
        let validRules = rules.filter { $0.isValid }
        for idx in offsets {
            validRules[idx].isValid = false
        }
        try? modelContext.save()
    }
}
