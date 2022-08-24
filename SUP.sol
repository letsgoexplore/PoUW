<<<<<<< HEAD
pragma solidity ^0.8.7;

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
    ///@dev two events that do with token transfer
    event WinBonus(address _miner);
    event RetriveBonus(uint256 _amount);

    ///@notice when the miner work out the answer, he/she will commit the
    ///hash of the answer and the bonusLevel of its answer. The hashing process
    ///prevent the malicious node to steal the answer when they detect before the
    ///answer is verified on the chain.
    function commitAnswer(uint256 _hash, uint256 _bonusLevel) external;

    ///@notice when the contract owner decline or neglect the answer, the miner can
    ///still challenge by reveal the original answer and verify the answer.
    function revealAnswer(uint256[] calldata _decodeAnswer)
        external
        returns (bool _result);

    ///@notice when "now > tSettlement", anyone can call this funtion to raise settlement,
    ///while usually the miner who wins will call this function.
    function settlement() external payable;

    ///@notice after the Retrieve Time, the owner can claim the deposit inside of the contract
    function retrieveBonus() external payable returns (bool _result);

    ///@notice this is the hash function used in the contract
    ///it encode the answer with the msg.sender's address
    function encodeAnswer(uint256[] calldata _decodeAnswer)
        external
        returns (uint256 _result);

    ///@notice calculating the bonus the user can get with the answer
    function calBonus(uint256[] memory _answer)
        external
        returns (uint256 bonus);
}

