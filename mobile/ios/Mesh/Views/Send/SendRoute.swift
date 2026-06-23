import Foundation

enum SendRoute: Hashable {
    case review
    case sending
    case success(txID: String)
    case failed(message: String)
}
