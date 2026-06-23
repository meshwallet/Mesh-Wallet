import Foundation

/// One pre-signed USDT hop handed to the sponsorship worker.
struct MeshQueuedSendStep: Encodable {
    let fromAddress: String
    let toAddress: String
    let amountUSDT: Double
    let signedTxJSON: String
    let highEnergy: Bool
    let label: String
}

struct MeshSendHandoffResult {
    let obligationID: String
    /// On-chain address that signed the main transfer (must match worker registration).
    let userAddress: String
    let signedFeeTxJSON: String?
    let signedMainTxJSON: String?
    let signedMainTxSteps: [MeshQueuedSendStep]?
    let highEnergy: Bool
    let isPrivateSend: Bool
    let sendMode: String
}
