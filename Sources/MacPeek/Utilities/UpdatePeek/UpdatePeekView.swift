#if os(macOS)
import SwiftUI
import UpdatePeekKit
import MacPeekCore

/// UpdatePeek's screen: the macOS version and what macOS says about updates (with a way to open Software Update), and
/// Homebrew and npm sections that only report what those tools themselves say. Updating anything is left to Software
/// Update, Terminal or, for one npm package at a time, an Update button the user has to confirm.
struct UpdatePeekView: View {
    @EnvironmentObject private var store: UpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MacOSCard(info: store.operatingSystem, state: store.macOS)
                PackageManagerCard(source: .homebrew, state: store.homebrew) { store.checkHomebrew() }
                PackageManagerCard(source: .npm, state: store.npm) { store.checkNpm() }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Other apps", systemImage: "questionmark.app").font(.caption.weight(.semibold))
                    Text(UpdateStatusService.otherAppsNotice).font(.caption2).foregroundStyle(.secondary)
                }
                .peekCard()
                .accessibilityElement(children: .combine)
                Text("MacPeek never installs macOS or Homebrew updates, and updates an npm package only when you press Update and confirm. Check now and npm's Check contact a server; nothing runs until you press a button.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct MacOSCard: View {
    @EnvironmentObject private var store: UpdateStore
    let info: OperatingSystemInfo
    let state: MacOSUpdateState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "desktopcomputer")
                VStack(alignment: .leading, spacing: 1) {
                    Text("macOS").font(.system(size: 13, weight: .semibold))
                    Text(info.displayString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 4)
                badge
                CopyButton(text: info.displayString, label: "Copy macOS version")
            }
            KeyValueRows(rows: [
                ("Version", info.versionString),
                ("Build", info.build ?? "Not reported"),
            ])
            statusBody
            HStack(spacing: 8) {
                Button("Open Software Update") { SystemSettingsOpener.open(.softwareUpdate) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open Software Update in System Settings")
                Button("Check now") { store.checkMacOS() }
                    .disabled(state == .checking)
                    .help("Ask Apple's update servers what is available (uses the network)")
                    .accessibilityLabel("Check now for macOS updates")
                if state == .checking { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
            Text(UpdateStatusService.osUpdateNotice).font(.caption2).foregroundStyle(.tertiary)
        }
        .peekCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .notChecked: StatusBadge(text: "Not checked", tone: .neutral)
        case .checking: StatusBadge(text: "Checking…", tone: .neutral)
        case .failed: StatusBadge(text: "Check failed", tone: .warning)
        case .known(let report):
            if report.updates.isEmpty {
                StatusBadge(text: "None reported", tone: .neutral)
            } else {
                StatusBadge(text: "\(report.updates.count) update\(report.updates.count == 1 ? "" : "s") found", tone: .warning)
            }
        }
    }

    @ViewBuilder private var statusBody: some View {
        switch state {
        case .notChecked:
            Text("macOS has no update listed in its own record, and MacPeek hasn't asked. Press Check now to ask Apple's update servers, or open Software Update.")
                .font(.caption).foregroundStyle(.secondary)
        case .checking:
            Text("Asking Apple's update servers… this can take a minute.").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            Text("Press Check now to try again.").font(.caption2).foregroundStyle(.secondary)
        case .known(let report):
            if report.updates.isEmpty {
                Text("macOS reports no new software available.").font(.caption)
            } else {
                Text("macOS lists these updates. Install them in Software Update; MacPeek never installs macOS updates.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(report.updates) { update in
                    MacOSUpdateRow(update: update)
                    Divider().opacity(0.4)
                }
            }
            Text(sourceNote(report)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func sourceNote(_ report: MacOSUpdateReport) -> String {
        let when = report.checkedAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
        switch report.source {
        case .macOSRecord:
            let date = when.map { " (" + $0 + ")" } ?? ""
            return "Source: macOS's own record of its last check" + date + ". It can be out of date; press Check now to ask again."
        case .softwareUpdateTool:
            let time = when.map { " at " + $0 } ?? ""
            return "Source: softwareupdate, which asked Apple's update servers" + time + "."
        }
    }
}

private struct MacOSUpdateRow: View {
    let update: MacOSUpdate

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(update.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if let version = update.version {
                    Text("Version \(version)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if update.isRecommended == true { StatusBadge(text: "Recommended", tone: .info) }
            if update.requiresRestart == true { StatusBadge(text: "Restart required", tone: .neutral) }
        }
        .accessibilityElement(children: .combine)
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
    @EnvironmentObject private var store: UpdateStore
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
            if source == .npm, let notice = store.npmNotice { BannerView(banner: notice) }
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
    @EnvironmentObject private var store: UpdateStore
    @State private var confirming = false
    let package: OutdatedPackage
    let known: [OutdatedPackage]

    private var isUpdating: Bool { store.updatingNpm == package.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(package.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(package.kind.label) · \(package.installedLabel) → \(package.currentVersion)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if isUpdating {
                    ProgressView().controlSize(.small)
                    Text("Updating…").font(.caption2).foregroundStyle(.secondary)
                } else {
                    StatusBadge(text: "Update available", tone: .warning)
                    if UpdateActions.canUpdateInMacPeek(package, among: known) {
                        Button("Update") { confirming = true }
                            .controlSize(.small)
                            .disabled(store.updatingNpm != nil)
                            .accessibilityLabel("Update \(package.name) with npm")
                    }
                }
                if case .copyUpgradeCommand(let command)? = UpdateActions.action(for: package, among: known) {
                    CopyButton(text: command, label: "Copy command to upgrade \(package.name)")
                }
            }
            if confirming {
                KillConfirmationView(
                    title: "Run npm install -g \(package.name)@latest? That is the latest version, which may be a new major version.",
                    confirmLabel: "Update", destructive: false,
                    onCancel: { confirming = false },
                    onConfirm: { confirming = false; store.updateNpm(package) })
            }
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
