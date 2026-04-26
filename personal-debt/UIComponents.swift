import SwiftUI

struct AppColors {
    static let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let accentGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let warningOrange = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let backgroundGray = Color(UIColor.systemGroupedBackground)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
}

extension DetailTone {
    var color: Color {
        switch self {
        case .info:
            return AppColors.primaryBlue
        case .success:
            return AppColors.accentGreen
        case .warning:
            return AppColors.warningOrange
        case .danger:
            return .red
        case .neutral:
            return .gray
        }
    }

    var softBackground: Color {
        color.opacity(0.1)
    }
}

struct DetailHeroCard: View {
    let title: String
    let subtitle: String
    let badgeText: String
    let badgeTone: DetailTone

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(badgeTone.softBackground)
                    .foregroundStyle(badgeTone.color)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

struct DetailStatusCard: View {
    let summary: DetailStatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.systemImage)
                    .font(.title3)
                    .foregroundStyle(summary.tone.color)
                    .frame(width: 38, height: 38)
                    .background(summary.tone.softBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Text(summary.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let footnote = summary.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summary.tone.softBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(summary.tone.color.opacity(0.18), lineWidth: 1)
        )
        .cornerRadius(18)
    }
}

struct DetailMetricGrid: View {
    let items: [DetailMetricItem]

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                DetailMetricCard(item: item)
            }
        }
    }
}

private struct DetailMetricCard: View {
    let item: DetailMetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.tone.color)
                    .frame(width: 28, height: 28)
                    .background(item.tone.softBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 0)
            }

            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }
}

struct DetailSectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

struct DetailFieldList: View {
    let items: [DetailFieldItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DetailRow(title: item.title, value: item.value, valueColor: item.tone.color)
                if index != items.count - 1 {
                    DetailDivider()
                }
            }
        }
    }
}

struct DetailTimelineCard: View {
    let title: String
    let subtitle: String
    let accessory: String?
    var tone: DetailTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tone.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let accessory, !accessory.isEmpty {
                Text(accessory)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(tone.softBackground.opacity(0.45))
        .cornerRadius(14)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let iconName: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.1))
                    .cornerRadius(7)
                
                Spacer()
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}

struct QuickActionCard: View {
    let title: String
    let iconName: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 50, height: 50)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppColors.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 3)
        }
    }
}

struct FilterGrid<Content: View>: View {
    var columns: Int = 2
    @ViewBuilder let content: () -> Content

    private var layout: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: max(columns, 1))
    }

    var body: some View {
        LazyVGrid(columns: layout, spacing: 8) {
            content()
        }
        .padding(.horizontal)
    }
}

struct FilterMenu<Option: Hashable>: View {
    let placeholder: String
    let selection: Option?
    let options: [Option]
    let displayText: (Option) -> String
    let onSelect: (Option?) -> Void

    private var selectedLabel: String {
        selection.map(displayText) ?? placeholder
    }

    var body: some View {
        Menu {
            Button(placeholder) {
                onSelect(nil)
            }

            ForEach(options, id: \.self) { option in
                Button(displayText(option)) {
                    onSelect(option)
                }
            }
        } label: {
            HStack {
                Text(selectedLabel)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppColors.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundColor(AppColors.primaryBlue)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}

struct DetailDivider: View {
    var body: some View {
        Divider()
            .padding(.leading)
    }
}

struct TitledInputRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
        }
    }
}

struct EntryCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(14)
    }
}

struct FloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppColors.primaryBlue)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("新增")
    }
}
