import SwiftUI

struct FirstAidView: View {
    var isModal: Bool = false          // true = 從 HomeView sheet 開啟，需要關閉按鈕
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    @State private var searchText = ""
    @State private var selectedScenario: FirstAidScenario? = nil
    @State private var showSOS = false
    @State private var scenarios: [FirstAidScenario] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "asterisk")
                    .foregroundStyle(.red)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 20)
                TextField("描述當前緊急狀況", text: $searchText)
                    .font(.system(size: 15))
                Spacer()
                Button { } label: {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Quick scenario buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(scenarios) { scenario in
                    Button {
                        selectedScenario = scenario
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(scenario.color.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: scenario.icon)
                                    .font(.system(size: 22))
                                    .foregroundStyle(scenario.color)
                            }
                            Text(scenario.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // AI First Aid Guide
            if let scenario = selectedScenario {
                firstAidGuide(scenario: scenario)
            } else {
                emptyGuide
            }

            Spacer()

            // SOS bottom button
            Button {
                showSOS = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18))
                    Text("呼叫 119 + 通知家屬")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(.red))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandBackground)
        .navigationTitle("急救指引")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
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
        .sheet(isPresented: $showSOS) {
            SOSView()
        }
        .task {
            scenarios = (try? await service.fetchFirstAidScenarios()) ?? []
        }
    }

    // MARK: - First Aid Guide
    private func firstAidGuide(scenario: FirstAidScenario) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // AI header
                HStack(spacing: 8) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.red))
                    Text("AI 實時急救建議")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Text("初步急救步驟")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 16)

                ForEach(Array(scenario.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(step)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                }

                // Disclaimer
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    Text("本指引基於衛福部急救手冊，僅供參考，請依實際情況判斷並盡快求得專業醫療協助。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var emptyGuide: some View {
        VStack(spacing: 12) {
            Image(systemName: "cross.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("選擇情況類型或輸入描述\n以獲取急救指引")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

#Preview {
    NavigationStack {
        FirstAidView()
    }
}
