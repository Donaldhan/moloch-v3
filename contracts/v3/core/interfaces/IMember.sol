pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';

interface IMember {
    /**
     * 是否为成员
     */
    function isActiveMember(Registry dao, address member) external returns (bool);    
     /**
     * 成员代理key
     */
    function memberAddress(Registry dao, address memberOrDelegateKey) external returns (address);
     /**
     * 更新成员投票份额
     */
    function updateMember(Registry dao, address applicant, uint256 shares) external;
     /**
     * 更新成员代理key
     */
    function updateDelegateKey(Registry dao, address member, address delegatedKey) external;
     /**
     * 销毁成员投票份额
     */
    function burnShares(Registry dao, address memberAddr, uint256 shares) external;
     /**
     * 获取用户投票份额
     */
    function nbShares(Registry dao, address member) external view returns (uint256);
     /**
     * 获取总份额
     */
    function getTotalShares() external view returns(uint256);
}