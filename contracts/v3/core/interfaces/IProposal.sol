pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';

interface IProposal {
    /**
     * 创建提案
     */
    function createProposal(Registry dao) external returns(uint256 proposalId);
    /**
     * 赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, address sponsoringMember, bytes calldata votingData) external;
}