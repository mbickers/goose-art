import Foundation

class AuthenticatedWebSocket<Inbound: Decodable, Outbound: Encodable> {
    private let request: URLRequest
    private let reconnectDelay: TimeInterval = 1.0
    private let onAuthenticationFailed: (() -> Void)?

    private var subscribers: [(Inbound) -> Void] = []

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
        onAuthenticationFailed: (() -> Void)? = nil
    ) {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        let url = components.url!.appendingPathComponent(path)
            .appending(queryItems: queryItems)

        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        self.request = request

        self.onAuthenticationFailed = onAuthenticationFailed
        connect()
    }

    func connect() {
        guard connectionTask == nil else { return }
        connectionTask = Task { await maintainConnection() }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func maintainConnection() async {
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
                print("error receiving message: \(error.localizedDescription)")
                // try? because sleep throws when the task is cancelled mid-wait
                try? await Task.sleep(for: .seconds(reconnectDelay))
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let s):
            guard let data = s.data(using: .utf8) else {
                print("error converting message string to data: invalid UTF-8")
                return
            }
            do {
                let inbound = try JSONDecoder().decode(
                    Inbound.self,
                    from: data
                )
                for subscriber in subscribers {
                    subscriber(inbound)
                }
            } catch {
                print("error decoding message: \(error.localizedDescription)")
            }
        case .data:
            print("error handling message: expected string message, received data message")
        @unknown default:
            print("error handling message: expected string message, received unknown type")
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
                print("error sending message: \(error.localizedDescription)")
            }
        }
    }
}
