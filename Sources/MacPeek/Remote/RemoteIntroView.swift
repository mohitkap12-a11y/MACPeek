#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// One picture of MacPeek Remote with what it shows.
private struct RemoteIntroSlide: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let text: String
    /// The plan shown beside the title for a feature of a paid plan of MacPeek Remote: "Pro" or "Ultra".
    var plan: String? = nil

    /// The picture for the window's appearance, from the app bundle (scripts/build-app.sh copies Resources/RemoteIntro
    /// there). Nil when MacPeek runs outside a bundle (`swift run`): the slide then shows its symbol instead.
    func image(dark: Bool) -> NSImage? {
        Bundle.main.url(forResource: "RemoteIntro-\(id)\(dark ? "-dark" : "")", withExtension: "heic")
            .flatMap { NSImage(contentsOf: $0) }
    }

    // Every feature named here is in MacPeek Remote's own source; the pictures are drawn from its redesign mockups
    // (macpeek-remote docs/mockups/redesign/app.html), with sample Macs.
    static let all = [
        RemoteIntroSlide(id: "overview", symbol: "square.grid.2x2",
                         title: "Every Mac you look after, in one window",
                         text: "CPU, memory and disk for each of your Macs, live. The ones that need a look say why."),
        RemoteIntroSlide(id: "mac", symbol: "gauge.medium",
                         title: "Open a Mac. See everything, now.",
                         text: "A live strip of CPU, GPU, memory and disk, then Overview, History, Peeks, Device and Management."),
        RemoteIntroSlide(id: "history", symbol: "chart.xyaxis.line",
                         title: "30 days of history",
                         text: "When each Mac was reachable, and its CPU, GPU, memory, disk and network. Export it as CSV. The Free plan shows the last 24 hours.",
                         plan: "Pro"),
        RemoteIntroSlide(id: "peeks", symbol: "eye",
                         title: "Every Peek, on another Mac",
                         text: "Ports, Processes, GPU, Containers, Models, Bluetooth and more, on a Mac you are not sitting at."),
        RemoteIntroSlide(id: "anywhere", symbol: "globe",
                         title: "Reach your Macs from anywhere",
                         text: "An end-to-end encrypted relay, no open ports. SSH in one click, or tunnel a port to localhost.",
                         plan: "Ultra"),
        RemoteIntroSlide(id: "alerts", symbol: "bell.badge",
                         title: "Alerts, with notifications",
                         text: "High CPU, memory pressure, a full disk, heat or a Mac gone offline: a notification when it starts.",
                         plan: "Pro"),
        RemoteIntroSlide(id: "search", symbol: "magnifyingglass",
                         title: "⌘K finds anything",
                         text: "Jump to a Mac, a screen or a Peek, or filter the fleet with cpu>80, port:3000, offline or group:home."),
        RemoteIntroSlide(id: "groups", symbol: "folder",
                         title: "Groups for your Macs",
                         text: "Sort Macs into groups such as Studio, Build and Home, synced to your other devices."),
        RemoteIntroSlide(id: "activity", symbol: "clock.arrow.circlepath",
                         title: "Activity and Logs",
                         text: "Each port freed, process quit and SSH opened, and how every connection was made and ended."),
    ]
}

/// The introduction window's content: the pictures sliding by, what MacPeek Remote is, and the three answers.
struct RemoteIntroView: View {
    static let size = CGSize(width: 720, height: 640)
    private static let pictureSize = CGSize(width: 672, height: 394)

