pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import './Module.sol';
import './Registry.sol';
import '../adapters/interfaces/IVoting.sol';
import '../core/interfaces/IProposal.sol';
import '../core/interfaces/IMember.sol';
import '../core/banking/Bank.sol';
import '../adapters/Onboarding.sol';
import '../adapters/Financing.sol';
import '../adapters/Managing.sol';
import '../adapters/Ragequit.sol';

contract DaoFactory is Module {
    //创建dao事件
    event NewDao(address summoner, address dao);

    mapping(bytes32 => address) addresses; //Dao模块地址

    constructor (address memberAddress, address proposalAddress, address votingAddress, address ragequitAddress, address managingAddress, address financingAddress, address onboardingAddress, address bankAddress) {
        addresses[MEMBER_MODULE] = memberAddress;//成员模块地址
        addresses[PROPOSAL_MODULE] = proposalAddress;//提案模块地址
        addresses[VOTING_MODULE] = votingAddress;//投票模块地址
        addresses[RAGEQUIT_MODULE] = ragequitAddress;//怒退模块地址
        addresses[MANAGING_MODULE] = managingAddress;//管理模块地址
        addresses[FINANCING_MODULE] = financingAddress;//金融模块地址
        addresses[ONBOARDING_MODULE] = onboardingAddress;//加入模块地址
        addresses[BANK_MODULE] = bankAddress;//银行模块地址
    }

    /*
     * @dev: A new DAO is instantiated with only the Core Modules enabled, to reduce the call cost. 
     *       Another call must be made to enable the default Adapters, see @registerDefaultAdapters.
     */
    function newDao(uint256 chunkSize, uint256 nbShares, uint256 votingPeriod) external returns (address) {
        Registry dao = new Registry();
        address daoAddress = address(dao);
        //Registering Core Modules 注册核心模块
        dao.addModule(BANK_MODULE, addresses[BANK_MODULE]);
        dao.addModule(MEMBER_MODULE, addresses[MEMBER_MODULE]);
        dao.addModule(PROPOSAL_MODULE, addresses[PROPOSAL_MODULE]);
        dao.addModule(VOTING_MODULE, addresses[VOTING_MODULE]);

        //Registring Adapters 注册Adapters
        dao.addModule(ONBOARDING_MODULE, addresses[ONBOARDING_MODULE]);
        dao.addModule(FINANCING_MODULE, addresses[FINANCING_MODULE]);
        dao.addModule(MANAGING_MODULE, addresses[MANAGING_MODULE]);
        dao.addModule(RAGEQUIT_MODULE, addresses[RAGEQUIT_MODULE]);
        //注册投票合约及投票间隔
        IVoting votingContract = IVoting(addresses[VOTING_MODULE]);
        votingContract.registerDao(daoAddress, votingPeriod);
        //添加初始成员，投票份额为1
        IMember memberContract = IMember(addresses[MEMBER_MODULE]);
        memberContract.updateMember(dao, msg.sender, 1);
        //入门合约
        OnboardingContract onboardingContract = OnboardingContract(addresses[ONBOARDING_MODULE]);
        onboardingContract.configureOnboarding(dao, chunkSize, nbShares);

        emit NewDao(msg.sender, daoAddress);

        return daoAddress;
    }

}