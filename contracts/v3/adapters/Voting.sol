pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../core/Registry.sol';
import '../core/Module.sol';
import '../core/interfaces/IMember.sol';
import './interfaces/IVoting.sol';
import '../helpers/FlagHelper.sol';

contract VotingContract is IVoting, Module {

    using FlagHelper for uint256;

    struct VotingConfig {
        uint256 flags;//标志
        uint256 votingPeriod;//投票间隔
        uint256 votingCount;//投票数量
    }
    struct Voting {
        uint256 nbYes;//赞成票
        uint256 nbNo;//反对票
        uint256 startingTime;//开始时间
    }
    
    mapping(address => mapping(uint256 => Voting)) votes;//Dao的提案投票
    mapping(address => VotingConfig) votingConfigs;//dao投票配置
    /**
     * 注册的dao，投票配置
     */
    function registerDao(address dao, uint256 votingPeriod) override external {
        votingConfigs[dao].flags = 1; // mark as exists
        votingConfigs[dao].votingPeriod = votingPeriod;
    }

    /**
    possible results here:
    0: has not started 没有开始
    1: tie 平局
    2: pass 通过
    3: not pass 不通过
    4: in progress 进行中
     */
    function voteResult(Registry dao, uint256 proposalId) override external view returns (uint256 state) {
        Voting storage vote = votes[address(dao)][proposalId];
        if(vote.startingTime == 0) {
            return 0;
        }

        if(block.timestamp < vote.startingTime + votingConfigs[address(dao)].votingPeriod) {
            return 4;
        }

        if(vote.nbYes > vote.nbNo) {
            return 2;
        } else if (vote.nbYes < vote.nbNo) {
            return 3;
        } else {
            return 1;
        }
    }
    /**
     * 赞助完成后，开启投票
     */
    //voting  data is not used for pure onchain voting
    function startNewVotingForProposal(Registry dao, uint256 proposalId, bytes calldata) override external returns (uint256){
        // compute startingPeriod for proposal
        Voting storage vote = votes[address(dao)][proposalId];
        vote.startingTime = block.timestamp;
    }
    /**
     * 投票
     */
    function submitVote(Registry dao, uint256 proposalId, uint256 voteValue) external {
        //确保为成员，同时为有效投票
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        require(memberContract.isActiveMember(dao, msg.sender), "only active members can vote");
        require(voteValue < 3, "only blank (0), yes (1) and no (2) are possible values");

        Voting storage vote = votes[address(dao)][proposalId];
       //确保投票开始
        require(vote.startingTime > 0, "this proposalId has not vote going on at the moment");
        require(block.timestamp < vote.startingTime + votingConfigs[address(dao)].votingPeriod, "vote has already ended");
        if(voteValue == 1) {
            vote.nbYes = vote.nbYes + 1;
        } else if (voteValue == 2) {
            vote.nbNo = vote.nbNo + 1;
        }
    }
}