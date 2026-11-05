import Foundation

public enum HelperError: Error, LocalizedError, Equatable {
    case nodeNotFound
    case nodeTooOld(String)
    case helperNotFound
    case protocolMismatch(Int)
    case remote(code: String, message: String)
    case exited(Int32)
    case timedOut(String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .nodeNotFound: "Node.js 20 or newer is required for code analysis. Install it, or set its path in Settings."
        case .nodeTooOld(let v): "Node.js \(v) is too old; Refine's helper needs 20 or newer."
        case .helperNotFound: "Refine's analysis helper is missing. Rebuild with Scripts/build-app.sh."
        case .protocolMismatch(let v): "The analysis helper speaks protocol \(v); this app expects \(HelperClient.protocolVersion)."
        case .remote(_, let message): message
        case .exited(let status): "The analysis helper stopped unexpectedly (status \(status))."
        case .timedOut(let method): "The analysis helper did not answer \(method) in time."
        case .malformedResponse(let s): "The analysis helper sent an invalid response: \(s)"
        }
    }
}

/// Runs RefineHelper (Node.js) on demand and talks to it over newline-delimited JSON (protocol v1,
/// see SharedSchemas/helper-protocol.schema.json). The process stops after a period of inactivity and
/// whenever the app quits; it also exits by itself when its stdin closes.
public actor HelperClient {
    public static let protocolVersion = 1

    public struct Hello: Decodable, Sendable { public var protocol_: Int; public var helperVersion: String; public var giottoVersion: String; public var node: String
        enum CodingKeys: String, CodingKey { case protocol_ = "protocol", helperVersion, giottoVersion, node }
    }

    private let nodeOverride: String?
    private let scriptOverride: URL?
    private let idleTimeout: Duration
    private var process: Process?
    private var stdin: FileHandle?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var idleTask: Task<Void, Never>?
    private var counter = 0
    public private(set) var hello: Hello?

    public init(nodePath: String? = nil, helperScript: URL? = nil, idleTimeout: Duration = .seconds(90)) {
        self.nodeOverride = nodePath?.isEmpty == false ? nodePath : nil
        self.scriptOverride = helperScript
        self.idleTimeout = idleTimeout
    }

    public var isRunning: Bool { process?.isRunning == true }

    public func request<P: Encodable & Sendable, R: Decodable & Sendable>(_ method: String, _ params: P, as: R.Type = R.self, timeout: Duration = .seconds(180)) async throws -> R {
        try await ensureStarted()
        let data = try await send(method, params, timeout: timeout)
        return try Self.decode(data, as: R.self)
    }

    public func stop() {
        idleTask?.cancel()
        guard let process else { return }
        try? stdin?.close()
        if process.isRunning { process.terminate() }
        self.process = nil
        stdin = nil
        hello = nil
        failAll(HelperError.exited(0))
    }

    // MARK: Process

    private func ensureStarted() async throws {
        if process?.isRunning == true { return }
        let node = try Self.locateNode(override: nodeOverride)
        let script = try scriptOverride ?? Self.locateHelperScript()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script.path]
        p.currentDirectoryURL = script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["NODE_ENV"] = "production"
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        let lines = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            guard let self else { return }
            for line in lines.append(chunk) { self.deliver(line) }
        }
        p.terminationHandler = { [weak self] proc in
            self?.deliverExit(proc)
        }
        try p.run()
        process = p
        stdin = input.fileHandleForWriting
        do {
            let data = try await send("hello", Empty(), timeout: .seconds(15))
            let h = try Self.decode(data, as: Hello.self)
            guard h.protocol_ == Self.protocolVersion else { stop(); throw HelperError.protocolMismatch(h.protocol_) }
            if let major = Int(h.node.dropFirst().prefix(while: \.isNumber)), major < 20 { stop(); throw HelperError.nodeTooOld(h.node) }
            hello = h
        } catch {
            stop()
            throw error
        }
    }

    private struct Empty: Encodable, Sendable {}

    private struct Envelope<P: Encodable>: Encodable {
        let `protocol`: Int
        let id: String
        let method: String
        let params: P
    }

    private func send<P: Encodable & Sendable>(_ method: String, _ params: P, timeout: Duration) async throws -> Data {
        guard let stdin else { throw HelperError.exited(-1) }
        counter += 1
        let id = "r\(counter)"
        var line = try JSONEncoder().encode(Envelope(protocol: Self.protocolVersion, id: id, method: method, params: params))
        line.append(0x0A)
        idleTask?.cancel()
        let timeoutTask = Task { [weak self] in
            guard (try? await Task.sleep(for: timeout)) != nil else { return } // cancelled: the response arrived
            await self?.fail(id, HelperError.timedOut(method))
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try stdin.write(contentsOf: line) } catch {
                pending.removeValue(forKey: id)?.resume(throwing: HelperError.exited(-1))
            }
        }
    }

    private nonisolated func deliver(_ line: Data) { Task { await self.receive(line) } }
    private nonisolated func deliverExit(_ proc: Process) {
        let status = proc.terminationStatus
        let id = ObjectIdentifier(proc)
        Task { await self.exited(status, id) }
    }

    private func receive(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? String,
              let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: line)
        scheduleIdleStop()
    }

    private func fail(_ id: String, _ error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
        // A helper that stopped answering is restarted on the next request.
        if case HelperError.timedOut = error { stop() }
    }

    private func failAll(_ error: Error) {
        let all = pending
        pending.removeAll()
        for c in all.values { c.resume(throwing: error) }
    }

    private func exited(_ status: Int32, _ proc: ObjectIdentifier) {
        guard let process, ObjectIdentifier(process) == proc else { return }
        self.process = nil
        stdin = nil
        hello = nil
        failAll(HelperError.exited(status))
    }

    private func scheduleIdleStop() {
        guard pending.isEmpty else { return }
        idleTask?.cancel()
        let timeout = idleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() { if pending.isEmpty { stop() } }

    // MARK: Decoding

    private struct Response<R: Decodable>: Decodable {
        struct Failure: Decodable { let code: String; let message: String }
        let `protocol`: Int
        let ok: Bool
        let result: R?
        let error: Failure?
    }

    static func decode<R: Decodable>(_ data: Data, as: R.Type) throws -> R {
        let response: Response<R>
        do { response = try JSONDecoder().decode(Response<R>.self, from: data) } catch {
            throw HelperError.malformedResponse(String(describing: error).prefix(300).description)
        }
        guard response.protocol == protocolVersion else { throw HelperError.protocolMismatch(response.protocol) }
        if response.ok, let result = response.result { return result }
        throw HelperError.remote(code: response.error?.code ?? "internal", message: response.error?.message ?? "Unknown helper error")
    }

    // MARK: Locating Node and the helper

    public static func locateNode(override: String?) throws -> String {
        let fm = FileManager.default
        if let override { if fm.isExecutableFile(atPath: override) { return override }; throw HelperError.nodeNotFound }
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(home)/.volta/bin/node", "\(home)/.local/share/fnm/aliases/default/bin/node", "/usr/bin/node"]
        // nvm installs one directory per version; prefer the newest.
        if let versions = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            candidates += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(home)/.nvm/versions/node/\($0)/bin/node" }
        }
        if let found = candidates.first(where: fm.isExecutableFile(atPath:)) { return found }
        throw HelperError.nodeNotFound
    }

    public static func locateHelperScript() throws -> URL {
        let fm = FileManager.default
        if let dir = ProcessInfo.processInfo.environment["REFINE_HELPER_DIR"] {
            let url = URL(fileURLWithPath: dir).appending(path: "dist/src/main.js")
            if fm.fileExists(atPath: url.path) { return url }
        }
        if let bundled = Bundle.main.resourceURL?.appending(path: "RefineHelper/dist/src/main.js"), fm.fileExists(atPath: bundled.path) { return bundled }
        // Development: walk up from the executable (.build/debug/Refine) to the repository.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appending(path: "RefineHelper/dist/src/main.js")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        throw HelperError.helperNotFound
    }
}

/// Splits a byte stream into lines. Called from the pipe's reader thread.
final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}
