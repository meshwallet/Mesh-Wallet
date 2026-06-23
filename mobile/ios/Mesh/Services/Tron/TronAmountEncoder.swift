import Foundation

enum TronAmountEncoder {
    static func usdtToSmallestUnits(_ amount: Decimal) throws -> UInt64 {
        guard amount > 0 else { throw TronAPIError.invalidAmount }
        let scaled = amount * Decimal(pow(10, Double(TronConfiguration.tokenDecimals)))
        let rounded = (scaled as NSDecimalNumber).rounding(accordingToBehavior: nil)
        let value = rounded.uint64Value
        guard value > 0 else { throw TronAPIError.invalidAmount }
        return value
    }

    static func smallestUnitsToUSDT(_ smallestUnits: UInt64) -> Decimal {
        Decimal(smallestUnits) / Decimal(pow(10, Double(TronConfiguration.tokenDecimals)))
    }

    static func encodeUInt256(smallestUnits: UInt64) -> Data {
        var data = Data(repeating: 0, count: 32)
        var value = smallestUnits
        var index = 31
        while value > 0, index >= 0 {
            data[index] = UInt8(value & 0xff)
            value >>= 8
            index -= 1
        }
        return data
    }
}
