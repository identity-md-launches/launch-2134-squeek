// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Squeek} from "../../src/Squeek.sol";

/// @dev Test-only factory used to exercise creation and subsequent distribution.
contract FactoryHarness {
    function deploy(bytes32 salt) external returns (Squeek) {
        return new Squeek{salt: salt}();
    }

    function distribute(Squeek token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}
