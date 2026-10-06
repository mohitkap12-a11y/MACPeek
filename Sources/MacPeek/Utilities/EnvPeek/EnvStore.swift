#if os(macOS)
import Foundation
import EnvPeekKit

/// Observable state for EnvPeek. Values live only in memory and on screen: nothing here is logged, written to
/// disk or sent anywhere, and process variables and revealed secrets are dropped when the screen is left.
@MainActor
final class EnvStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case macPeek = "This app"
        case process = "A process"
        var id: String { rawValue }
    }

    @Published private(set) var mode: Mode = .macPeek
    @Published var query = ""
    @Published var pidText = ""
    @Published private(set) var variables: [EnvVariable] = []
    /// What the list on screen came from. Nil when nothing is shown, so the label can never name a stale source.
    @Published private(set) var source: EnvSource?
    @Published private(set) var error: String?
    @Published private(set) var revealed: Set<String> = []
    @Published var expandedPathVariable: String?

    private let reader: ProcessEnvironmentReading
    private let ownEnvironment: () -> [String: String]

    init(reader: ProcessEnvironmentReading, ownEnvironment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }) {
        self.reader = reader
        self.ownEnvironment = ownEnvironment
    }

    var visible: [EnvVariable] { EnvSearch.filter(variables, query: query) }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        clearValues()
        if newMode == .macPeek { loadOwn() }
    }

    func loadOwn() {
        source = .macPeek
        variables = MacPeekEnvironment.variables(ownEnvironment())
        error = nil
    }

    /// Reads the environment of the process in `pidText`. Only processes your user owns can be read.
    func inspectProcess() {
        let trimmed = pidText.trimmingCharacters(in: .whitespaces)
        guard let pid = Int(trimmed), pid > 0, pid <= Int(Int32.max) else {
            clearValues()
            error = "Enter a valid process ID (PID). ProcessPeek shows PIDs."
            return
        }
        do {
            let arguments = try reader.read(pid: pid)
            let name = arguments.executable.flatMap { $0.split(separator: "/").last.map(String.init) }
            source = .process(pid: pid, name: name)
            variables = arguments.environment
            revealed = []
            expandedPathVariable = nil
            error = nil
        } catch {
            clearValues()
            self.error = error.localizedDescription
            Log.envPeek.error("process read failed")
        }
    }

    func toggleReveal(_ name: String) {
        if revealed.contains(name) { revealed.remove(name) } else { revealed.insert(name) }
    }

    func isRevealed(_ variable: EnvVariable) -> Bool { !variable.isSensitive || revealed.contains(variable.name) }

    /// Called when the screen is left: drop every value from memory and hide anything that was revealed.
    func leave() {
        revealed = []
        expandedPathVariable = nil
        variables = []
        source = nil
    }

    func enter() {
        if mode == .macPeek { loadOwn() }
    }

    private func clearValues() {
        source = nil
        variables = []
        revealed = []
        expandedPathVariable = nil
        error = nil
    }
}
#endif
