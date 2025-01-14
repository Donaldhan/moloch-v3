pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../core/Registry.sol';

/**
 * @dev Contract module that helps restrict the module access to Core Modules only.
 * 模块访问限制
 */
abstract contract ModuleGuard {

    /**
     * @dev Only Core Module of the DAO are allowed to execute the function call.
     * 只有模块可以访问
     */
    modifier onlyModule(Registry dao) {
        require(dao.isModule(msg.sender), "only core modules are allowed to call this function");
        _;
    }
}