    @EnvironmentObject private var intro: RemoteIntroController
    @EnvironmentObject private var settings: AppSettings
    @State private var index = 0
    @State private var hovering = false
    private let slides = RemoteIntroSlide.all
    private let advance = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            pictures
                .padding(.top, 34)
            dots
                .padding(.top, 12)
            words
                .padding(.top, 14)
                .padding(.horizontal, 40)
            Spacer(minLength: 10)
            answers
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PeekTheme.ground)
        .preferredColorScheme(settings.appearance.colorScheme)
        // The pictures move on by themselves, but not while the pointer rests on them.
        .onReceive(advance) { _ in if !hovering { go(to: index + 1) } }
    }

    private func go(to new: Int) {
        withAnimation(.easeInOut(duration: 0.45)) { index = (new + slides.count) % slides.count }
    }

    // MARK: Pictures

    private var pictures: some View {
        HStack(spacing: 0) {
            ForEach(slides) { slide in
                RemoteIntroPicture(slide: slide)
                    .frame(width: Self.pictureSize.width, height: Self.pictureSize.height)
            }
        }
        .offset(x: -CGFloat(index) * Self.pictureSize.width)
        .frame(width: Self.pictureSize.width, height: Self.pictureSize.height, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PeekTheme.border))
        .overlay(alignment: .leading) { arrow("chevron.left", label: "Previous picture") { go(to: index - 1) } }
        .overlay(alignment: .trailing) { arrow("chevron.right", label: "Next picture") { go(to: index + 1) } }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pictures of MacPeek Remote, \(index + 1) of \(slides.count)")
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.45), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .opacity(hovering ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(slides.indices, id: \.self) { i in
                Button { go(to: i) } label: {
                    Capsule()
                        .fill(i == index ? PeekTheme.accent : PeekTheme.track)
                        .frame(width: i == index ? 18 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Picture \(i + 1): \(slides[i].title)")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    // MARK: Words

    private var words: some View {
        VStack(spacing: 7) {
            Text("NEW · FREE FOR 3 MACS")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(PeekTheme.pillText)
                .background(PeekTheme.pillBackground, in: Capsule())
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(slides[index].title)
                    .font(.system(size: 21, weight: .bold))
                    .multilineTextAlignment(.center)
                if let plan = slides[index].plan {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(PeekTheme.muted)
                        .overlay(Capsule().strokeBorder(PeekTheme.border))
                        .help("Part of MacPeek Remote \(plan)\(plan == "Pro" ? " and Ultra" : ""). MacPeek Remote is free for up to 3 Macs on your network.")
                }
            }
            Text(slides[index].text)
                .font(.system(size: 13.5))
                .foregroundStyle(PeekTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("MacPeek stays free on this Mac. MacPeek Remote is a separate console app for the Macs you look after: free for up to 3 on your network.")
                .font(.system(size: 12))
                .foregroundStyle(PeekTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        // The words change with the picture without sliding: only a quick fade.
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    // MARK: Answers

    private var answers: some View {
        HStack(spacing: 10) {
            Button("Never show this again") { intro.neverShowAgain() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(PeekTheme.muted)
                .help("The MacPeek Remote row at the bottom of MacPeek still opens this.")
            Spacer()
            Button("Remind Me Later") { intro.remindLater() }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .help("Shows this again in a week.")
            Button { intro.getRemote() } label: {
                Label("Get MacPeek Remote", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(PeekTheme.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .help("Opens remote.macpeekapp.com in your browser.")
        }
    }
}

/// A slide's picture, or its symbol on a card when the picture is not in the bundle.
private struct RemoteIntroPicture: View {
    let slide: RemoteIntroSlide
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = slide.image(dark: colorScheme == .dark) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel(slide.title)
        } else {
            VStack(spacing: 14) {
                Image(systemName: slide.symbol)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(PeekTheme.accent)
                Text("MacPeek Remote").font(.system(size: 15, weight: .semibold)).foregroundStyle(PeekTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PeekTheme.card)
            .accessibilityHidden(true)
        }
    }
}

/// The launcher's row at the bottom of MacPeek: what MacPeek Remote is, in one line. It opens the introduction.
struct RemoteIntroRow: View {
    @EnvironmentObject private var intro: RemoteIntroController

    var body: some View {
        Button { intro.show() } label: {
            HStack(spacing: 10) {
                Image(systemName: "display.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PeekTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(PeekTheme.pillBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("MacPeek Remote").font(.system(size: 13, weight: .medium))
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .foregroundStyle(PeekTheme.pillText)
                            .background(PeekTheme.pillBackground, in: Capsule())
                    }
                    Text("All your Macs, live in one window").font(.caption).foregroundStyle(PeekTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PeekRowButtonStyle())
        .overlay(alignment: .top) { Rectangle().fill(PeekTheme.border).frame(height: 1) }
        .help("See what MacPeek Remote is")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MacPeek Remote, new: all your Macs, live in one window")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
