// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Splits one user-signed call into recipient USDT + Mesh treasury fee (TRC-20).
interface ITRC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract MeshSendRouter {
    address public immutable usdt;
    address public immutable treasury;

    event SendWithFee(
        address indexed sender,
        address indexed recipient,
        uint256 recipientAmount,
        uint256 feeAmount
    );

    constructor(address usdt_, address treasury_) {
        require(usdt_ != address(0) && treasury_ != address(0), "zero address");
        usdt = usdt_;
        treasury = treasury_;
    }

    /// @param recipient Tron recipient (base58 decoded to EVM address in client).
    /// @param recipientAmount USDT smallest units (6 decimals) to recipient.
    /// @param feeAmount USDT smallest units to treasury.
    function sendWithFee(
        address recipient,
        uint256 recipientAmount,
        uint256 feeAmount
    ) external {
        require(recipient != address(0), "recipient");
        require(recipientAmount > 0 || feeAmount > 0, "amount");

        address sender = msg.sender;
        ITRC20 token = ITRC20(usdt);

        if (recipientAmount > 0) {
            require(token.transferFrom(sender, recipient, recipientAmount), "recipient");
        }
        if (feeAmount > 0) {
            require(token.transferFrom(sender, treasury, feeAmount), "fee");
        }

        emit SendWithFee(sender, recipient, recipientAmount, feeAmount);
    }
}
