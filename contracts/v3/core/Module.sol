pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT
/**
 *  核心模块
 */
abstract contract Module {

    // Core Modules 银行、成员、提案、投票核心模块
    bytes32 constant BANK_MODULE = keccak256("bank");
    bytes32 constant MEMBER_MODULE = keccak256("member");
    bytes32 constant PROPOSAL_MODULE = keccak256("proposal");
    bytes32 constant VOTING_MODULE = keccak256("voting");

    // Adapters， 加入，金融、管理，怒退适配器
    bytes32 constant ONBOARDING_MODULE = keccak256("onboarding");//加入
    bytes32 constant FINANCING_MODULE = keccak256("financing");
    bytes32 constant MANAGING_MODULE = keccak256("managing");
    bytes32 constant RAGEQUIT_MODULE = keccak256("ragequit");
    
}