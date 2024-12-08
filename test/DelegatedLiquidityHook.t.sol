// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {GovernorFlexibleVotingMock} from "test/mocks/GovernorMock.sol";
import {GovernorTokenMock} from "test/mocks/GovernorTokenMock.sol";
import {MockERC20} from "v4-periphery/lib/permit2/test/mocks/MockERC20.sol";
// import {DelegatedFlexClientHarness} from "test/harnesses/DelegatedFlexClientHarness.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey, PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {DelegatedLiquidityHook} from "src/DelegatedLiquidityHook.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {HooksTest} from "v4-core/test/HooksTest.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import { VotingRouter } from "src/VotingRouter.sol";

// contract DelegatedLiquidityHookTest is HookTest, Deployers {
contract DelegatedLiquidityHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // struct CallbackData {
    //     address sender;
    //     PoolKey key;
    //     IPoolManager.ModifyPositionParams params;
    //     bytes hookData;
    // }

    Currency tokenCurrency0;
    Currency tokenCurrency1;

    MockERC20 erc20;
    GovernorTokenMock erc20Votes;
    GovernorFlexibleVotingMock gov;
    DelegatedLiquidityHook hook;
    PoolKey poolKey;
    PoolId poolId;
    //   DelegatedFlexClientHarness client;
    VotingRouter voting_router;

    event VoteCast(
        address indexed voter,
        uint256 proposalId,
        uint256 voteAgainst,
        uint256 voteFor,
        uint256 voteAbstain
    );

    function setUp() public {
        // Helpers for interacting with the pool
        // creates the pool manager, test tokens, and other utility routers
        // HookTest.initHookTestEnv();
        manager = new PoolManager();

        erc20Votes = new GovernorTokenMock();
        erc20 = new MockERC20("Test", "TST", 18);
        gov = new GovernorFlexibleVotingMock("Governor", erc20Votes);

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG
        );
        deployCodeTo("DelegatedLiquidityHook.sol", abi.encode(manager, address(gov)), address(flags));

        hook = DelegatedLiquidityHook(address(flags));

        voting_router = new VotingRouter(manager, address(erc20Votes), address(erc20), true, true, address(gov), address(hook));

        tokenCurrency0 = Currency.wrap(address(voting_router.token0()));
        tokenCurrency1 = Currency.wrap(address(voting_router.token1()));

        // Initialize a pool
        (key, ) = initPool(
            tokenCurrency0, 
            tokenCurrency1,
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        uint256 _amountToAdd = 100 ether;
        erc20.mint(address(this), _amountToAdd);
        erc20Votes.mint(address(this), _amountToAdd);
        erc20.approve(address(voting_router), type(uint256).max);
        erc20Votes.approve(address(voting_router), type(uint256).max);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            _amountToAdd
        );
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        voting_router.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            abi.encode(address(this))

        );
    }

    //   function modifyPosition(
    //     PoolKey memory key,
    //     IPoolManager.ModifyPositionParams memory params,
    //     bytes memory hookData
    //   ) internal returns (BalanceDelta delta) {
    //     delta = abi.decode(
    //       manager.lock(abi.encode(CallbackData(address(this), key, params, hookData))), (BalanceDelta)
    //     );

    //     uint256 ethBalance = address(this).balance;
    //     if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    //   }

    //   function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
    //     require(msg.sender == address(manager));

    //     CallbackData memory data = abi.decode(rawData, (CallbackData));

    //     BalanceDelta delta = manager.modifyPosition(data.key, data.params, data.hookData);

    //     if (delta.amount0() > 0) {
    //       if (data.key.currency0.isNative()) {
    //         manager.settle{value: uint128(delta.amount0())}(data.key.currency0);
    //       } else {
    //         IERC20Minimal(Currency.unwrap(data.key.currency0)).transfer(
    //           // data.sender,
    //           address(manager),
    //           uint128(delta.amount0())
    //         );
    //         manager.settle(data.key.currency0);
    //       }
    //     }
    //     if (delta.amount1() > 0) {
    //       if (data.key.currency1.isNative()) {
    //         manager.settle{value: uint128(delta.amount1())}(data.key.currency1);
    //       } else {
    //         IERC20Minimal(Currency.unwrap(data.key.currency1)).transfer(
    //           // data.sender,
    //           address(manager),
    //           uint128(delta.amount1())
    //         );
    //         manager.settle(data.key.currency1);
    //       }
    //     }

    //     if (delta.amount0() < 0) {
    //       manager.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
    //     }
    //     if (delta.amount1() < 0) {
    //       manager.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
    //     }

    //     return abi.encode(delta);
    //   }
    // }
}

