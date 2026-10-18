// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Squeek (SQK)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract Squeek is ERC20 {
    /// @notice One billion SQK, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The creating account receives everything, including when it is a factory.
    constructor() ERC20("Squeek", "SQK") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
