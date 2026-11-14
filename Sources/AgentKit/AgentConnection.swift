import HookMeUpCore
import HookMeUpIPC

/// The agent's side of one hook connection: what `AgentController` needs from it.
protocol AgentConnection: AnyObject {
    /// Sends one framed message to the hook.
    func send(_ message: WireMessage) throws
    /// Closes the connection; the hook sees EOF.
    func close()
}

extension Connection: AgentConnection {}
