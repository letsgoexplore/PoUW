# Document

## Introduction

### SUP(Standard User Problem)

SUPs are raised by the users. The users(we will called them owners below), propose the problem they want to solve, and other miners will try to solve the problems.

SUP consists lots of subordinated types of  problem, such as machine learning problem or the CSP mentioned below. SUP stipulates the general behavior/function of all those subordinated problems possess.

### CSP(Constraints Satisfying Problem)

CSP is a type of problem that consists of 3 portion:

- varibles : {X1,X2,…Xn}
- domains : the value that Xi(i = 1,2,…n) can get.
- constraints : the constraints that {X1,X2,…Xn} should satisfied

Typical CSP problems include sudoku, eight queen problem. The problem will grow more complex with the increase of the number of varibles and constraints.

![eight queen.png](Document%20fa6ce4d2c0a74cac96827ad0a011b487/eight_queen.png)

### Timeline

![PoCWTimeline.jpg](Document%20fa6ce4d2c0a74cac96827ad0a011b487/PoCWTimeline.jpg)

The general timeline is showed ahead. The owner **proposes** the problem **by deploy the contract** at first, and is able to **amend** before the problem is finally **launch**.(**Launch** is realized with a funtion in the contract.) The owner will stipulated the varibles, domains, constraints and the bonus table. When the answer conforms to a constraint, a bonus will be added to the total bonus. The miner who provides the answer with the highest total bonus, will win all the bonus the owner provided, while other miner will get nothing.

The miners can commit the answer, after **Launch** and before the **commitDeadline**. Miner needs to provide the Hash(answer, address) and the according total bonus of the answer. The miner will reveal the decoded answer after a time interval. The time interval aims to prevent stealing answer. Due to the delay of the network, other nodes that receive the decoded answer can immediately announce its own answer. Obviously, this steals other’s outcomes, which should be baned. Therefore, miners will first commit the hash of the answer, and reveal the decoded answer after a time interval, which can prevent stealing answer. The hash function used here is **keccak256**.

The **Settlement** time is pre-setted by the owner. During the Settlement, all the miners with valid answer, (which means the revealed decoded answer accords with the commit hash,) will be compared by the contract, and the highest miner will gain the bonus.

The **Retrieve** time is also pre-setted by the owner. The owner might send more tokens to the contract. He/She can retrieve back after the Retrieve time.

## Contract Illustration

### Contract Relationship

There are 4 modules in the SUP.sol, showed below:

```solidity
library SafeMath
interface SUPInterface
abstract contract SUP is SUPInterface
contract CSPContract is SUP
```

We are trying to build the SUP(Standard User Problem), and CSP(Constraints Satisfying Problem) is one of the subordinated problem of SUP. Therefore, we use the abstract contract SUP to stipulate the general behavior/function of the SUP. CSPContract inherits from SUP, and fulfils the complete and specific function.

 Detaied information is  showed below:

```solidity
library SafeMath
	//a widely used library that makes sure the operation is safe
interface SUPInterface
	//the interface for other contracts to call
abstract contract SUP is SUPInterface
	//stipulate the general behavior/function of the SUP
contract CSPContract is SUP
	//stipulate the specific behavior/function of the CSP, a subordinated problem of SUP
```

### Function Illustration

**event**

```solidity
//event
	event CommitAnswer(address _miner, uint _bonusLevel);
  event RevealAnswer(address _miner, uint _bonusLevel, uint[] _decodeAnswer);
  event ProblemSettle();
  event WinBonus(address _miner);
  event RetriveBonus(uint256 _amount);
```

**modifier**

```solidity
//verify whether the msg.sender is owner
modifier onlyOwner();
//verify whether the problem is launched
modifier alreadyLaunch();
modifier beforeLaunch();
//verify whether the user has already commit answer
modifier alreadyCommit();
```

**amend problem**

```solidity
//@param _varibles : _varibles should be bigger than present varible
function addVaribles(uint256 _varibles) public onlyOwner beforeLaunch;

//@param _colors : _colors should be bigger than present colors
function addColors(uint256 _colors) public onlyOwner beforeLaunch;

//@param _constraint : _constraint = [0,1,2,5], means that each two of the varibles 
//X0,X1,X2,X5 is not allowed to have the same colors.
//@param _constraintBonus : the bonus the miner will get, 
//if the answer satisfy the constraint
function addConstraints(
        uint256[] memory _constraint,
        uint256 _constraintBonus
    ) public onlyOwner beforeLaunch;

//@param _varible : _varible = 2, means we are trying to add domains for X2
//@param _domain : _domain = [0,1,3], means that X2 can only get colors from 
//color No.0, No.1 and No.3.
function addDomain(uint256 _varible, uint256[] memory _domain)
        public
        onlyOwner
        beforeLaunch
```

**commit Answer**

```solidity
//@param _hash: the hash of the answer and msg.sender address, 
//which uint(keccak256(abi.encodePacked(uint[], address(msg.sender))))
//@param _bonusLevel: the total bonus of the answer
 function commitAnswer(uint256 _hash, uint256 _bonusLevel) external;

```

**reveal Answer**

```solidity
//@param _decodeAnswer : [0,3,2,0,...1,6], means that X0 with color No.0,
//X1 with color No.3, X2 with color No.2...
function revealAnswer(uint256[] calldata _decodeAnswer)
      external
      returns (bool _result);
```

**settlement**

```solidity
///@notice when "now > tSettlement", anyone can call this funtion to raise settlement,
///while usually the miner who wins will call this function.
function settlement() external payable;
```

**retrieveBonus**

```solidity
  ///@notice after the Retrieve Time, the owner can claim the deposit inside of the contract
  function retrieveBonus() external payable returns (bool _result);
```

**other debugging function**

```solidity
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
```

## Detailed Illustration

![PoCW_full_illustration.jpg](Document%20fa6ce4d2c0a74cac96827ad0a011b487/PoCW_full_illustration.jpg)