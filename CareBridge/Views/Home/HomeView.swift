import SwiftUI
import Charts

// MARK: - Brand Color
extension Color {
    static let brandTeal = Color(red: 0.0, green: 0.50, blue: 0.55)
    static let brandTealLight = Color(red: 0.82, green: 0.94, blue: 0.95)
    static let brandBackground = Color(red: 0.94, green: 0.97, blue: 0.98)
}

// MARK: - HomeView
struct HomeView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    @State private var health = HealthData.sample
    @State private var showNotifications = false
    @State private var showSOS = false
    private let weekDays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Greeting
                    greetingSection

                    // SOS Button
                    sosButton

                    // Activity Trend Card
                    activityTrendCard

                    // Today's Tasks
                    todayTasksCard

                    // Heart Rate Card
                    heartRateCard

                    // Blood Oxygen Card
                    bloodOxygenCard

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.brandTeal)
                            Text("CareBridge")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        Button { } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .sheet(isPresented: $showSOS) {
                NavigationStack { FirstAidView(isModal: true) }
            }
        }
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Hank")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    // MARK: - SOS Button
    private var sosButton: some View {
        Button {
            showSOS = true
        } label: {
            HStack {
                Spacer()
                Text("SOS EMERGENCY\nASSISTANCE")
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 44, height: 44)
                    Image(systemName: "asterisk")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(red: 0.85, green: 0.15, blue: 0.15))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity Trend Card
    private var activityTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Trend")
                        .font(.system(size: 17, weight: .bold))
                    Text("Movement & Steps last 7 days")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 0) {
                    Text("Week")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandTealLight))
                        .foregroundStyle(Color.brandTeal)
                    Text("Month")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
            }

            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(HealthData.weeklySteps.enumerated()), id: \.offset) { index, steps in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == 3 ? Color.brandTeal : Color.brandTealLight)
                            .frame(height: CGFloat(steps) / 35)
                        Text(weekDays[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            .padding(.vertical, 4)

            Divider()

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("12% more active than last week")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink(destination: HealthMonitorView()) {
                    Text("FULL\nREPORT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.brandTeal)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Today's Tasks
    private var todayTasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日處理事項")
                .font(.system(size: 17, weight: .bold))

            // Medication row
            NavigationLink(destination: MedicationView(userRole: userRole)) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandTealLight)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "pills.fill")
                                .foregroundStyle(Color.brandTeal)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medication")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Next: 2:00 PM")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("2/3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.brandTeal)
                        Text("DONE")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)

            // Blood pressure row
            NavigationLink(destination: HealthMonitorView()) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandTealLight)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(Color.brandTeal)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pressure")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Last check: 9 AM")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("128/82")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("NORMAL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Heart Rate Card
    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("HEART RATE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("STABLE")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(health.heartRate)")
                    .font(.system(size: 52, weight: .bold))
                Text("bpm")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Spacer()
                // Mini pulse graphic
                HStack(alignment: .center, spacing: 2) {
                    ForEach([0.3, 0.6, 1.0, 0.7, 0.5, 0.8, 0.4], id: \.self) { h in
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.6, blue: 0.6))
                            .frame(width: 4, height: 40 * h)
                    }
                }
                .frame(height: 40)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Blood Oxygen Card
    private var bloodOxygenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wind")
                    .foregroundStyle(Color.brandTeal)
                Text("BLOOD OXYGEN")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.brandTeal)
                        .frame(width: 6, height: 6)
                    Text("OPTIMAL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(Int(health.bloodOxygen))")
                    .font(.system(size: 52, weight: .bold))
                Text("% SpO2")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}

#Preview {
    HomeView(showProfile: .constant(false), userRole: .family)
        .environment(MedicationStore())
        .environment(CareLogStore())
        .environment(CalendarStore())
}
