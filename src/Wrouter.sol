// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {WrappedToken} from "test/PointsHook.t.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolTestBase} from "@uniswap/v4-core/src/test/PoolTestBase.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {console2 as console} from "forge-std/console2.sol";

contract Wrouter {
    using CurrencySettler for Currency;
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    error NoSwapOccurred();

    enum Type {
        SWAP,
        MODIFY_LIQUIDITY
    }

    struct CallbackDataModifyLiquidity {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

    struct CallbackDataSwap {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }

    IPoolManager public immutable manager;

    // I think all these can be immutable
    ERC20 token0;
    ERC20 token1;
    WrappedToken wrappedToken0;
    WrappedToken wrappedToken1;

    Currency tokenCurrency0;
    Currency tokenCurrency1;

    Currency wtokenCurrency0;
    Currency wtokenCurrency1;

    constructor(
        IPoolManager _manager,
        address _token0,
        address _token1,
        address _wrappedToken0,
        address _wrappedToken1
    ) {
        manager = _manager;
        token0 = ERC20(_token0);
        token1 = ERC20(_token1);
        wrappedToken0 = WrappedToken(_wrappedToken0);
        wrappedToken1 = WrappedToken(_wrappedToken1);

        tokenCurrency0 = Currency.wrap(address(token0));
        tokenCurrency1 = Currency.wrap(address(token1));

        wtokenCurrency0 = Currency.wrap(address(wrappedToken0));
        wtokenCurrency1 = Currency.wrap(address(wrappedToken1));
        wrappedToken0.approve(address(manager), type(uint256).max);
        wrappedToken1.approve(address(manager), type(uint256).max);
        token0.approve(_wrappedToken0, type(uint256).max);
        token1.approve(_wrappedToken1, type(uint256).max);
    }

    function _getWrappedToken(
        address token
    ) internal view returns (WrappedToken) {
        if (token == address(token0)) {
            return wrappedToken0;
        } else if (token == address(token1)) {
            return wrappedToken1;
        } else {
            revert("invalid token");
        }
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    Type.SWAP,
                    abi.encode(
                        CallbackDataSwap(
                            msg.sender,
                            testSettings,
                            key,
                            params,
                            hookData
                        )
                    )
                )
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0)
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = modifyLiquidity(key, params, hookData, false, false);
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool settleUsingBurn,
        bool takeClaims
    ) public payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    Type.MODIFY_LIQUIDITY,
                    abi.encode(
                        CallbackDataModifyLiquidity(
                            msg.sender,
                            key,
                            params,
                            hookData,
                            settleUsingBurn,
                            takeClaims
                        )
                    )
                )
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
        }
    }

    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        require(msg.sender == address(manager));
        (Type t, bytes memory data) = abi.decode(rawData, (Type, bytes));
        if (t == Type.SWAP) {
            return _unlockCallbackSwap(abi.decode(data, (CallbackDataSwap)));
        } else if (t == Type.MODIFY_LIQUIDITY) {
            return
                _unlockCallbackModifyLiquidity(
                    abi.decode(data, (CallbackDataModifyLiquidity))
                );
        } else {
            revert("invalid type");
        }
    }

    function _unlockCallbackSwap(
        CallbackDataSwap memory data
    ) internal returns (bytes memory) {
        (, , int256 deltaBefore0) = _fetchBalances(
            data.key.currency0,
            data.sender,
            address(this)
        );
        (, , int256 deltaBefore1) = _fetchBalances(
            data.key.currency1,
            data.sender,
            address(this)
        );

        require(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (, , int256 deltaAfter0) = _fetchBalances(
            data.key.currency0,
            data.sender,
            address(this)
        );
        (, , int256 deltaAfter1) = _fetchBalances(
            data.key.currency1,
            data.sender,
            address(this)
        );

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                require(
                    deltaAfter0 >= data.params.amountSpecified,
                    "deltaAfter0 is not greater than or equal to data.params.amountSpecified"
                );
                require(
                    delta.amount0() == deltaAfter0,
                    "delta.amount0() is not equal to deltaAfter0"
                );
                require(
                    deltaAfter1 >= 0,
                    "deltaAfter1 is not greater than or equal to 0"
                );
            } else {
                // exact output, 0 for 1
                require(
                    deltaAfter0 <= 0,
                    "deltaAfter0 is not less than or equal to zero"
                );
                require(
                    delta.amount1() == deltaAfter1,
                    "delta.amount1() is not equal to deltaAfter1"
                );
                require(
                    deltaAfter1 <= data.params.amountSpecified,
                    "deltaAfter1 is not less than or equal to data.params.amountSpecified"
                );
            }
        } else {
            if (data.params.amountSpecified < 0) {
                // exact input, 1 for 0
                require(
                    deltaAfter1 >= data.params.amountSpecified,
                    "deltaAfter1 is not greater than or equal to data.params.amountSpecified"
                );
                require(
                    delta.amount1() == deltaAfter1,
                    "delta.amount1() is not equal to deltaAfter1"
                );
                require(
                    deltaAfter0 >= 0,
                    "deltaAfter0 is not greater than or equal to 0"
                );
            } else {
                // exact output, 1 for 0
                require(
                    deltaAfter1 <= 0,
                    "deltaAfter1 is not less than or equal to 0"
                );
                require(
                    delta.amount0() == deltaAfter0,
                    "delta.amount0() is not equal to deltaAfter0"
                );
                require(
                    deltaAfter0 <= data.params.amountSpecified,
                    "deltaAfter0 is not less than or equal to data.params.amountSpecified"
                );
            }
        }

        WrappedToken currentWrappedToken;
        uint amount;
        if (deltaAfter0 < 0) {
            console.log("a");
            amount = uint256(-deltaAfter0);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency0)
            );

            // transfer in underlying from user
            currentWrappedToken.token().transferFrom(
                data.sender,
                address(this),
                amount
            );

            // mint wrapped token for pool
            currentWrappedToken.mint(address(this), amount);

            // data.sender
            data.key.currency0.settle(
                manager,
                address(this),
                amount,
                data.testSettings.settleUsingBurn
            );
        }
        if (deltaAfter1 < 0) {
            console.log("b");
            amount = uint256(-deltaAfter1);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency1)
            );

            // transfer in underlying from user 
            currentWrappedToken.token().transferFrom(
                data.sender,
                address(this),
                amount
            );

            // mint wrapped token for pool
            currentWrappedToken.mint(address(this), amount);


            data.key.currency1.settle(
                manager,
                address(this),
                uint256(-deltaAfter1),
                data.testSettings.settleUsingBurn
            );
        }
        if (deltaAfter0 > 0) {
            console.log("c");
            amount = uint256(deltaAfter0);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency0)
            );
            data.key.currency0.take(
                manager,
                address(this),
                amount,
                data.testSettings.takeClaims
            );

            currentWrappedToken.burn(data.sender, amount);
        }
        if (deltaAfter1 > 0) {
            console.log("d");
            amount = uint256(deltaAfter1);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency1)
            );

            data.key.currency1.take(
                manager,
                address(this),
                amount,
                data.testSettings.takeClaims
            );
        }

        return abi.encode(delta);
    }

    function _unlockCallbackModifyLiquidity(
        CallbackDataModifyLiquidity memory data
    ) internal returns (bytes memory) {
        (uint128 liquidityBefore, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (BalanceDelta delta, ) = manager.modifyLiquidity(
            data.key,
            data.params,
            data.hookData
        );

        (uint128 liquidityAfter, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (, , int256 delta0) = _fetchBalances(
            data.key.currency0,
            data.sender,
            address(this)
        );
        (, , int256 delta1) = _fetchBalances(
            data.key.currency1,
            data.sender,
            address(this)
        );

        require(
            int128(liquidityBefore) + data.params.liquidityDelta ==
                int128(liquidityAfter),
            "liquidity change incorrect"
        );

        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        WrappedToken currentWrappedToken;
        uint amount;
        if (delta0 < 0) {
            console.log("1");
            amount = uint256(-delta0);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency0)
            );

            // transfer in underlying from user
            currentWrappedToken.token().transferFrom(
                data.sender,
                address(this),
                amount
            );

            // mint wrapped token for pool
            currentWrappedToken.mint(address(this), amount);

            data.key.currency0.settle(
                manager,
                address(this),
                amount,
                data.settleUsingBurn
            );
        }
        if (delta1 < 0) {
            console.log("2");
            amount = uint256(-delta1);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency1)
            );

            // transfer in underlying from user
            currentWrappedToken.token().transferFrom(
                data.sender,
                address(this),
                amount
            );

            // mint wrapped token for pool
            currentWrappedToken.mint(address(this), amount);


            data.key.currency1.settle(
                manager,
                address(this),
                amount,
                data.settleUsingBurn
            );
        }
        if (delta0 > 0) {
            console.log("3");
            amount = uint256(delta0);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency0)
            );
            data.key.currency0.take(
                manager,
                address(this),
                amount,
                data.takeClaims
            );

            currentWrappedToken.burn(data.sender, amount);
        }
        if (delta1 > 0) {
            console.log("4");
            amount = uint256(delta1);
            currentWrappedToken = WrappedToken(
                Currency.unwrap(data.key.currency1)
            );
            data.key.currency1.take(
                manager,
                address(this),
                amount,
                data.takeClaims
            );

            currentWrappedToken.burn(data.sender, amount);
        }
        return abi.encode(delta);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    )
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(manager));
        delta = manager.currencyDelta(deltaHolder, currency);
    }
}
