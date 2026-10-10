#if os(macOS)
import SwiftUI
import UpdatePeekKit
import MacPeekCore

/// UpdatePeek's screen: the macOS version with a way to Software Update, and Homebrew and npm sections that only report
/// what those tools themselves say. It never installs anything and never says anything is up to date.
struct UpdatePeekView: View {
    @EnvironmentObject private var store: UpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacOSCard(info: store.operatingSystem)
                PackageManagerCard(source: .homebrew, state: store.homebrew) { store.checkHomebrew() }
                PackageManagerCard(source: .npm, state: store.npm) { store.checkNpm() }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Other apps", systemImage: "questionmark.app").font(.caption.weight(.semibold))
                    Text(UpdateStatusService.otherAppsNotice).font(.caption2).foregroundStyle(.secondary)
                }
                .peekCard()
                .accessibilityElement(children: .combine)
                Text("MacPeek never installs updates. Checks are read-only and ask for no extra permission; only npm's check contacts a server.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct MacOSCard: View {
    let info: OperatingSystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "desktopcomputer")
                VStack(alignment: .leading, spacing: 1) {
                    Text("macOS").font(.system(size: 13, weight: .semibold))
                    Text(info.displayString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 4)
                StatusBadge(text: "Update status not checked", tone: .neutral)
                CopyButton(text: info.displayString, label: "Copy macOS version")
            }
            KeyValueRows(rows: [
                ("Version", info.versionString),
                ("Build", info.build ?? "Not reported"),
                ("Source", "This Mac (installed version)"),
            ])
            Text(UpdateStatusService.osUpdateNotice).font(.caption2).foregroundStyle(.secondary)
            Button("Open Software Update") { SystemSettingsOpener.open(.softwareUpdate) }
                .controlSize(.small)
                .accessibilityLabel("Open Software Update in System Settings")
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }
}

/// Which package manager a card is about, with its wording. Homebrew answers from its local index; npm asks its registry.
private enum PackageSource {
    case homebrew, npm

    var title: String { self == .homebrew ? "Homebrew packages" : "npm global packages" }
    var symbol: String { self == .homebrew ? "shippingbox" : "cube" }
    var checkLabel: String { self == .homebrew ? "Check Homebrew for outdated packages" : "Check npm for outdated global packages" }
    var notInstalled: String {
        self == .homebrew
            ? "Homebrew isn't installed, so there is nothing to check here."
            : "npm wasn't found in /opt/homebrew/bin or /usr/local/bin, so there is nothing to check here. npm installed with nvm, fnm or Volta isn't detected."
    }
    var notChecked: String {
        self == .homebrew
            ? "Press Check to ask Homebrew which packages it lists as outdated. This runs `brew outdated` only and doesn't update Homebrew."
            : "Press Check to ask npm which globally installed packages are outdated. This runs `npm outdated -g` and contacts the npm registry (a network request); project dependencies aren't checked."
    }
    var waiting: String { self == .homebrew ? "Asking Homebrew…" : "Asking npm and its registry…" }
    var none: String { self == .homebrew ? "Homebrew reports no outdated packages." : "npm reports no outdated global packages." }
    func sourceNote(checkedAt: String) -> String {
        switch self {
        case .homebrew:
            return "Source: Homebrew, from its last-fetched package index. Checked \(checkedAt). MacPeek doesn't run brew update, so newer versions may exist that Homebrew hasn't fetched yet."
        case .npm:
            return "Source: npm, compared with its registry at \(checkedAt). Only global packages are checked. \"Latest\" may be a major version your setup isn't ready for, so read the package's notes before upgrading."
        }
    }
}

private struct PackageManagerCard: View {
    let source: PackageSource
    let state: PackageCheckState
    let check: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: source.symbol)
                Text(source.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if state == .checking { ProgressView().controlSize(.small) }
                if canCheck {
                    Button("Check") { check() }
                        .controlSize(.small)
                        .accessibilityLabel(source.checkLabel)
                }
            }
            switch state {
            case .notInstalled:
                Text(source.notInstalled).font(.caption).foregroundStyle(.secondary)
            case .notChecked:
                Text(source.notChecked).font(.caption).foregroundStyle(.secondary)
            case .checking:
                Text(source.waiting).font(.caption).foregroundStyle(.secondary)
            case .failed(let message, let retryable):
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                if retryable { Text("Press Check to try again.").font(.caption2).foregroundStyle(.secondary) }
            case .checked(let report):
                Report(source: source, report: report)
            }
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }

    private var canCheck: Bool {
        switch state {
        case .notInstalled, .checking: return false
        default: return true
        }
    }
}

private struct Report: View {
    let source: PackageSource
    let report: PackageReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.packages.isEmpty {
                Text(source.none).font(.caption)
            } else {
                Text("\(report.packages.count) outdated package\(report.packages.count == 1 ? "" : "s") reported")
                    .font(.caption.weight(.semibold))
                ForEach(report.packages) { package in
                    PackageRow(package: package, known: report.packages)
                    Divider().opacity(0.4)
                }
            }
            Text(source.sourceNote(checkedAt: report.checkedAt.formatted(date: .omitted, time: .standard)))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct PackageRow: View {
    let package: OutdatedPackage
    let known: [OutdatedPackage]

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(package.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(package.kind.label) · \(package.installedLabel) → \(package.currentVersion)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusBadge(text: "Update available", tone: .warning)
            if case .copyUpgradeCommand(let command)? = UpdateActions.action(for: package, among: known) {
                CopyButton(text: command, label: "Copy command to upgrade \(package.name)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
