import SwiftUI

struct SequencedAction<Action: Codable>: Codable {
    let action: Action
    let deviceSequenceNumber: Int
}

struct DistributedStateMachineLocalState<State: Codable, Action: Codable>: Codable {
    let deviceSequenceNumber: Int
    let confirmedState: State
    let unsyncedActions: [SequencedAction<Action>]
}

@Observable class DistributedStateMachineClient<State: Codable, Action: Codable> {
    private let connection: DistributedStateMachineConnection<State, Action>?
    private let reduce: (State, Action) -> State
    private let persistState: ((DistributedStateMachineLocalState<State, Action>) -> Void)?

    private var localState: DistributedStateMachineLocalState<State, Action>

    init(
        initialState: State,
        reduce: @escaping (State, Action) -> State,
        connection: DistributedStateMachineConnection<State, Action>? = nil,
        localState: DistributedStateMachineLocalState<State, Action>? = nil,
        persistState: ((DistributedStateMachineLocalState<State, Action>) -> Void)? = nil
    ) {
        self.connection = connection
        self.reduce = reduce
        self.persistState = persistState
        self.localState =
            localState
            ?? DistributedStateMachineLocalState(
                deviceSequenceNumber: 0,
                confirmedState: initialState,
                unsyncedActions: []
            )

        if let message = connection?.mostRecentServerMessage {
            serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                state: message.state
            )
        }
        connection?.subscribeToServerMessages { [weak self] message in
            self?.serverUpdate(
                greatestSeenDeviceSequenceNumber: message.greatestSeenDeviceSequenceNumber,
                state: message.state
            )
        }
        connection?.updateActionsToSend(self.localState.unsyncedActions)
    }

    private func update(localState: DistributedStateMachineLocalState<State, Action>) {
        self.localState = localState
        persistState?(localState)
    }

    var state: State {
        localState.unsyncedActions.reduce(localState.confirmedState) { state, sequencedAction in
            reduce(state, sequencedAction.action)
        }
    }

    func apply(_ action: Action) {
        let deviceSequenceNumber = localState.deviceSequenceNumber + 1
        let unsyncedActions =
            localState.unsyncedActions
            + [
                SequencedAction(
                    action: action,
                    deviceSequenceNumber: deviceSequenceNumber
                )
            ]
        update(
            localState: DistributedStateMachineLocalState(
                deviceSequenceNumber: deviceSequenceNumber,
                confirmedState: localState.confirmedState,
                unsyncedActions: unsyncedActions
            )
        )
        connection?.updateActionsToSend(unsyncedActions)
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
