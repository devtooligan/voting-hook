// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { WrapRouter } from "src/WrapRouter.sol";
import { FlexVotingClient } from "flexible-voting/FlexVotingClient.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { TokenBalancesTrackerHook } from "src/TokenBalancesTrackerHook.sol";

contract VotingRouter is WrapRouter, FlexVotingClient {
    TokenBalancesTrackerHook immutable hook;
    constructor(
        IPoolManager _poolManager,
        address _tokenA,
        address _tokenB,
        bool isWrappedTokenA,
        bool isWrappedTokenB,
        address gov,
        address _hook
    ) WrapRouter(_poolManager, _tokenA, _tokenB, isWrappedTokenA, isWrappedTokenB) FlexVotingClient(gov) {
        hook = TokenBalancesTrackerHook(_hook);
    }

    function _rawBalanceOf(address _user) internal view virtual override returns (uint208) {
        // todo: should we have the hook return a uint208?
        return uint208(hook.rawBalanceOf(_user));
    }
}
