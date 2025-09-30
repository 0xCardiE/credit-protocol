// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {HoneyVault} from "./HoneyVault.sol";
import {ILoanManager} from "./interfaces/ILoanManager.sol";

contract LoanManager is ILoanManager {
    using SafeERC20 for IERC20;

    HoneyVault public immutable vault;
    IERC20 public immutable asset;
    address public manager;

    uint256 public nextLoanId;
    uint256 public timeScale = 1;
    uint256 public scaleChangeTimestamp;
    uint256 public virtualTimeAtScaleChange;
    mapping(uint256 => Loan) internal _loans;
    mapping(address => bool) public allowedBorrowers;

    event TimeScaleSet(uint256 newScale);
    event BorrowerAllowed(address indexed borrower, bool allowed);
    event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 principal);
    event LoanFunded(uint256 indexed loanId);
    event LoanRepaid(uint256 indexed loanId, uint256 principal, uint256 interest);
    event LoanImpaired(uint256 indexed loanId, uint256 expectedLoss);
    event LoanDefaulted(uint256 indexed loanId);
    event LoanRecovered(uint256 indexed loanId, uint256 recoveredAmount);

    modifier onlyManager() {
        require(msg.sender == manager, "only manager");
        _;
    }

    modifier onlyAllowedBorrower(address borrower) {
        require(allowedBorrowers[borrower], "borrower not allowed");
        _;
    }

    constructor(address vault_, address asset_) {
        vault = HoneyVault(vault_);
        asset = IERC20(asset_);
        manager = msg.sender;
        scaleChangeTimestamp = block.timestamp;
    }

    function setTimeScale(uint256 scale) external onlyManager {
        require(scale >= 1 && scale <= 720, "scale 1-720");
        virtualTimeAtScaleChange = _virtualTimeNow();
        scaleChangeTimestamp = block.timestamp;
        timeScale = scale;
        emit TimeScaleSet(scale);
    }

    function _virtualTimeNow() internal view returns (uint256) {
        return virtualTimeAtScaleChange + (block.timestamp - scaleChangeTimestamp) * timeScale;
    }

    function setAllowedBorrower(address borrower, bool allowed) external onlyManager {
        allowedBorrowers[borrower] = allowed;
        emit BorrowerAllowed(borrower, allowed);
    }

    function createLoan(
        uint256 principal,
        uint256 apr,
        uint256 duration,
        address collateralToken,
        uint256 collateralAmount,
        address borrower
    ) external onlyAllowedBorrower(borrower) returns (uint256 loanId) {
        require(msg.sender == borrower || msg.sender == manager, "not borrower or manager");
        loanId = nextLoanId++;
        _loans[loanId] = Loan({
            borrower: borrower,
            principal: principal,
            apr: apr,
            duration: duration,
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            startTime: 0,
            virtualStartTime: 0,
            interestAccrued: 0,
            expectedLoss: 0,
            status: LoanStatus.Created
        });
        emit LoanCreated(loanId, borrower, principal);
    }

    function fundLoan(uint256 loanId) external onlyManager {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Created, "loan not in Created state");

        if (loan.collateralToken != address(0) && loan.collateralAmount > 0) {
            IERC20(loan.collateralToken).safeTransferFrom(loan.borrower, address(this), loan.collateralAmount);
        }

        loan.status = LoanStatus.Active;
        loan.startTime = block.timestamp;
        loan.virtualStartTime = _virtualTimeNow();

        vault.fundLoan(loanId, loan.borrower, loan.principal);
        emit LoanFunded(loanId);
    }

    function accrue(uint256 loanId) public view returns (uint256 interest) {
        Loan storage loan = _loans[loanId];
        if (loan.status != LoanStatus.Active && loan.status != LoanStatus.Impaired) return 0;

        uint256 elapsed = _virtualTimeNow() - loan.virtualStartTime;
        if (elapsed > loan.duration) elapsed = loan.duration;

        interest = (loan.principal * loan.apr * elapsed) / (365 days * 10_000);
    }

    function repay(uint256 loanId) external {
        Loan storage loan = _loans[loanId];
        require(
            loan.status == LoanStatus.Active || loan.status == LoanStatus.Impaired,
            "loan not repayable"
        );

        uint256 interest = accrue(loanId);
        uint256 totalOwed = loan.principal + interest;

        asset.safeTransferFrom(msg.sender, address(vault), totalOwed);

        loan.interestAccrued = interest;
        loan.status = LoanStatus.Repaid;

        if (loan.expectedLoss > 0) {
            vault.recoverLoss(loanId, loan.expectedLoss);
            loan.expectedLoss = 0;
        }

        vault.notifyRepayment(loanId, loan.principal, interest);

        if (loan.collateralToken != address(0) && loan.collateralAmount > 0) {
            IERC20(loan.collateralToken).safeTransfer(loan.borrower, loan.collateralAmount);
        }

        emit LoanRepaid(loanId, loan.principal, interest);
    }

    function markImpaired(uint256 loanId, uint256 expectedLoss) external onlyManager {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Active, "loan not active");

        loan.status = LoanStatus.Impaired;
        loan.expectedLoss = expectedLoss;

        vault.recordLoss(loanId, expectedLoss);
        emit LoanImpaired(loanId, expectedLoss);
    }

    function declareDefault(uint256 loanId) external onlyManager {
        Loan storage loan = _loans[loanId];
        require(
            loan.status == LoanStatus.Active || loan.status == LoanStatus.Impaired,
            "cannot default"
        );

        uint256 additionalLoss = 0;
        if (loan.status == LoanStatus.Active) {
            additionalLoss = loan.principal;
            vault.recordLoss(loanId, additionalLoss);
            loan.expectedLoss = additionalLoss;
        } else {
            if (loan.expectedLoss < loan.principal) {
                additionalLoss = loan.principal - loan.expectedLoss;
                vault.recordLoss(loanId, additionalLoss);
                loan.expectedLoss = loan.principal;
            }
        }

        loan.status = LoanStatus.Defaulted;
        emit LoanDefaulted(loanId);
    }

    function recover(uint256 loanId, uint256 recoveredAmount) external onlyManager {
        Loan storage loan = _loans[loanId];
        require(loan.status == LoanStatus.Defaulted, "loan not defaulted");

        if (recoveredAmount > 0) {
            asset.safeTransferFrom(msg.sender, address(vault), recoveredAmount);

            uint256 lossReduction = recoveredAmount > loan.expectedLoss ? loan.expectedLoss : recoveredAmount;
            loan.expectedLoss -= lossReduction;

            uint256 principalRecovered = recoveredAmount > loan.principal ? loan.principal : recoveredAmount;
            vault.notifyRepayment(loanId, principalRecovered, 0);
            vault.recoverLoss(loanId, lossReduction);

            emit LoanRecovered(loanId, recoveredAmount);
        }
    }

    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return _loans[loanId];
    }

    function getLoanCount() external view returns (uint256) {
        return nextLoanId;
    }
}
