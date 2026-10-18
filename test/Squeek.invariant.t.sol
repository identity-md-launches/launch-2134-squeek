// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev Test-only actors and an independent accounting model for sequences of token operations.
contract SqueekHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Squeek private immutable token;
    address[5] public actors;
    uint256[5] public expectedBalances;
    uint256[5][5] public expectedAllowances;

    constructor(Squeek token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
        expectedBalances[0] = SUPPLY;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 amount = bound(amountSeed, 0, expectedBalances[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        // Finite approvals near the supply make exhaustion reachable in short sequences.
        _approve(ownerSeed, spenderSeed, bound(amount, 0, SUPPLY));
    }

    function approveInfinite(uint8 ownerSeed, uint8 spenderSeed) external {
        _approve(ownerSeed, spenderSeed, type(uint256).max);
    }

    function revoke(uint8 ownerSeed, uint8 spenderSeed) external {
        _approve(ownerSeed, spenderSeed, 0);
    }

    function _approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) private {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint8 fromSeed, uint8 toSeed, uint8 spenderSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 allowed = expectedAllowances[from][spender];
        uint256 maximum = allowed < expectedBalances[from] ? allowed : expectedBalances[from];
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowances[from][spender] -= amount;
        }
    }

    function overdraw(uint8 fromSeed, uint8 toSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalances[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, balance + 1)
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], balance + 1);
    }

    function transferFromOverLimit(uint8 fromSeed, uint8 toSeed, uint8 spenderSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 balance = expectedBalances[from];
        uint256 allowed = expectedAllowances[from][spender];
        uint256 amount;
        if (allowed > balance) {
            // The allowance suffices, so this reaches the balance check, including
            // after an infinite approval. A revert must roll back allowance spending.
            amount = balance + 1;
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
            );
        } else {
            amount = allowed + 1;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowed, amount
                )
            );
        }
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[to], amount);
        // No ghost updates: both invariants must observe the complete pre-call state.
    }

    function transferToZero(uint8 fromSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 amount = bound(amountSeed, 0, expectedBalances[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(actors[from]);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint8 fromSeed, uint8 spenderSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 allowed = expectedAllowances[from][spender];
        uint256 maximum = allowed < expectedBalances[from] ? allowed : expectedBalances[from];
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], address(0), amount);
    }

    function approveZeroSpender(uint8 ownerSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[owner]);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        token = new Squeek();
        handler = new SqueekHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        // Start with several funded actors and usable approvals. Without these,
        // early transferFrom calls mostly transfer zero while waiting for approvals.
        for (uint8 i = 1; i < 5; ++i) {
            handler.transfer(0, i, SUPPLY / 5);
        }
        for (uint8 i; i < 5; ++i) {
            handler.approve(i, (i + 1) % 5, SUPPLY / 5);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.overdraw.selector;
        selectors[4] = handler.approveInfinite.selector;
        selectors[5] = handler.revoke.selector;
        selectors[6] = handler.transferFromOverLimit.selector;
        selectors[7] = handler.transferToZero.selector;
        selectors[8] = handler.transferFromToZero.selector;
        selectors[9] = handler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertEq(balance, handler.expectedBalances(i));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < 5; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 5; ++j) {
                assertEq(token.allowance(handler.actors(i), handler.actors(j)), handler.expectedAllowances(i, j));
            }
        }
    }

    function afterInvariant() public {
        // Every holder can still move its entire balance after an arbitrary sequence
        // of approvals, revocations, successful transfers and rejected operations.
        for (uint8 i = 1; i < 5; ++i) {
            handler.transfer(i, 0, handler.expectedBalances(i));
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_supplyAndBalancesMatchModel();
        invariant_allowancesMatchModel();
    }
}
