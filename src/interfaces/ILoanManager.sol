// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILoanManager {
    enum LoanStatus {
        Created,
        Active,
        Repaid,
        Impaired,
        Defaulted
    }

    struct Loan {
        address borrower;
        uint256 principal;
        uint256 apr; // basis points (e.g. 1000 = 10%)
        uint256 duration; // seconds
        address collateralToken;
        uint256 collateralAmount;
        uint256 startTime;
        uint256 interestAccrued;
        uint256 expectedLoss;
        LoanStatus status;
    }

    function getLoan(uint256 loanId) external view returns (Loan memory);
    function accrue(uint256 loanId) external view returns (uint256 interest);
}
