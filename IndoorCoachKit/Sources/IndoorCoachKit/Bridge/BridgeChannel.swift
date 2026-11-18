import Foundation
@preconcurrency import Dispatch
import Network

/// Resumes a continuation exactly once.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// Async wrapper around one framed `NWConnection`. All callbacks run on `queue`.
final class BridgeChannel: @unchecked Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func cancel() { connection.cancel() }

    static func map(_ error: NWError) -> BridgeError {
        switch error {
        case .tls: return .authenticationFailed
        case .posix(let code):
            switch code {
            case .ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN, .EHOSTDOWN, .ENOENT, .ECANCELED:
                return .unreachable
            default: return .authenticationFailed
            }
        default: return .unreachable
        }
    }

    /// Starts the connection and waits until it is ready. A TLS (PSK) failure becomes `.authenticationFailed`.
    func start(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            let timer = DispatchWorkItem { [connection] in
                once.run { cont.resume(throwing: BridgeError.unreachable); connection.cancel() }
            }
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    once.run { timer.cancel(); cont.resume() }
                case .failed(let error), .waiting(let error):
                    once.run { timer.cancel(); cont.resume(throwing: Self.map(error)) }
                    connection.cancel()
                case .cancelled:
                    once.run { timer.cancel(); cont.resume(throwing: BridgeError.unreachable) }
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.start(queue: queue)
        }
    }

    func send(_ message: BridgeMessage) async throws {
        let payload = try BridgeCodec.encode(message)
        let framerMessage = NWProtocolFramer.Message(definition: BridgeFramer.definition)
        framerMessage[BridgeFramer.metadataKey] = BridgeCodec.type(of: message)
        let context = NWConnection.ContentContext(identifier: "BridgeMessage", metadata: [framerMessage])
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, contentContext: context, isComplete: true,
                            completion: .contentProcessed { error in
                if let error { cont.resume(throwing: Self.map(error)) } else { cont.resume() }
            })
        }
    }

    /// Receives one framed message; cancels the connection when nothing arrives within `timeout`.
    func receive(timeout: TimeInterval) async throws -> BridgeMessage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<BridgeMessage, Error>) in
            let once = Once()
            let timer = DispatchWorkItem { [connection] in
                once.run { cont.resume(throwing: BridgeError.unreachable); connection.cancel() }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.receiveMessage { data, context, _, error in
                once.run {
                    timer.cancel()
                    if let error { cont.resume(throwing: Self.map(error)); return }
                    guard let context,
                          let meta = context.protocolMetadata(definition: BridgeFramer.definition)
                            as? NWProtocolFramer.Message,
                          let type = meta[BridgeFramer.metadataKey] as? UInt32 else {
                        cont.resume(throwing: BridgeError.malformedMessage)
                        return
                    }
                    do { cont.resume(returning: try BridgeCodec.decode(type: type, payload: data ?? Data())) }
                    catch { cont.resume(throwing: error) }
                }
            }
        }
    }

    /// Sends `message` and waits for the answer. `.failure` becomes `BridgeError.server`.
    func request(_ message: BridgeMessage, timeout: TimeInterval) async throws -> BridgeMessage {
        try await send(message)
        let answer = try await receive(timeout: timeout)
        if case .failure(let text) = answer { throw BridgeError.server(text) }
        return answer
    }
}
