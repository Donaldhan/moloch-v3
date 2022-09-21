pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';
import '../Module.sol';
import '../interfaces/IMember.sol';
import '../interfaces/IProposal.sol';
import '../../adapters/interfaces/IVoting.sol';
import '../../helpers/FlagHelper.sol';
import '../../guards/ModuleGuard.sol';

contract ProposalContract is IProposal, Module, ModuleGuard {
    
    using FlagHelper for uint256;
    //赞助提案
    event SponsorProposal(uint256 proposalId, uint256 proposalIndex, uint256 startingTime);
    //创建提案
    event NewProposal(uint256 proposalId, uint256 proposalIndex);
    //提案标志
    struct Proposal {
        uint256 flags; // using bit function to read the flag. That means that we have up to 256 slots for flags
    }

    mapping(address => uint256) public proposalCount;//DAO提案数量
    mapping(address => mapping(uint256 => Proposal)) public proposals; //dao提案
      /**
     * 创建提案
     */
    function createProposal(Registry dao) override external onlyModule(dao) returns(uint256) {
        uint256 counter = proposalCount[address(dao)];
        proposals[address(dao)][counter++] = Proposal(1);
        proposalCount[address(dao)] = counter;
        uint256 proposalId = counter - 1;

        emit NewProposal(proposalId, counter);
        
        return proposalId;
    }
    /**
     * 赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, address sponsoringMember, bytes calldata votingData) override external onlyModule(dao) {
        Proposal memory proposal = proposals[address(dao)][proposalId];
        //确保提案存在，且没有赞助和取消
        require(proposal.flags.exists(), "proposal does not exist for this dao");
        require(!proposal.flags.isSponsored(), "the proposal has already been sponsored");
        require(!proposal.flags.isCancelled(), "the proposal has been cancelled");
        //确保为成员
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        require(memberContract.isActiveMember(dao, sponsoringMember), "only active members can sponsor someone joining");
        //创建新的提案
        IVoting votingContract = IVoting(dao.getAddress(VOTING_MODULE));
        uint256 votingId = votingContract.startNewVotingForProposal(dao, proposalId, votingData);
        
        emit SponsorProposal(proposalId, votingId, block.timestamp);
    }
}