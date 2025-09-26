// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILoanManager} from "./interfaces/ILoanManager.sol";

contract HoneyVault is ERC4626 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public manager;
    address public loanManager;

    uint256 public totalLoansPrincipal;
    uint256 public unrealizedLosses;

    event LoanManagerSet(address indexed loanManager);
    event LoanFunded(uint256 indexed loanId, uint256 amount);
    event LoanRepaid(uint256 indexed loanId, uint256 principal, uint256 interest);
    event LossRecorded(uint256 indexed loanId, uint256 loss);
    event LossRecovered(uint256 indexed loanId, uint256 recovered);

    modifier onlyManager() {
        require(msg.sender == manager, "only manager");
        _;
    }

    modifier onlyLoanManager() {
        require(msg.sender == loanManager, "only loan manager");
        _;
    }

    constructor(IERC20 asset_) ERC4626(asset_) ERC20("Honey USDC", "honeyUSDC") {
        manager = msg.sender;
    }

    function setLoanManager(address lm) external onlyManager {
        loanManager = lm;
        emit LoanManagerSet(lm);
    }

    function fundLoan(uint256 loanId, address borrower, uint256 amount) external onlyLoanManager {
        totalLoansPrincipal += amount;
        IERC20(asset()).safeTransfer(borrower, amount);
        emit LoanFunded(loanId, amount);
    }

    function notifyRepayment(uint256 loanId, uint256 principal, uint256 interest) external onlyLoanManager {
        if (principal > totalLoansPrincipal) {
            totalLoansPrincipal = 0;
        } else {
            totalLoansPrincipal -= principal;
        }
        emit LoanRepaid(loanId, principal, interest);
    }

    function recordLoss(uint256 loanId, uint256 loss) external onlyLoanManager {
        unrealizedLosses += loss;
        emit LossRecorded(loanId, loss);
    }

    function recoverLoss(uint256 loanId, uint256 recovered) external onlyLoanManager {
        if (recovered > unrealizedLosses) {
            unrealizedLosses = 0;
        } else {
            unrealizedLosses -= recovered;
        }
        emit LossRecovered(loanId, recovered);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 cash = IERC20(asset()).balanceOf(address(this));
        uint256 loansValue = totalLoansPrincipal > unrealizedLosses
            ? totalLoansPrincipal - unrealizedLosses
            : 0;
        return cash + loansValue;
    }

    function availableLiquidity() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function utilizationRate() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return totalLoansPrincipal.mulDiv(1e18, total);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
