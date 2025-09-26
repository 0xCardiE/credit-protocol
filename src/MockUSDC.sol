// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    address public admin;

    constructor() ERC20("USD Coin (Mock)", "USDC") {
        admin = msg.sender;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == admin, "only admin");
        _mint(to, amount);
    }

    function faucet(uint256 amount) external {
        require(amount <= 1_000_000e6, "max 1M per faucet call");
        _mint(msg.sender, amount);
    }
}
