import Foundation

#if canImport(WalletCore)
import WalletCore
import SwiftProtobuf

struct TronChainBlock: Equatable {
    let timestamp: Int64
    let header: TronBlockHeader
}

enum TronBlockService {
    private static var cachedBlock: TronChainBlock?
    private static var cachedAt: Date?
    private static let cacheLifetime: TimeInterval = 3

    static func fetchLatestBlock() async throws -> TronChainBlock {
        if let cachedBlock,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < cacheLifetime
        {
            return cachedBlock
        }
        let block = try await fetchLatestBlockFromNetwork()
        cachedBlock = block
        cachedAt = Date()
        return block
    }

    /// Warms the block cache while the user is on the review screen.
    static func prefetchLatestBlock() {
        Task {
            _ = try? await fetchLatestBlock()
        }
    }

    private static func fetchLatestBlockFromNetwork() async throws -> TronChainBlock {
        let data = try await TronAPIClient.post(path: "/wallet/getnowblock")
        let decoded = try JSONDecoder().decode(TronNowBlockResponse.self, from: data)
        guard let raw = decoded.block_header?.raw_data,
              let timestamp = raw.timestamp,
              let number = raw.number,
              let version = raw.version,
              let txTrieRootHex = raw.txTrieRoot,
              let parentHashHex = raw.parentHash,
              let witnessHex = raw.witness_address,
              let txTrieRoot = Data(hexString: normalizeHex(txTrieRootHex)),
              let parentHash = Data(hexString: normalizeHex(parentHashHex)),
              let witnessAddress = Data(hexString: normalizeHex(witnessHex))
        else {
            throw TronAPIError.decodingFailed
        }

        let header = TronBlockHeader.with {
            $0.timestamp = timestamp
            $0.number = number
            $0.version = version
            $0.txTrieRoot = txTrieRoot
            $0.parentHash = parentHash
            $0.witnessAddress = witnessAddress
        }
        return TronChainBlock(timestamp: timestamp, header: header)
    }

    private static func normalizeHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }
}

private struct TronNowBlockResponse: Decodable {
    let block_header: TronBlockHeaderWrapper?
}

private struct TronBlockHeaderWrapper: Decodable {
    let raw_data: TronBlockRawData?
}

private struct TronBlockRawData: Decodable {
    let number: Int64?
    let timestamp: Int64?
    let txTrieRoot: String?
    let parentHash: String?
    let witness_address: String?
    let version: Int32?
}
#endif
