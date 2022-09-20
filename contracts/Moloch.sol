pragma solidity ^0.7.0;

import "./v3/utils/SafeMath.sol";
import "./v3/utils/IERC20.sol";
import "./v3/guards/ReentrancyGuard.sol";

// SPDX-License-Identifier: MIT

contract Moloch is ReentrancyGuard {
    using SafeMath for uint256;

    /***************
    GLOBAL CONSTANTS
    ***************/
    uint256 public periodDuration; // default = 17280 = 4.8 hours in seconds (5 periods per day) 默认间隔长度，每天5个间隔
    uint256 public votingPeriodLength; // default = 35 periods (7 days) 默认投票间隔长度
    uint256 public gracePeriodLength; // default = 35 periods (7 days) 默认缓冲间隔长度
    uint256 public proposalDeposit; // default = 10 ETH (~$1,000 worth of ETH at contract deployment)提案质押token
    uint256 public dilutionBound; // default = 3 - maximum multiplier a YES voter will be obligated to pay in case of mass ragequit 怒退时，赞成投票者的稀释率
    uint256 public processingReward; // default = 0.1 - amount of ETH to give to whoever processes a proposal 处理提案的奖励
    uint256 public summoningTime; // needed to determine the current period，召唤时间，决定当前间隔是需要； DAO启动的时间

    address public depositToken; // deposit token contract reference; default = wETH 质押token合约地址

    // HARD-CODED LIMITS
    // These numbers are quite arbitrary; they are small enough to avoid overflows when doing calculations
    // with periods or shares, yet big enough to not limit reasonable use cases.
    uint256 constant MAX_VOTING_PERIOD_LENGTH = 10**18; // maximum length of voting period 最大投票间隔长度
    uint256 constant MAX_GRACE_PERIOD_LENGTH = 10**18; // maximum length of grace period 最大缓冲间隔长度
    uint256 constant MAX_DILUTION_BOUND = 10**18; // maximum dilution bound
    uint256 constant MAX_NUMBER_OF_SHARES_AND_LOOT = 10**18; // maximum number of shares that can be minted 最大mint份额
    uint256 constant MAX_TOKEN_WHITELIST_COUNT = 400; // maximum number of whitelisted tokens 最大白名单token数量
    uint256 constant MAX_TOKEN_GUILDBANK_COUNT = 200; // maximum number of tokens with non-zero balance in guildbank 公会银行最大非零token数量

    // ***************
    // EVENTS
    // ***************
    event SummonComplete(address indexed summoner, address[] tokens, uint256 summoningTime, uint256 periodDuration, uint256 votingPeriodLength, uint256 gracePeriodLength, uint256 proposalDeposit, uint256 dilutionBound, uint256 processingReward);
    event SubmitProposal(address indexed applicant, uint256 sharesRequested, uint256 lootRequested, uint256 tributeOffered, address tributeToken, uint256 paymentRequested, address paymentToken, string details, bool[6] flags, uint256 proposalId, address indexed delegateKey, address indexed memberAddress);
    event SponsorProposal(address indexed delegateKey, address indexed memberAddress, uint256 proposalId, uint256 proposalIndex, uint256 startingPeriod);
    //提交投票
    event SubmitVote(uint256 proposalId, uint256 indexed proposalIndex, address indexed delegateKey, address indexed memberAddress, uint8 uintVote);
    //处理提案
    event ProcessProposal(uint256 indexed proposalIndex, uint256 indexed proposalId, bool didPass);
    //处理白名单提案
    event ProcessWhitelistProposal(uint256 indexed proposalIndex, uint256 indexed proposalId, bool didPass);
    //处理公会踢出提案事件
    event ProcessGuildKickProposal(uint256 indexed proposalIndex, uint256 indexed proposalId, bool didPass);
    //怒退事件
    event Ragequit(address indexed memberAddress, uint256 sharesToBurn, uint256 lootToBurn);
    // 矫正公会token余额
    event TokensCollected(address indexed token, uint256 amountToCollect);
    //取消提案
    event CancelProposal(uint256 indexed proposalId, address applicantAddress);
    //更新成员dialing
    event UpdateDelegateKey(address indexed memberAddress, address newDelegateKey);
    //提现事件
    event Withdraw(address indexed memberAddress, address token, uint256 amount);

    // *******************
    // INTERNAL ACCOUNTING
    // *******************
    uint256 public proposalCount = 0; // total proposals submitted 提交的提案数量
    uint256 public totalShares = 0; // total shares across all members 所有成员的总份额
    uint256 public totalLoot = 0; // total loot across all members 所有成员loot数量

    uint256 public totalGuildBankTokens = 0; // total tokens with non-zero balance in guild bank 公会非零token数量

    address public constant GUILD = address(0xdead);//公会银行
    address public constant ESCROW = address(0xbeef);//第三方托管, 托管提议奖励的token
    address public constant TOTAL = address(0xbabe);//总token池
     //账户的token余额
    mapping (address => mapping(address => uint256)) public userTokenBalances; // userTokenBalances[userAddress][tokenAddress]

    enum Vote {
        Null, // default value, counted as abstention，弃权
        Yes, // 赞成
        No//反对
    }

    struct Member {
        address delegateKey; // the key responsible for submitting proposals and voting - defaults to member address unless updated 代理
        uint256 shares; // the # of voting shares assigned to this member 投票份额
        uint256 loot; // the loot amount available to this member (combined with shares on ragequit) 股份份额
        bool exists; // always true once a member has been created 是否存在
        uint256 highestIndexYesVote; // highest proposal index # on which the member voted YES 成员投yes的最大提案数
        uint256 jailed; // set to proposalIndex of a passing guild kick proposal for this member, prevents voting on and sponsoring proposals 当前成员被踢出的提案，阻止投票和发起提案
    }

    struct Proposal {
        //希望成为成员的applicant
        address applicant; // the applicant who wishes to become a member - this key will be used for withdrawals (doubles as guild kick target for gkick proposals)
        address proposer; // the account that submitted the proposal (can be non-member) 提交提案的人，可以为非成员
        address sponsor; // the member that sponsored the proposal (moving it into the queue) 赞助提案的成员
        uint256 sharesRequested; // the # of shares the applicant is requesting  请求投票份额
        uint256 lootRequested; // the amount of loot the applicant is requesting 请求的股份份额
        uint256 tributeOffered; // amount of tokens offered as tribute 奖励的token数量
        address tributeToken; // tribute token contract reference  感谢token地址， 提案发起者贡献给公会的
        uint256 paymentRequested; // amount of tokens requested as payment 提案通过，请求公会需要支付的token数量
        address paymentToken; // payment token contract reference 支付token地址
        uint256 startingPeriod; // the period in which voting can start for this proposal 开始投票间隔
        uint256 yesVotes; // the total number of YES votes for this proposal 赞成票
        uint256 noVotes; // the total number of NO votes for this proposal 反对票
        // 提案各节点状态标志
        // [sponsored(提案是否已赞助), processed（提案是否处理）, didPass（提案是否通过）, cancelled（提案是否取消）, whitelist（token白名单提案）, guildkick（是否为公会踢出成员提案）]
        bool[6] flags; // [sponsored, processed, didPass, cancelled, whitelist, guildkick] 
        string details; // proposal details - could be IPFS hash, plaintext, or JSON 体检详情，可以为ipfs hash
        uint256 maxTotalSharesAndLootAtYesVote; // the maximum # of total shares encountered at a yes vote on this proposal 赞成的投票和股份份额最大份额
        mapping(address => Vote) votesByMember; // the votes on this proposal by each member 成员投票信息
    }

    mapping(address => bool) public tokenWhitelist; //白名单token
    address[] public approvedTokens;//授权token

    mapping(address => bool) public proposedToWhitelist;// 提案白名单
    mapping(address => bool) public proposedToKick;//被踢出的成员

    mapping(address => Member) public members;//成员
    mapping(address => address) public memberAddressByDelegateKey;//成员代理key

    mapping(uint256 => Proposal) public proposals;//提案

    uint256[] public proposalQueue;//提案队列

   //成员限制
    modifier onlyMember {
        require(members[msg.sender].shares > 0 || members[msg.sender].loot > 0, "not a member");
        _;
    }
    //投票份额限制
    modifier onlyShareholder {
        require(members[msg.sender].shares > 0, "not a shareholder");
        _;
    }
    //代理限制
    modifier onlyDelegate {
        require(members[memberAddressByDelegateKey[msg.sender]].shares > 0, "not a delegate");
        _;
    }

    constructor(
        address _summoner,
        address[] memory _approvedTokens,
        uint256 _periodDuration,//提案间隔
        uint256 _votingPeriodLength,//投票间隔长度
        uint256 _gracePeriodLength,// 缓冲期（Grace Period），在此期间，对投票结果不满意的股东可以怒退
        uint256 _proposalDeposit, //提案押金， 赞助者赞成需要质押的金额
        uint256 _dilutionBound, //提案share与loot份额占公会总share与loot份额的比率, 超过比率，则无效；用于处理极端情况下的，投票份额稀释，投票最终结果无效；
        uint256 _processingReward//处理提案奖励
    ) {
        //参数检查
        require(_summoner != address(0), "summoner cannot be 0");
        require(_periodDuration > 0, "_periodDuration cannot be 0");
        require(_votingPeriodLength > 0, "_votingPeriodLength cannot be 0");
        require(_votingPeriodLength <= MAX_VOTING_PERIOD_LENGTH, "_votingPeriodLength exceeds limit");
        require(_gracePeriodLength <= MAX_GRACE_PERIOD_LENGTH, "_gracePeriodLength exceeds limit");
        require(_dilutionBound > 0, "_dilutionBound cannot be 0");
        require(_dilutionBound <= MAX_DILUTION_BOUND, "_dilutionBound exceeds limit");
        require(_approvedTokens.length > 0, "need at least one approved token");
        require(_approvedTokens.length <= MAX_TOKEN_WHITELIST_COUNT, "too many tokens");
        require(_proposalDeposit >= _processingReward, "_proposalDeposit cannot be smaller than _processingReward");
        
        depositToken = _approvedTokens[0]; //质押token
        // NOTE: move event up here, avoid stack too deep if too many approved tokens
        // 移到这里避免stack太深
        emit SummonComplete(_summoner, _approvedTokens, block.timestamp, _periodDuration, _votingPeriodLength, _gracePeriodLength, _proposalDeposit, _dilutionBound, _processingReward);

        //添加白名单及允许的token
        for (uint256 i = 0; i < _approvedTokens.length; i++) {
            require(_approvedTokens[i] != address(0), "_approvedToken cannot be 0");
            require(!tokenWhitelist[_approvedTokens[i]], "duplicate approved token");
            tokenWhitelist[_approvedTokens[i]] = true;
            approvedTokens.push(_approvedTokens[i]);
        } 
        //间隔，投票间隔、缓冲间隔长度
        periodDuration = _periodDuration;
        votingPeriodLength = _votingPeriodLength;
        gracePeriodLength = _gracePeriodLength;
        //提案质押数量
        proposalDeposit = _proposalDeposit;
        dilutionBound = _dilutionBound;
        //处理提案奖励
        processingReward = _processingReward;
        //召唤DAO时间
        summoningTime = block.timestamp;
        //初始化成员  
        members[_summoner] = Member(_summoner, 1, 0, true, 0, 0);
        memberAddressByDelegateKey[_summoner] = _summoner;
        totalShares = 1;
       
    }

    /*****************
    PROPOSAL FUNCTIONS
    *****************/
    /**
     * 提交提案
     */
    function submitProposal(
        address applicant,
        uint256 sharesRequested,//提案成功时的请求增加投票份额
        uint256 lootRequested,
        uint256 tributeOffered,//提案者贡献给公会的token
        address tributeToken,
        uint256 paymentRequested,//提案成功，公会者支付给提案的token
        address paymentToken,
        string memory details
    ) public nonReentrant returns (uint256 proposalId) {
        //检查投票份额
        require(sharesRequested.add(lootRequested) <= MAX_NUMBER_OF_SHARES_AND_LOOT, "too many shares requested");
        //检查奖励和支付token白名单
        require(tokenWhitelist[tributeToken], "tributeToken is not whitelisted");
        require(tokenWhitelist[paymentToken], "payment is not whitelisted");
        require(applicant != address(0), "applicant cannot be 0");
        //非公会，托管，总池账号
        require(applicant != GUILD && applicant != ESCROW && applicant != TOTAL, "applicant address cannot be reserved");
        //applicant不能被踢出
        require(members[applicant].jailed == 0, "proposal applicant must not be jailed");
        //检查用户在公会的奖励数量 
        if (tributeOffered > 0 && userTokenBalances[GUILD][tributeToken] == 0) {
            require(totalGuildBankTokens < MAX_TOKEN_GUILDBANK_COUNT, 'cannot submit more tribute proposals for new tokens - guildbank is full');
        }

        // collect tribute from proposer and store it in the Moloch until the proposal is processed
        require(IERC20(tributeToken).transferFrom(msg.sender, address(this), tributeOffered), "tribute token transfer failed");
        unsafeAddToBalance(ESCROW, tributeToken, tributeOffered);

        bool[6] memory flags; // [sponsored, processed, didPass, cancelled, whitelist, guildkick]

        _submitProposal(applicant, sharesRequested, lootRequested, tributeOffered, tributeToken, paymentRequested, paymentToken, details, flags);
        return proposalCount - 1; // return proposalId - contracts calling submit might want it
    }
    /**
     * 提交白名单提案
     */
    function submitWhitelistProposal(address tokenToWhitelist, string memory details) public nonReentrant returns (uint256 proposalId) {
        //白名单token限制检查
        require(tokenToWhitelist != address(0), "must provide token address");
        require(!tokenWhitelist[tokenToWhitelist], "cannot already have whitelisted the token");
        require(approvedTokens.length < MAX_TOKEN_WHITELIST_COUNT, "cannot submit more whitelist proposals");

        bool[6] memory flags; // [sponsored, processed, didPass, cancelled, whitelist, guildkick]
        flags[4] = true; // whitelist

        _submitProposal(address(0), 0, 0, 0, tokenToWhitelist, 0, address(0), details, flags);
        return proposalCount - 1;
    }
    /**
     * 发起踢出成员提案
     */
    function submitGuildKickProposal(address memberToKick, string memory details) public nonReentrant returns (uint256 proposalId) {
        Member memory member = members[memberToKick];

        require(member.shares > 0 || member.loot > 0, "member must have at least one share or one loot");
        require(members[memberToKick].jailed == 0, "member must not already be jailed");

        bool[6] memory flags; // [sponsored, processed, didPass, cancelled, whitelist, guildkick]
        flags[5] = true; // guild kick

        _submitProposal(memberToKick, 0, 0, 0, address(0), 0, address(0), details, flags);
        return proposalCount - 1;
    }
    /**
     * 提交提案
     */
    function _submitProposal(
        address applicant,
        uint256 sharesRequested,//提案成功时的请求增加投票份额
        uint256 lootRequested,//提案成功时的请求增加股份份额
        uint256 tributeOffered, //提案者贡献给公会的token
        address tributeToken, //提案者贡献给公会的token地址
        uint256 paymentRequested, //提案成功，公会者支付给提案的token
        address paymentToken,//提案成功需要支付的token地址
        string memory details,
        bool[6] memory flags
    ) internal {
        Proposal storage proposal = proposals[proposalCount];

        proposal.applicant = applicant;
        proposal.proposer = msg.sender;
        proposal.sponsor = address(0);
        proposal.sharesRequested = sharesRequested;
        proposal.lootRequested = lootRequested;
        proposal.tributeOffered = tributeOffered;
        proposal.tributeToken = tributeToken;
        proposal.paymentRequested = paymentRequested;
        proposal.paymentToken = paymentToken;
        proposal.startingPeriod = 0;
        proposal.yesVotes = 0;
        proposal.noVotes = 0;
        proposal.flags = flags;
        proposal.details = details;
        proposal.maxTotalSharesAndLootAtYesVote = 0;

        address memberAddress = memberAddressByDelegateKey[msg.sender];
        // NOTE: argument order matters, avoid stack too deep
        emit SubmitProposal(applicant, sharesRequested, lootRequested, tributeOffered, tributeToken, paymentRequested, paymentToken, details, flags, proposalCount, msg.sender, memberAddress);
        proposalCount += 1;
    }
    /**
     * 赞助提案
     */
    function sponsorProposal(uint256 proposalId) public nonReentrant onlyDelegate {
        // collect proposal deposit from sponsor and store it in the Moloch until the proposal is processed
        //质押token
        require(IERC20(depositToken).transferFrom(msg.sender, address(this), proposalDeposit), "proposal deposit token transfer failed");
        //更新托管账户余额
        unsafeAddToBalance(ESCROW, depositToken, proposalDeposit);

        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), 'proposal must have been proposed');
        require(!proposal.flags[0], "proposal has already been sponsored"); //提案没有被赞助
        require(!proposal.flags[3], "proposal has been cancelled");//提案没有被取消
        require(members[proposal.applicant].jailed == 0, "proposal applicant must not be jailed");//提案发起者没有被踢出

        if (proposal.tributeOffered > 0 && userTokenBalances[GUILD][proposal.tributeToken] == 0) {
            //奖励token地址，当前公会银行没有，需要添加，检查
            require(totalGuildBankTokens < MAX_TOKEN_GUILDBANK_COUNT, 'cannot sponsor more tribute proposals for new tokens - guildbank is full');
        }

        // whitelist proposal 白名单提案
        if (proposal.flags[4]) {
            require(!tokenWhitelist[address(proposal.tributeToken)], "cannot already have whitelisted the token");
            require(!proposedToWhitelist[address(proposal.tributeToken)], 'already proposed to whitelist');
            require(approvedTokens.length < MAX_TOKEN_WHITELIST_COUNT, "cannot sponsor more whitelist proposals");
            //更新提案白名单token状态为true
            proposedToWhitelist[address(proposal.tributeToken)] = true;

        // guild kick proposal 踢出成员提案
        } else if (proposal.flags[5]) {
            require(!proposedToKick[proposal.applicant], 'already proposed to kick');
            //更新提案踢出者状态为true
            proposedToKick[proposal.applicant] = true;
        }

        // compute startingPeriod for proposal 开始间隔
        uint256 startingPeriod = max(
            getCurrentPeriod(),
            proposalQueue.length == 0 ? 0 : proposals[proposalQueue[proposalQueue.length.sub(1)]].startingPeriod
        ).add(1);
        //更新提案开始间隔，赞助成员，赞助状态
        proposal.startingPeriod = startingPeriod;

        address memberAddress = memberAddressByDelegateKey[msg.sender];
        proposal.sponsor = memberAddress;

        proposal.flags[0] = true; // sponsored

        // append proposal to the queue 添加提案到队列
        proposalQueue.push(proposalId);
        //赞助提案
        emit SponsorProposal(msg.sender, memberAddress, proposalId, proposalQueue.length.sub(1), startingPeriod);
    }
     
    // NOTE: In MolochV2 proposalIndex !== proposalId
    /**
     * 提交投票
     */
    function submitVote(uint256 proposalIndex, uint8 uintVote) public nonReentrant onlyDelegate {
        address memberAddress = memberAddressByDelegateKey[msg.sender];
        Member storage member = members[memberAddress];

        require(proposalIndex < proposalQueue.length, "proposal does not exist"); //检查提案索引
        Proposal storage proposal = proposals[proposalQueue[proposalIndex]];

        require(uintVote < 3, "must be less than 3"); //投票行为VOTE，0,1,2
        Vote vote = Vote(uintVote);
        //需要处于投票器
        require(getCurrentPeriod() >= proposal.startingPeriod, "voting period has not started");
        //确保没有过期
        require(!hasVotingPeriodExpired(proposal.startingPeriod), "proposal voting period has expired");
        //确保投票
        require(proposal.votesByMember[memberAddress] == Vote.Null, "member has already voted");
        //确保投票为赞助或者反对
        require(vote == Vote.Yes || vote == Vote.No, "vote must be either Yes or No");
        //更新成员投票信息
        proposal.votesByMember[memberAddress] = vote;

        if (vote == Vote.Yes) {//赞成
            //更新赞成票数
            proposal.yesVotes = proposal.yesVotes.add(member.shares);

            // set highest index (latest) yes vote - must be processed for member to ragequit
            //更新成员赞成提案索引，用户怒退的处理
            if (proposalIndex > member.highestIndexYesVote) {
                member.highestIndexYesVote = proposalIndex;
            }

            // set maximum of total shares encountered at a yes vote - used to bound dilution for yes voters
            //提案时的投票份额与股份份额
            if (totalShares.add(totalLoot) > proposal.maxTotalSharesAndLootAtYesVote) {
                proposal.maxTotalSharesAndLootAtYesVote = totalShares.add(totalLoot);
            }

        } else if (vote == Vote.No) {//反对
            proposal.noVotes = proposal.noVotes.add(member.shares);
        }
     
        // NOTE: subgraph indexes by proposalId not proposalIndex since proposalIndex isn't set untill it's been sponsored but proposal is created on submission
        //投票成功
        emit SubmitVote(proposalQueue[proposalIndex], proposalIndex, msg.sender, memberAddress, uintVote);
    }
    /**
     * 处理提案
     */
    function processProposal(uint256 proposalIndex) public nonReentrant {
        //检查提案，确保可以处理
        _validateProposalForProcessing(proposalIndex);

        uint256 proposalId = proposalQueue[proposalIndex];
        Proposal storage proposal = proposals[proposalId];
        //必须为标准提案，非白名单和踢出成员提案
        require(!proposal.flags[4] && !proposal.flags[5], "must be a standard proposal");
        //更新处理标志
        proposal.flags[1] = true; // processed
        //投票结果   
        bool didPass = _didPass(proposalIndex);

        // Make the proposal fail if the new total number of shares and loot exceeds the limit
        //当前总投票和股份份额+投赞成票的总投票和股份份额，大于最大份额限制，则为false；
        if (totalShares.add(totalLoot).add(proposal.sharesRequested).add(proposal.lootRequested) > MAX_NUMBER_OF_SHARES_AND_LOOT) {
            didPass = false;
        }

        // Make the proposal fail if it is requesting more tokens as payment than the available guild bank balance
        // 请求支付的token数量，大于公会账户余额，则为false
        if (proposal.paymentRequested > userTokenBalances[GUILD][proposal.paymentToken]) {
            didPass = false;
        }

        // Make the proposal fail if it would result in too many tokens with non-zero balance in guild bank
        // 奖励token无法加入白名单，白名单token超限
        if (proposal.tributeOffered > 0 && userTokenBalances[GUILD][proposal.tributeToken] == 0 && totalGuildBankTokens >= MAX_TOKEN_GUILDBANK_COUNT) {
           didPass = false;
        }

        // PROPOSAL PASSED
        if (didPass) {// 通过
            proposal.flags[2] = true; // didPass

            // if the applicant is already a member, add to their existing shares & loot
            if (members[proposal.applicant].exists) {//applicant已存在，增加投票份额和股份份额
                members[proposal.applicant].shares = members[proposal.applicant].shares.add(proposal.sharesRequested);
                members[proposal.applicant].loot = members[proposal.applicant].loot.add(proposal.lootRequested);

            // the applicant is a new member, create a new record for them
            //创建新成员
            } else {
                // if the applicant address is already taken by a member's delegateKey, reset it to their member address
                //applicant为当前成员的代理key，重置他的成员地址
                if (members[memberAddressByDelegateKey[proposal.applicant]].exists) {
                    address memberToOverride = memberAddressByDelegateKey[proposal.applicant];
                    memberAddressByDelegateKey[memberToOverride] = memberToOverride;
                    members[memberToOverride].delegateKey = memberToOverride;
                }

                // use applicant address as delegateKey by default， 新成员，代理key为其自己
                members[proposal.applicant] = Member(proposal.applicant, proposal.sharesRequested, proposal.lootRequested, true, 0, 0);
                memberAddressByDelegateKey[proposal.applicant] = proposal.applicant;
            }

            // mint new shares & loot 挖取总投票份额和股份份额
            totalShares = totalShares.add(proposal.sharesRequested);
            totalLoot = totalLoot.add(proposal.lootRequested);

            // if the proposal tribute is the first tokens of its kind to make it into the guild bank, increment total guild bank tokens
            //更新公会token数量
            if (userTokenBalances[GUILD][proposal.tributeToken] == 0 && proposal.tributeOffered > 0) {
                totalGuildBankTokens += 1;
            }
            //从托管划转奖励token到公会
            unsafeInternalTransfer(ESCROW, GUILD, proposal.tributeToken, proposal.tributeOffered);
            //从公会划转支付token给提案者
            unsafeInternalTransfer(GUILD, proposal.applicant, proposal.paymentToken, proposal.paymentRequested);

            // if the proposal spends 100% of guild bank balance for a token, decrement total guild bank tokens
            // 支付token余额为0，剔除
            if (userTokenBalances[GUILD][proposal.paymentToken] == 0 && proposal.paymentRequested > 0) {
                totalGuildBankTokens -= 1;
            }

        // PROPOSAL FAILED
        } else { //提案不通过
            // return all tokens to the proposer (not the applicant, because funds come from proposer)
            //从返回托管贡献token数给提案者
            unsafeInternalTransfer(ESCROW, proposal.proposer, proposal.tributeToken, proposal.tributeOffered);
        }
       //奖励质押token给提案处理者，将剩余质押token返回给赞助者
        _returnDeposit(proposal.sponsor);

        emit ProcessProposal(proposalIndex, proposalId, didPass);
    }
    /**
     * 处理白名单提案
     */
    function processWhitelistProposal(uint256 proposalIndex) public nonReentrant {
        //检查提案，确保可以处理
        _validateProposalForProcessing(proposalIndex);

        uint256 proposalId = proposalQueue[proposalIndex];
        Proposal storage proposal = proposals[proposalId];

        require(proposal.flags[4], "must be a whitelist proposal");

        proposal.flags[1] = true; // processed
        //投票结果   
        bool didPass = _didPass(proposalIndex);

        if (approvedTokens.length >= MAX_TOKEN_WHITELIST_COUNT) {//超过白名单token直接失败
            didPass = false;
        }

        if (didPass) {
            //通过则添加奖励token到白名单和授权token 
            proposal.flags[2] = true; // didPass

            tokenWhitelist[address(proposal.tributeToken)] = true;
            approvedTokens.push(proposal.tributeToken);
        }
        //从提案白名单列表剔除
        proposedToWhitelist[address(proposal.tributeToken)] = false;
        //奖励质押token给提案处理者，将剩余质押token返回给赞助者
        _returnDeposit(proposal.sponsor);

        emit ProcessWhitelistProposal(proposalIndex, proposalId, didPass);
    }
    /**
     * 处理踢出提案；成功则用户的投票份额shares转化为股份份额loot
     */
    function processGuildKickProposal(uint256 proposalIndex) public nonReentrant {
        //检查提案，确保可以处理
        _validateProposalForProcessing(proposalIndex);

        uint256 proposalId = proposalQueue[proposalIndex];
        Proposal storage proposal = proposals[proposalId];

        require(proposal.flags[5], "must be a guild kick proposal");

        proposal.flags[1] = true; // processed
        //投票结果   
        bool didPass = _didPass(proposalIndex);

        if (didPass) {
            proposal.flags[2] = true; // didPass
            Member storage member = members[proposal.applicant];
            //更新成员剔除提案索引
            member.jailed = proposalIndex;

            // transfer shares to loot
            // 更新用户股份份额
            member.loot = member.loot.add(member.shares);
            //更新投票份额
            totalShares = totalShares.sub(member.shares);
            //更新股份份额
            totalLoot = totalLoot.add(member.shares);
            //收回投票
            member.shares = 0; // revoke all shares
        }
        //从剔除成员提案列表移除
        proposedToKick[proposal.applicant] = false;
         //奖励质押token给提案处理者，将剩余质押token返回给赞助者
        _returnDeposit(proposal.sponsor);

        emit ProcessGuildKickProposal(proposalIndex, proposalId, didPass);
    }
    /**
     * 提案是否通过
     */
    function _didPass(uint256 proposalIndex) internal view returns (bool didPass) {
        Proposal storage proposal = proposals[proposalQueue[proposalIndex]];
        //赞成份额大于反对票数
        didPass = proposal.yesVotes > proposal.noVotes;

        // Make the proposal fail if the dilutionBound is exceeded
        // 如果在处理提案时，投票和股份份额*dilutionBound 小于提案赞成的投票和股份份额总额，则投票失败，防止怒退的情况
        // 即投赞成票的要占，总投票份额和股份份额的1/3
        if ((totalShares.add(totalLoot)).mul(dilutionBound) < proposal.maxTotalSharesAndLootAtYesVote) {
            didPass = false;
        }

        // Make the proposal fail if the applicant is jailed
        // - for standard proposals, we don't want the applicant to get any shares/loot/payment
        // - for guild kick proposals, we should never be able to propose to kick a jailed member (or have two kick proposals active), so it doesn't matter
        // 确保提案者没有被踢出
        if (members[proposal.applicant].jailed != 0) {
            didPass = false;
        }

        return didPass;
    }
    /**
     * 校验提案
     */ 
    function _validateProposalForProcessing(uint256 proposalIndex) internal view {
        //提案有效
        require(proposalIndex < proposalQueue.length, "proposal does not exist");
        Proposal storage proposal = proposals[proposalQueue[proposalIndex]];
        //提案投票结束  
        require(getCurrentPeriod() >= proposal.startingPeriod.add(votingPeriodLength).add(gracePeriodLength), "proposal is not ready to be processed");
        //提案没有被处理
        require(proposal.flags[1] == false, "proposal has already been processed");
        //前驱提案必须先处理
        require(proposalIndex == 0 || proposals[proposalQueue[proposalIndex.sub(1)]].flags[1], "previous proposal must be processed");
    }
    /**
     * 奖励质押token给提案处理者，将剩余质押token返回给赞助者
     */
    function _returnDeposit(address sponsor) internal {
        //奖励质押token给提案处理者
        unsafeInternalTransfer(ESCROW, msg.sender, depositToken, processingReward);
        //将剩余质押token返回给赞助者
        unsafeInternalTransfer(ESCROW, sponsor, depositToken, proposalDeposit.sub(processingReward));
    }
    /**
     * 怒退
     */
    function ragequit(uint256 sharesToBurn, uint256 lootToBurn) public nonReentrant onlyMember {
        _ragequit(msg.sender, sharesToBurn, lootToBurn);
    }
    /**
     * 处理怒退 
     */
    function _ragequit(address memberAddress, uint256 sharesToBurn, uint256 lootToBurn) internal {
        //怒退时的总份额
        uint256 initialTotalSharesAndLoot = totalShares.add(totalLoot);

        Member storage member = members[memberAddress];
        //检查怒退投票份额和股份份额
        require(member.shares >= sharesToBurn, "insufficient shares");
        require(member.loot >= lootToBurn, "insufficient loot");

        require(canRagequit(member.highestIndexYesVote), "cannot ragequit until highest index proposal member voted YES on is processed");
        //怒退的总投票份额和股份份额
        uint256 sharesAndLootToBurn = sharesToBurn.add(lootToBurn);

        // burn shares and loot
        //更新用户的投票份额和股份份额
        member.shares = member.shares.sub(sharesToBurn);
        member.loot = member.loot.sub(lootToBurn);
        //更新公会的投票份额和股份份额
        totalShares = totalShares.sub(sharesToBurn);
        totalLoot = totalLoot.sub(lootToBurn);
        //从公会划出怒退时，成员可获得的公会token份额
        for (uint256 i = 0; i < approvedTokens.length; i++) {
            //获取怒退token的占比数量
            uint256 amountToRagequit = fairShare(userTokenBalances[GUILD][approvedTokens[i]], sharesAndLootToBurn, initialTotalSharesAndLoot);
            if (amountToRagequit > 0) { // gas optimization to allow a higher maximum token limit
                // deliberately not using safemath here to keep overflows from preventing the function execution (which would break ragekicks)
                // if a token overflows, it is because the supply was artificially inflated to oblivion, so we probably don't care about it anyways
                //从公会划出怒退时，成员可获得的公会token份额
                userTokenBalances[GUILD][approvedTokens[i]] -= amountToRagequit;
                userTokenBalances[memberAddress][approvedTokens[i]] += amountToRagequit;
            }
        }

        emit Ragequit(msg.sender, sharesToBurn, lootToBurn);
    }
    /**
     * 怒踢，怒踢的成员投票份额，不作为股份份额，进行公会token分成；
     */ 
    function ragekick(address memberToKick) public nonReentrant {
        Member storage member = members[memberToKick];
        //确保成员没有被踢出，同时存在股份份额 
        require(member.jailed != 0, "member must be in jail");
        require(member.loot > 0, "member must have some loot"); // note - should be impossible for jailed member to have shares
        //确保成员给定投票赞成的提案是否已处理
        require(canRagequit(member.highestIndexYesVote), "cannot ragequit until highest index proposal member voted YES on is processed");
        //怒踢的成员投票份额，不作为股份份额，进行公会token分成；
        _ragequit(memberToKick, 0, member.loot);
    }
    /**
     * 体现
     */
    function withdrawBalance(address token, uint256 amount) public nonReentrant {
        _withdrawBalance(token, amount);
    }
    /**
    * 批量体现模式
     */
    function withdrawBalances(address[] memory tokens, uint256[] memory amounts, bool max) public nonReentrant {
        require(tokens.length == amounts.length, "tokens and amounts arrays must be matching lengths");

        for (uint256 i=0; i < tokens.length; i++) {
            uint256 withdrawAmount = amounts[i];
            if (max) { // withdraw the maximum balance，全额体现
                withdrawAmount = userTokenBalances[msg.sender][tokens[i]];
            }

            _withdrawBalance(tokens[i], withdrawAmount);
        }
    }
    /**
     * 
     */
    function _withdrawBalance(address token, uint256 amount) internal {
        //需要账户余额充足
        require(userTokenBalances[msg.sender][token] >= amount, "insufficient balance");
        //检查账户余额
        unsafeSubtractFromBalance(msg.sender, token, amount);
        //转正给账户
        require(IERC20(token).transfer(msg.sender, amount), "transfer failed");
        emit Withdraw(msg.sender, token, amount);
    }
    /**
     * 矫正公会token余额
     */
    function collectTokens(address token) public onlyDelegate nonReentrant {
        //20Token差额
        uint256 amountToCollect = IERC20(token).balanceOf(address(this)).sub(userTokenBalances[TOTAL][token]);
        // only collect if 1) there are tokens to collect 2) token is whitelisted 3) token has non-zero balance
        //确保，存在差额，同时为白名单token，公会token有余额
        require(amountToCollect > 0, 'no tokens to collect');
        require(tokenWhitelist[token], 'token to collect must be whitelisted');
        require(userTokenBalances[GUILD][token] > 0, 'token to collect must have non-zero guild bank balance');
        //更新公会token余额
        unsafeAddToBalance(GUILD, token, amountToCollect);
        emit TokensCollected(token, amountToCollect);
    }
    /**
     * 取消提案，只有提案自己可以取消
     */
    // NOTE: requires that delegate key which sent the original proposal cancels, msg.sender == proposal.proposer
    function cancelProposal(uint256 proposalId) public nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.flags[0], "proposal has already been sponsored");
        require(!proposal.flags[3], "proposal has already been cancelled");
        require(msg.sender == proposal.proposer, "solely the proposer can cancel");

        proposal.flags[3] = true; // cancelled
        //返回提案贡献公会token
        unsafeInternalTransfer(ESCROW, proposal.proposer, proposal.tributeToken, proposal.tributeOffered);
        emit CancelProposal(proposalId, msg.sender);
    }
    /**
     * 更新成员代理
     */
    function updateDelegateKey(address newDelegateKey) public nonReentrant onlyShareholder {
        require(newDelegateKey != address(0), "newDelegateKey cannot be 0");

        // skip checks if member is setting the delegate key to their member address
        // 检查成员代理key是否为他们的沉管底子
        if (newDelegateKey != msg.sender) {
            require(!members[newDelegateKey].exists, "cannot overwrite existing members");
            require(!members[memberAddressByDelegateKey[newDelegateKey]].exists, "cannot overwrite existing delegate keys");
        }

        Member storage member = members[msg.sender];
        memberAddressByDelegateKey[member.delegateKey] = address(0);
        memberAddressByDelegateKey[newDelegateKey] = msg.sender;
        member.delegateKey = newDelegateKey;

        emit UpdateDelegateKey(msg.sender, newDelegateKey);
    }

    // can only ragequit if the latest proposal you voted YES on has been processed
    /**
     * 给定投票赞成的提案是否已处理
     */
    function canRagequit(uint256 highestIndexYesVote) public view returns (bool) {
        require(highestIndexYesVote < proposalQueue.length, "proposal does not exist");
        return proposals[proposalQueue[highestIndexYesVote]].flags[1];
    }
    /**
     * 投票是否过期
     */
    function hasVotingPeriodExpired(uint256 startingPeriod) public view returns (bool) {
        return getCurrentPeriod() >= startingPeriod.add(votingPeriodLength);
    }

    /***************
    GETTER FUNCTIONS
    ***************/

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }
    /**
     * 当前间隔
     */
    function getCurrentPeriod() public view returns (uint256) {
        return block.timestamp.sub(summoningTime).div(periodDuration);
    }

    function getProposalQueueLength() public view returns (uint256) {
        return proposalQueue.length;
    }

    function getProposalFlags(uint256 proposalId) public view returns (bool[6] memory) {
        return proposals[proposalId].flags;
    }

    function getUserTokenBalance(address user, address token) public view returns (uint256) {
        return userTokenBalances[user][token];
    }

    function getMemberProposalVote(address memberAddress, uint256 proposalIndex) public view returns (Vote) {
        require(members[memberAddress].exists, "member does not exist");
        require(proposalIndex < proposalQueue.length, "proposal does not exist");
        return proposals[proposalQueue[proposalIndex]].votesByMember[memberAddress];
    }

    function getTokenCount() public view returns (uint256) {
        return approvedTokens.length;
    }

    /***************
    HELPER FUNCTIONS
    ***************/
    /**
     * 添加用户账户余额，并添加到总池
     */
    function unsafeAddToBalance(address user, address token, uint256 amount) internal {
        userTokenBalances[user][token] += amount;
        userTokenBalances[TOTAL][token] += amount;
    }
    /**
    * 减少用户账户余额，级联到总池
     */
    function unsafeSubtractFromBalance(address user, address token, uint256 amount) internal {
        userTokenBalances[user][token] -= amount;
        userTokenBalances[TOTAL][token] -= amount;
    }
    /**
     * 内部转账
     */
    function unsafeInternalTransfer(address from, address to, address token, uint256 amount) internal {
        unsafeSubtractFromBalance(from, token, amount);
        unsafeAddToBalance(to, token, amount);
    }
    /**
     * 计算份额
     */
    function fairShare(uint256 balance, uint256 shares, uint256 _totalShares) internal pure returns (uint256) {
        require(_totalShares != 0, "total shares should not be 0");

        if (balance == 0) {//公会token为0
            return 0;
        }

        uint256 prod = balance * shares; 

        if (prod / balance == shares) { // no overflow in multiplication above? 没有溢出
            return prod / _totalShares;
        }
        //实际总份额 
        return (balance / _totalShares) * shares;
    }
}
