import Foundation

class DistributedStateMachineConnection<State: Codable, Action: Codable> {
    private let request: URLRequest
    private let reconnectDelay: TimeInterval = 1.0
    private let onError: ((String) -> Void)?
    private let onAuthenticationFailed: (() -> Void)?

    private var serverMessageSubscribers: [(ServerMessage<State>) -> Void] = []
    private(set) var mostRecentServerMessage: ServerMessage<State>?

    func subscribeToServerMessages(_ callback: @escaping (ServerMessage<State>) -> Void) {
        serverMessageSubscribers.append(callback)
    }

    private var socket: URLSessionWebSocketTask?
    private var queuedPayload: String?
    private var connectionTask: Task<Void, Never>?

    init(
        baseURL: URL,
        path: String,
        token: String,
        deviceId: String,
        onError: ((String) -> Void)? = nil,
        onAuthenticationFailed: (() -> Void)? = nil
    ) {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        let url = components.url!.appendingPathComponent(path)
            .appending(
                queryItems: [
                    URLQueryItem(name: "deviceId", value: deviceId)
                ])

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
                let serverMessage = try JSONDecoder().decode(
                    ServerMessage<State>.self,
                    from: data
                )
                mostRecentServerMessage = serverMessage
                for subscriber in serverMessageSubscribers {
                    subscriber(serverMessage)
                }
            } catch {
                onError?(
                    "Error decoding server message: \(error.localizedDescription)"
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

    func updateActionsToSend(_ actionsToSend: [SequencedAction<Action>]) {
        if actionsToSend.count > 0 {
            let data = try! JSONEncoder().encode(ClientMessage(actions: actionsToSend))
            self.queuedPayload = String(data: data, encoding: .utf8)!
        } else {
            self.queuedPayload = nil
        }
        maybeSendQueuedPayload()
    }

    func maybeSendQueuedPayload() {
        guard let queuedPayload else { return }
        guard let socket else { return }
        Task {
            do {
                try await socket.send(.string(queuedPayload))
            } catch {
                self.socket = nil
                onError?("Error sending actions: \(error.localizedDescription)")
            }
        }
    }

}

struct ClientMessage<Action: Codable>: Codable {
    let actions: [SequencedAction<Action>]
}

struct ServerMessage<State: Codable>: Codable {
    let greatestSeenDeviceSequenceNumber: Int
    let state: State
}
