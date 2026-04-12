import SwiftUI
import CoreLocation

// MARK: - Location Manager

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var coordinate: CLLocationCoordinate2D?
    var locationString: String = "取得位置中..."
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            locationString = "位置存取被拒絕"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        locationString = String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationString = "無法取得位置"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

// MARK: - SOS View

struct SOSView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false
    @State private var countdown = 5
    @State private var isTriggered = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isTriggered {
                    triggeredView
                } else {
                    mainView
                }
            }
            .background(isTriggered ? Color.red : Color.brandBackground)
            .navigationTitle("SOS 緊急呼叫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        timerTask?.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(isTriggered ? .white : .primary)
                    }
                }
            }
        }
    }

    // MARK: - Main View
    private var mainView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Text("緊急求助")
                    .font(.system(size: 28, weight: .bold))

                Text("按下後將自動撥打 119\n並通知所有家庭成員")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring()) {
                        countdown = 5
                        isConfirming = true
                        locationManager.requestLocation()
                        startCountdown()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 200, height: 200)
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 160, height: 160)
                        Circle()
                            .fill(.red)
                            .frame(width: 120, height: 120)
                        Image(systemName: "sos")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }

            if isConfirming {
                confirmingView
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("最近 SOS 紀錄")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    Text("過去30天 無 SOS 紀錄")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Countdown Logic
    private func startCountdown() {
        timerTask?.cancel()
        timerTask = Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                await MainActor.run {
                    if countdown > 0 { countdown -= 1 }
                }
            }
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        isTriggered = true
                        isConfirming = false
                    }
                    // 撥打 119
                    if let url = URL(string: "tel://119") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Confirming View
    private var confirmingView: some View {
        VStack(spacing: 12) {
            Text("將在 \(countdown) 秒後觸發 SOS")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.red)

            Button {
                timerTask?.cancel()
                timerTask = nil
                isConfirming = false
                countdown = 5
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 120)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Triggered View
    private var triggeredView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "sos")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Text("SOS 已觸發")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("正在撥打 119...")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.9))
            }

            // GPS 位置
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                Text(locationManager.locationString)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.2)))

            VStack(alignment: .leading, spacing: 10) {
                Text("已通知以下成員")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                ForEach(["林小明", "林大華", "林美華"], id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text(name)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))

            Spacer()

            Button {
                isTriggered = false
                dismiss()
            } label: {
                Text("解除緊急狀態")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    SOSView()
}
