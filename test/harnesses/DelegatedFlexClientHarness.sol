// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.26;

// import {CommonBase} from "forge-std/Base.sol";
// // import {DelegatedFlexClient} from "src/DelegatedLiquidityHook.sol";
// import {MockERC20} from "v4-periphery/lib/permit2/test/mocks/MockERC20.sol";
// import {PoolManager} from "v4-core/PoolManager.sol";
// import {Governor, IGovernor} from "@openzeppelin/contracts/governance/Governor.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

// // contract DelegatedFlexClientHarness is DelegatedFlexClient, CommonBase {
// contract DelegatedFlexClientHarness is CommonBase {
//   Governor gov;

//   constructor(address _governor, IPoolManager _poolManager)
//     DelegatedFlexClient(_governor, _poolManager)
//   {
//     gov = Governor(payable(_governor));
//   }

//   function _createExampleProposal(address l1Erc20) internal returns (uint256) {
//     bytes memory proposalCalldata = abi.encode(MockERC20.mint.selector, address(GOVERNOR), 100_000);

//     address[] memory targets = new address[](1);
//     bytes[] memory calldatas = new bytes[](1);
//     uint256[] memory values = new uint256[](1);

//     targets[0] = address(l1Erc20);
//     calldatas[0] = proposalCalldata;
//     values[0] = 0;

//     return
//       IGovernor(address(GOVERNOR)).propose(targets, values, calldatas, "Proposal: To inflate token");
//   }

//   function createProposalVote(address l1Erc20) public returns (uint256) {
//     uint256 _proposalId = _createExampleProposal(l1Erc20);
//     return _proposalId;
//   }

//   function _jumpToActiveProposal(uint256 proposalId) public {
//     uint256 _deadline = GOVERNOR.proposalDeadline(proposalId);
//     vm.roll(_deadline - 1);
//   }
// }
