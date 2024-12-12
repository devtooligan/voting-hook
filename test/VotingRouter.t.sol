// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {GovernorFlexibleVotingMock} from "test/mocks/GovernorMock.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {GovernorTokenMock} from "test/mocks/GovernorTokenMock.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { WrapRouter } from "src/WrapRouter.sol";
import { VotingRouter } from "src/VotingRouter.sol";
import {FlexVotingClient} from "flexible-voting/FlexVotingClient.sol";
import {TokenBalancesTrackerHook} from "src/TokenBalancesTrackerHook.sol";
contract WrappedToken is ERC20 {
    ERC20 public token;

    // todo: add this back: constructor(address _token, string memory name, string memory symbol) ERC20("WrappedToken", "WT") {
    constructor(address _token) ERC20("WrappedToken", "WT") {
        token = ERC20(_token);
    }

    function mint(address to, uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public {
        _burn(msg.sender, amount);
        token.transfer(to, amount);
    }
}

contract VotingRouterHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    GovernorFlexibleVotingMock gov;

    address token0;
    address token1;
    ERC20 wrappedToken0;
    ERC20 wrappedToken1;

    Currency tokenCurrency0;
    Currency tokenCurrency1;

    Currency wtokenCurrency0;
    Currency wtokenCurrency1;

    TokenBalancesTrackerHook hook;
    VotingRouter voting_router;

    function setUp() public {
        address tokenA = address(new GovernorTokenMock());
        address tokenB = address(new MockERC20("Test Token0", "TEST0", 18));
        manager = new PoolManager();
        gov = new GovernorFlexibleVotingMock("Governor", GovernorTokenMock(tokenA));
        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG
        );
        deployCodeTo("TokenBalancesTrackerHook.sol", abi.encode(manager, address(gov)), address(flags));

        hook = TokenBalancesTrackerHook(address(flags));


        voting_router = new VotingRouter(
            manager,
            tokenA,
            tokenB,
            true,
            true,
            address(0),
            address(hook)

        );
        token0 = address(voting_router.token0());
        token1 = address(voting_router.token1());
        tokenCurrency0 = voting_router.tokenCurrency0();
        tokenCurrency1 = voting_router.tokenCurrency1();

        // Mint a bunch of TOKEN to ourselves and to address(1)
        MockERC20(tokenA).mint(address(this), 1000 ether);
        MockERC20(tokenA).mint(address(1), 1000 ether);
        // Mint a bunch of TOKEN to ourselves and to address(1)
        MockERC20(tokenB).mint(address(this), 1000 ether);
        MockERC20(tokenB).mint(address(1), 1000 ether);

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        ERC20(tokenA).approve(address(voting_router), type(uint256).max);
        ERC20(tokenB).approve(address(voting_router), type(uint256).max);

        // Initialize a pool
        (key, ) = initPool(
            tokenCurrency0, 
            tokenCurrency1,
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );
    }

    function test_addLiquidityAndSwap() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 amountToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            amountToAdd
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
            hookData
        );
        voting_router.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            WrapRouter.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // TODO: Add test for swapping other direction
        // TODO: Add test for removing liquidity
    }
}
