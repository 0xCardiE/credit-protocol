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

    // ══════════════════════════════════════════════════════════════
    //  9. SHARE PRICE MANIPULATION — ERC4626 ECONOMIC ATTACKS
    // ══════════════════════════════════════════════════════════════

    /// @dev First depositor should not be able to grief later depositors via donation attack.
    ///      Classic ERC4626 inflation attack: deposit 1 wei, donate a large amount,
    ///      then the second depositor gets 0 shares due to rounding.
    function testFuzz_inflationAttackMitigation(uint256 donationAmt) public {
        donationAmt = bound(donationAmt, 1e6, 10_000_000e6);
        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");

        // Attacker deposits 1 USDC (smallest meaningful amount)
        uint256 attackerShares = _depositAs(attacker, 1e6);
        assertGt(attackerShares, 0);

        // Attacker donates USDC directly to vault (inflating share price)
        usdc.mint(attacker, donationAmt);
        vm.prank(attacker);
        usdc.transfer(address(vault), donationAmt);

        // Victim deposits a reasonable amount — should still get shares
        uint256 victimDeposit = donationAmt;
        uint256 victimShares = _depositAs(victim, victimDeposit);

        // Victim must receive nonzero shares; if 0, the attack worked
        assertGt(victimShares, 0, "victim must receive shares (inflation attack succeeded)");
    }

    /// @dev Late depositors should get fewer shares per USDC when interest has accrued.
    ///      This verifies the share price actually increases from earned interest.
    function testFuzz_sharePriceIncreasesWithInterest(
        uint256 depositAmt,
        uint256 principal,
        uint256 apr,
        uint256 elapsed
    ) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        apr = bound(apr, 100, 5000); // at least 1% so interest is nonzero
        elapsed = bound(elapsed, 30 days, 365 days);

        address earlyLP = makeAddr("earlyLP");
        address lateLP = makeAddr("lateLP");

        _depositAs(earlyLP, depositAmt);

        uint256 loanId = _createAndFundLoan(principal, apr, 3650 days);
        vm.warp(block.timestamp + elapsed);

        uint256 interest = loanManager.accrue(loanId);
        uint256 totalOwed = principal + interest;
        usdc.mint(borrower1, totalOwed);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), totalOwed);
        loanManager.repay(loanId);
        vm.stopPrank();

        // Vault now has depositAmt + interest in cash
        // Late LP deposits the same amount but should get fewer shares
        uint256 lateShares = _depositAs(lateLP, depositAmt);
        uint256 earlyShares = vault.balanceOf(earlyLP);

        if (interest > 0) {
            assertLt(lateShares, earlyShares, "late depositor must get fewer shares");
        }
    }

    /// @dev No depositor can withdraw more USDC than the vault actually holds + loans value.
    ///      The total redeemable value of all shares must never exceed totalAssets.
    function testFuzz_totalSharesNeverExceedAssets(uint256 dep1, uint256 dep2) public {
        dep1 = _boundDeposit(dep1);
        dep2 = _boundDeposit(dep2);

        address lp1 = makeAddr("solvencyLP1");
        address lp2 = makeAddr("solvencyLP2");

        uint256 shares1 = _depositAs(lp1, dep1);
        uint256 shares2 = _depositAs(lp2, dep2);

        uint256 totalRedeemable = vault.previewRedeem(shares1) + vault.previewRedeem(shares2);
        assertLe(totalRedeemable, vault.totalAssets(), "redeemable must never exceed totalAssets");
    }

    // ══════════════════════════════════════════════════════════════
    //  10. LOAN STATE MACHINE — ILLEGAL TRANSITIONS
    // ══════════════════════════════════════════════════════════════

    /// @dev A repaid loan cannot be repaid again, impaired, or defaulted.
    function testFuzz_repaidLoanIsTerminal(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpTerminal"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        usdc.mint(borrower1, principal);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), principal);
        loanManager.repay(loanId);
        vm.stopPrank();

        vm.expectRevert("loan not repayable");
        vm.prank(borrower1);
        loanManager.repay(loanId);

        vm.expectRevert("loan not active");
        loanManager.markImpaired(loanId, 1e6);

        vm.expectRevert("cannot default");
        loanManager.declareDefault(loanId);
    }

    /// @dev A defaulted loan cannot be repaid, impaired, re-defaulted, or re-funded.
    function testFuzz_defaultedLoanIsTerminal(uint256 depositAmt, uint256 principal) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);

        _depositAs(makeAddr("lpDefTerm"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        loanManager.declareDefault(loanId);

        vm.expectRevert("loan not repayable");
        vm.prank(borrower1);
        loanManager.repay(loanId);

        vm.expectRevert("loan not active");
        loanManager.markImpaired(loanId, 1e6);

        vm.expectRevert("cannot default");
        loanManager.declareDefault(loanId);

        vm.expectRevert("loan not in Created state");
        loanManager.fundLoan(loanId);
    }

    /// @dev A created (unfunded) loan cannot be repaid, impaired, or defaulted.
    function testFuzz_createdLoanCanOnlyBeFunded(uint256 principal) public {
        principal = bound(principal, 1e6, 10_000_000e6);

        uint256 loanId = loanManager.createLoan(principal, 1000, 180 days, address(0), 0, borrower1);

        vm.expectRevert("loan not repayable");
        vm.prank(borrower1);
        loanManager.repay(loanId);

        vm.expectRevert("loan not active");
        loanManager.markImpaired(loanId, 1e6);

        vm.expectRevert("cannot default");
        loanManager.declareDefault(loanId);
    }

    // ══════════════════════════════════════════════════════════════
    //  11. MULTI-LOAN ACCOUNTING — NO CROSS-CONTAMINATION
    // ══════════════════════════════════════════════════════════════

    /// @dev Multiple concurrent loans: defaulting one should not affect the other's repayment.
    function testFuzz_multiLoanIsolation(
        uint256 depositAmt,
        uint256 p1,
        uint256 p2
    ) public {
        depositAmt = bound(depositAmt, 10_000e6, MAX_USDC);
        p1 = bound(p1, 1e6, depositAmt / 3);
        p2 = bound(p2, 1e6, depositAmt / 3);

        address borrower2 = makeAddr("borrower2");
        loanManager.setAllowedBorrower(borrower2, true);

        _depositAs(makeAddr("lpMulti"), depositAmt);

        uint256 loan1 = _createAndFundLoan(p1, 1000, 180 days);
        uint256 loan2 = loanManager.createLoan(p2, 800, 365 days, address(0), 0, borrower2);
        loanManager.fundLoan(loan2);

        assertEq(vault.totalLoansPrincipal(), p1 + p2);

        // Default loan 1
        loanManager.declareDefault(loan1);
        assertEq(vault.unrealizedLosses(), p1);

        // Loan 2 should still be active and repayable
        vm.warp(block.timestamp + 90 days);
        uint256 interest2 = loanManager.accrue(loan2);
        uint256 owed2 = p2 + interest2;

        usdc.mint(borrower2, owed2);
        vm.startPrank(borrower2);
        usdc.approve(address(loanManager), owed2);
        loanManager.repay(loan2);
        vm.stopPrank();

        // loan1's principal stays in totalLoansPrincipal (default doesn't remove it)
        assertEq(vault.totalLoansPrincipal(), p1, "defaulted loan principal remains tracked");
        assertEq(vault.unrealizedLosses(), p1, "loan1 loss still tracked");
    }

    /// @dev Total vault accounting identity: totalAssets = cash + totalLoansPrincipal - unrealizedLosses.
    function testFuzz_accountingIdentity(
        uint256 depositAmt,
        uint256 principal,
        uint256 lossFraction
    ) public {
        depositAmt = _boundDeposit(depositAmt);
        principal = _boundPrincipal(principal, depositAmt);
        lossFraction = bound(lossFraction, 0, 10000);

        _depositAs(makeAddr("lpIdentity"), depositAmt);
        uint256 loanId = _createAndFundLoan(principal, 1000, 180 days);

        if (lossFraction > 0) {
            uint256 loss = (principal * lossFraction) / 10000;
            if (loss == 0) loss = 1;
            loanManager.markImpaired(loanId, loss);
        }

        uint256 cash = usdc.balanceOf(address(vault));
        uint256 loansValue = vault.totalLoansPrincipal() > vault.unrealizedLosses()
            ? vault.totalLoansPrincipal() - vault.unrealizedLosses()
            : 0;

        assertEq(vault.totalAssets(), cash + loansValue, "accounting identity violated");
    }

    // ══════════════════════════════════════════════════════════════
    //  12. WITHDRAWAL QUEUE — FIFO CORRECTNESS
    // ══════════════════════════════════════════════════════════════

    /// @dev Withdrawal queue should process in FIFO order and return correct assets.
    function testFuzz_withdrawalQueueFIFO(uint256 depositAmt, uint256 loanPrincipal) public {
        depositAmt = bound(depositAmt, 100_000e6, MAX_USDC);
        loanPrincipal = bound(loanPrincipal, depositAmt / 2, (depositAmt * 9) / 10);

        address lp1 = makeAddr("queueLP1");
        address lp2 = makeAddr("queueLP2");

        // Both LPs deposit equally
        uint256 half = depositAmt / 2;
        uint256 shares1 = _depositAs(lp1, half);
        uint256 shares2 = _depositAs(lp2, half);

        // Lock most liquidity in a loan
        _createAndFundLoan(loanPrincipal, 1000, 365 days);

        // Both LPs queue withdrawal
        uint256 requestShares1 = shares1 / 2;
        uint256 requestShares2 = shares2 / 2;

        vm.startPrank(lp1);
        IERC20(address(vault)).approve(address(withdrawalQueue), requestShares1);
        uint256 reqId1 = withdrawalQueue.requestWithdrawal(requestShares1);
        vm.stopPrank();

        vm.startPrank(lp2);
        IERC20(address(vault)).approve(address(withdrawalQueue), requestShares2);
        uint256 reqId2 = withdrawalQueue.requestWithdrawal(requestShares2);
        vm.stopPrank();

        assertEq(reqId1, 0, "first request should be id 0");
        assertEq(reqId2, 1, "second request should be id 1");
        assertEq(withdrawalQueue.pendingCount(), 2);

        // Repay loan to free liquidity
        vm.warp(block.timestamp + 365 days);
        uint256 interest = loanManager.accrue(0);
        usdc.mint(borrower1, loanPrincipal + interest);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), loanPrincipal + interest);
        loanManager.repay(0);
        vm.stopPrank();

        // Process queue — should handle both in FIFO order
        uint256 processed = withdrawalQueue.processQueue(10);
        assertEq(processed, 2, "both requests should be processed");
        assertEq(withdrawalQueue.pendingCount(), 0, "no pending requests");

        // Both LPs should have received USDC
        assertGt(usdc.balanceOf(lp1), 0, "lp1 got USDC from queue");
        assertGt(usdc.balanceOf(lp2), 0, "lp2 got USDC from queue");
    }

    // ══════════════════════════════════════════════════════════════
    //  13. ERC4626 SYMMETRY — deposit/mint AND withdraw/redeem
    // ══════════════════════════════════════════════════════════════

    /// @dev previewDeposit and previewRedeem should be consistent inverses.
    function testFuzz_erc4626PreviewConsistency(uint256 amount) public {
        amount = _boundDeposit(amount);

        // Seed the vault so share price != 1:1
        _depositAs(makeAddr("lpSeed"), 50_000e6);
        _createAndFundLoan(25_000e6, 1000, 365 days);
        vm.warp(block.timestamp + 180 days);
        uint256 interest = loanManager.accrue(0);
        usdc.mint(borrower1, 25_000e6 + interest);
        vm.startPrank(borrower1);
        usdc.approve(address(loanManager), 25_000e6 + interest);
        loanManager.repay(0);
        vm.stopPrank();

        // Preview: how many shares for `amount` assets?
        uint256 previewedShares = vault.previewDeposit(amount);

        // Preview: how many assets for those shares?
        uint256 previewedAssets = vault.previewRedeem(previewedShares);

        // Due to rounding, previewedAssets should be <= amount (ERC4626 favors vault)
        assertLe(previewedAssets, amount, "ERC4626 must round in vault's favor");

        // But the difference should be negligible (at most 1 unit of asset per share)
        assertApproxEqAbs(previewedAssets, amount, previewedShares, "round-trip too lossy");
    }
}
