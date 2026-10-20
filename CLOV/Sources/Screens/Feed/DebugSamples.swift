import SwiftUI

#if DEBUG
/// Local-only interactive preview for checking the live voting card on the
/// simulator. Votes stay in this view and are never written to Supabase.
struct SampleVotingSessionCard: View {
    @State private var selectedLook: Int?
    @State private var showingDetails = false

    private let looks: [(id: Int, title: String, imageURL: String, votes: Int)] = [
        (1, "Soft layers", "https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=900&q=85", 7),
        (2, "Cool classic", "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=900&q=85", 5)
    ]

    private var totalVotes: Int { looks.reduce(0) { $0 + $1.votes } + (selectedLook == nil ? 0 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                AvatarView(url: nil, nickname: "Maya", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maya Chen")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Sample Fit-Check")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Label("LIVE", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.iconSage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.iconSage.opacity(0.11), in: Capsule())
            }

            Text("Which look works for a coffee date?")
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 9) {
                ForEach(looks, id: \.id) { look in
                    Button {
                        guard selectedLook == nil else { return }
                        withAnimation(Theme.press) { selectedLook = look.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: look.imageURL, label: look.title)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 196)
                                    .clipped()
                                LinearGradient(colors: [.clear, .black.opacity(0.52)], startPoint: .center, endPoint: .bottom)
                                HStack {
                                    Text("LOOK \(look.id == 1 ? "A" : "B")")
                                        .font(.system(size: 10, weight: .black))
                                        .tracking(0.8)
                                    Spacer()
                                    if selectedLook == look.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(9)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(selectedLook == look.id ? Theme.accent : Theme.line.opacity(0.10), lineWidth: selectedLook == look.id ? 2 : 1)
                            }

                            HStack(spacing: 5) {
                                Text(look.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if selectedLook != nil {
                                    Text("\(Int((Double(look.votes + (selectedLook == look.id ? 1 : 0)) / Double(totalVotes) * 100).rounded()))%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedLook != nil)
                    .accessibilityLabel("Vote for look \(look.id == 1 ? "A" : "B"), \(look.title)")
                    .accessibilityAddTraits(selectedLook == look.id ? .isSelected : [])
                }
            }

            HStack {
                Label("\(totalVotes) votes", systemImage: "chart.bar.fill")
                Spacer()
                Button { showingDetails = true } label: {
                    Label("3 comments", systemImage: "bubble.left")
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .font(.system(.caption, design: .default).weight(.medium))
            .foregroundStyle(Theme.mutedForeground)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Theme.line.opacity(0.1), lineWidth: 1))
        .sheet(isPresented: $showingDetails) {
            SampleFitCheckDetailView()
        }
    }
}

private struct SampleComment: Identifiable {
    let id = UUID()
    let author: String
    let message: String
}

private struct SampleFitCheckDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var comments = [
        SampleComment(author: "Ava", message: "The soft layers feel perfect for a coffee date."),
        SampleComment(author: "Nina", message: "Look B feels polished without being too dressed up."),
        SampleComment(author: "Jules", message: "A for me — love the proportions!")
    ]

    private let imageURLs = [
        "https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=900&q=85",
        "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=900&q=85"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("LIVE FIT-CHECK · SAMPLE")
                        .font(.system(.caption2, design: .default).weight(.black))
                        .tracking(1.3)
                        .foregroundStyle(Theme.accent)

                    HStack(spacing: 10) {
                        AvatarView(url: nil, nickname: "Maya", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maya Chen").font(.system(.subheadline, design: .default).weight(.semibold))
                            Text("4 hours left · Coffee date")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        Spacer()
                    }

                    Text("Which look works for a coffee date?")
                        .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                        .foregroundStyle(Theme.ink)

                    HStack(spacing: 10) {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: url)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 250)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                Text(index == 0 ? "LOOK A · SOFT LAYERS" : "LOOK B · COOL CLASSIC")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.3)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    HStack {
                        Label("12 votes", systemImage: "chart.bar.fill")
                        Spacer()
                        Label("Voting is open", systemImage: "clock")
                    }
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(Theme.mutedForeground)

                    Rectangle().fill(Theme.line.opacity(0.12)).frame(height: 1)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Notes from the circle")
                            .font(Theme.editorialFont(size: 23, relativeTo: .title3))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(comments.count)")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 10) {
                            AvatarView(url: nil, nickname: comment.author, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.author)
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(comment.message)
                                    .font(.system(.subheadline, design: .default))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.muted, in: Capsule())
                    Button(action: postComment) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.inverseText)
                            .frame(width: 38, height: 38)
                            .background(Theme.ink, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Post comment")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.background)
            }
            .navigationTitle("Fit-Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func postComment() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        comments.append(SampleComment(author: "You", message: message))
        draft = ""
        Haptics.success()
    }
}

#Preview("Sample voting card") {
    SampleVotingSessionCard()
        .padding(20)
        .background(Theme.background)
}
#endif
