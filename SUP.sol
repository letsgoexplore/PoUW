pragma solidity ^0.8.16;

library SafeMath {
    /**
     * @dev Multiplies two numbers, throws on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
     * @dev Integer division of two numbers, truncating the quotient.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
     * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
     * @dev Adds two numbers, throws on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

interface SUPInterface {
    event WinBonus(address _miner);
    event RetriveBonus();

    function commitAnswer(uint256 _hash) external;

    function secretConveyAnswer() external;

    function approveAnswer(address _answerProvider) external payable;

    function declineAnswer(address _answerProvider) external;

    function revealAnswer(uint256[] calldata _decodeAnswer)
        external
        payable
        returns (bool _result);

    function settlement() external payable;

    function retrieveBonus() external payable returns (bool _result);
}

contract SUP {
    using SafeMath for uint256;
    //记录constraint
    struct couple {
        uint256 varible1;
        uint256 varible2;
    }

    struct commitRecord {
        address commiter;
        uint256 commitTime;
        uint256 conveyTime;
        uint256 bonusLevel;
        uint256 answerHash;
        uint256[] revealAnswer;
    }

    //合约参数
    //发布者
    address owner;
    //发布者设置的奖金
    uint256 bonus;
    //最小赎回时间
    uint256 minimumRetrieveTime;
    //奖励列表
    mapping(uint256 => uint256) bonusList;

    //proposal的问题描述
    //变量
    uint256[] _varibles;
    //变量的取值
    mapping(uint256 => uint256[]) _domains;
    //变量的约束条件
    couple[] _constraints;

    //动态数据
    //提交者的信息集
    commitRecord[] commitList;
    //提交者优先级列表（仅包含同一等级最先发布的提交者）
    uint256[] commiterPrioity;
    //发布时间
    uint256 proposeTime;
    //当前最高的答案等级
    uint256 hightestLevel;
    //当前最高等级的第一个答案commit时间
    uint256 highestLevelCommitTime;
    //若发布者没有approveAnswer，则合约会在验证合格后通过revealAnswer将答案写入finalAnswer
    uint256[] finalAnswer;
}
