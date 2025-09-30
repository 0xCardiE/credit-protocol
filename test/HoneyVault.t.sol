// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {HoneyVault} from "../src/HoneyVault.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {WithdrawalQueue} from "../src/WithdrawalQueue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HoneyVaultTest is Test {
    MockUSDC usdc;
    HoneyVault vault;
    LoanManager loanManager;
    WithdrawalQueue withdrawalQueue;

    address admin = address(this);
    address lp1 = makeAddr("lp1");
    address lp2 = makeAddr("lp2");
    address borrower1 = makeAddr("borrower1");

    function setUp() public {
        usdc = new MockUSDC();
        vault = new HoneyVault(IERC20(address(usdc)));
        loanManager = new LoanManager(address(vault), address(usdc));
        withdrawalQueue = new WithdrawalQueue(address(vault), address(usdc));

        vault.setLoanManager(address(loanManager));
        loanManager.setAllowedBorrower(borrower1, true);

        usdc.mint(lp1, 1_000_000e6);
        usdc.mint(lp2, 500_000e6);
        usdc.mint(borrower1, 100_000e6);
    }

    function test_deposit_and_shares() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 100_000e6);
        uint256 shares = vault.deposit(100_000e6, lp1);
        vm.stopPrank();

        assertEq(shares, 100_000e6);
        assertEq(vault.balanceOf(lp1), 100_000e6);
        assertEq(vault.totalAssets(), 100_000e6);
    }

    function test_withdraw() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, lp1);

        uint256 assets = vault.redeem(50_000e6, lp1, lp1);
        vm.stopPrank();

        assertEq(assets, 50_000e6);
        assertEq(usdc.balanceOf(lp1), 950_000e6);
    }

    function test_full_loan_lifecycle() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, lp1);
        vm.stopPrank();

        uint256 loanId = loanManager.createLoan(100_000e6, 1000, 365 days, address(0), 0, borrower1);
        assertEq(loanId, 0);

        loanManager.fundLoan(loanId);

        assertEq(usdc.balanceOf(borrower1), 200_000e6);
        assertEq(vault.totalLoansPrincipal(), 100_000e6);

        vm.warp(block.timestamp + 182.5 days);

        uint256 interest = loanManager.accrue(loanId);
        assertApproxEqRel(interest, 5_000e6, 0.01e18);

        uint256 totalOwed = 100_000e6 + interest;
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), totalOwed);
        loanManager.repay(loanId);
        vm.stopPrank();

        assertEq(vault.totalLoansPrincipal(), 0);
        assertGt(vault.totalAssets(), 500_000e6);
    }

    function test_impairment_and_nav() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, lp1);
        vm.stopPrank();

        loanManager.createLoan(200_000e6, 800, 180 days, address(0), 0, borrower1);
        loanManager.fundLoan(0);

        assertEq(vault.totalAssets(), 500_000e6);

        loanManager.markImpaired(0, 100_000e6);
        assertEq(vault.unrealizedLosses(), 100_000e6);
        assertEq(vault.totalAssets(), 400_000e6);
    }

    function test_default_and_recovery() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, lp1);
        vm.stopPrank();

        loanManager.createLoan(200_000e6, 800, 180 days, address(0), 0, borrower1);
        loanManager.fundLoan(0);

        loanManager.markImpaired(0, 100_000e6);
        loanManager.declareDefault(0);

        assertEq(vault.unrealizedLosses(), 200_000e6);
        assertEq(vault.totalAssets(), 300_000e6);

        usdc.mint(admin, 150_000e6);
        usdc.approve(address(loanManager), 150_000e6);
        loanManager.recover(0, 150_000e6);

        assertEq(vault.unrealizedLosses(), 50_000e6);
    }

    function test_withdrawal_queue() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, lp1);
        vm.stopPrank();

        loanManager.createLoan(400_000e6, 1000, 365 days, address(0), 0, borrower1);
        loanManager.fundLoan(0);

        assertEq(vault.availableLiquidity(), 100_000e6);

        vm.startPrank(lp1);
        IERC20(address(vault)).approve(address(withdrawalQueue), 200_000e6);
        withdrawalQueue.requestWithdrawal(200_000e6);
        vm.stopPrank();

        assertEq(withdrawalQueue.pendingCount(), 1);

        uint256 processed = withdrawalQueue.processQueue(10);
        assertEq(processed, 0);

        vm.warp(block.timestamp + 365 days);
        uint256 interest = loanManager.accrue(0);
        usdc.mint(borrower1, interest);

        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), 400_000e6 + interest);
        loanManager.repay(0);
        vm.stopPrank();

        processed = withdrawalQueue.processQueue(10);
        assertEq(processed, 1);
        assertEq(withdrawalQueue.pendingCount(), 0);
    }

    function test_utilization_rate() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, lp1);
        vm.stopPrank();

        assertEq(vault.utilizationRate(), 0);

        loanManager.createLoan(250_000e6, 1000, 365 days, address(0), 0, borrower1);
        loanManager.fundLoan(0);

        assertEq(vault.utilizationRate(), 0.5e18);
    }

    function test_borrower_allowlist() public {
        address rando = makeAddr("rando");
        vm.expectRevert("borrower not allowed");
        loanManager.createLoan(100_000e6, 1000, 365 days, address(0), 0, rando);
    }

    function test_only_borrower_or_manager_can_create_loan() public {
        vm.prank(lp1);
        vm.expectRevert("not borrower or manager");
        loanManager.createLoan(100_000e6, 1000, 365 days, address(0), 0, borrower1);
    }

    function test_borrower_can_create_own_loan() public {
        vm.prank(borrower1);
        uint256 loanId = loanManager.createLoan(50_000e6, 800, 180 days, address(0), 0, borrower1);
        assertEq(loanId, 0);
    }

    function test_exchange_rate_after_interest() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, lp1);
        vm.stopPrank();

        loanManager.createLoan(50_000e6, 1000, 365 days, address(0), 0, borrower1);
        loanManager.fundLoan(0);

        vm.warp(block.timestamp + 365 days);

        uint256 interest = loanManager.accrue(0);
        usdc.mint(borrower1, interest);

        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), 50_000e6 + interest);
        loanManager.repay(0);
        vm.stopPrank();

        assertGt(vault.totalAssets(), 100_000e6);

        vm.startPrank(lp2);
        usdc.approve(address(vault), 100_000e6);
        uint256 shares = vault.deposit(100_000e6, lp2);
        vm.stopPrank();

        assertLt(shares, 100_000e6);
    }
}
