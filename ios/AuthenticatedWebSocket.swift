import Foundation

// Maintains a bearer-token-authenticated websocket, reconnecting after transient
// failures. Generic over the message types, with two stipulations on the protocol
// it carries:
// - Outbound: holds a single latest message, replacing any unsent one, and re-sends
//   it on every reconnect. Messages must be complete and idempotent, not deltas.
// - Inbound: only the most recent message is cached for late subscribers, so each
//   message must be a self-contained snapshot.
class AuthenticatedWebSocket<Inbound: Decodable, Outbound: Encodable> {
    private let request: URLRequest
    private let reconnectDelay: TimeInterval = 1.0
    private let onError: ((String) -> Void)?
    private let onAuthenticationFailed: (() -> Void)?

    private var subscribers: [(Inbound) -> Void] = []
    private(set) var mostRecentMessage: Inbound?

    func subscribe(_ callback: @escaping (Inbound) -> Void) {
        subscribers.append(callback)
    }

    private var socket: URLSessionWebSocketTask?
    private var queuedPayload: String?
    private var connectionTask: Task<Void, Never>?

    init(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String,
        onError: ((String) -> Void)? = nil,
        onAuthenticationFailed: (() -> Void)? = nil
    ) {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        let url = components.url!.appendingPathComponent(path)
            .appending(queryItems: queryItems)

        // the token goes in a header rather than the query string, which uvicorn
        // writes to its access log in cleartext on every connect
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        self.request = request

        self.onError = onError
        self.onAuthenticationFailed = onAuthenticationFailed
        connectionTask = Task { await connect() }
    }

    // the connection task retains this connection, so without an explicit teardown it
    // outlives the session that made it and keeps reconnecting with a stale token
    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func connect() async {
        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: request)
            socket.resume()
            self.socket = socket
            maybeSendQueuedPayload()

            do {
                while true {
                    let message = try await socket.receive()
                    handleMessage(message)
                }
            } catch {
                self.socket = nil
                if Task.isCancelled { return }
                // the server rejects the handshake with 403 when the token is bad,
                // so retrying would spin forever against a credential that cannot work
                if (socket.response as? HTTPURLResponse)?.statusCode == 403 {
                    onAuthenticationFailed?()
                    return
                }
                onError?(
                    "Error receiving message: \(error.localizedDescription)"
                )
                // try? because sleep throws when the task is cancelled mid-wait
                try? await Task.sleep(for: .seconds(reconnectDelay))
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let s):
            guard let data = s.data(using: .utf8) else {
                onError?(
                    "Error converting message string to data: invalid UTF-8"
                )
                return
            }
            do {
                let inbound = try JSONDecoder().decode(
                    Inbound.self,
                    from: data
                )
                mostRecentMessage = inbound
                for subscriber in subscribers {
                    subscriber(inbound)
                }
            } catch {
                onError?(
                    "Error decoding message: \(error.localizedDescription)"
                )
            }
        case .data:
            onError?(
                "Error handling message: expected string message, received data message"
            )
        @unknown default:
            onError?(
                "Error handling message: expected string message, received unknown message type"
            )
        }
    }

    // nil clears the outbox so nothing is re-sent on the next reconnect
    func setOutbound(_ message: Outbound?) {
        queuedPayload = message.map { message in
            String(data: try! JSONEncoder().encode(message), encoding: .utf8)!
        }
        maybeSendQueuedPayload()
    }

    private func maybeSendQueuedPayload() {
        guard let queuedPayload else { return }
        guard let socket else { return }
        Task {
            do {
                try await socket.send(.string(queuedPayload))
            } catch {
                self.socket = nil
                onError?("Error sending message: \(error.localizedDescription)")
            }
        }
    }
}
