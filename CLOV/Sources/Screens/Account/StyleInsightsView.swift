@preconcurrency import SwiftUI

@MainActor
struct StyleInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var report: WeeklyStyleReport?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR WEEK")
                    .font(Theme.micro)
                    .tracking(1.5)
                    .foregroundStyle(Theme.accentDeep)
                Text("Style momentum")
                    .font(Theme.editorialFont(size: 34))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                Text("A quick look at how you showed up this week.")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)

                AsyncStateView(isLoading: isLoading, error: error, topPadding: 16, hasLoaded: hasLoaded, retry: { await load() }) {
                    if let report {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Theme.iconCoral)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(report.currentStreak)-day streak")
                                        .font(Theme.title)
                                        .foregroundStyle(Theme.ink)
                                    Text(report.currentStreak == 0 ? "Start with one small style action today." : "Keep the momentum going.")
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                            .softCard()

                            LazyVGrid(columns: columns, spacing: 12) {
                                metric("Votes", value: report.votesCast, icon: "hand.thumbsup.fill")
                                metric("Fit-Checks", value: report.fitChecksPosted, icon: "camera.fill")
                                metric("Comments", value: report.commentsWritten, icon: "bubble.left.fill")
                                metric("New pieces", value: report.wardrobePiecesAdded, icon: "hanger")
                            }

                            if let occasion = report.topOccasion {
                                HStack {
                                    Text("Your top vibe: \(occasion)")
                                        .font(Theme.bodyEmphasis)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                }
                                .softCard(radius: Theme.tileRadius, padding: 14)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Your week")
        .navigationBarTitleDisplayMode(.inline)
        .revisionTask(appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .softCard(radius: Theme.tileRadius, padding: 14)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            report = try await API.fetchWeeklyStyleReport(userId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load your weekly report. Please try again."
        }
    }
}
