// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorCountingFractional} from "flexible-voting/GovernorCountingFractional.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

contract GovernorFlexibleVotingMock is GovernorCountingFractional, GovernorVotes {
  constructor(string memory _name, ERC20Votes _token) Governor(_name) GovernorVotes(_token) {}

  function quorum(uint256) public pure override returns (uint256) {
    return 0;
  }

  function votingDelay() public pure override returns (uint256) {
    return 4;
  }

  function votingPeriod() public pure override returns (uint256) {
    return 16;
  }

  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function castVoteWithReasonAndParamsBySig(
    uint256 proposalId,
    uint8 support,
    string calldata reason,
    bytes memory params,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public returns (uint256) {
  }
  // ) public override(Governor, GovernorCountingFractional) returns (uint256) {
  //   return GovernorCountingFractional.castVoteWithReasonAndParamsBySig(
  //     proposalId, support, reason, params, v, r, s
  //   );
  // }

  function cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 salt
  ) public override returns (uint256 proposalId) {
    return _cancel(targets, values, calldatas, salt);
  }
}