abstract contract SUP is SUPInterface {
    using SafeMath for uint256;

    ///@notice the struct that record the commit info
    ///'answerHash' is uint(keccak256(abi.encodePacked(uint[], address(msg.sender))))
    ///there is "encodeAnswer" function
    ///@dev remember to initialize isUsed
    struct commitRecord {
        bool isUsed;
        uint256 commitTime;
        uint256 bonusLevel;
        uint256 answerHash;
        uint256[] revealAnswer;
        bool revealResult;
    }

    ///@dev static data
    ///the proposer/owner
    address payable owner;
    ///the total token the owner put into the contract
    uint256 settedBonus;
    ///whether this is CSP, formulus calculating or sth else
    string problemType;
    ///whether any valid answer is provided
    bool isSolved;
    ///the minimum and maximum interval between commit and reveal
    uint256 tcrmin;
    uint256 tcrmax;
    ///the deadline of committing,
    ///tCommitDeadline = tLauch + tlcInterval
    uint256 tlcInterval;
    uint256 tCommitDeadline;
    ///the time to settle, that is to decide the winner
    ///tSettlement = tLaunch + tlsInterval
    uint256 tcsInterval;
    uint256 tSettlement;
    ///only after this time can the
    ///@dev notice the relation constraints within the T varibles
    ///tRetrieval = tLaunch + tlrInterval
    uint256 tsrInterval;
    uint256 tRetrieval;

    ///@dev dynamic data
    ///the mapping and address list that collect the info of the answer commiter
    mapping(address => commitRecord) commitList;
    address payable[] commiterList;
    ///the proposing time
    uint256 tPropose;
    ///final bonus winner
    address payable winner;
    ///the final bonus winner wins
    uint256 winBonus;
    ///@dev the proposer can change the constrains before the contract launch
    bool isLaunched;
    ///@dev all the time point should be relative with 'tLaunch',
    ///rather than 'tPropose'
    uint256 tLaunch;
    ///already settle
    bool isSettled;
    ///owner already retrieved back balance
    bool isRetrieved;
    ///the final answer of the problem
    uint256[] finalAnswer;

    ///@notice the proposer can add condition to the contract
    ///after the proposerTx and before the contract is finally launched.
    function launchProblem() public onlyOwner {
        require(!isLaunched);
        tLaunch = block.timestamp;
        isLaunched = true;
        tCommitDeadline = tLaunch.add(tlcInterval);
        tSettlement = tCommitDeadline.add(tcsInterval);
        tRetrieval = tSettlement.add(tsrInterval);
    }

    ///@notice when the miner work out the answer, he/she will commit the
    ///hash of the answer and the bonusLevel of its answer. The hashing process
    ///prevent the malicious node to steal the answer when they detect before the
    ///answer is verified on the chain.
    ///@param _hash the hash function used here is keccak256
    ///@dev needa to make sure the time is before the tCommitDeadline,
    ///and after the proposer is launched.
    function commitAnswer(uint256 _hash, uint256 _bonusLevel)
        external
        alreadyLaunch
    {
        require(block.timestamp <= tCommitDeadline);
        commiterList.push(payable(msg.sender));
        commitRecord storage commiter = commitList[msg.sender];
        commiter.isUsed = true;
        commiter.answerHash = _hash;
        commiter.bonusLevel = _bonusLevel;
        commiter.commitTime = block.timestamp;
        commiter.revealResult = false;
    }

    ///@notice when the contract owner decline or neglect the answer, the miner can
    ///still challenge by reveal the original answer and verify the answer.
    ///@dev few steps:
    ///1.address already committed
    ///2.check the "tccmin <= now - commitTime <= Tccmax"
    ///3.verify the answer and record
    function revealAnswer(uint256[] calldata _decodeAnswer)
        external
        alreadyCommit
        returns (bool _result)
    {
        commitRecord storage commiter = commitList[msg.sender];
        require(
            (block.timestamp - commiter.commitTime >= tcrmin) &&
                (block.timestamp - commiter.commitTime <= tcrmax)
        );
        require(verifyAnswer(_decodeAnswer));
        commiter.revealAnswer = _decodeAnswer;
        commiter.revealResult = true;
        return true;
    }

    ///@notice calculating the bonus the user can get with the answer
    ///@param _answer the answer of the user
    ///the default format is int[]
    ///this can be implemented in the description of the problem
    ///@return bonus the bonus the user can get
    ///@dev inherit this virtual funtion in the actual contract
    function calBonus(uint256[] memory _answer)
        public
        view
        virtual
        returns (uint256 bonus);

    ///@notice verify whether the decode answer accord with the requirement
    ///and check whether the user has change its answer compared with the hash
    ///during the commit time.
    ///This function contains three validation part:
    ///1.check whether the sender has committed
    ///2.check whether the answer conform to the bonus level it claim
    ///3.check the hash of the decode answer is the same with the hash it claim during commit Tx
    ///@param _answer the answer of the sender
    ///@return result whether both three validations mentioned above, is passed
    function verifyAnswer(uint256[] memory _answer)
        internal
        view
        returns (bool result)
    {
        commitRecord memory commiter = commitList[msg.sender];
        if (calBonus(_answer) != commiter.bonusLevel) {
            return false;
        }
        if (encodeAnswer(_answer) != commiter.answerHash) {
            return false;
        }
        return true;
    }

    ///@notice when "now > tSettlement", anyone can call this funtion to raise settlement,
    ///while usually the miner who wins will call this function.
    ///@dev few steps:
    ///1."now > tSettlement"
    ///2.find the winner from the commitList
    function settlement() public payable {
        require(!isSettled);
        require(block.timestamp > tSettlement);
        if (commiterList.length == 0) {
            isSolved = false;
        }
        address payable winer;
        uint256 winnerBonus;
        uint256 winnerTime;
        bool anyValidUser = false;

        for (uint256 i = 0; i < commiterList.length; i++) {
            address payable commiter = commiterList[i];
            commitRecord memory commitInfo = commitList[commiter];
            //when no valid answer is found in the list
            if (!anyValidUser) {
                if (commitInfo.revealResult) {
                    winer = commiter;
                    winnerBonus = commitInfo.bonusLevel;
                    winnerTime = commitInfo.commitTime;
                    anyValidUser = true;
                }
            } else {
                if (commitInfo.revealResult) {
                    if (
                        (commitInfo.bonusLevel > winnerBonus) ||
                        (commitInfo.bonusLevel == winnerBonus &&
                            commitInfo.commitTime < winnerTime)
                    ) {
                        winer = commiter;
                        winnerBonus = commitInfo.bonusLevel;
                    }
                }
            }
        }

        if (!anyValidUser) {
            isSolved = false;
        } else {
            winner = winer;
            winBonus = winnerBonus;
            finalAnswer = commitList[winner].revealAnswer;
            winner.transfer(winBonus);
            emit WinBonus(winner);
        }
        isSettled = true;
    }

    ///@notice after the Retrieve Time, the owner can claim the deposit inside of the contract
    function retrieveBonus() external payable onlyOwner returns (bool _result) {
        require(block.timestamp >= tRetrieval);
        require(isSettled);
        require(!isRetrieved);
        uint256 amount = address(this).balance;
        owner.transfer(amount);
        emit RetriveBonus(amount);
        return true;
    }

    ///@notice this is the hash function used in the contract
    ///it encode the answer with the msg.sender's address
    function encodeAnswer(uint256[] memory _decodeAnswer)
        public
        view
        returns (uint256 _result)
    {
        return
            uint256(
                keccak256(abi.encodePacked(_decodeAnswer, address(msg.sender)))
            );
    }

    fallback() external {}

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier alreadyLaunch() {
        require(isLaunched);
        _;
    }

    modifier beforeLaunch() {
        require(!isLaunched);
        _;
    }

    modifier alreadyCommit() {
        require(commitList[msg.sender].isUsed == true);
        _;
    }
}

