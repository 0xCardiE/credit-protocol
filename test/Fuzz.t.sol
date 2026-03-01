// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {HoneyVault} from "../src/HoneyVault.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager.sol";
import {WithdrawalQueue} from "../src/WithdrawalQueue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FuzzTest is Test {
    MockUSDC usdc;
    HoneyVault vault;
    LoanManager loanManager;
    WithdrawalQueue withdrawalQueue;

    address admin = address(this);
    address borrower1 = makeAddr("borrower1");

    uint256 constant MAX_USDC = 100_000_000e6; // 100M USDC ceiling

    function setUp() public {
        usdc = new MockUSDC();
        vault = new HoneyVault(IERC20(address(usdc)));
        loanManager = new LoanManager(address(vault), address(usdc));
        withdrawalQueue = new WithdrawalQueue(address(vault), address(usdc));

        vault.setLoanManager(address(loanManager));
        loanManager.setAllowedBorrower(borrower1, true);
    }

    // ── Helpers ─────────────────────────────────────────────────

    function _boundDeposit(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1e6, MAX_USDC);
    }

    function _boundPrincipal(uint256 raw, uint256 liquidity) internal pure returns (uint256) {
        if (liquidity < 1e6) return 1e6;
        return bound(raw, 1e6, liquidity);
    }

    function _boundApr(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1, 5000); // 0.01% – 50%
    }

    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1 days, 3650 days); // 1 day – 10 years
    }

    function _depositAs(address lp, uint256 amount) internal returns (uint256 shares) {
        usdc.mint(lp, amount);
        vm.startPrank(lp);
        usdc.approve(address(vault), amount);
        shares = vault.deposit(amount, lp);
        vm.stopPrank();
    }

    function _createAndFundLoan(uint256 principal, uint256 apr, uint256 duration) internal returns (uint256 loanId) {
        loanId = loanManager.createLoan(principal, apr, duration, address(0), 0, borrower1);
        loanManager.fundLoan(loanId);
    }

    // ══════════════════════════════════════════════════════════════
    //  1. DEPOSIT / WITHDRAW INVARIANTS
    // ══════════════════════════════════════════════════════════════

    /// @dev Depositing and fully withdrawing should return the exact same amount (no loans outstanding).
    function testFuzz_depositWithdrawRoundTrip(uint256 amount) public {
        amount = _boundDeposit(amount);
        address lp = makeAddr("lpRoundTrip");

        uint256 shares = _depositAs(lp, amount);

        vm.startPrank(lp);
        uint256 assets = vault.redeem(shares, lp, lp);
        vm.stopPrank();

        assertEq(assets, amount, "round-trip should be lossless with no loans");
        assertEq(vault.totalAssets(), 0, "vault should be empty");
    }

    /// @dev Shares minted should be > 0 for any nonzero deposit.
    function testFuzz_depositAlwaysMintsShares(uint256 amount) public {
        amount = _boundDeposit(amount);
        address lp = makeAddr("lpShares");

        uint256 shares = _depositAs(lp, amount);
        assertGt(shares, 0, "must mint nonzero shares");
    }

    /// @dev totalAssets should always equal cash + loansValue after deposits.
    function testFuzz_totalAssetsConsistency(uint256 dep1, uint256 dep2) public {
        dep1 = _boundDeposit(dep1);
        dep2 = _boundDeposit(dep2);

        _depositAs(makeAddr("lp1"), dep1);
        _depositAs(makeAddr("lp2"), dep2);

        assertEq(vault.totalAssets(), dep1 + dep2, "totalAssets = sum of deposits");
        assertEq(vault.availableLiquidity(), dep1 + dep2, "liquidity = sum of deposits");
    }

    // ══════════════════════════════════════════════════════════════
    //  2. INTEREST ACCRUAL MATH
    // ══════════════════════════════════════════════════════════════

    /// @dev Interest should be exactly principal * apr * elapsed / (365d * 10000), capped at duration.
    function testFuzz_interestAccrualFormula(
        uint256 principal,
        uint256 apr,
        uint256 duration,
        uint256 elapsed
    ) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        apr = _boundApr(apr);
        duration = _boundDuration(duration);
        elapsed = bound(elapsed, 0, duration + 365 days);

        uint256 deposit = principal + 1e6;
        _depositAs(makeAddr("lpInterest"), deposit);

        uint256 loanId = _createAndFundLoan(principal, apr, duration);
        vm.warp(block.timestamp + elapsed);

        uint256 interest = loanManager.accrue(loanId);

        uint256 effectiveElapsed = elapsed > duration ? duration : elapsed;
        uint256 expected = (principal * apr * effectiveElapsed) / (365 days * 10_000);

        assertEq(interest, expected, "interest mismatch");
    }

    /// @dev Interest at time 0 should be 0.
    function testFuzz_interestZeroAtStart(uint256 principal, uint256 apr, uint256 duration) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        apr = _boundApr(apr);
        duration = _boundDuration(duration);

        _depositAs(makeAddr("lpZero"), principal + 1e6);
        uint256 loanId = _createAndFundLoan(principal, apr, duration);

        assertEq(loanManager.accrue(loanId), 0, "interest at t=0 should be 0");
    }

    /// @dev Interest should be capped at duration (no extra accrual past maturity).
    function testFuzz_interestCappedAtDuration(
        uint256 principal,
        uint256 apr,
        uint256 duration,
        uint256 extraTime
    ) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        apr = _boundApr(apr);
        duration = _boundDuration(duration);
        extraTime = bound(extraTime, 1, 365 days);

        _depositAs(makeAddr("lpCap"), principal + 1e6);
        uint256 loanId = _createAndFundLoan(principal, apr, duration);

        vm.warp(block.timestamp + duration);
        uint256 interestAtMaturity = loanManager.accrue(loanId);

        vm.warp(block.timestamp + extraTime);
        uint256 interestAfter = loanManager.accrue(loanId);

        assertEq(interestAfter, interestAtMaturity, "interest must not grow past duration");
    }

    /// @dev Interest should monotonically increase over time.
    function testFuzz_interestMonotonicallyIncreasing(
        uint256 principal,
        uint256 apr,
        uint256 duration,
        uint256 t1,
        uint256 t2
    ) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        apr = _boundApr(apr);
        duration = _boundDuration(duration);
        t1 = bound(t1, 0, duration);
        t2 = bound(t2, t1, duration);

        _depositAs(makeAddr("lpMono"), principal + 1e6);
        uint256 loanId = _createAndFundLoan(principal, apr, duration);
        uint256 startTs = block.timestamp;

        vm.warp(startTs + t1);
        uint256 i1 = loanManager.accrue(loanId);

        vm.warp(startTs + t2);
        uint256 i2 = loanManager.accrue(loanId);

        assertGe(i2, i1, "interest must be monotonically increasing");
    }

    // ══════════════════════════════════════════════════════════════
    //  3. LOAN LIFECYCLE — NAV INVARIANTS
    // ══════════════════════════════════════════════════════════════

    /// @dev After funding a loan: totalAssets stays the same, but cash decreases by principal.
    function testFuzz_fundLoanPreservesNav(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpNav"), depositAmt);
        uint256 navBefore = vault.totalAssets();

        _createAndFundLoan(principal, 1000, 180 days);

        assertEq(vault.totalAssets(), navBefore, "NAV must not change on fund");
        assertEq(vault.availableLiquidity(), depositAmt - principal, "cash reduced by principal");
        assertEq(vault.totalLoansPrincipal(), principal, "principal tracked");
    }

    /// @dev After full repayment: totalAssets >= pre-loan amount (interest earned), totalLoansPrincipal back to 0.
    function testFuzz_repayRestoresNav(
        uint256 depositAmt,
        uint256 principal,
        uint256 apr,
        uint256 duration,
        uint256 elapsed
    ) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        apr = _boundApr(apr);
        duration = _boundDuration(duration);
        elapsed = bound(elapsed, 1, duration);

        _depositAs(makeAddr("lpRepay"), depositAmt);
        uint256 navBefore = vault.totalAssets();

        uint256 loanId = _createAndFundLoan(principal, apr, duration);
        vm.warp(block.timestamp + elapsed);

        uint256 interest = loanManager.accrue(loanId);
        uint256 totalOwed = principal + interest;

        usdc.mint(borrower1, totalOwed);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), totalOwed);
        loanManager.repay(loanId);
        vm.stopPrank();

        assertEq(vault.totalLoansPrincipal(), 0, "loans principal should be 0");
        assertGe(vault.totalAssets(), navBefore, "NAV must grow from interest");
        assertEq(vault.totalAssets(), navBefore + interest, "NAV = original + interest");
    }

    /// @dev Impairment reduces totalAssets by exactly expectedLoss.
    function testFuzz_impairmentReducesNav(uint256 depositAmt, uint256 principal, uint256 lossFraction) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        lossFraction = bound(lossFraction, 1, 10000); // 0.01% – 100% of principal

        _depositAs(makeAddr("lpImpair"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        uint256 expectedLoss = (principal * lossFraction) / 10000;
        if (expectedLoss == 0) expectedLoss = 1;

        uint256 navBefore = vault.totalAssets();
        loanManager.markImpaired(loanId, expectedLoss);

        assertEq(vault.totalAssets(), navBefore - expectedLoss, "NAV reduced by expectedLoss");
        assertEq(vault.unrealizedLosses(), expectedLoss, "unrealizedLosses tracked");
    }

    /// @dev Default from Active: expectedLoss = full principal.
    function testFuzz_defaultFromActiveFullLoss(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpDefault"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        loanManager.declareDefault(loanId);

        ILoanManager.Loan memory loan = loanManager.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILoanManager.LoanStatus.Defaulted));
        assertEq(loan.expectedLoss, principal, "default from active = full principal loss");
        assertEq(vault.unrealizedLosses(), principal);
    }

    /// @dev Default from Impaired: total loss tops up to full principal.
    function testFuzz_defaultFromImpaired(uint256 depositAmt, uint256 principal, uint256 partialLoss) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        partialLoss = bound(partialLoss, 1, principal);

        _depositAs(makeAddr("lpDefImp"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        loanManager.markImpaired(loanId, partialLoss);
        loanManager.declareDefault(loanId);

        ILoanManager.Loan memory loan = loanManager.getLoan(loanId);
        assertEq(loan.expectedLoss, principal, "total loss = full principal");
        assertEq(vault.unrealizedLosses(), principal, "vault losses = principal");
    }

    // ══════════════════════════════════════════════════════════════
    //  4. RECOVERY INVARIANTS
    // ══════════════════════════════════════════════════════════════

    /// @dev Recovery should reduce unrealizedLosses, never below 0.
    function testFuzz_recoveryReducesLosses(uint256 depositAmt, uint256 principal, uint256 recoveryAmt) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        recoveryAmt = bound(recoveryAmt, 1, principal * 2);

        _depositAs(makeAddr("lpRecover"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        loanManager.declareDefault(loanId);
        uint256 lossesBefore = vault.unrealizedLosses();

        usdc.mint(admin, recoveryAmt);
        usdc.approve(address(loanManager), recoveryAmt);
        loanManager.recover(loanId, recoveryAmt);

        uint256 lossReduction = recoveryAmt > lossesBefore ? lossesBefore : recoveryAmt;
        assertEq(vault.unrealizedLosses(), lossesBefore - lossReduction, "losses reduced correctly");
    }

    /// @dev Full recovery restores NAV to (deposit - principal + recovery).
    function testFuzz_fullRecoveryNav(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpFullRecov"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        loanManager.declareDefault(loanId);

        usdc.mint(admin, principal);
        usdc.approve(address(loanManager), principal);
        loanManager.recover(loanId, principal);

        assertEq(vault.unrealizedLosses(), 0, "full recovery clears losses");
        assertEq(vault.totalAssets(), depositAmt, "NAV fully restored");
    }

    // ══════════════════════════════════════════════════════════════
    //  5. TURBO MODE — TIME SCALE INVARIANTS
    // ══════════════════════════════════════════════════════════════

    /// @dev Turbo interest for (realTime * scale) should match normal interest for (realTime * scale).
    function testFuzz_turboScaleEquivalence(
        uint256 principal,
        uint256 apr,
        uint256 scale,
        uint256 realSeconds
    ) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        apr = _boundApr(apr);
        scale = bound(scale, 1, 720);
        realSeconds = bound(realSeconds, 1, 180 days);

        _depositAs(makeAddr("lpTurbo"), principal + 1e6);

        uint256 duration = 3650 days;
        uint256 loanId = _createAndFundLoan(principal, apr, duration);

        loanManager.setTimeScale(scale);
        vm.warp(block.timestamp + realSeconds);
        uint256 actual = loanManager.accrue(loanId);

        uint256 virtualElapsed = realSeconds * scale;
        if (virtualElapsed > duration) virtualElapsed = duration;
        uint256 expectedInterest = (principal * apr * virtualElapsed) / (365 days * 10_000);

        assertEq(actual, expectedInterest, "turbo interest must match formula");
    }

    /// @dev Switching time scale mid-loan should not lose or create interest.
    function testFuzz_turboScaleSwitchConsistency(
        uint256 principal,
        uint256 scale1,
        uint256 scale2,
        uint256 t1,
        uint256 t2
    ) public {
        principal = bound(principal, 1e6, 10_000_000e6);
        scale1 = bound(scale1, 1, 720);
        scale2 = bound(scale2, 1, 720);
        t1 = bound(t1, 1, 30 days);
        t2 = bound(t2, 1, 30 days);

        _depositAs(makeAddr("lpSwitch"), principal + 1e6);
        uint256 duration = 3650 days;
        uint256 loanId = _createAndFundLoan(principal, 1000, duration);

        loanManager.setTimeScale(scale1);
        vm.warp(block.timestamp + t1);

        loanManager.setTimeScale(scale2);
        vm.warp(block.timestamp + t2);

        uint256 interest = loanManager.accrue(loanId);

        uint256 totalVirtual = t1 * scale1 + t2 * scale2;
        if (totalVirtual > duration) totalVirtual = duration;
        uint256 expected = (principal * 1000 * totalVirtual) / (365 days * 10_000);

        assertEq(interest, expected, "multi-scale interest must be additive");
    }

    // ══════════════════════════════════════════════════════════════
    //  6. UTILIZATION RATE
    // ══════════════════════════════════════════════════════════════

    /// @dev Utilization = totalLoansPrincipal / totalAssets, scaled by 1e18.
    function testFuzz_utilizationRate(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpUtil"), depositAmt);
        _createAndFundLoan(principal, 1000, 180 days);

        uint256 utilization = vault.utilizationRate();
        uint256 expected = (principal * 1e18) / depositAmt;

        assertEq(utilization, expected, "utilization rate mismatch");
    }

    // ══════════════════════════════════════════════════════════════
    //  7. REPAY IMPAIRED LOAN — LOSS RECOVERY
    // ══════════════════════════════════════════════════════════════

    /// @dev Repaying an impaired loan should clear unrealizedLosses and restore NAV.
    function testFuzz_repayImpairedLoan(
        uint256 depositAmt,
        uint256 principal,
        uint256 lossFraction,
        uint256 elapsed
    ) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        lossFraction = bound(lossFraction, 1, 10000);
        elapsed = bound(elapsed, 1, 180 days);

        _depositAs(makeAddr("lpImpRepay"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        uint256 expectedLoss = (principal * lossFraction) / 10000;
        if (expectedLoss == 0) expectedLoss = 1;

        loanManager.markImpaired(loanId, expectedLoss);

        vm.warp(block.timestamp + elapsed);
        uint256 interest = loanManager.accrue(loanId);
        uint256 totalOwed = principal + interest;

        usdc.mint(borrower1, totalOwed);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), totalOwed);
        loanManager.repay(loanId);
        vm.stopPrank();

        assertEq(vault.unrealizedLosses(), 0, "losses cleared after repay");
        assertEq(vault.totalLoansPrincipal(), 0, "principal cleared");
        assertEq(vault.totalAssets(), depositAmt + interest, "NAV = deposit + interest");
    }

    // ══════════════════════════════════════════════════════════════
    //  8. ACCESS CONTROL
    // ══════════════════════════════════════════════════════════════

    /// @dev Random address cannot fund, impair, or default loans.
    function testFuzz_onlyManagerCanManageLoans(address rando) public {
        vm.assume(rando != admin);
        vm.assume(rando != address(0));

        _depositAs(makeAddr("lpAccess"), 100_000e6);
        uint256 loanId = _createAndFundLoan(50_000e6, 1000, 180 days);

        vm.startPrank(rando);

        vm.expectRevert("only manager");
        loanManager.fundLoan(99);

        vm.expectRevert("only manager");
        loanManager.markImpaired(loanId, 10_000e6);

        vm.expectRevert("only manager");
        loanManager.declareDefault(loanId);

        vm.expectRevert("only manager");
        loanManager.setTimeScale(720);

        vm.stopPrank();
    }

    /// @dev Non-allowed borrower cannot create loans.
    function testFuzz_onlyAllowedBorrowerCanCreate(address rando) public {
        vm.assume(rando != admin);
        vm.assume(rando != borrower1);
        vm.assume(rando != address(0));

        vm.prank(rando);
        vm.expectRevert("borrower not allowed");
        loanManager.createLoan(100e6, 1000, 180 days, address(0), 0, rando);
    }
}
