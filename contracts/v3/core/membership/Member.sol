pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';
import '../Module.sol';
import '../interfaces/IMember.sol';
import '../interfaces/IBank.sol';
import '../../utils/SafeMath.sol';
import '../../helpers/FlagHelper.sol';
import '../../guards/ModuleGuard.sol';
import '../../guards/ReentrancyGuard.sol';

contract MemberContract is IMember, Module, ModuleGuard, ReentrancyGuard {
    using FlagHelper for uint256;
    using SafeMath for uint256;

    event UpdateMember(address dao, address member, uint256 shares);
    event UpdateDelegateKey(address dao, address indexed memberAddress, address newDelegateKey);

    struct Member {
        uint256 flags;//成员标志
        address delegateKey;//代理key
        uint256 nbShares;//投票份额
    }
    //总份额
    uint256 public totalShares = 1; // Maximum number of shares 2**256 - 1

    mapping(address => mapping(address => Member)) members;//dao-》memberAddress->Member
    mapping(address => mapping(address => address)) memberAddresses//dao-》memberAddress->Member
    mapping(address => mapping(address => address)) memberAddressesByDelegatedKey;//成员代理key
     /**
     * 是否为成员
     */
    function isActiveMember(Registry dao, address addr) override external view returns (bool) {
        //成员地址
        address memberAddr = memberAddressesByDelegatedKey[address(dao)][addr];
        uint256 memberFlags = members[address(dao)][memberAddr].flags;
        //成员存在，且没有被踢出，投票份额大于0
        return memberFlags.exists() && !memberFlags.isJailed() && members[address(dao)][memberAddr].nbShares > 0;
    }
    /**
     * 成员代理key
     */
    function memberAddress(Registry dao, address memberOrDelegateKey) override external view returns (address) {
        return memberAddresses[address(dao)][memberOrDelegateKey];
    }
    /**
     * 更新成员投票份额
     */
    function updateMember(Registry dao, address memberAddr, uint256 shares) override external onlyModule(dao) {
        Member storage member = members[address(dao)][memberAddr];
        if(member.delegateKey == address(0x0)) { //新成员
            member.flags = 1;
            member.delegateKey = memberAddr;
        }

        member.nbShares = shares;//投票份额
        
        totalShares = totalShares.add(shares);//总份额
        //更新代理key地址
        memberAddressesByDelegatedKey[address(dao)][member.delegateKey] = memberAddr;

        emit UpdateMember(address(dao), memberAddr, shares);
    }
      /**
     * 更新成员代理key
     */
    function updateDelegateKey(Registry dao, address memberAddr, address newDelegateKey) override external onlyModule(dao) {
        require(newDelegateKey != address(0), "newDelegateKey cannot be 0");

        // skip checks if member is setting the delegate key to their member address
        if (newDelegateKey != memberAddr) {
            //确保不会重写当前成员
            require(memberAddresses[address(dao)][newDelegateKey] == address(0x0), "cannot overwrite existing members");
            //确保不会重新代理key
            require(memberAddresses[address(dao)][memberAddressesByDelegatedKey[address(dao)][newDelegateKey]] == address(0x0), "cannot overwrite existing delegate keys");
        }

        Member storage member = members[address(dao)][memberAddr];
        //确保成员存在
        require(member.flags.exists(), "member does not exist");
        memberAddressesByDelegatedKey[address(dao)][member.delegateKey] = address(0x0);//清除老的代理key
        memberAddressesByDelegatedKey[address(dao)][newDelegateKey] = memberAddr;
        member.delegateKey = newDelegateKey;

        emit UpdateDelegateKey(address(dao), memberAddr, newDelegateKey);
    }
    /**
     * 销毁成员投票份额
     */
    function burnShares(Registry dao, address memberAddr, uint256 sharesToBurn) override external onlyModule(dao) {
        //确保足够销毁
        require(_enoughSharesToBurn(dao, memberAddr, sharesToBurn), "insufficient shares");
        
        Member storage member = members[address(dao)][memberAddr];
        member.nbShares = member.nbShares.sub(sharesToBurn);
        totalShares = totalShares.sub(sharesToBurn);

        emit UpdateMember(address(dao), memberAddr, member.nbShares);
    }

    /**
     * Public read-only functions  成员份额
     */
    function nbShares(Registry dao, address member) override external view returns (uint256) {
        return members[address(dao)][member].nbShares;
    }

    function getTotalShares() override external view returns(uint256) {
        return totalShares;
    }

    /**
     * Internal Utility Functions
     */
    /**
     * 确保足够销毁
     */

    function _enoughSharesToBurn(Registry dao, address memberAddr, uint256 sharesToBurn) internal view returns (bool) {
        return sharesToBurn > 0 && members[address(dao)][memberAddr].nbShares >= sharesToBurn;
    }

}