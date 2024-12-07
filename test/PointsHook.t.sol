// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Wrouter} from "src/Wrouter.sol";
import {PointsHook} from "src/PointsHook.sol";

contract WrappedToken is ERC20 {
    ERC20 public token;

    constructor(address _token, string memory name, string memory symbol) ERC20(name, symbol) {
        token = ERC20(_token);
    }

    function mint(address to, uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        token.transfer(msg.sender, amount);
        _burn(from, amount);
    }
}

contract TestPointsHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 token0;
    MockERC20 token1;
    ERC20 wrappedToken0;
    ERC20 wrappedToken1;

    Currency tokenCurrency0;
    Currency tokenCurrency1;

    Currency wtokenCurrency0;
    Currency wtokenCurrency1;

    PointsHook hook;
    Wrouter wrouter;

    function setUp() public {
        manager = new PoolManager();

        // Deploy our TOKEN contract
        token0 = new MockERC20("Test Token0", "TEST0", 18);
        token1 = new MockERC20("Test Token1", "TEST1", 18);
        wrappedToken0 = new WrappedToken(address(token0), "Wrapped Test Token", "wTEST0");
        wrappedToken1 = new WrappedToken(address(token1), "Wrapped Test Token", "wTEST1");

        wrouter = new Wrouter(manager, address(token0), address(token1), address(wrappedToken0), address(wrappedToken1));
        tokenCurrency0 = Currency.wrap(address(token0));
        tokenCurrency1 = Currency.wrap(address(token1));

        wtokenCurrency0 = Currency.wrap(address(wrappedToken0));
        wtokenCurrency1 = Currency.wrap(address(wrappedToken1));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token0.mint(address(this), 1000 ether);
        token0.mint(address(1), 1000 ether);
        // Mint a bunch of TOKEN to ourselves and to address(1)
        token1.mint(address(this), 1000 ether);
        token1.mint(address(1), 1000 ether);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(manager, "Points Token", "TEST_POINTS"), address(flags));

        // Deploy our hook
        hook = PointsHook(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token0.approve(address(wrouter), type(uint256).max);
        token1.approve(address(wrouter), type(uint256).max);

        // Initialize a pool
        (key,) = initPool(
            wtokenCurrency0, // Currency 0 = TOKEN
            wtokenCurrency1, // Currency 1 = TOKEN1
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );
    }

    function test_addLiquidityAndSwap() public {
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceAtTickLower, SQRT_PRICE_1_1, ethToAdd);
        uint256 tokenToAdd =
            LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        wrouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );
        uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

        assertApproxEqAbs(
            pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
            0.1 ether,
            0.001 ether // error margin for precision loss
        );

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        wrouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            Wrouter.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
        assertEq(pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity, 2 * 10 ** 14);

        // TODO: Add test for swapping other direction
        // TODO: Add test for removing liquidity
    }
}
