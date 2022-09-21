pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../../core/Registry.sol';

interface IVoting {
    /**
     * 赞助完成后，开启投票
     */
    function startNewVotingForProposal(Registry dao, uint256 proposalId, bytes calldata data) external returns (uint256);
    /**
     * 投票结果
     */
    function voteResult(Registry dao, uint256 proposalId) external returns (uint256 state);
    /**
     * 注册dao投票间隔
     */
    function registerDao(address dao, uint256 votingPeriod) external;
}