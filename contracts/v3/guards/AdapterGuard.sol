pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../core/Registry.sol';
import '../core/interfaces/IMember.sol';
import '../core/Module.sol';

/**
 * @dev Contract module that helps restrict the adapter access to DAO Members only.
 * DAO成员adapter限制
 */
abstract contract AdapterGuard is Module {

    /**
     * @dev Only members of the Guild are allowed to execute the function call.
     * 只有活跃成员可以访问
     */
    modifier onlyMember(Registry dao) {
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        require(memberContract.isActiveMember(dao, msg.sender), "only DAO members are allowed to call this function");
        _;
    }
}
