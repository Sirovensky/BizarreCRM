import SwiftUI
import DesignSystem

// MARK: - TopEmployeesCard

public struct TopEmployeesCard: View {
    public let employees: [EmployeePerf]
    public let maxCount: Int

    public init(employees: [EmployeePerf], maxCount: Int = 5) {
        self.employees = employees
        self.maxCount = maxCount
    }

    private var topEmployees: [EmployeePerf] {
        Array(employees.sorted { $0.revenueCents > $1.revenueCents }.prefix(maxCount))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            cardHeader
            if topEmployees.isEmpty {
                ContentUnavailableView("No Employee Data",
                                       systemImage: "person.3",
                                       description: Text("No employee performance data for this period."))
            } else {
                ForEach(topEmployees.indices, id: \.self) { idx in
                    employeeRow(topEmployees[idx], rank: idx + 1)
                    if idx < topEmployees.count - 1 {
                        Divider().padding(.leading, BrandSpacing.xl + BrandSpacing.sm)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var cardHeader: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.bizarreMagenta)
                .accessibilityHidden(true)
            Text("Top Employees")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func employeeRow(_ emp: EmployeePerf, rank: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            rankBadge(rank)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(emp.employeeName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(emp.ticketsClosed) tickets · \(String(format: "%.1f", emp.avgResolutionHours))h avg")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(emp.revenueDollars, format: .currency(code: "USD"))
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreSuccess)
        }
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(emp.employeeName). \(emp.ticketsClosed) tickets closed. Revenue \(String(format: "$%.2f", emp.revenueDollars)).")
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.brandTitleSmall())
            .foregroundStyle(rank == 1 ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
            .frame(width: BrandSpacing.xl, height: BrandSpacing.xl)
            .background(
                (rank == 1 ? Color.bizarreOrange : Color.bizarreSurface2).opacity(0.2),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}
