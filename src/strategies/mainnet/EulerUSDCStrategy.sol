pragma solidity ^0.8.21;

import {IERC4626} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";
import {MYTStrategy} from "../../MYTStrategy.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract EulerUSDCStrategy is MYTStrategy {
    IERC20 public immutable usdc; // 0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
    IERC4626 public immutable vault; // 0xe0a80d35bB6618CBA260120b279d357978c42BCE

    constructor(address _myt, StrategyParams memory _params, address _usdc, address _eulerVault, address _permit2Address)
        MYTStrategy(_myt, _params, _permit2Address, _usdc)
    {
        usdc = IERC20(_usdc);
        vault = IERC4626(_eulerVault);
    }

    function _allocate(uint256 amount) internal override returns (uint256 depositReturn) {
        require(TokenUtils.safeBalanceOf(address(usdc), address(this)) >= amount, "Strategy balance is less than amount");
        depositReturn = amount;
        TokenUtils.safeApprove(address(usdc), address(vault), amount);
        vault.deposit(amount, address(this));
    }

    function _deallocate(uint256 amount) internal override returns (uint256 withdrawReturn) {
        vault.withdraw(amount, address(this), address(this));
        withdrawReturn = amount;
        require(TokenUtils.safeBalanceOf(address(usdc), address(this)) >= amount, "Strategy balance is less than the amount needed");
        TokenUtils.safeApprove(address(usdc), msg.sender, amount);
    }

    function realAssets() external view override returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    function _previewAdjustedWithdraw(uint256 amount) internal view override returns (uint256) {
        uint256 shares = vault.previewWithdraw(amount);
        uint256 assets = vault.convertToAssets(shares);
        return assets - (assets * slippageBPS / 10_000);
    }
}
