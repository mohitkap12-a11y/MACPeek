#if os(macOS)
import SwiftUI
import UpdatePeekKit
import MacPeekCore

/// UpdatePeek's screen: the macOS version with a way to Software Update, and a Homebrew section that only reports what
/// Homebrew itself says. It never installs anything and never says anything is up to date.
struct UpdatePeekView: View {
    @EnvironmentObject private var store: UpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacOSCard(info: store.operatingSystem)
                HomebrewCard(state: store.homebrew)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Other apps", systemImage: "questionmark.app").font(.caption.weight(.semibold))
                    Text(UpdateStatusService.otherAppsNotice).font(.caption2).foregroundStyle(.secondary)
                }
                .peekCard()
                .accessibilityElement(children: .combine)
                Text("MacPeek never installs updates. Checks are read-only and ask for no extra permission.")
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

private struct HomebrewCard: View {
    @EnvironmentObject private var store: UpdateStore
    let state: HomebrewState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "shippingbox")
                Text("Homebrew packages").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if state == .checking { ProgressView().controlSize(.small) }
                if canCheck {
                    Button("Check") { store.checkHomebrew() }
                        .controlSize(.small)
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityLabel("Check Homebrew for outdated packages")
                }
            }
            switch state {
            case .notInstalled:
                Text("Homebrew isn't installed, so there is nothing to check here.").font(.caption).foregroundStyle(.secondary)
            case .notChecked:
                Text("Press Check to ask Homebrew which packages it lists as outdated. This runs `brew outdated` only and doesn't update Homebrew.")
                    .font(.caption).foregroundStyle(.secondary)
            case .checking:
                Text("Asking Homebrew…").font(.caption).foregroundStyle(.secondary)
            case .failed(let message, let retryable):
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                if retryable { Text("Press Check to try again.").font(.caption2).foregroundStyle(.secondary) }
            case .checked(let report):
                Report(report: report)
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
    let report: HomebrewReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.packages.isEmpty {
                Text("Homebrew reports no outdated packages.").font(.caption)
            } else {
                Text("\(report.packages.count) outdated package\(report.packages.count == 1 ? "" : "s") reported")
                    .font(.caption.weight(.semibold))
                ForEach(report.packages) { package in
                    PackageRow(package: package, known: report.packages)
                    Divider().opacity(0.4)
                }
            }
            Text("Source: Homebrew, from its last-fetched package index. Checked \(report.checkedAt.formatted(date: .omitted, time: .standard)). MacPeek doesn't run brew update, so newer versions may exist that Homebrew hasn't fetched yet.")
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
