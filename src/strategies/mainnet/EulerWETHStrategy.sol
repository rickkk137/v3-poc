pragma solidity ^0.8.21;

import {IERC4626} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TokenUtils} from "../../libraries/TokenUtils.sol";
import {MYTStrategy} from "../../MYTStrategy.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract EulerWETHStrategy is MYTStrategy {
    // Mainnet WETH and Euler wETH EVK vault (ERC-4626)
    // WETH:  0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2
    // EVK:   0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2
    IERC20 public immutable weth; // 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2
    IERC4626 public immutable vault; // 0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2

    constructor(address _myt, StrategyParams memory _params, address _weth, address _eulerVault, address _permit2Address)
        MYTStrategy(_myt, _params, _permit2Address, _weth)
    {
        weth = IERC20(_weth);
        vault = IERC4626(_eulerVault);
    }

    function _allocate(uint256 amount) internal override returns (uint256 depositReturn) {
        require(TokenUtils.safeBalanceOf(address(weth), address(this)) >= amount, "Strategy balance is less than amount");
        depositReturn = amount;
        TokenUtils.safeApprove(address(weth), address(vault), amount);
        vault.deposit(amount, address(this));
    }

    function _deallocate(uint256 amount) internal override returns (uint256 withdrawReturn) {
        vault.withdraw(amount, address(this), address(this));
        withdrawReturn = amount;
        require(TokenUtils.safeBalanceOf(address(weth), address(this)) >= amount, "Strategy balance is less than the amount needed");
        TokenUtils.safeApprove(address(weth), msg.sender, amount);
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
