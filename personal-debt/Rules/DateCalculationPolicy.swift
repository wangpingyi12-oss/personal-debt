import Foundation

struct DateCalculationPolicy: Sendable {
    var calendar: Calendar

    static let standard = DateCalculationPolicy(calendar: Calendar(identifier: .gregorian))

    func clampedDay(_ day: Int, inMonthContaining date: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: date)
        let maxDay = range?.count ?? 28
        return min(max(day, 1), maxDay)
    }

    func date(inMonthContaining date: Date, day: Int) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        let clamped = clampedDay(day, inMonthContaining: date)
        return calendar.date(from: DateComponents(year: components.year, month: components.month, day: clamped)) ?? date
    }

    func addingMonths(_ months: Int, to date: Date, matchingDay day: Int? = nil) -> Date {
        let shifted = calendar.date(byAdding: .month, value: months, to: date) ?? date
        guard let day else { return shifted }
        return self.date(inMonthContaining: shifted, day: day)
    }

    func firstRepaymentDate(after startDate: Date, dayOfMonth: Int) -> Date {
        let candidate = date(inMonthContaining: startDate, day: dayOfMonth)
        if candidate > startDate {
            return candidate
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate
        return date(inMonthContaining: nextMonth, day: dayOfMonth)
    }

    func daysBetween(_ startDate: Date, _ endDate: Date) -> Int {
        max(calendar.dateComponents([.day], from: startOfDay(startDate), to: startOfDay(endDate)).day ?? 0, 0)
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