contract CSPContract is SUP {
    using SafeMath for uint256;
    struct varibleDomain {
        bool isRestricted;
        uint256[] domain;
    }
    ///@notice CSP(constraints satisfying problem) consists of three part:
    ///1.varibles: here, to save the memory, we use 0,1,2,...N-1 to represent N varibles.
    ///2.domains: that is, the value each varibles can be.
    ///3.constraints: the condition that the varibles should satisfy.
    uint256 varibles;
    uint256 colors;
    mapping(uint256 => varibleDomain) domains;
    uint256 constraintsNumber;
    mapping(uint256 => uint256[]) constraints;
    uint256[] bonusTable;
    ///the sum of the bonus in bonusTable
    uint256 totalBonusTableValue;

    constructor(
        string memory _problemType,
        uint256 _tcrmin,
        uint256 _tcrmax,
        uint256 _tlcInterval,
        uint256 _tcsInterval,
        uint256 _tsrInterval,
        uint256 _varibles,
        uint256 _colors
    ) payable {
        require(_tcrmax > _tcrmin);
        require(_tcsInterval > _tcrmax);

        owner = payable(msg.sender);
        tPropose = block.timestamp;
        settedBonus = msg.value;
        problemType = _problemType;
        tcrmax = _tcrmax;
        tcrmin = _tcrmin;
        tlcInterval = _tlcInterval;
        tcsInterval = _tcsInterval;
        tsrInterval = _tsrInterval;

        varibles = _varibles;
        colors = _colors;
        constraintsNumber = 0;
        totalBonusTableValue = 0;
    }

    ///@notice only adding varibles and adding colors is allowed,
    ///because deleting varibles need great changes to the memory.
    function addVaribles(uint256 _varibles) public onlyOwner beforeLaunch {
        require(_varibles > varibles);
        varibles = _varibles;
    }

    function addColors(uint256 _colors) public onlyOwner beforeLaunch {
        require(_colors > colors);
        colors = _colors;
    }

    ///@dev few step:
    ///1. verify the _constraint is legitimate, that is without replicate and in increasing order
    ///2. add the constraint to the constraints, bonusTable, constraintsNumber
    function addConstraints(
        uint256[] memory _constraint,
        uint256 _constraintBonus
    ) public onlyOwner beforeLaunch {
        require(checkIsIncreasingAndDifferent(_constraint));
        //due to the increasing order, verifying the last element is adequate.
        require(_constraint[_constraint.length - 1] < varibles);

        constraints[constraintsNumber] = _constraint;
        require((totalBonusTableValue.add(_constraintBonus)) <= settedBonus);
        totalBonusTableValue.add(_constraintBonus);
        bonusTable.push(_constraintBonus);
        constraintsNumber++;
    }

    function addDomain(uint256 _varible, uint256[] memory _domain)
        public
        onlyOwner
        beforeLaunch
    {
        require(checkIsIncreasingAndDifferent(_domain));
        require(_domain[_domain.length - 1] < colors);
        domains[_varible].isRestricted = true;
        domains[_varible].domain = _domain;
    }

    ///@notice avoid the same element in the domain and constraint
    function checkIsIncreasingAndDifferent(uint256[] memory _input)
        internal
        pure
        returns (bool _result)
    {
        for (uint256 i = 0; i < _input.length - 1; i++) {
            if (_input[i] >= _input[i + 1]) {
                return false;
            }
        }
        return true;
    }

    ///@notice given the specific varible and according value,
    ///verify whether this satisfied the domains
    function domainSatisfy(uint256 _elem, uint256 _elemVal)
        internal
        view
        returns (bool _result)
    {
        if (_elemVal >= colors) {
            return false;
        }
        varibleDomain memory domain = domains[_elem];
        if (!domain.isRestricted) {
            return true;
        }
        for (uint256 i = 0; i < varibles; i++) {
            if (domain.domain[i] == _elemVal) {
                return true;
            }
        }
        return false;
    }

    function allDomainSatisfy(uint256[] memory _variblesVal)
        public
        view
        returns (bool _result)
    {
        for (uint256 i = 0; i < varibles; i++) {
            if (!domainSatisfy(i, _variblesVal[i])) {
                return false;
            }
        }
        return true;
    }

    ///@notice varify whether the answer satisfy single constraint
    ///@param _variblesVal the value of the varibles
    ///@param _constraint the single constraint the varible should satisfy
    ///@dev notice that, the varible may not satisfy the domains conditon,
    ///omitting this judgement aims to lessen the calculation cost
    function elemConsSatisfy(
        uint256[] memory _variblesVal,
        uint256[] memory _constraint
    ) internal pure returns (bool _result) {
        for (uint256 i = 0; i < _constraint.length; i++) {
            for (uint256 j = i + 1; j < _constraint.length; j++) {
                if (
                    _variblesVal[_constraint[i]] == _variblesVal[_constraint[j]]
                ) {
                    return false;
                }
            }
        }
        return true;
    }

    function calBonus(uint256[] memory _answer)
        public
        view
        override
        returns (uint256 bonus)
    {
        uint256 presentBonus = 0;
        require(_answer.length == varibles);
        if (!allDomainSatisfy(_answer)) {
            return 0;
        }
        for (uint256 i = 0; i < constraintsNumber; i++) {
            if (elemConsSatisfy(_answer, constraints[i])) {
                presentBonus = presentBonus.add(bonusTable[i]);
            }
        }
        return presentBonus;
    }
}
=======
pragma solidity ^0.8.7;

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
    ///@dev two events that do with token transfer
    event WinBonus(address _miner);
    event RetriveBonus(uint256 _amount);

    function commitAnswer(uint256 _hash, uint256 _bonusLevel) external;

    function revealAnswer(uint256[] calldata _decodeAnswer)
        external
        returns (bool _result);

    function settlement() external payable;

    function retrieveBonus() external payable returns (bool _result);

    function encodeAnswer(uint256[] calldata _decodeAnswer)
        external
        returns (uint256 _result);

    function calBonus(uint256[] memory _answer)
        external
        returns (uint256 bonus);
}

