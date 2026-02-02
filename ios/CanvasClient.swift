import Foundation

class CanvasClient {
    private let baseURL: URL
    private let userId: String
    private let deviceId: String
    private var webSocketTask: URLSessionWebSocketTask?
    private let reconnectDelay: TimeInterval = 1.0

    private let onServerMessage: (ServerMessage) -> Void
    private let onError: ((String) -> Void)?

    init(baseURL: URL, userId: String, deviceId: String, onServerMessage: @escaping (ServerMessage) -> Void, onError: ((String) -> Void)? = nil) {
        self.baseURL = baseURL
        self.userId = userId
        self.deviceId = deviceId
        self.onServerMessage = onServerMessage
        self.onError = onError
    }

    func connect() async {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/canvas"
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "device_id", value: deviceId)
        ]

        guard let wsURL = components?.url else {
            onError?("Error building WebSocket URL: invalid URL components")
            return
        }

        while true {
            if webSocketTask == nil {
                let task = URLSession.shared.webSocketTask(with: wsURL)
                webSocketTask = task
                task.resume()
            }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await webSocketTask!.receive()
            } catch {
                webSocketTask = nil
                onError?("Error receiving message: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(reconnectDelay))
                continue
            }

            handleMessage(message)
        }
    }

    func sendActions(_ actions: [SequencedAction]) async {
        guard let webSocketTask = webSocketTask else {
            onError?("Error sending actions: not connected")
            return
        }

        let payload = ClientMessage(actions: actions)

        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            onError?("Error encoding actions: \(error.localizedDescription)")
            return
        }

        do {
            try await webSocketTask.send(.data(data))
        } catch {
            self.webSocketTask = nil
            onError?("Error sending actions: \(error.localizedDescription)")
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let s):
            guard let d = s.data(using: .utf8) else {
                onError?("Error converting message string to data: invalid UTF-8")
                return
            }
            data = d
        case .data:
            onError?("Error handling message: expected string message, received data message")
            return
        @unknown default:
            onError?("Error handling message: expected string message, received unknown message type")
            return
        }

        let serverMessage: ServerMessage
        do {
            serverMessage = try JSONDecoder().decode(ServerMessage.self, from: data)
        } catch {
            onError?("Error decoding server message: \(error.localizedDescription)")
            return
        }

        onServerMessage(serverMessage)
    }
}

struct ClientMessage: Codable {
    let actions: [SequencedAction]
}

struct ServerMessage: Codable {
    let greatestSeenDeviceSequenceNumber: Int
    let placements: [Placement]
}
