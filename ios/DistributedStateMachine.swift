import SwiftUI

struct SequencedAction<Action: Codable>: Codable {
    let action: Action
    let deviceSequenceNumber: Int
}

struct ClientMessage<Action: Codable>: Codable {
    let actions: [SequencedAction<Action>]
}

struct ServerMessage<State: Codable>: Codable {
    let greatestSeenDeviceSequenceNumber: Int
    let state: State
}

struct DistributedStateMachineLocalState<State: Codable, Action: Codable>: Codable {
    let deviceSequenceNumber: Int
    let confirmedState: State
    let unsyncedActions: [SequencedAction<Action>]
}

extension DistributedStateMachineLocalState {
    init(initialState: State) {
        self.init(
            deviceSequenceNumber: 0,
            confirmedState: initialState,
            unsyncedActions: []
        )
    }
}

@Observable class DistributedStateMachineClient<State: Codable, Action: Codable> {
    private let connection: AuthenticatedWebSocket<ServerMessage<State>, ClientMessage<Action>>?
    private let reduce: (State, Action) -> State
    private let persistState: ((DistributedStateMachineLocalState<State, Action>) -> Void)?
    // the first update carries the state the session opened with rather than a change to
    // it, which a subscriber that reacts to arrivals wants to tell apart
    private let onServerUpdate:
        ((_ previous: State, _ current: State, _ isFirstUpdateOfSession: Bool) -> Void)?

    private var localState: DistributedStateMachineLocalState<State, Action>
    @ObservationIgnored private var receivedServerUpdate = false

    init(
        localState: DistributedStateMachineLocalState<State, Action>,
        reduce: @escaping (State, Action) -> State,
        connection: AuthenticatedWebSocket<ServerMessage<State>, ClientMessage<Action>>? = nil,
        persistState: ((DistributedStateMachineLocalState<State, Action>) -> Void)? = nil,
        onServerUpdate: (
            (_ previous: State, _ current: State, _ isFirstUpdateOfSession: Bool) -> Void
        )? = nil
    ) {
        self.connection = connection
        self.reduce = reduce
        self.persistState = persistState
        self.onServerUpdate = onServerUpdate
        self.localState = localState

        // the session hydrates from the first message the connection delivers, which is
        // its opening state rather than news
        connection?.subscribe { [weak self] message in
            self?.applyServerMessage(message)
        }
        pushUnsyncedActions()
    }

    private func applyServerMessage(_ message: ServerMessage<State>) {
        let previousState = state
        let isFirstUpdateOfSession = !receivedServerUpdate
        receivedServerUpdate = true
        serverUpdate(
            greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
            state: message.state
        )
        onServerUpdate?(previousState, state, isFirstUpdateOfSession)
    }

    private func update(localState: DistributedStateMachineLocalState<State, Action>) {
        self.localState = localState
        persistState?(localState)
    }

    private func pushUnsyncedActions() {
        let actions = localState.unsyncedActions
        connection?.setOutbound(actions.isEmpty ? nil : ClientMessage(actions: actions))
    }

    var state: State {
        localState.unsyncedActions.reduce(localState.confirmedState) { state, sequencedAction in
            reduce(state, sequencedAction.action)
        }
    }

    func apply(_ action: Action) {
        let deviceSequenceNumber = localState.deviceSequenceNumber + 1
        update(
            localState: DistributedStateMachineLocalState(
                deviceSequenceNumber: deviceSequenceNumber,
                confirmedState: localState.confirmedState,
                unsyncedActions: localState.unsyncedActions
                    + [
                        SequencedAction(
                            action: action,
                            deviceSequenceNumber: deviceSequenceNumber
                        )
                    ]
            )
        )
        pushUnsyncedActions()
    }

    // the server holds state in memory, so a restart pushes the initial state and a
    // sequence number back at 0. that is a normal update, not an error: resetting the
    // state is fine, crashing or wedging the connection over it is not
    func serverUpdate(
        greatestSeenDeviceSequenceNumber: Int,
        state: State
    ) {
        update(
            localState: DistributedStateMachineLocalState(
                // avoid server rejecting actions if client crashes after sending an update
                deviceSequenceNumber: max(
                    localState.deviceSequenceNumber,
                    greatestSeenDeviceSequenceNumber
                ),
                confirmedState: state,
                unsyncedActions: localState.unsyncedActions.filter {
                    sequencedAction in
                    sequencedAction.deviceSequenceNumber
                        > greatestSeenDeviceSequenceNumber
                }
            )
        )
    }
}
