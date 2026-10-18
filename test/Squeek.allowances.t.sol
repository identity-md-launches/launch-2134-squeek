// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev Complements the original ERC-20 tests with allowance transitions and retry properties.
/// forge-config: default.fuzz.runs = 1000
contract SqueekAllowanceTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Squeek private token;
    address private holder;
    address private spender;
    address private recipient;

    function setUp() public {
        holder = makeAddr("allowance-holder");
        spender = makeAddr("allowance-spender");
        recipient = makeAddr("allowance-recipient");
        token = new Squeek();
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function test_maximumFiniteAllowanceDecrements() public {
        _approve(type(uint256).max - 1);
        _spend(1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);

        _spend(SUPPLY - 1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedTransferRevertsWithoutConsumingInfiniteApproval() public {
        _approve(type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeReusedAfterBalanceRefill() public {
        _approve(SUPPLY);
        _spend(SUPPLY);
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReplacedAndRevoked() public {
        _approve(type(uint256).max);
        _spend(1);
        assertEq(token.allowance(holder, spender), type(uint256).max);

        _approve(1);
        _spend(1);
        assertEq(token.allowance(holder, spender), 0);
        _approve(type(uint256).max);
        _approve(0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 2);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_zeroDelegatedTransferStillRejectsZeroRecipient() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            _approve(approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(holder, address(0), 0);
            assertEq(token.allowance(holder, spender), approvals[i]);
            assertEq(token.balanceOf(holder), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        _approve(1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.allowance(holder, address(0)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_allThreeTransferFromRolesCanBeTheSameAccount() public {
        vm.prank(holder);
        assertTrue(token.approve(holder, SUPPLY));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, holder, SUPPLY));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, holder, 1);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(
        uint256 allowanceSeed,
        uint256 balanceSeed,
        uint256 amountSeed
    ) public {
        uint256 approved = bound(allowanceSeed, 1, SUPPLY);
        uint256 held = bound(balanceSeed, 0, approved - 1);
        uint256 amount = bound(amountSeed, held + 1, approved);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), SUPPLY - held));
        _approve(approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, held, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), held);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);

        // The failed attempt must leave all of the original authorization available.
        assertTrue(token.transfer(holder, amount - held));
        _spend(amount);
        assertEq(token.allowance(holder, spender), approved - amount);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingPartlySpentAllowanceDiscardsTheRemainder(uint256 firstSeed, uint256 replacementSeed)
        public
    {
        uint256 first = bound(firstSeed, 1, SUPPLY / 4);
        uint256 replacement = bound(replacementSeed, 0, SUPPLY / 4);
        _approve(first * 2);
        _spend(first);
        assertEq(token.allowance(holder, spender), first);
        _approve(replacement);
        assertEq(token.allowance(holder, spender), replacement);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, replacement + 1);
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.balanceOf(holder), SUPPLY - first);
        assertEq(token.balanceOf(recipient), first);

        _spend(replacement);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - first - replacement);
        assertEq(token.balanceOf(recipient), first + replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalancesButDoesNotRestoreSpentAllowance(
        uint256 amountSeed,
        uint256 allowanceSeed,
        bool infinite
    ) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : bound(allowanceSeed, amount, type(uint256).max - 1);
        _approve(approved);
        _spend(amount);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        uint256 remaining = infinite ? approved : approved - amount;
        assertEq(token.allowance(holder, spender), remaining);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), remaining);
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_spendingOneApprovalDoesNotChangeAnotherOwnersOrSpendersApproval(
        uint256 amountSeed,
        uint256 otherOwnerApproval,
        uint256 otherSpenderApproval
    ) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        _approve(amount);
        vm.prank(recipient);
        assertTrue(token.approve(spender, otherOwnerApproval));
        vm.prank(holder);
        assertTrue(token.approve(recipient, otherSpenderApproval));

        _spend(amount);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(recipient, spender), otherOwnerApproval);
        assertEq(token.allowance(holder, recipient), otherSpenderApproval);
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(uint256 amount) private {
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
    }

    function _spend(uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
    }
}
