pragma solidity ^0.7.0;
import '../../core/Registry.sol';
// SPDX-License-Identifier: MIT

interface IManaging {
    /**
     * 模块变更
     */
    function createModuleChangeRequest(Registry dao, bytes32 moduleId, address moduleAddress) external returns (uint256);
    /**
     * 赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, bytes calldata data) external;    
    /**
     * 处理提案
     */
    function processProposal(Registry dao, uint256 proposalId) external;
}