import Foundation
import K2Core

@MainActor
final class BackendClient {
    private var process: Process?
    private var stdoutEnded = false
    private var exitStatus: Int32?
    private var protocolError: Error?
    private var stderrText = ""
    private var finished: ((Int32, Error?) -> Void)?
    private var jobID: String?
    private var controlInput: FileHandle?

    func start(_ request: BackendRequest, onEvent: @escaping (BackendEvent) -> Void,
               onFinish: @escaping (Int32, Error?) -> Void) throws {
        guard process == nil else { throw NSError(domain: "K2", code: 1, userInfo: [NSLocalizedDescriptionKey: "后台任务仍在运行"]) }
        guard let helper = Bundle.main.url(forResource: "k2-backend", withExtension: nil, subdirectory: "Backend") else {
            throw NSError(domain: "K2", code: 2, userInfo: [NSLocalizedDescriptionKey: "应用内缺少升级核心，请重新构建应用"])
        }
        let input = Pipe(), output = Pipe(), errors = Pipe()
        let child = Process(); child.executableURL = helper
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONHOME"); environment.removeValue(forKey: "PYTHONPATH")
        child.environment = environment
        child.currentDirectoryURL = helper.deletingLastPathComponent()
        child.standardInput = input; child.standardOutput = output; child.standardError = errors
        let decoder = EventLineDecoder()
        stdoutEnded = false; exitStatus = nil; protocolError = nil; stderrText = ""
        finished = onFinish; jobID = request.id
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                var error: Error?
                do { try decoder.finish() } catch let failure { error = failure }
                DispatchQueue.main.async {
                    guard self?.jobID == request.id else { return }
                    self?.stdoutEnded = true
                    if let error { self?.protocolError = error }
                    self?.finalizeIfReady()
                }
                return
            }
            do {
                let events = try decoder.feed(data)
                DispatchQueue.main.async {
                    guard self?.jobID == request.id else { return }
                    for event in events where event.id == request.id { onEvent(event) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self?.jobID == request.id else { return }
                    self?.protocolError = error
                    // Do not terminate an upgrade process because the UI pipe
                    // failed; allow the core to close its hardware safely.
                    if request.operation.canCancel { self?.process?.interrupt() }
                }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard self?.jobID == request.id else { return }
                self?.stderrText = String(((self?.stderrText ?? "") + text).suffix(8192))
            }
        }
        child.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard self?.jobID == request.id else { return }
                self?.exitStatus = process.terminationStatus
                self?.finalizeIfReady()
            }
        }
        do {
            try child.run()
            process = child
            try input.fileHandleForWriting.write(contentsOf: WireCodec.requestData(request))
            if request.operation == .monitor { controlInput = input.fileHandleForWriting }
            else { try input.fileHandleForWriting.close() }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if child.isRunning { child.interrupt() }
            process = nil; jobID = nil; finished = nil
            throw error
        }
    }

    private func finalizeIfReady() {
        guard stdoutEnded, let status = exitStatus else { return }
        let callback = finished
        let error = protocolError
        try? controlInput?.close(); controlInput = nil
        process = nil; finished = nil; jobID = nil
        callback?(status, error)
    }

    func cancelReadOnly() { process?.interrupt() }
    func sendControl(_ fields: [String: JSONValue]) throws {
        guard let controlInput else { throw NSError(domain: "K2", code: 3, userInfo: [NSLocalizedDescriptionKey: "采集后台未连接"]) }
        var data = try JSONEncoder().encode(fields); data.append(10)
        try controlInput.write(contentsOf: data)
    }
}
