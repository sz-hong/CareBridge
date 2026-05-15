import SwiftUI

struct FirstAidView: View {
    var isModal: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    @State private var searchText = ""
    @State private var selectedScenario: FirstAidScenario?
    @State private var showSOS = false
    @State private var scenarios: [FirstAidScenario] = []
    @State private var aiAnswer: FirstAidAnswer?
    @State private var isAsking = false
    @State private var askError: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                ForEach(scenarios) { scenario in
                    Button {
                        aiAnswer = nil
                        askError = nil
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
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            if let aiAnswer {
                firstAidAnswerGuide(answer: aiAnswer)
            } else if let selectedScenario {
                firstAidGuide(scenario: selectedScenario)
            } else if let askError {
                errorGuide(message: askError)
            } else {
                emptyGuide
            }

            Spacer()

            Button {
                showSOS = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18))
                    Text("撥打 119 並通知家人")
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
        .navigationTitle("急救指南")
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "asterisk")
                .foregroundStyle(.red)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 20)

            TextField("描述症狀或急救問題", text: $searchText)
                .font(.system(size: 15))
                .onSubmit {
                    Task { await askFirstAid() }
                }

            Spacer()

            Button {
                Task { await askFirstAid() }
            } label: {
                if isAsking {
                    ProgressView()
                } else {
                    Image(systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "paperplane.fill")
                }
            }
            .disabled(isAsking || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func firstAidGuide(scenario: FirstAidScenario) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.red))
                    Text("AI 急救建議")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                }

                Text(scenario.title)
                    .font(.system(size: 18, weight: .bold))

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
                }

                disclaimer
            }
            .padding(16)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func firstAidAnswerGuide(answer: FirstAidAnswer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.red))
                    Text("AI 急救回覆")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                }

                Text(answer.answer)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                if !answer.sources.isEmpty {
                    Divider()
                    ForEach(answer.sources, id: \.self) { source in
                        Text("\(source.title) - \(source.source)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                disclaimer
            }
            .padding(16)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            Text("此內容僅供緊急處置參考，若出現嚴重症狀請立即撥打 119 或聯絡醫療人員。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }

    private var emptyGuide: some View {
        VStack(spacing: 12) {
            Image(systemName: "cross.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("選擇上方急救情境，或輸入症狀讓 AI 提供急救建議。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func errorGuide(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }

    @MainActor
    private func askFirstAid() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAsking else { return }

        isAsking = true
        askError = nil
        aiAnswer = nil
        selectedScenario = nil

        do {
            aiAnswer = try await service.askFirstAid(query: query)
        } catch {
            askError = error.localizedDescription
        }

        isAsking = false
    }
}

#Preview {
    NavigationStack {
        FirstAidView()
    }
}
