// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {HoneyVault} from "../src/HoneyVault.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {WithdrawalQueue} from "../src/WithdrawalQueue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        HoneyVault vault = new HoneyVault(IERC20(address(usdc)));
        console.log("HoneyVault:", address(vault));

        LoanManager loanManager = new LoanManager(address(vault), address(usdc));
        console.log("LoanManager:", address(loanManager));

        WithdrawalQueue withdrawalQueue = new WithdrawalQueue(address(vault), address(usdc));
        console.log("WithdrawalQueue:", address(withdrawalQueue));

        vault.setLoanManager(address(loanManager));
        console.log("--- Deployment complete ---");

        vm.stopBroadcast();
    }
}
