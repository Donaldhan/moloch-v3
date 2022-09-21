pragma solidity ^0.7.0;
import '../../core/Registry.sol';

// SPDX-License-Identifier: MIT

interface IFinancing {
    /**
     *  创建提案金融需求：那个token，多少金额
     */
    function createFinancingRequest(Registry dao, address applicant, address token, uint256 amount, bytes32 details) external returns (uint256);
    /**
     * 赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, bytes calldata data) external;    
    /**
     * 处理提案
     */
    function processProposal(Registry dao, uint256 proposalId) external;
}