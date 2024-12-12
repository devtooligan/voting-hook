
<div align="center">
    <center>
        <img src="https://bouncy-print-988.notion.site/image/https%3A%2F%2Fnotionforms-prod.s3.eu-west-2.amazonaws.com%2Fforms%2F112346%2Fsubmissions%2FScreenshot-2024-12-07-at-5.17.33PM_35e5a887-f5ff-4339-bbb7-0f6f69de6a7d.png?table=block&id=1565f044-4abe-81ca-acf3-ca4008b1fd43&spaceId=3118cd40-1c65-4df1-afa4-02528d8d0ffd&width=2000&userId=&cache=v2" height="350" alt="@offbeatsecurity" style="margin-bottom: 20px;">
        <h1>voting-hook</h1>
        <p><i>A Uniswap V4 Hook that allows LP holders to vote with their underlying tokens</i></p>
        <br>
        <p>Developed by:</p> 
        <p><b>devtooligan</b> and <b>wildmolasses</b></p>
        <p>Uniswap Hook Incubator Cohort #3</p> 
    </center>
</div>

# Overview
Liquidity providers in DeFi face a common dilemma: they must choose between earning fees by providing liquidity or participating in governance. When tokens are locked in a liquidity pool, LPs lose their ability to vote with those tokens. Our hook solves this problem by enabling LP token holders to participate in governance using their underlying token position.



# Problem & Solution
## The Problem
When users provide liquidity to a Uniswap pool their governance tokens get locked in the pool so they must choose between earning fees or participating in governance

## Our Solution
The voting-hook:
1. Tracks underlying token amounts through price and liquidity checkpoints
2. Calculates governance token ownership at any block number
3. Integrates with governance systems while tokens remain in the pool

# Technical Implementation
# Technical Implementation

## Architecture
The voting-hook system consists of three main components that work together to enable LP governance participation:

1. **TokenBalancesTrackerHook**
   - Core Uniswap v4 Hook that users' underlying token balances in LP positions
   - Uses OpenZeppelin's Checkpoints to maintain secure history of:
     - Position liquidity
     - Pool prices
     - Position tick ranges
   - Retrieves balances at any historical block

2. **WrapRouter**
   - Simple router that wraps/unwraps tokens for pool interactions
   - Pool holds wrapped tokens while router custodies the underlying tokens
   - There are many use cases for this type of router:
     - Lending out underlying tokens for yield
     - Solves certain security vulnerabilities for example tokens with a blacklist can prevent flashloaning of their tokens to meet regulatory guidelines

3. **Flexible Voting Integration**
   - WrapRouter extends FlexVotingClient
   - Flexible Voting is a powerful governance primitive developed by Scopelift:
     - Allows splitting voting weight across For/Against/Abstain
     - Integrated into OpenZeppelin's Governor contracts
     - Adopted by major DAOs like Aave, Gitcoin, and Frax
   - Enables LP governance participation while:
     - Maintaining liquidity position
     - Earning trading fees
     - Potentially earning additional yield

## Future Direction
- WrapRouter is currently a simple implementation based on the utilities used by Uniswap test framework. We want to build out a full-fledged router.
- Build a simple UI that would allow holders of these LP tokens to cast votes on their underlying tokens