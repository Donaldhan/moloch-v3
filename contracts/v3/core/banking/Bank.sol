pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import '../Registry.sol';
import '../Module.sol';
import '../interfaces/IBank.sol';
import '../interfaces/IMember.sol';
import '../../utils/SafeMath.sol';
import '../../utils/IERC20.sol';
import '../../guards/ModuleGuard.sol';
/**
 * 银行模块
 */
contract BankContract is IBank, Module, ModuleGuard {
    using SafeMath for uint256;
    //矫正token
    event TokensCollected(address indexed moloch, address indexed token, uint256 amountToCollect);
    //转移事件
    event Transfer(address indexed fromAddress, address indexed toAddress, address token, uint256 amount);

    address public constant GUILD = address(0xdead);//公会地址
    address public constant ESCROW = address(0xbeef);//托管地址
    address public constant TOTAL = address(0xbabe);//总池
    uint256 public constant MAX_TOKENS = 100;//最大token数
    /**
     * 银行状态
     */
    struct BankingState {
        address[] tokens;//token
        mapping(address => bool) availableTokens; //可用token
        mapping(address => mapping(address => uint256)) tokenBalances; //token余额
    }

    mapping(address => BankingState) states;  //dao银行
    /**
     * 添加token到公会银行 ，托管
     */
    function addToEscrow(Registry dao, address token, uint256 amount) override external onlyModule(dao) {
        //确保非公会银行账号
        require(token != GUILD && token != ESCROW && token != TOTAL, "invalid token");
        //托管token
        unsafeAddToBalance(address(dao), ESCROW, token, amount);
        //维护Token到DAO银行
        if (!states[address(dao)].availableTokens[token]) {
            require(states[address(dao)].tokens.length < MAX_TOKENS, "max limit reached");
            states[address(dao)].availableTokens[token] = true;
            states[address(dao)].tokens.push(token);
        }
    }
    /**
     * 添加token到公会银行 
     */
    function addToGuild(Registry dao, address token, uint256 amount) override external onlyModule(dao) {
         //确保非公会银行账号
        require(token != GUILD && token != ESCROW && token != TOTAL, "invalid token");
        //添加公会token
        unsafeAddToBalance(address(dao), GUILD, token, amount);
        //维护Token到DAO银行
        if (!states[address(dao)].availableTokens[token]) {
            require(states[address(dao)].tokens.length < MAX_TOKENS, "max limit reached");
            states[address(dao)].availableTokens[token] = true;
            states[address(dao)].tokens.push(token);
        }
    }
    /**
     * 从公会转移给定token给applicant
     */
    function transferFromGuild(Registry dao, address applicant, address token, uint256 amount) override external onlyModule(dao) {
         //确保非公会银行token余额足够
        require(states[address(dao)].tokenBalances[GUILD][token] >= amount, "insufficient balance");
        //减公会余额
        unsafeSubtractFromBalance(address(dao), GUILD, token, amount);
        //添加用户token数量
        unsafeAddToBalance(address(dao), applicant, token, amount);
        emit Transfer(GUILD, applicant, token, amount);
    }
     /**
     * 怒退
     */
    function ragequit(Registry dao, address memberAddr, uint256 sharesToBurn) override external onlyModule(dao) {
        //Get the total shares before burning member shares 获取成员信息
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        uint256 totalShares = memberContract.getTotalShares();
        //Burn shares if member has enough shares 销毁成员投票份额
        memberContract.burnShares(dao, memberAddr, sharesToBurn);
        //Update internal Guild and Member balances 取回用户分成
        for (uint256 i = 0; i < states[address(dao)].tokens.length; i++) {
            address token = states[address(dao)].tokens[i];
            uint256 amountToRagequit = fairShare(states[address(dao)].tokenBalances[GUILD][token], sharesToBurn, totalShares);
            if (amountToRagequit > 0) { // gas optimization to allow a higher maximum token limit
                // deliberately not using safemath here to keep overflows from preventing the function execution 
                // (which would break ragekicks) if a token overflows, 
                // it is because the supply was artificially inflated to oblivion, so we probably don't care about it anyways
                states[address(dao)].tokenBalances[GUILD][token] -= amountToRagequit;
                states[address(dao)].tokenBalances[memberAddr][token] += amountToRagequit;
                //TODO: do we want to emit an event for each token transfer?
                // emit Transfer(GUILD, applicant, token, amount);
            }
        }
    }
    /**
     * 非预留地址
     */
    function isNotReservedAddress(address applicant) override pure external returns (bool) {
        return applicant != address(0x0) && applicant != GUILD && applicant != ESCROW && applicant != TOTAL;
    }

    /**
     * Public read-only functions 
     */
    function balanceOf(Registry dao, address user, address token) override external view returns (uint256) {
        return states[address(dao)].tokenBalances[user][token];
    }
    
    /**
     * Internal bookkeeping， 增加用户账户余额，总池加
     */
    function unsafeAddToBalance(address dao, address user, address token, uint256 amount) internal {
        states[dao].tokenBalances[user][token] += amount;
        states[dao].tokenBalances[TOTAL][token] += amount;
    }
    /**
     * 从账户余额减，总池减
     */
    function unsafeSubtractFromBalance(address dao, address user, address token, uint256 amount) internal {
        states[dao].tokenBalances[user][token] -= amount;
        states[dao].tokenBalances[TOTAL][token] -= amount;
    }
    /**
     * 内部转账
     */
    function unsafeInternalTransfer(address dao, address from, address to, address token, uint256 amount) internal {
        unsafeSubtractFromBalance(dao, from, token, amount);
        unsafeAddToBalance(dao, to, token, amount);
    }

    /**
     * Internal utility 计算用户应得份额
     */
    function fairShare(uint256 balance, uint256 shares, uint256 _totalShares) internal pure returns (uint256) {
        require(_totalShares != 0, "total shares should not be 0");
        if (balance == 0) {
            return 0;
        }
        uint256 prod = balance * shares;
        if (prod / balance == shares) { // no overflow in multiplication above?
            return prod / _totalShares;
        }
        return (balance / _totalShares) * shares;
    }

}