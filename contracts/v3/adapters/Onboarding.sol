pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import './interfaces/IOnboarding.sol';
import '../core/Module.sol';
import '../core/Registry.sol';
import '../adapters/interfaces/IVoting.sol';
import '../core/interfaces/IProposal.sol';
import '../core/interfaces/IBank.sol';
import '../utils/SafeMath.sol';
import '../guards/AdapterGuard.sol';
import '../guards/ModuleGuard.sol';

contract OnboardingContract is IOnboarding, Module, AdapterGuard, ModuleGuard {
    using SafeMath for uint256;
    // 提案详情
    struct ProposalDetails {
        uint256 amount;//以太坊数量
        uint256 sharesRequested; //请求投票份额
        bool processed;
        address applicant;
    }
    //成员加入配置，投票份额配置，多少以太币（chunkSize），获取多少投票份额（sharesPerChunk）
    struct OnboardingConfig {
        uint256 chunkSize;//分块代销
        uint256 sharesPerChunk;//每块的投票份额数
    }

    mapping(address => OnboardingConfig) public configs;//
    mapping(address => mapping(uint256 => ProposalDetails)) public proposals;//
    /**
     */
    function configureOnboarding(Registry dao, uint256 chunkSize, uint256 sharesPerChunk) external onlyModule(dao) {
        configs[address(dao)].chunkSize = chunkSize;
        configs[address(dao)].sharesPerChunk = sharesPerChunk;
    }
    /**
     * 处理加入
     */
    function processOnboarding(Registry dao, address applicant, uint256 value) override external returns (uint256) {
        //获取配置
        OnboardingConfig memory config = configs[address(dao)];
        
        require(config.sharesPerChunk > 0, "shares per chunk should not be 0");
        require(config.chunkSize > 0, "shares per chunk should not be 0");
        
        uint256 numberOfChunks = value.div(config.chunkSize);
        require(numberOfChunks > 0, "amount of ETH sent was not sufficient");
        uint256 amount = numberOfChunks.mul(config.chunkSize);
        uint256 sharesRequested = numberOfChunks.mul(config.sharesPerChunk);
        // 提交成员加入提案 
        _submitMembershipProposal(dao, applicant, sharesRequested, amount);
        
        return amount;    
    }
    /**
     * 更新代理key
     */
    function updateDelegateKey(Registry dao, address delegateKey) external {
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        memberContract.updateDelegateKey(dao, msg.sender, delegateKey);
    }
    /**
     * 提交成员加入提案
     */
    function _submitMembershipProposal(Registry dao, address newMember, uint256 sharesRequested, uint256 amount) internal {
        IProposal proposalContract = IProposal(dao.getAddress(PROPOSAL_MODULE));
        uint256 proposalId = proposalContract.createProposal(dao);
        ProposalDetails storage proposal = proposals[address(dao)][proposalId];
        proposal.amount = amount;
        proposal.sharesRequested = sharesRequested;
        proposal.applicant = newMember;
    }
   /**
     *  赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, bytes calldata data) override external onlyMember(dao) {
        IProposal proposalContract = IProposal(dao.getAddress(PROPOSAL_MODULE));
        proposalContract.sponsorProposal(dao, proposalId, msg.sender, data);
    }
    /**
     * 处理提案
     */
    function processProposal(Registry dao, uint256 proposalId) override external {
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        require(memberContract.isActiveMember(dao, msg.sender), "only members can sponsor a membership proposal");
        IVoting votingContract = IVoting(dao.getAddress(VOTING_MODULE));
        require(votingContract.voteResult(dao, proposalId) == 2, "proposal need to pass to be processed");
        ProposalDetails storage proposal = proposals[address(dao)][proposalId];
        //更新dao成员，投票份额
        memberContract.updateMember(dao, proposal.applicant, proposal.sharesRequested);
        
        IBank bankContract = IBank(dao.getAddress(BANK_MODULE));
        // address 0 represents native ETH， 地址0为以太坊
        bankContract.addToGuild(dao, address(0), proposal.amount);
    }
}