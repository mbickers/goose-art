import Foundation

class CanvasClient {
    private let canvasURL: URL
    private let reconnectDelay: TimeInterval = 1.0
    private let onServerMessage: (ServerMessage) -> Void
    private let onError: ((String) -> Void)?

    private var socket: URLSessionWebSocketTask?
    private var queuedPayload: Data?

    init(
        baseURL: URL,
        userId: String,
        deviceId: String,
        onServerMessage: @escaping (ServerMessage) -> Void,
        onError: ((String) -> Void)? = nil
    ) {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        canvasURL = components.url!.appendingPathComponent("canvas").appending(
            queryItems: [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "device_id", value: deviceId),
            ])

        self.onServerMessage = onServerMessage
        self.onError = onError
    }

    func connect() async {
        while true {
            let socket = URLSession.shared.webSocketTask(with: canvasURL)
            socket.resume()
            self.socket = socket
            await maybeSendQueuedPayload()

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
                onServerMessage(serverMessage)
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

    func updateActionsToSend(_ actionsToSend: [SequencedAction]) async {
        if actionsToSend.count > 0 {
            self.queuedPayload = try! JSONEncoder().encode(
                ClientMessage(actions: actionsToSend)
            )
        } else {
            self.queuedPayload = nil
        }
        await maybeSendQueuedPayload()
    }

    func maybeSendQueuedPayload() async {
        guard let queuedPayload else { return }
        guard let socket else { return }
        do {
            // TODO: figure out why this is data and not string
            // TODO: don't wait for
            try await socket.send(.data(queuedPayload))
        } catch {
            self.socket = nil
            onError?("Error sending actions: \(error.localizedDescription)")
        }
    }

}

struct ClientMessage: Codable {
    let actions: [SequencedAction]
}

struct ServerMessage: Codable {
    let greatestSeenDeviceSequenceNumber: Int
    let placements: [Placement]
}
