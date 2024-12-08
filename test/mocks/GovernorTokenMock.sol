// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MyToken } from "@openzeppelin/contracts/mocks/docs/governance/MyToken.sol";

// I imported this "MyToken" which is already working in the openzeppelin contracts lib
contract GovernorTokenMock is MyToken {
  function mint(address account, uint256 amount) public {
    _mint(account, amount);
    delegate(account);
  }
  
}

// /// @notice An ERC20Votes token to help test the L2 voting system
// contract GovernorTokenMock is ERC20Votes {
//   constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) {}

//   /// @dev Mints tokens to an address to help test bridging and voting.
//   /// @param account The address of where to mint the tokens.
//   /// @param amount The amount of tokens to mint.
//   function mint(address account, uint256 amount) public {
//     _mint(account, amount);
//     delegate(account);
//   }

//   /**
//    * @dev Not really needed, except as compatibility shim for our GovernorMock (which is
//    * ERC20VotesComp)
//    */
//   function getPriorVotes(address account, uint256 blockNumber)
//     external
//     view
//     virtual
//     returns (uint256)
//   {
//     return getPastVotes(account, blockNumber);
//   }
// }