abstract contract SUP is SUPInterface {
    using SafeMath for uint256;

    ///@notice the struct that record the commit info
    ///'answerHash' is uint(keccak256(abi.encodePacked(uint[], address(msg.sender))))
    ///there is "encodeAnswer" function
    ///@dev remember to initialize isUsed
    struct commitRecord {
        bool isUsed;
        uint256 commitTime;
        uint256 bonusLevel;
        uint256 answerHash;
        uint256[] revealAnswer;
        bool revealResult;
    }

    ///@dev static data
    ///the proposer/owner
    address payable owner;
    ///the total token the owner put into the contract
    uint256 settedBonus;
    ///@notice when all the procedure ends and the owner wanna to retrieve the balance,
    ///the contract need to transfer to the owner, while this Tx needs gas fee,
    ///therefore, excessive fee should be kept in the contract,
    ///or the balance in contract cannot be retrieved.
    uint256 txFee;
    ///whether this is CSP, formulus calculating or sth else
    string problemType;
    ///whether any valid answer is provided
    bool isSolved;
    ///the minimum and maximum interval between commit and reveal
    uint256 tcrmin;
    uint256 tcrmax;
    ///the deadline of committing,
    ///tCommitDeadline = tLauch + tlcInterval
    uint256 tlcInterval;
    uint256 tCommitDeadline;
    ///the time to settle, that is to decide the winner
    ///tSettlement = tLaunch + tlsInterval
    uint256 tcsInterval;
    uint256 tSettlement;
    ///only after this time can the
    ///@dev notice the relation constraints within the T varibles
    ///tRetrieval = tLaunch + tlrInterval
    uint256 tsrInterval;
    uint256 tRetrieval;

    ///@dev dynamic data
    ///the mapping and address list that collect the info of the answer commiter
    mapping(address => commitRecord) commitList;
    address payable[] commiterList;
    ///the proposing time
    uint256 tPropose;
    ///final bonus winner
    address payable winner;
    ///the final bonus winner wins
    uint256 winBonus;
    ///@dev the proposer can change the constrains before the contract launch
    bool isLaunched;
    ///@dev all the time point should be relative with 'tLaunch',
    ///rather than 'tPropose'
    uint256 tLaunch;
    ///already claim the bonus or not
    bool isClaimed;

    bool isRetrieved;
    ///the final answer of the problem
    uint256[] finalAnswer;

    ///@notice the proposer can add condition to the contract
    ///after the proposerTx and before the contract is finally launched.
    function launchProblem() public onlyOwner {
        require(!isLaunched);
        tLaunch = block.timestamp;
        isLaunched = true;
        tCommitDeadline = tLaunch.add(tlcInterval);
        tSettlement = tCommitDeadline.add(tcsInterval);
        tRetrieval = tSettlement.add(tsrInterval);
    }

    ///@notice when the miner work out the answer, he/she will commit the
    ///hash of the answer and the bonusLevel of its answer. The hashing process
    ///prevent the malicious node to steal the answer when they detect before the
    ///answer is verified on the chain.
    ///@param _hash the hash function used here is keccak256
    ///@dev needa to make sure the time is before the tCommitDeadline,
    ///and after the proposer is launched.
    function commitAnswer(uint256 _hash, uint256 _bonusLevel)
        external
        alreadyLaunch
    {
        require(block.timestamp <= tCommitDeadline);
        commiterList.push(payable(msg.sender));
        commitRecord storage commiter = commitList[msg.sender];
        commiter.isUsed = true;
        commiter.answerHash = _hash;
        commiter.bonusLevel = _bonusLevel;
        commiter.commitTime = block.timestamp;
    }

    ///@notice when the contract owner decline or neglect the answer, the miner can
    ///still challenge by reveal the original answer and verify the answer.
    ///@dev few steps:
    ///1.address already committed
    ///2.check the "tccmin <= now - commitTime <= Tccmax"
    ///3.verify the answer and record
    function revealAnswer(uint256[] calldata _decodeAnswer)
        external
        alreadyCommit
        returns (bool _result)
    {
        commitRecord storage commiter = commitList[msg.sender];
        require(
            (block.timestamp - commiter.commitTime >= tcrmin) &&
                (block.timestamp - commiter.commitTime <= tcrmax)
        );
        require(verifyAnswer(_decodeAnswer));
        commiter.revealAnswer = _decodeAnswer;
        commiter.revealResult = true;
        return true;
    }

    ///@notice calculating the bonus the user can get with the answer
    ///@param _answer the answer of the user
    ///the default format is int[]
    ///this can be implemented in the description of the problem
    ///@return bonus the bonus the user can get
    ///@dev inherit this virtual funtion in the actual contract
    function calBonus(uint256[] memory _answer)
        public
        view
        virtual
        returns (uint256 bonus);

    ///@notice verify whether the decode answer accord with the requirement
    ///and check whether the user has change its answer compared with the hash
    ///during the commit time.
    ///This function contains three validation part:
    ///1.check whether the sender has committed
    ///2.check whether the answer conform to the bonus level it claim
    ///3.check the hash of the decode answer is the same with the hash it claim during commit Tx
    ///@param _answer the answer of the sender
    ///@return result whether both three validations mentioned above, is passed
    function verifyAnswer(uint256[] memory _answer)
        internal
        view
        returns (bool result)
    {
        commitRecord memory commiter = commitList[msg.sender];
        if (calBonus(_answer) == commiter.bonusLevel) {
            return false;
        }
        if (encodeAnswer(_answer) == commiter.answerHash) {
            return false;
        }
        return true;
    }

    ///@notice when "now > tSettlement", anyone can call this funtion to raise settlement,
    ///while usually the miner who wins will call this function.
    ///@dev few steps:
    ///1."now > tSettlement"
    ///2.find the winner from the commitList
    function settlement() public payable {
        require(block.timestamp > tSettlement);
        if (commiterList.length == 0) {
            isSolved = false;
        }
        address payable winer;
        uint256 winnerBonus;
        bool anyValidUser;

        for (uint256 i = 0; i < commiterList.length; i++) {
            address payable commiter = commiterList[i];
            commitRecord memory commitInfo = commitList[commiter];
            //when no valid answer is found in the list
            if (!anyValidUser) {
                if (commitInfo.revealResult) {
                    winer = commiter;
                    winnerBonus = commitInfo.bonusLevel;
                    anyValidUser = true;
                }
            } else {
                if (commitInfo.revealResult) {
                    if (commitInfo.bonusLevel > winnerBonus) {
                        winer = commiter;
                        winnerBonus = commitInfo.bonusLevel;
                    }
                }
            }
        }

        if (!anyValidUser) {
            isSolved = false;
        } else {
            if (!isClaimed) {
                winner = winer;
                winBonus = winnerBonus;
                finalAnswer = commitList[winner].revealAnswer;
                winner.transfer(winBonus);
                emit WinBonus(winner);
            }
        }
    }

    ///@notice after the Retrieve Time, the owner can claim the deposit inside of the contract
    function retrieveBonus() external payable onlyOwner returns (bool _result) {
        require(block.timestamp >= tRetrieval);
        require(!isSolved || isClaimed);
        require(!isRetrieved);
        uint256 amount = address(this).balance - txFee;
        owner.transfer(amount);
        emit RetriveBonus(amount);
        return true;
    }

    function encodeAnswer(uint256[] memory _decodeAnswer)
        public
        view
        returns (uint256 _result)
    {
        return
            uint256(
                keccak256(abi.encodePacked(_decodeAnswer, address(msg.sender)))
            );
    }

    fallback() external {}

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier alreadyLaunch() {
        require(isLaunched);
        _;
    }

    modifier BeforeLaunch() {
        require(!isLaunched);
        _;
    }

    modifier alreadyCommit() {
        require(commitList[msg.sender].isUsed == true);
        _;
    }
}

