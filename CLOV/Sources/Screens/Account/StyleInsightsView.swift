@preconcurrency import SwiftUI

@MainActor
struct StyleInsightsView: View {
    var inline = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var report: WeeklyStyleReport?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @ScaledMetric(relativeTo: .title2) private var streakIconSize: CGFloat = 28

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if inline {
                analyticsPanel
                    .accessibilityIdentifier("profile.analytics.content")
            } else {
                ScrollView {
                    reportContent.padding(20)
                }
                .clearsTabBar()
                .background(Theme.background)
                .navigationTitle("Your week")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await load() }
            }
        }
        .revisionTask(appState.contentRevision) { await load() }
    }

    private var analyticsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Style momentum")
                    .font(Theme.displayFont)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Last 7 days")
                    .font(Theme.label)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(16)

            AsyncStateView(isLoading: isLoading, error: error, topPadding: 0,
                           hasLoaded: hasLoaded, retry: { await load() }) {
                if let report {
                    analyticsMetrics(report).padding(.horizontal, 16)
                    analyticsHighlights(report)
                }
            }
            .padding(.bottom, report == nil || error != nil ? 16 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.line.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
    }

    private func analyticsMetrics(_ report: WeeklyStyleReport) -> some View {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: count),
                         alignment: .leading, spacing: 0) {
            analyticsMetric("Votes", value: report.votesCast, id: "votes")
            analyticsMetric("Fit-Checks", value: report.fitChecksPosted, id: "posts")
            analyticsMetric("Comments", value: report.commentsWritten, id: "comments")
            analyticsMetric("New pieces", value: report.wardrobePiecesAdded, id: "wardrobe")
        }
    }

    private func analyticsMetric(_ title: String, value: Int, id: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(Theme.body)
                        .foregroundStyle(Theme.mutedForeground)
                    Spacer(minLength: 0)
                    analyticsValue(value).fixedSize(horizontal: true, vertical: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    analyticsValue(value)
                    Text(title)
                        .font(Theme.label)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().overlay(Theme.line.opacity(0.08)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted())
        .accessibilityIdentifier("profile.analytics.\(id)")
    }

    private func analyticsValue(_ value: Int) -> some View {
        Text(value.formatted())
            .font(Theme.editorialFont(size: 31, relativeTo: .title2))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
    }

    private func analyticsHighlights(_ report: WeeklyStyleReport) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            analyticsHighlight(
                "Current streak", value: "\(report.currentStreak.formatted()) \(report.currentStreak == 1 ? "day" : "days")",
                symbol: "flame"
            )
            if let occasion = report.topOccasion, !occasion.isEmpty {
                analyticsHighlight("Top occasion", value: occasion, symbol: "tag")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.accentTint)
    }

    private func analyticsHighlight(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentDeep)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.mutedForeground)
                Text(value)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var reportContent: some View {
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
                                    .font(.system(size: streakIconSize, weight: .bold))
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
