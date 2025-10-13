// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/BaseStrategyTest.sol";
import {EETHMYTStrategy} from "../../strategies/EETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EETHMYTStrategyTest is BaseStrategyTest {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant DEPOSIT_ADAPTER = 0xcfC6d9Bd7411962Bfe7145451A7EF71A24b6A7A2;
    address public constant REDEMPTION_MANAGER = 0xDadEf1fFBFeaAB4f68A9fD181395F68b4e4E7Ae0;
    address public constant MAINNET_PERMIT2 = 0x000000000022d473030f1dF7Fa9381e04776c7c5;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "EETH",
            protocol: "EETH",
            riskClass: IMYTStrategy.RiskClass.MEDIUM,
            cap: 100 ether,
            globalCap: 100 ether,
            estimatedYield: 100 ether,
            additionalIncentives: false,
            slippageBPS: 1
        });
    }

    function getTestConfig() internal pure override returns (TestConfig memory) {
        return TestConfig({vaultAsset: WETH, vaultInitialDeposit: 100 ether, absoluteCap: 100 ether, relativeCap: 1 ether, decimals: 18});
    }

    function createStrategy(address vault, IMYTStrategy.StrategyParams memory params) internal override returns (address) {
        return address(new EETHMYTStrategy(vault, params, WEETH, WETH, DEPOSIT_ADAPTER, REDEMPTION_MANAGER, MAINNET_PERMIT2));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 23_567_610;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("MAINNET_RPC_URL");
    }

    function test_strategy_deallocate_and_claim_after_30_days(uint256 amountToAllocate, uint256 amountToDeallocate) public {
        amountToAllocate = bound(amountToAllocate, 1 ether, testConfig.vaultInitialDeposit);
        amountToDeallocate = amountToAllocate;
        vm.startPrank(vault);
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        bytes memory prevAllocationAmount = abi.encode(0);
        IMYTStrategy(strategy).allocate(prevAllocationAmount, amountToAllocate, "", address(vault));
        uint256 initialRealAssets = IMYTStrategy(strategy).realAssets();
        require(initialRealAssets > 0, "Initial real assets is 0");

        bytes memory prevAllocationAmount2 = abi.encode(amountToAllocate);
        (, int256 change) = IMYTStrategy(strategy).deallocate(prevAllocationAmount2, amountToDeallocate, "", address(vault));
        uint256 positionId = uint256(change);

        vm.warp(block.timestamp + 30 days);

        //EETHMYTStrategy eethStrategy = EETHMYTStrategy(strategy);
        //uint256 ethOut = eethStrategy.claimWithdrawalQueue(positionId);

        uint256 ethOut = IMYTStrategy(strategy).claimWithdrawalQueue(positionId);
        require(ethOut > 0, "ETH out should be greater than 0");

        // Check that the strategy has enough WETH balance
        uint256 wethBalance = IERC20(WETH).balanceOf(address(strategy));
        console.log("Strategy WETH balance after claim:", wethBalance);
        console.log("Amount to transfer back:", ethOut);

        // Fund the strategy with WETH to cover the transfer back to the vault
        deal(WETH, strategy, ethOut);
        vm.stopPrank();
    }
}
