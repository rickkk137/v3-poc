// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/BaseStrategyTest.sol";
import {SfrxETHStrategy} from "../../strategies/SfrxETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SfrxETHStrategyTest is BaseStrategyTest {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant FRAX_MINTER = 0x7Bc6bad540453360F744666D625fec0ee1320cA3;
    address public constant REDEMPTION_QUEUE = 0xfDC69e6BE352BD5644C438302DE4E311AAD5565b;
    address public constant MAINNET_PERMIT2 = 0x000000000022d473030f1dF7Fa9381e04776c7c5;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "SfrxETH",
            protocol: "SfrxETH",
            riskClass: IMYTStrategy.RiskClass.LOW,
            cap: 100 ether,
            globalCap: 100 ether,
            estimatedYield: 100 ether,
            additionalIncentives: false,
            slippageBPS: 1
        });
    }

    function getTestConfig() internal pure override returns (TestConfig memory) {
        return TestConfig({
            vaultAsset: WETH,
            vaultInitialDeposit: 100 ether,
            absoluteCap: 100 ether,
            relativeCap: 1 ether,
            decimals: 18
        });
    }

    function createStrategy(address vault, IMYTStrategy.StrategyParams memory params) internal override returns (address payable) {
        return payable(new SfrxETHStrategy(vault, params, SFRXETH, FRAX_MINTER, REDEMPTION_QUEUE, MAINNET_PERMIT2));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 22_089_302;
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
        
        SfrxETHStrategy sfrxStrategy = SfrxETHStrategy(strategy);
        uint256 ethOut = sfrxStrategy.claimWithdrawalQueue(positionId);
        require(ethOut > 0, "ETH out should be greater than 0");
        
        // Check that the strategy has enough WETH balance
        uint256 wethBalance = IERC20(WETH).balanceOf(address(strategy));
        console.log("Strategy WETH balance after claim:", wethBalance);
        console.log("Amount to transfer back:", ethOut);
        
        // Fund the strategy with WETH to cover the transfer back to the vault
        deal(WETH, strategy, ethOut);
        vm.stopPrank();
    }

    function test_realAssets() public {
        vm.startPrank(vault);
        deal(testConfig.vaultAsset, strategy, 10 ether);
        bytes memory prevAllocationAmount = abi.encode(0);
        IMYTStrategy(strategy).allocate(prevAllocationAmount, 10 ether, "", address(vault));
        
        uint256 realAssets = IMYTStrategy(strategy).realAssets();
        console.log("Real assets after allocation:", realAssets);
        assertGt(realAssets, 0);
        
        // Test deallocation
        bytes memory prevAllocationAmount2 = abi.encode(10 ether);
        (, int256 change) = IMYTStrategy(strategy).deallocate(prevAllocationAmount2, 5 ether, "", address(vault));
        uint256 positionId = uint256(change);
        
        // Wait for redemption
        vm.warp(block.timestamp + 30 days);
        SfrxETHStrategy sfrxStrategy = SfrxETHStrategy(strategy);
        sfrxStrategy.claimWithdrawalQueue(positionId);
        
        uint256 realAssetsAfter = IMYTStrategy(strategy).realAssets();
        console.log("Real assets after deallocation:", realAssetsAfter);
        assertLt(realAssetsAfter, realAssets);
        vm.stopPrank();
    }

    function test_previewAdjustedWithdraw() public {
        vm.startPrank(vault);
        deal(testConfig.vaultAsset, strategy, 10 ether);
        bytes memory prevAllocationAmount = abi.encode(0);
        IMYTStrategy(strategy).allocate(prevAllocationAmount, 10 ether, "", address(vault));
        
        uint256 amount = 5 ether;
        uint256 adjustedAmount = IMYTStrategy(strategy).previewAdjustedWithdraw(amount);
        console.log("Original amount:", amount);
        console.log("Adjusted amount with slippage:", adjustedAmount);
        
        // With slippageBPS = 1, adjusted amount should be slightly less
        assertLt(adjustedAmount, amount);
        vm.stopPrank();
    }
}
