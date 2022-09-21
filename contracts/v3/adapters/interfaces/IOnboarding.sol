pragma solidity ^0.7.0;

import '../../core/Registry.sol';
// SPDX-License-Identifier: MIT

interface IOnboarding {
    /**
     *  赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, bytes calldata data) external;    
    /**
     * 处理提案
     */
    function processProposal(Registry dao, uint256 proposalId) external;
    /**
     * 处理成员加入
     */
    function processOnboarding(Registry dao, address applicant, uint256 value) external returns (uint256);
}