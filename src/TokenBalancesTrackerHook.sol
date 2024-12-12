// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IFractionalGovernor} from "flexible-voting/interfaces/IFractionalGovernor.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
contract TokenBalancesTrackerHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using Checkpoints for Checkpoints.Trace208;

    mapping(bytes32 positionId => Checkpoints.Trace208) internal positionLiquidityCheckpoints;
    Checkpoints.Trace208 internal priceCheckpoints;
    mapping(bytes32 positionId => int24[2]) internal positionTicks;

    mapping(address => bytes32[]) internal positionsByAddress;
    mapping(bytes32 => bool) internal seenPosition;

    bool public isGovToken0;
    address immutable GOV_TOKEN;

    constructor(IPoolManager _poolManager, address _governor) BaseHook(_poolManager) {
        GOV_TOKEN = IFractionalGovernor(_governor).token();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false, // TODO: confirm
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false // TODO: confirm
        });
    }

    /**
     * @notice Callback after a pool is initialized. Record which token (token0 or token1) is the gov
     * token, to return appropriate values in other methods
     */
    function afterInitialize(
        address, // sender
        PoolKey calldata key,
        uint160, // sqrtPriceX96
        int24 // tick
    ) external override returns (bytes4 selector) {
        // todo: fix this logic:
        // isGovToken0 = Currency.unwrap(key.currency0) == GOV_TOKEN;
        // // If neither token in the pair is the gov token, revert
        // if (!isGovToken0 && Currency.unwrap(key.currency1) != GOV_TOKEN) {
        //     revert("Currency pair does not include governor token");
        // }
        selector = BaseHook.afterInitialize.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata modifyParams,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    )
        // bytes calldata
        external
        override
        returns (bytes4 selector, BalanceDelta)
    {
        _afterModifyLiquidity(sender, key, modifyParams);
        return(BaseHook.afterAddLiquidity.selector, delta);
    }

    function afterRemoveLiquidity(
                address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata modifyParams,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4 selector, BalanceDelta) {
        _afterModifyLiquidity(sender, key, modifyParams);
        selector = BaseHook.afterAddLiquidity.selector;
    }

    function _afterModifyLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata modifyParams
    ) internal returns (bytes4 selector) {
    // ) external override returns (bytes4 selector) {
        bytes32 positionId = keccak256(abi.encodePacked(sender, modifyParams.tickLower, modifyParams.tickUpper));

        // Save tickLower & tickUpper into a mapping for this position id
        positionTicks[positionId] = [modifyParams.tickLower, modifyParams.tickUpper];

        // get current liquidity
        uint256 liquidity = positionLiquidityCheckpoints[positionId].latest();
        uint256 liquidityNext = modifyParams.liquidityDelta < 0
            ? liquidity - uint256(-modifyParams.liquidityDelta)
            : liquidity + uint256(modifyParams.liquidityDelta);

        // checkpoint position liquidity
        positionLiquidityCheckpoints[positionId].push(uint48(block.number), uint208(liquidityNext));
        // Checkpoint pool price StateLibrary.getSlot0(manager, poolId);
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, key.toId());
        // (uint160 sqrtPriceX96,,,) = poolManager.getSlot0();
        priceCheckpoints.push(uint48(block.number), uint208(sqrtPriceX96));
        // Record position for address
        if (seenPosition[positionId] == false) {
            seenPosition[positionId] = true;
            positionsByAddress[sender].push(positionId);
        }
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4 selector, int128)
    {
        (uint160 price,,,) = StateLibrary.getSlot0(poolManager, key.toId());
        priceCheckpoints.push(uint48(block.timestamp), price);
        selector = BaseHook.afterSwap.selector;
    }

    function rawBalanceOf(address _user) external view returns (uint256) {
        uint256 _rawBalance;
        for (uint256 i = 0; i < positionsByAddress[_user].length; i++) {
            _rawBalance += getPastBalance(positionsByAddress[_user][i], block.number);
        }
        return _rawBalance;
    }

    function getPastBalance(bytes32 positionId, uint256 blockNumber) public view returns (uint256) {
        // TODO: make sure these unchecked casts are safe
        uint160 price = uint160(priceCheckpoints.upperLookupRecent(uint48(blockNumber)));
        uint128 liquidity = uint128(positionLiquidityCheckpoints[positionId].upperLookupRecent(uint48(blockNumber)));
        (uint256 token0, uint256 token1) = LiquidityAmounts.getAmountsForLiquidity(
            price,
            TickMath.getSqrtPriceAtTick(positionTicks[positionId][0]),
            TickMath.getSqrtPriceAtTick(positionTicks[positionId][1]),
            liquidity
        );
        return isGovToken0 ? token0 : token1;
    }
}
