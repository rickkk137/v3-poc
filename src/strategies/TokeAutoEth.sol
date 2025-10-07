// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {MYTStrategy} from "../MYTStrategy.sol";

import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMainRewarder, IAutopilotRouter} from "./interfaces/ITokemac.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

interface WETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface RootOracle {
    function getPriceInEth(address token) external returns (uint256 price);
}

contract TokeAutoEthStrategy is MYTStrategy {
    IERC4626 public immutable autoEth;
    IAutopilotRouter public immutable router;
    IMainRewarder public immutable rewarder;
    WETH public immutable weth;
    RootOracle public immutable oracle;
    address public immutable rewardToken;

    event TokeAutoETHStrategyTestLog(string message, uint256 value);

    constructor(
        address _myt,
        StrategyParams memory _params,
        address _autoEth,
        address _router,
        address _rewarder,
        address _weth,
        address _oracle,
        address _permit2Address
    ) MYTStrategy(_myt, _params, _permit2Address, _autoEth) {
        autoEth = IERC4626(_autoEth);
        router = IAutopilotRouter(_router);
        rewarder = IMainRewarder(_rewarder);
        weth = WETH(_weth);
        oracle = RootOracle(_oracle);
    }

    // @dev Impleenetation can alternatively make use of a multicall
    function _allocate(uint256 amount) internal override returns (uint256 depositReturn) {
        require(TokenUtils.safeBalanceOf(address(weth), address(this)) >= amount, "Strategy balance is less than amount");
        depositReturn = amount;
        TokenUtils.safeApprove(address(weth), address(router), amount);
        uint256 shares = router.depositMax(autoEth, address(this), 0);
        // Stake on behalf of MYT
        autoEth.approve(address(rewarder), shares);
        rewarder.stake(address(this), shares);
    }

    // todo slippage checks
    function _deallocate(uint256 amount) internal override returns (uint256 withdrawReturn) {
        uint256 sharesNeeded = _previewAdjustedWithdraw(amount);
        emit TokeAutoETHStrategyTestLog("sharesNeeded", sharesNeeded);
        rewarder.withdraw(address(this), sharesNeeded, false);
        emit TokeAutoETHStrategyTestLog("withdrawnnn", sharesNeeded);
        autoEth.redeem(sharesNeeded, address(this), address(this));
        emit TokeAutoETHStrategyTestLog("redeemed", sharesNeeded);
        withdrawReturn = amount;
        require(TokenUtils.safeBalanceOf(address(weth), address(this)) >= withdrawReturn, "Strategy balance is less than amount");
        TokenUtils.safeApprove(address(weth), msg.sender, amount);
    }

    function _previewAdjustedWithdraw(uint256 amount) internal view override returns (uint256) {
        uint256 shareBalance = autoEth.balanceOf(msg.sender);

        // Shares ecpected to be recieved from rewarder for this amount
        // uint256 shares = autoEth.previewWithdraw(amount);
        //uint256 shares = amount;

        // Assets expected to be recieved from autoEth for this number of shares
        // uint256 assets = autoEth.convertToAssets(amount);
        // Slippage protection
        return amount - (amount * slippageBPS / 10_000);
    }

    function _claimRewards() internal override returns (uint256 rewardsClaimed) {
        rewardsClaimed = rewarder.earned(address(this));
        rewarder.getReward(address(this), address(MYT), false);
    }

    function _unwrapWETH(uint256 amount, address to) internal {
        weth.withdraw(amount);
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH send failed");
    }

    function _computeBaseRatePerSecond() internal override returns (uint256 ratePerSec, uint256 newIndex) {
        uint256 dt = lastSnapshotTime == 0 ? 0 : block.timestamp - lastSnapshotTime;

        uint256 currentPPS = autoEth.convertToAssets(1e18);

        newIndex = currentPPS;
        if (lastIndex == 0 || dt == 0 || currentPPS <= lastIndex) return (0, newIndex);
        uint256 growth = (currentPPS - lastIndex) * FIXED_POINT_SCALAR / lastIndex;
        ratePerSec = growth / dt;
        return (ratePerSec, newIndex);
    }

    function _computeRewardsRatePerSecond() internal override returns (uint256) {
        if (rewarder.rewardToken() == address(0)) return 0;

        uint256 assetPrice = oracle.getPriceInEth(address(autoEth));
        uint256 tvlAssets = autoEth.balanceOf(address(MYT));
        if (tvlAssets == 0 || assetPrice == 0) return 0;

        (uint256 rewardPrice, bool haveRew) = _rewardPricePerSecond();
        if (!haveRew || rewardPrice == 0) return 0;

        uint256 tvlEth = tvlAssets * assetPrice / FIXED_POINT_SCALAR;

        if (tvlEth == 0) return 0;
        return rewardPrice * FIXED_POINT_SCALAR / tvlEth;
    }

    function _rewardPricePerSecond() internal returns (uint256 usdPerSecRaw, bool ok) {
        if (rewarder.rewardToken() == address(0)) return (0, false);
        uint256 rewardPrice = oracle.getPriceInEth(rewarder.rewardToken());
        if (rewardPrice == 0) return (0, false);

        uint256 rate = rewarder.rewardRate();
        if (rate == 0) return (0, false);

        return (rate * rewardPrice, true);
    }

    function realAssets() external view override returns (uint256) {
        uint256 stakedShares = rewarder.balanceOf(address(this));
        return autoEth.convertToAssets(stakedShares);
    }
}
