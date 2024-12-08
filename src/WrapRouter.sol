// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import {console2 as console} from "forge-std/console2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
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

contract WrapRouter {
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
    ERC20 public immutable token0;
    ERC20 public immutable token1;

    bool public immutable isWrappedToken0;
    bool public immutable isWrappedToken1;

    Currency public tokenCurrency0;
    Currency public tokenCurrency1;

    // deployer passes two tokens and bools to determine which should be wrapped
    // the tokens are wrapped in the constructor
    // token0 and token1 of the pool will be based on the wrapped tokens addresses
    constructor(IPoolManager _manager, address _tokenA, address _tokenB, bool _isWrappedTokenA, bool _isWrappedTokenB) {
        require(_isWrappedTokenA || _isWrappedTokenB, "at least one token must be wrapped");
        manager = _manager;

        address wrappedTokenA;
        address wrappedTokenB;
        if (_isWrappedTokenA) {
            wrappedTokenA = address(new WrappedToken(_tokenA));
            ERC20(_tokenA).approve(wrappedTokenA, type(uint256).max);
        }
        if (_isWrappedTokenB) {
            wrappedTokenB = address(new WrappedToken(address(_tokenB)));
            ERC20(_tokenB).approve(wrappedTokenB, type(uint256).max);
        }

        address currentTokenA = _isWrappedTokenA ? wrappedTokenA : _tokenA;
        address currentTokenB = _isWrappedTokenB ? wrappedTokenB : _tokenB;

        if (currentTokenA > currentTokenB) {
            token1 = ERC20(currentTokenA);
            isWrappedToken1 = _isWrappedTokenA;
            token0 = ERC20(currentTokenB);
            isWrappedToken0 = _isWrappedTokenB;
        } else {
            token0 = ERC20(currentTokenA);
            isWrappedToken0 = _isWrappedTokenA;
            token1 = ERC20(currentTokenB);
            isWrappedToken1 = _isWrappedTokenB;
        }

        tokenCurrency0 = Currency.wrap(address(token0));
        tokenCurrency1 = Currency.wrap(address(token1));

        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);
    }

    // function _getWrappedToken(address token) internal view returns (WrappedToken) {
    //     if (token == address(token0)) {
    //         return wrappedToken0;
    //     } else if (token == address(token1)) {
    //         return wrappedToken1;
    //     } else {
    //         revert("invalid token");
    //     }
    // }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.unlock(
                abi.encode(Type.SWAP, abi.encode(CallbackDataSwap(msg.sender, testSettings, key, params, hookData)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
        }
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
                        CallbackDataModifyLiquidity(msg.sender, key, params, hookData, settleUsingBurn, takeClaims)
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

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        
        require(msg.sender == address(manager));
        (Type t, bytes memory data) = abi.decode(rawData, (Type, bytes));
        if (t == Type.SWAP) {
            return _unlockCallbackSwap(abi.decode(data, (CallbackDataSwap)));
        } else if (t == Type.MODIFY_LIQUIDITY) {
            return _unlockCallbackModifyLiquidity(abi.decode(data, (CallbackDataModifyLiquidity)));
        } else {
            revert("invalid type");
        }
    }

    function _unlockCallbackSwap(CallbackDataSwap memory data) internal returns (bytes memory) {
        (, , int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (, , int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (, , int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (, , int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                require(
                    deltaAfter0 >= data.params.amountSpecified,
                    "deltaAfter0 is not greater than or equal to data.params.amountSpecified"
                );
                require(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                require(deltaAfter1 >= 0, "deltaAfter1 is not greater than or equal to 0");
            } else {
                // exact output, 0 for 1
                require(deltaAfter0 <= 0, "deltaAfter0 is not less than or equal to zero");
                require(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
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
                require(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
                require(deltaAfter0 >= 0, "deltaAfter0 is not greater than or equal to 0");
            } else {
                // exact output, 1 for 0
                require(deltaAfter1 <= 0, "deltaAfter1 is not less than or equal to 0");
                require(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                require(
                    deltaAfter0 <= data.params.amountSpecified,
                    "deltaAfter0 is not less than or equal to data.params.amountSpecified"
                );
            }
        }

        WrappedToken currentToken;
        Currency currentCurrency;
        uint256 currentAmount;
        if (deltaAfter0 < 0) {
            currentAmount = uint256(-deltaAfter0);
            currentCurrency = data.key.currency0;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            if (isWrappedToken0) {
                // transfer in underlying from user
                currentToken.token().transferFrom(data.sender, address(this), currentAmount);

                // mint wrapped token for pool
                currentToken.mint(address(this), currentAmount);
            } else {
                currentToken.transferFrom(data.sender, address(this), currentAmount);
            }

            // data.sender
            currentCurrency.settle(manager, address(this), currentAmount, data.testSettings.settleUsingBurn);
        }
        if (deltaAfter1 < 0) {
            currentAmount = uint256(-deltaAfter1);
            currentCurrency = data.key.currency1;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            if (isWrappedToken1) {
                // transfer in underlying from user
                currentToken.token().transferFrom(data.sender, address(this), currentAmount);

                // mint wrapped token for pool
                currentToken.mint(address(this), currentAmount);
            } else {
                currentToken.transferFrom(data.sender, address(this), currentAmount);
            }

            // data.sender
            currentCurrency.settle(manager, address(this), currentAmount, data.testSettings.settleUsingBurn);
        }

        if (deltaAfter0 > 0) {
            console.log('hello');
            
            currentAmount = uint256(deltaAfter0);
            currentCurrency = data.key.currency0;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            currentCurrency.take(manager, address(this), currentAmount, data.testSettings.takeClaims);

            if (isWrappedToken0) {
                currentToken.burn(data.sender, currentAmount);
            } else {
                currentToken.transfer(data.sender, currentAmount);
            }
        }
        if (deltaAfter1 > 0) {
            console.log('moto');
            currentAmount = uint256(deltaAfter1);
            currentCurrency = data.key.currency1;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            currentCurrency.take(manager, address(this), currentAmount, data.testSettings.takeClaims);
            console.log("LOOK", currentToken.balanceOf(address(this)));
            if (isWrappedToken1) {
                currentToken.burn(data.sender, currentAmount);
            } else {
                currentToken.transfer(data.sender, currentAmount);
            }
        }

        return abi.encode(delta);
    }

    function _unlockCallbackModifyLiquidity(CallbackDataModifyLiquidity memory data) internal returns (bytes memory) {
        
        (uint128 liquidityBefore, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );
        (BalanceDelta delta, ) = manager.modifyLiquidity(data.key, data.params, data.hookData);
        (uint128 liquidityAfter, , ) = manager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (, , int256 delta0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (, , int256 delta1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(
            int128(liquidityBefore) + data.params.liquidityDelta == int128(liquidityAfter),
            "liquidity change incorrect"
        );
        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        WrappedToken currentToken;
        Currency currentCurrency;
        uint256 currentAmount;
        if (delta0 < 0) {
            currentAmount = uint256(-delta0);
            currentCurrency = data.key.currency0;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            if (isWrappedToken0) {
                // transfer in underlying from user
                currentToken.token().transferFrom(data.sender, address(this), currentAmount);

                // mint wrapped token for pool
                currentToken.mint(address(this), currentAmount);
            } else {
                currentToken.transferFrom(data.sender, address(this), currentAmount);
            }
            currentCurrency.settle(manager, address(this), currentAmount, data.settleUsingBurn);
        }
        if (delta1 < 0) {
            currentAmount = uint256(-delta1);
            currentCurrency = data.key.currency1;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            if (isWrappedToken1) {
                // transfer in underlying from user
                currentToken.token().transferFrom(data.sender, address(this), currentAmount);

                // mint wrapped token for pool
                currentToken.mint(address(this), currentAmount);
            } else {
                currentToken.transferFrom(data.sender, address(this), currentAmount);
            }
            currentCurrency.settle(manager, address(this), currentAmount, data.settleUsingBurn);
        }
        if (delta0 > 0) {
            currentAmount = uint256(delta0);
            currentCurrency = data.key.currency0;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            currentCurrency.take(manager, address(this), currentAmount, data.takeClaims);

            if (isWrappedToken0) {
                currentToken.burn(data.sender, currentAmount);
            } else {
                currentToken.transfer(data.sender, currentAmount);
            }
        }
        if (delta1 > 0) {
            currentAmount = uint256(delta1);
            currentCurrency = data.key.currency1;
            currentToken = WrappedToken(Currency.unwrap(currentCurrency));

            currentCurrency.take(manager, address(this), currentAmount, data.takeClaims);

            if (isWrappedToken0) {
                currentToken.burn(data.sender, currentAmount);
            } else {
                currentToken.transfer(data.sender, currentAmount);
            }
        }
        return abi.encode(delta);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    ) internal view returns (uint256 userBalance, uint256 poolBalance, int256 delta) {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(manager));
        delta = manager.currencyDelta(deltaHolder, currency);
    }
}
