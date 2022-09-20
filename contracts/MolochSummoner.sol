pragma solidity ^0.7.0;
// SPDX-License-Identifier: MIT
import "./Moloch.sol";

contract MolochSummoner {

    Moloch private M;
    //DAO组织
    address[] public Molochs;

    event Summoned(address indexed M, address indexed _summoner);
    /**
     * 创建dao组织
     */
    function summonMoloch(
        address[] memory _summoner,//初始化成员
        address[] memory _approvedTokens,//允许的token
        uint256 _periodDuration,//提案间隔
        uint256 _votingPeriodLength,//投票间隔长度
        uint256 _gracePeriodLength,// 缓冲期（Grace Period），在此期间，对投票结果不满意的股东可以怒退
        uint256 _proposalDeposit, //提案押金， 赞助者赞成需要质押的金额
        uint256 _dilutionBound, //提案share与loot份额占公会总share与loot份额的比率, 超过比率，则无效；用于处理极端情况下的，投票份额稀释，投票最终结果无效；
        uint256 _processingReward, //处理提案奖励
        uint256[] memory _summonerShares) // 初始成员份额
        public {

        M = new Moloch(
            _summoner,
            _approvedTokens,
            _periodDuration,
            _votingPeriodLength,
            _gracePeriodLength,
            _proposalDeposit,
            _dilutionBound,
            _processingReward);

        Molochs.push(address(M));

        emit Summoned(address(M), _summoner);

    }

    function getMolochCount() public view returns (uint256 MolochCount) {
        return Molochs.length;
    }
}
