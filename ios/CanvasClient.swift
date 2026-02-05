import Foundation

class CanvasClient {
    let userId: String
    private let canvasURL: URL
    private let reconnectDelay: TimeInterval = 1.0
    private let onError: ((String) -> Void)?

    private var serverMessageSubscribers: [(ServerMessage) -> Void] = []
    private(set) var mostRecentServerMessage: ServerMessage?

    func subscribeToServerMessages(_ callback: @escaping (ServerMessage) -> Void) {
        serverMessageSubscribers.append(callback)
    }

    private var socket: URLSessionWebSocketTask?
    private var queuedPayload: Data?

    init(
        baseURL: URL,
        userId: String,
        deviceId: String,
        onError: ((String) -> Void)? = nil
    ) {
        self.userId = userId

        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        canvasURL = components.url!.appendingPathComponent("canvas").appending(
            queryItems: [
                URLQueryItem(name: "userId", value: userId),
                URLQueryItem(name: "deviceId", value: deviceId),
            ])

        self.onError = onError
        Task { await connect() }
    }

    private func connect() async {
        while true {
            let socket = URLSession.shared.webSocketTask(with: canvasURL)
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
                onError?(
                    "Error receiving message: \(error.localizedDescription)"
                )
                try! await Task.sleep(for: .seconds(reconnectDelay))
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
                    ServerMessage.self,
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

    func updateActionsToSend(_ actionsToSend: [SequencedAction]) {
        if actionsToSend.count > 0 {
            self.queuedPayload = try! JSONEncoder().encode(
                ClientMessage(actions: actionsToSend)
            )
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
                try await socket.send(.data(queuedPayload))
            } catch {
                self.socket = nil
                onError?("Error sending actions: \(error.localizedDescription)")
            }
        }
    }

}

struct ClientMessage: Codable {
    let actions: [SequencedAction]
}

struct ServerMessage: Codable, Equatable {
    let greatestSeenDeviceSequenceNumber: Int
    let placements: [Placement]
}
