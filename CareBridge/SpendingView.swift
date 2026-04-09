import SwiftUI
import Charts

struct SpendingView: View {
    @State private var expenses = Expense.samples
    @State private var showReceiptScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with label
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CAREBRIDGE WALLET")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(1.5)
                            Text("消費記帳")
                                .font(.system(size: 28, weight: .bold))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Monthly total card
                    monthlyCard

                    // Recent transactions
                    recentTransactions

                    Spacer(minLength: 80)
                }
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.brandTeal)
                        Text("CareBridge")
                            .font(.system(size: 20, weight: .bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brandTeal)
                    Button {
                        showReceiptScanner = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16))
                            Text("拍攝收據")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.brandTeal))
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 24)
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView()
            }
        }
    }

    // MARK: - Monthly Card
    private var monthlyCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月支出總計")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("NT$ \(Int(Expense.monthlyTotal).formatted())")
                        .font(.system(size: 34, weight: .bold))
                }
                Spacer()
                Button {
                    // Show full report
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .frame(width: 40, height: 40)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }

            // Donut chart simulation
            ZStack {
                // Outer ring segments
                Circle()
                    .trim(from: 0, to: 0.45)
                    .stroke(Color.brandTeal, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.45, to: 0.70)
                    .stroke(Color.orange, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.70, to: 0.90)
                    .stroke(Color.purple, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.90, to: 1.0)
                    .stroke(Color(.systemGray4), lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("AUGUST")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("2024")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .frame(width: 160, height: 160)
            .padding(.vertical, 8)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Expense.categoryBreakdown, id: \.0) { name, pct, color in
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("\(Int(pct))%")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
    }

    // MARK: - Recent Transactions
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近交易")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    // Show all
                } label: {
                    Text("查看全部")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandTeal)
                }
            }

            ForEach(expenses) { expense in
                ExpenseRow(expense: expense)
                if expense.id != expenses.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
    }
}

// MARK: - Expense Row
struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(expense.categoryColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: expense.categoryIcon)
                    .foregroundStyle(expense.categoryColor)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if Calendar.current.isDateInToday(expense.date) {
                        Text("今天")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(expense.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("- TWD \(Int(expense.amount).formatted())")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Receipt Scanner View
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Camera frame
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 280)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color.brandTeal)
                                Text("對準收據拍攝")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                        }

                    // Corner guides
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.brandTeal, lineWidth: 3)
                        .frame(width: 220, height: 160)
                }
                .padding(.horizontal, 32)

                Text("OCR 自動辨識收據金額與品項")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Button {
                    // Capture
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("拍攝")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 140)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.brandTeal))
                }
                .buttonStyle(.plain)

                Button {
                    // From library
                } label: {
                    Text("從相簿選擇")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandTeal)
                }

                Spacer()
            }
            .navigationTitle("拍攝收據")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

#Preview {
    SpendingView()
}
