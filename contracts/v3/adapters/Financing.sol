pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import './interfaces/IFinancing.sol';
import '../core/Module.sol';
import '../core/Registry.sol';
import '../adapters/interfaces/IVoting.sol';
import '../core/interfaces/IProposal.sol';
import '../core/interfaces/IBank.sol';
import '../guards/AdapterGuard.sol';
import '../utils/SafeMath.sol';

contract FinancingContract is IFinancing, Module, AdapterGuard  {
    using SafeMath for uint256;
    /**
     * 提案详情
     */
    struct ProposalDetails {
        address applicant;
        uint256 amount;//提案需要token数量
        address token;//提案token地址
        bytes32 details;
        bool processed;//提案是否处理
    }

    mapping(address => mapping(uint256 => ProposalDetails)) public proposals; //dao提案

    /* 
     * default fallback function to prevent from sending ether to the contract
     * 阻止向此合约发送eth
     */
    receive() external payable {
        revert();
    }
    /**
     * 创建金融需求提案：那个token，多少金额
     */
    function createFinancingRequest(Registry dao, address applicant, address token, uint256 amount, bytes32 details) override external returns (uint256) {
        require(amount > 0, "invalid requested amount");
        require(token == address(0x0), "only raw eth token is supported");
        //TODO (fforbeck): check if other types of tokens are supported/allowed

        IBank bankContract = IBank(dao.getAddress(BANK_MODULE));
        require(bankContract.isNotReservedAddress(applicant), "applicant address cannot be reserved");
        
        IProposal proposalContract = IProposal(dao.getAddress(PROPOSAL_MODULE));
        uint256 proposalId = proposalContract.createProposal(dao);

        ProposalDetails storage proposal = proposals[address(dao)][proposalId];
        proposal.applicant = applicant;
        proposal.amount = amount;
        proposal.details = details;
        proposal.processed = false;
        proposal.token = token;
        return proposalId;
    }
    /**
     * 赞助提案
     */
    function sponsorProposal(Registry dao, uint256 proposalId, bytes calldata data) override external onlyMember(dao) {
        IProposal proposalContract = IProposal(dao.getAddress(PROPOSAL_MODULE));
        proposalContract.sponsorProposal(dao, proposalId, msg.sender, data);
    }
    /**
     * 处理提案
     */
    function processProposal(Registry dao, uint256 proposalId) override external onlyMember(dao) {
        //确保提案没有处理过
        ProposalDetails memory proposal = proposals[address(dao)][proposalId];
        require(!proposal.processed, "proposal already processed");
        //需要提案通过
        IVoting votingContract = IVoting(dao.getAddress(VOTING_MODULE));
        require(votingContract.voteResult(dao, proposalId) == 2, "proposal need to pass to be processed");

        IBank bankContract = IBank(dao.getAddress(BANK_MODULE));
        proposals[address(dao)][proposalId].processed = true;
        //转账给提案者
        bankContract.transferFromGuild(dao, proposal.applicant, proposal.token, proposal.amount);
    }
}