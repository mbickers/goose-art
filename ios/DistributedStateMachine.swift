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

    private var localState: DistributedStateMachineLocalState<State, Action>

    init(
        localState: DistributedStateMachineLocalState<State, Action>,
        reduce: @escaping (State, Action) -> State,
        connection: AuthenticatedWebSocket<ServerMessage<State>, ClientMessage<Action>>? = nil,
        persistState: ((DistributedStateMachineLocalState<State, Action>) -> Void)? = nil
    ) {
        self.connection = connection
        self.reduce = reduce
        self.persistState = persistState
        self.localState = localState

        if let message = connection?.mostRecentMessage {
            serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                state: message.state
            )
        }
        connection?.subscribe { [weak self] message in
            self?.serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                state: message.state
            )
        }
        pushUnsyncedActions()
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