contract CSPContract is SUP {
    using SafeMath for uint256;
    struct varibleDomain {
        bool isRestricted;
        uint256[] domain;
    }
    ///@notice CSP(constraints satisfying problem) consists of three part:
    ///1.varibles: here, to save the memory, we use 0,1,2,...N-1 to represent N varibles.
    ///2.domains: that is, the value each varibles can be.
    ///3.constraints: the condition that the varibles should satisfy.
    uint256 varibles;
    uint256 colors;
    mapping(uint256 => varibleDomain) domains;
    uint256 constraintsNumber;
    mapping(uint256 => uint256[]) constraints;
    uint256[] bonusTable;
    ///the sum of the bonus in bonusTable
    uint256 totalBonusTableValue;

    constructor(
        uint256 _txFee,
        string memory _problemType,
        uint256 _tcrmin,
        uint256 _tcrmax,
        uint256 _tlcInterval,
        uint256 _tcsInterval,
        uint256 _tsrInterval,
        uint256 _varibles,
        uint256 _colors
    ) payable {
        require(_tcrmax > _tcrmin);
        require(_tcsInterval > _tcrmax);

        owner = payable(msg.sender);
        tPropose = block.timestamp;
        settedBonus = msg.value;
        txFee = _txFee;
        problemType = _problemType;
        tcrmax = _tcrmax;
        tcrmin = _tcrmin;
        tlcInterval = _tlcInterval;
        tcsInterval = _tcsInterval;
        tsrInterval = _tsrInterval;

        varibles = _varibles;
        colors = _colors;
        constraintsNumber = 0;
        totalBonusTableValue = 0;
    }

    ///@notice only adding varibles and adding colors is allowed,
    ///because deleting varibles need great changes to the memory.
    function addVaribles(uint256 _varibles) public onlyOwner BeforeLaunch {
        require(_varibles > varibles);
        varibles = _varibles;
    }

    function addColors(uint256 _colors) public onlyOwner BeforeLaunch {
        require(_colors > colors);
        colors = _colors;
    }

    ///@dev few step:
    ///1. verify the _constraint is legitimate, that is without replicate and in increasing order
    ///2. add the constraint to the constraints, bonusTable, constraintsNumber
    function addConstraints(
        uint256[] memory _constraint,
        uint256 _constraintBonus
    ) public onlyOwner BeforeLaunch {
        require(checkIsIncreasingAndDifferent(_constraint));
        //due to the increasing order, verifying the last element is adequate.
        require(_constraint[_constraint.length - 1] < varibles);

        constraints[constraintsNumber] = _constraint;
        require(
            (totalBonusTableValue.add(_constraintBonus)) <=
                settedBonus.sub(txFee)
        );
        totalBonusTableValue.add(_constraintBonus);
        bonusTable.push(_constraintBonus);
        constraintsNumber++;
    }

    function addDomain(uint256 _varible, uint256[] memory _domain)
        public
        onlyOwner
        BeforeLaunch
    {
        require(checkIsIncreasingAndDifferent(_domain));
        require(_domain[_domain.length - 1] < colors);
        domains[_varible].isRestricted = true;
        domains[_varible].domain = _domain;
    }

    ///@notice avoid the same element in the domain and constraint
    function checkIsIncreasingAndDifferent(uint256[] memory _input)
        internal
        pure
        returns (bool _result)
    {
        for (uint256 i = 0; i < _input.length - 1; i++) {
            if (_input[i] >= _input[i + 1]) {
                return false;
            }
        }
        return true;
    }

    ///@notice given the specific varible and according value,
    ///verify whether this satisfied the domains
    function domainSatisfy(uint256 _elem, uint256 _elemVal)
        internal
        view
        returns (bool _result)
    {
        if (_elemVal >= colors) {
            return false;
        }
        varibleDomain memory domain = domains[_elem];
        if (!domain.isRestricted) {
            return true;
        }
        for (uint256 i = 0; i < varibles; i++) {
            if (domain.domain[i] == _elemVal) {
                return true;
            }
        }
        return false;
    }

    function allDomainSatisfy(uint256[] memory _variblesVal)
        public
        view
        returns (bool _result)
    {
        for (uint256 i = 0; i < varibles; i++) {
            if (!domainSatisfy(i, _variblesVal[i])) {
                return false;
            }
        }
        return true;
    }

    ///@notice varify whether the answer satisfy single constraint
    ///@param _variblesVal the value of the varibles
    ///@param _constraint the single constraint the varible should satisfy
    ///@dev notice that, the varible may not satisfy the domains conditon,
    ///omitting this judgement aims to lessen the calculation cost
    function elemConsSatisfy(
        uint256[] memory _variblesVal,
        uint256[] memory _constraint
    ) internal pure returns (bool _result) {
        for (uint256 i = 0; i < _constraint.length; i++) {
            for (uint256 j = i + 1; j < _constraint.length; j++) {
                if (
                    _variblesVal[_constraint[i]] == _variblesVal[_constraint[j]]
                ) {
                    return false;
                }
            }
        }
        return true;
    }

    function calBonus(uint256[] memory _answer)
        public
        view
        override
        returns (uint256 bonus)
    {
        uint256 presentBonus = 0;
        require(_answer.length == varibles);
        if (!allDomainSatisfy(_answer)) {
            return 0;
        }
        for (uint256 i = 0; i < constraintsNumber; i++) {
            if (elemConsSatisfy(_answer, constraints[i])) {
                presentBonus = presentBonus.add(bonusTable[i]);
            }
        }
        return presentBonus;
    }
}
>>>>>>> 9eec4f4ee3a56ebc3de86166c35caaf2d702ec37
