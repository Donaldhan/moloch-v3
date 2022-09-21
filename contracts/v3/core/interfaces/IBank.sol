pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';
/**
 * 银行接口
 */
interface IBank {
    /**
     * 添加token到公会银行 
     */
    function addToGuild(Registry dao, address tokenAddress, uint256 amount) external;
    /**
     * 添加token到公会银行 
     */
    function addToEscrow(Registry dao, address tokenAddress, uint256 amount) external;
    /**
     * token余额
     */
    function balanceOf(Registry dao, address tokenAddress, address account) external returns (uint256);
    /**
     * 非预留地址
     */
    function isNotReservedAddress(address applicant) external returns (bool);
    /**
     * 从公会转移给定token给applicant
     */
    function transferFromGuild(Registry dao, address applicant, address tokenAddress, uint256 amount) external;
     /**
     * 怒退
     */
    function ragequit(Registry dao, address member, uint256 sharesToBurn) external;
}