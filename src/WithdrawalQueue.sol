// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {HoneyVault} from "./HoneyVault.sol";

contract WithdrawalQueue {
    using SafeERC20 for IERC20;

    struct Request {
        address owner;
        uint256 shares;
        uint256 timestamp;
        bool fulfilled;
    }

    HoneyVault public immutable vault;
    IERC20 public immutable asset;
    address public manager;

    Request[] public requests;
    uint256 public nextProcessIndex;

    event WithdrawalRequested(uint256 indexed requestId, address indexed owner, uint256 shares);
    event WithdrawalFulfilled(uint256 indexed requestId, address indexed owner, uint256 assets);
    event QueueProcessed(uint256 processed, uint256 remaining);

    modifier onlyManager() {
        require(msg.sender == manager, "only manager");
        _;
    }

    constructor(address vault_, address asset_) {
        vault = HoneyVault(vault_);
        asset = IERC20(asset_);
        manager = msg.sender;
    }

    function requestWithdrawal(uint256 shares) external returns (uint256 requestId) {
        require(shares > 0, "zero shares");

        IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), shares);

        requestId = requests.length;
        requests.push(Request({owner: msg.sender, shares: shares, timestamp: block.timestamp, fulfilled: false}));

        emit WithdrawalRequested(requestId, msg.sender, shares);
    }

    function processQueue(uint256 maxCount) external returns (uint256 processed) {
        uint256 available = vault.availableLiquidity();
        uint256 end = nextProcessIndex + maxCount;
        if (end > requests.length) end = requests.length;

        for (uint256 i = nextProcessIndex; i < end; i++) {
            Request storage req = requests[i];
            if (req.fulfilled) {
                nextProcessIndex = i + 1;
                continue;
            }

            uint256 assets = vault.previewRedeem(req.shares);
            if (assets > available) break;

            IERC20(address(vault)).safeIncreaseAllowance(address(vault), req.shares);
            uint256 redeemed = vault.redeem(req.shares, address(this), address(this));

            asset.safeTransfer(req.owner, redeemed);

            req.fulfilled = true;
            available -= redeemed;
            processed++;
            nextProcessIndex = i + 1;

            emit WithdrawalFulfilled(i, req.owner, redeemed);
        }

        emit QueueProcessed(processed, pendingCount());
    }

    function pendingCount() public view returns (uint256 count) {
        for (uint256 i = nextProcessIndex; i < requests.length; i++) {
            if (!requests[i].fulfilled) count++;
        }
    }

    function getQueueLength() external view returns (uint256) {
        return requests.length;
    }

    function getRequest(uint256 requestId) external view returns (Request memory) {
        return requests[requestId];
    }

    function getUserRequests(address user) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i].owner == user) count++;
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i].owner == user) {
                ids[idx++] = i;
            }
        }
        return ids;
    }
}
