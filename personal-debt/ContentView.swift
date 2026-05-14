import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            OverviewDashboardView()
                .tabItem {
                    Label("总览", systemImage: "rectangle.grid.1x2")
                }

            DebtsDashboardView()
                .tabItem {
                    Label("债务", systemImage: "list.bullet.rectangle")
                }

            StrategyDashboardView()
                .tabItem {
                    Label("策略", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

            AnalyticsDashboardView()
                .tabItem {
                    Label("统计", systemImage: "chart.xyaxis.line")
                }

            RulesDashboardView()
                .tabItem {
                    Label("规则", systemImage: "bell.badge")
                }

            SettingsDashboardView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}