contract AddLiquidity is DelegatedLiquidityHookTest {
    using PoolIdLibrary for PoolKey;

    // function test_castVoteAbstain() public {
    //     address owner = address(this);
    //     int128 amount0 = 1000;
    //     int128 amount1;
    //     uint128 posAmount0 = uint128(amount0);
    //     uint128 posAmount1 = uint128(amount1);
    //     (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolKey.toId());
    //     uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
    //         sqrtPriceX96,
    //         TickMath.getSqrtRatioAtTick(int24(-60)),
    //         TickMath.getSqrtRatioAtTick(int24(60)),
    //         uint256(posAmount0),
    //         uint256(posAmount1)
    //     );

    //     bytes32 positionId = keccak256(abi.encodePacked(address(owner), int24(-60), int24(60)));

    //     uint256 blockNumber = block.number;
    //     vm.roll(block.number + 5);
    //     uint256 amount = client.getPastBalance(positionId, blockNumber + 4);
    //     (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         sqrtPriceX96,
    //         TickMath.getSqrtRatioAtTick(int24(-60)),
    //         TickMath.getSqrtRatioAtTick(int24(60)),
    //         liquidity
    //     );
    //     // TODO: tighten the following assertion so that voting power (amount) exactly equals the amount
    //     // due to the LP
    //     // assertEq(amount, govToken == address(token1) ? amount1 : amount0);
    // }

    // function test_castVoteAbstain(address owner, int128 amount0, int128 amount1) public {
    //     // vm.assume(address(0) != owner);
    //     owner = address(this);
    //     vm.assume(int256(amount0) + amount1 != 0);
    //     amount0 = int128(bound(amount0, 100, type(int64).max)); // greater causes a revert
    //     amount1 = int128(bound(amount1, 100, type(int64).max)); // greater causes a revert
    //     uint128 posAmount0 = uint128(amount0);
    //     uint128 posAmount1 = uint128(amount1);
    //     (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolKey.toId());
    //     uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
    //         sqrtPriceX96,
    //         TickMath.getSqrtRatioAtTick(int24(-60)),
    //         TickMath.getSqrtRatioAtTick(int24(60)),
    //         uint256(posAmount0),
    //         uint256(posAmount1)
    //     );

    //     vm.startPrank(owner);
    //     token0.mint(owner, posAmount0);
    //     token1.mint(owner, posAmount1);
    //     token0.approve(address(manager), posAmount0);
    //     token1.approve(address(manager), posAmount1);
    //     modifyPosition(
    //         poolKey,
    //         IPoolManager.ModifyPositionParams(int24(-60), int24(60), int256(uint256(liquidity))),
    //         ZERO_BYTES
    //     );
    //     vm.stopPrank();

    //     bytes32 positionId = keccak256(abi.encodePacked(address(owner), int24(-60), int24(60)));

    //     uint256 blockNumber = block.number;
    //     vm.roll(block.number + 5);
    //     uint256 amount = client.getPastBalance(positionId, blockNumber + 4);
    //     (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         sqrtPriceX96,
    //         TickMath.getSqrtRatioAtTick(int24(-60)),
    //         TickMath.getSqrtRatioAtTick(int24(60)),
    //         liquidity
    //     );
    //     // TODO: tighten the following assertion so that voting power (amount) exactly equals the amount
    //     // due to the LP
    //     // assertEq(amount, govToken == address(token1) ? amount1 : amount0);
    // }
}
