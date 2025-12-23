// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {KYCRegistry} from "../src/KYCRegistry.sol";
import {IndonesiaPropertyToken} from "../src/IndonesiaPropertyToken.sol";

contract IndonesiaPropertyTokenTest is Test {
    KYCRegistry public kyc;
    IndonesiaPropertyToken public token;

    // Test accounts
    address public admin;
    address public investor1;
    address public investor2;
    address public unverifiedUser;

    // Property constants
    string public constant TOKEN_NAME = "Sudirman Tower Token";
    string public constant TOKEN_SYMBOL = "SDMN";
    string public constant PROPERTY_NAME = "Apartemen Sudirman Tower";
    string public constant LOCATION = "Jakarta Selatan";
    uint256 public constant TOTAL_VALUE = 50_000_000_000; // Rp 50 Miliar
    uint256 public constant TOTAL_TOKENS = 10000 ether;   // 10,000 tokens

    // KYC constants
    uint16 public constant INDONESIA = 360;
    uint256 public constant VALID_DAYS = 365;

    // ============================================
    // SETUP
    // ============================================

    function setUp() public {
        admin = address(this);
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        unverifiedUser = makeAddr("unverifiedUser");

        // Deploy KYCRegistry first
        kyc = new KYCRegistry();

        // Deploy PropertyToken with KYCRegistry address
        token = new IndonesiaPropertyToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(kyc),
            PROPERTY_NAME,
            LOCATION,
            TOTAL_VALUE,
            TOTAL_TOKENS
        );

        // Register investors for KYC
        kyc.registerInvestor(investor1, KYCRegistry.KYCLevel.VERIFIED, INDONESIA, VALID_DAYS);
        kyc.registerInvestor(investor2, KYCRegistry.KYCLevel.BASIC, INDONESIA, VALID_DAYS);
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_ConstructorSetsTokenMetadata() public view {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.decimals(), 18);
    }

    function test_ConstructorSetsPropertyInfo() public view {
        (
            string memory propertyName,
            string memory location,
            uint256 totalValue,
            uint256 totalTokens,
            ,
            bool isActive
        ) = token.property();

        assertEq(propertyName, PROPERTY_NAME);
        assertEq(location, LOCATION);
        assertEq(totalValue, TOTAL_VALUE);
        assertEq(totalTokens, TOTAL_TOKENS);
        assertTrue(isActive);
    }

    function test_ConstructorMintsTokensToAdmin() public view {
        assertEq(token.totalSupply(), TOTAL_TOKENS);
        assertEq(token.balanceOf(admin), TOTAL_TOKENS);
    }

    function test_ConstructorSetsKYCRegistry() public view {
        assertEq(token.kycRegistry(), address(kyc));
    }

    function test_RevertWhen_ConstructorWithZeroKYCRegistry() public {
        vm.expectRevert("Invalid KYC registry");
        new IndonesiaPropertyToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(0),  // Invalid
            PROPERTY_NAME,
            LOCATION,
            TOTAL_VALUE,
            TOTAL_TOKENS
        );
    }

    // ============================================
    // TRANSFER TESTS (COMPLIANCE)
    // ============================================

    function test_TransferToVerifiedInvestor() public {
        uint256 transferAmount = 100 ether;

        // Admin transfers to verified investor
        token.transfer(investor1, transferAmount);

        assertEq(token.balanceOf(investor1), transferAmount);
        assertEq(token.balanceOf(admin), TOTAL_TOKENS - transferAmount);
    }

    function test_TransferEmitsEvent() public {
        uint256 transferAmount = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit IndonesiaPropertyToken.Transfer(admin, investor1, transferAmount);

        token.transfer(investor1, transferAmount);
    }

    function test_TransferBetweenVerifiedInvestors() public {
        // Admin sends to investor1
        token.transfer(investor1, 500 ether);

        // Investor1 sends to investor2
        vm.prank(investor1);
        token.transfer(investor2, 200 ether);

        assertEq(token.balanceOf(investor1), 300 ether);
        assertEq(token.balanceOf(investor2), 200 ether);
    }

    function test_RevertWhen_TransferToUnverifiedUser() public {
        vm.expectRevert("Not KYC verified");
        token.transfer(unverifiedUser, 100 ether);
    }

    function test_RevertWhen_TransferFromUnverifiedUser() public {
        // First, force transfer some tokens to unverified user (admin can do this)
        token.forceTransfer(admin, unverifiedUser, 100 ether);

        // Unverified user tries to transfer
        vm.prank(unverifiedUser);
        vm.expectRevert("Not KYC verified");
        token.transfer(investor1, 50 ether);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(investor1);
        vm.expectRevert("Insufficient balance");
        token.transfer(investor2, 100 ether);
    }

    function test_RevertWhen_TransferToZeroAddress() public {
        vm.expectRevert("Invalid recipient");
        token.transfer(address(0), 100 ether);
    }

    function test_RevertWhen_TransferExceedsMaxInvestment() public {
        // Max investment is 1000 ether by default
        // Try to transfer more than max
        vm.expectRevert("Exceeds max investment");
        token.transfer(investor1, 1001 ether);
    }

    // ============================================
    // TRANSFER FROM TESTS
    // ============================================

    function test_TransferFrom() public {
        // Admin approves investor1 to spend tokens
        token.approve(investor1, 500 ether);

        // Investor1 transfers from admin to investor2
        vm.prank(investor1);
        token.transferFrom(admin, investor2, 200 ether);

        assertEq(token.balanceOf(investor2), 200 ether);
        assertEq(token.allowance(admin, investor1), 300 ether);
    }

    function test_RevertWhen_TransferFromInsufficientAllowance() public {
        token.approve(investor1, 100 ether);

        vm.prank(investor1);
        vm.expectRevert("Insufficient allowance");
        token.transferFrom(admin, investor2, 200 ether);
    }

    // ============================================
    // APPROVE TESTS
    // ============================================

    function test_Approve() public {
        token.approve(investor1, 500 ether);
        assertEq(token.allowance(admin, investor1), 500 ether);
    }

    function test_ApproveEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IndonesiaPropertyToken.Approval(admin, investor1, 500 ether);

        token.approve(investor1, 500 ether);
    }

    // ============================================
    // FREEZE ACCOUNT TESTS
    // ============================================

    function test_FreezeAccount() public {
        token.freezeAccount(investor1, "Suspicious activity");

        assertTrue(token.frozen(investor1));
    }

    function test_FreezeAccountEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IndonesiaPropertyToken.AccountFrozen(investor1, "AML investigation");

        token.freezeAccount(investor1, "AML investigation");
    }

    function test_RevertWhen_TransferFromFrozenAccount() public {
        // Give investor1 some tokens
        token.transfer(investor1, 500 ether);

        // Freeze investor1
        token.freezeAccount(investor1, "AML investigation");

        // Investor1 tries to transfer
        vm.prank(investor1);
        vm.expectRevert("Account is frozen");
        token.transfer(investor2, 100 ether);
    }

    function test_RevertWhen_TransferToFrozenAccount() public {
        // Freeze investor1
        token.freezeAccount(investor1, "AML investigation");

        // Admin tries to transfer to frozen account
        vm.expectRevert("Account is frozen");
        token.transfer(investor1, 100 ether);
    }

    function test_RevertWhen_NonAdminFreezes() public {
        vm.prank(investor1);
        vm.expectRevert("Only admin");
        token.freezeAccount(investor2, "Suspicious");
    }

    // ============================================
    // UNFREEZE ACCOUNT TESTS
    // ============================================

    function test_UnfreezeAccount() public {
        token.freezeAccount(investor1, "Investigation");
        token.unfreezeAccount(investor1);

        assertFalse(token.frozen(investor1));
    }

    function test_UnfreezeAccountEmitsEvent() public {
        token.freezeAccount(investor1, "Investigation");

        vm.expectEmit(true, false, false, false);
        emit IndonesiaPropertyToken.AccountUnfrozen(investor1);

        token.unfreezeAccount(investor1);
    }

    function test_TransferAfterUnfreeze() public {
        // Give investor1 tokens
        token.transfer(investor1, 500 ether);

        // Freeze then unfreeze
        token.freezeAccount(investor1, "Investigation");
        token.unfreezeAccount(investor1);

        // Should be able to transfer now
        vm.prank(investor1);
        token.transfer(investor2, 100 ether);

        assertEq(token.balanceOf(investor2), 100 ether);
    }

    // ============================================
    // FORCE TRANSFER TESTS
    // ============================================

    function test_ForceTransfer() public {
        // Give investor1 tokens
        token.transfer(investor1, 500 ether);

        // Force transfer (even if frozen or unverified destination)
        token.forceTransfer(investor1, unverifiedUser, 200 ether);

        assertEq(token.balanceOf(investor1), 300 ether);
        assertEq(token.balanceOf(unverifiedUser), 200 ether);
    }

    function test_ForceTransferFromFrozenAccount() public {
        token.transfer(investor1, 500 ether);
        token.freezeAccount(investor1, "Court order");

        // Admin can still force transfer from frozen account
        token.forceTransfer(investor1, investor2, 300 ether);

        assertEq(token.balanceOf(investor2), 300 ether);
    }

    function test_ForceTransferEmitsEvent() public {
        token.transfer(investor1, 500 ether);

        vm.expectEmit(true, true, false, true);
        emit IndonesiaPropertyToken.Transfer(investor1, investor2, 200 ether);

        token.forceTransfer(investor1, investor2, 200 ether);
    }

    function test_RevertWhen_NonAdminForceTransfers() public {
        token.transfer(investor1, 500 ether);

        vm.prank(investor1);
        vm.expectRevert("Only admin");
        token.forceTransfer(investor1, investor2, 100 ether);
    }

    function test_RevertWhen_ForceTransferInsufficientBalance() public {
        vm.expectRevert("Insufficient balance");
        token.forceTransfer(investor1, investor2, 100 ether);
    }

    // ============================================
    // SET LEGAL DOCUMENT TESTS
    // ============================================

    function test_SetLegalDocument() public {
        string memory ipfsHash = "QmXyz123456789...";
        token.setLegalDocument(ipfsHash);

        (,,,, string memory legalDoc,) = token.property();
        assertEq(legalDoc, ipfsHash);
    }

    function test_RevertWhen_NonAdminSetsLegalDocument() public {
        vm.prank(investor1);
        vm.expectRevert("Only admin");
        token.setLegalDocument("QmXyz...");
    }

    // ============================================
    // SET INVESTMENT LIMITS TESTS
    // ============================================

    function test_SetInvestmentLimits() public {
        token.setInvestmentLimits(0.5 ether, 2000 ether);

        assertEq(token.minInvestment(), 0.5 ether);
        assertEq(token.maxInvestment(), 2000 ether);
    }

    function test_RevertWhen_InvalidLimits() public {
        vm.expectRevert("Invalid limits");
        token.setInvestmentLimits(1000 ether, 500 ether); // min > max
    }

    function test_RevertWhen_NonAdminSetsLimits() public {
        vm.prank(investor1);
        vm.expectRevert("Only admin");
        token.setInvestmentLimits(1 ether, 500 ether);
    }

    // ============================================
    // VIEW FUNCTIONS TESTS
    // ============================================

    function test_GetOwnershipPercent() public {
        // Transfer 1000 tokens (10% of 10000)
        token.transfer(investor1, 1000 ether);

        uint256 ownershipBps = token.getOwnershipPercent(investor1);
        assertEq(ownershipBps, 1000); // 1000 basis points = 10%
    }

    function test_GetOwnershipPercentAdmin() public view {
        // Admin owns 100% initially
        uint256 ownershipBps = token.getOwnershipPercent(admin);
        assertEq(ownershipBps, 10000); // 10000 basis points = 100%
    }

    function test_GetTokenValueIDR() public view {
        uint256 tokenValue = token.getTokenValueIDR();
        // 50 Miliar / 10000 tokens = 5 Juta per token
        assertEq(tokenValue, 5_000_000);
    }

    function test_CanTransferReturnsTrue() public view {
        (bool canTransfer, string memory reason) = token.canTransfer(admin, investor1, 100 ether);
        assertTrue(canTransfer);
        assertEq(reason, "Transfer allowed");
    }

    function test_CanTransferReturnsFalseForFrozenSender() public {
        token.transfer(investor1, 500 ether);
        token.freezeAccount(investor1, "Investigation");

        (bool canTransfer, string memory reason) = token.canTransfer(investor1, investor2, 100 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Sender is frozen");
    }

    function test_CanTransferReturnsFalseForFrozenReceiver() public {
        token.freezeAccount(investor1, "Investigation");

        (bool canTransfer, string memory reason) = token.canTransfer(admin, investor1, 100 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Receiver is frozen");
    }

    function test_CanTransferReturnsFalseForUnverifiedSender() public {
        token.forceTransfer(admin, unverifiedUser, 100 ether);

        (bool canTransfer, string memory reason) = token.canTransfer(unverifiedUser, investor1, 50 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Sender not KYC verified");
    }

    function test_CanTransferReturnsFalseForUnverifiedReceiver() public {
        (bool canTransfer, string memory reason) = token.canTransfer(admin, unverifiedUser, 100 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Receiver not KYC verified");
    }

    function test_CanTransferReturnsFalseForInsufficientBalance() public {
        (bool canTransfer, string memory reason) = token.canTransfer(investor1, investor2, 100 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Insufficient balance");
    }

    function test_CanTransferReturnsFalseForExceedsMax() public {
        (bool canTransfer, string memory reason) = token.canTransfer(admin, investor1, 1001 ether);
        assertFalse(canTransfer);
        assertEq(reason, "Exceeds max investment");
    }

    // ============================================
    // INTEGRATION TESTS: KYC EXPIRY
    // ============================================

    function test_TransferFailsAfterKYCExpiry() public {
        // Give investor1 some tokens
        token.transfer(investor1, 500 ether);

        // Warp time past KYC expiry
        vm.warp(block.timestamp + VALID_DAYS * 1 days + 1);

        // Should fail because KYC expired
        vm.prank(investor1);
        vm.expectRevert("Not KYC verified");
        token.transfer(investor2, 100 ether);
    }

    function test_TransferSucceedsAfterKYCRenewal() public {
        token.transfer(investor1, 500 ether);

        // Warp time past expiry
        vm.warp(block.timestamp + VALID_DAYS * 1 days + 1);

        // Revoke and re-register (renewal) for both investors
        kyc.revokeInvestor(investor1);
        kyc.registerInvestor(investor1, KYCRegistry.KYCLevel.VERIFIED, INDONESIA, VALID_DAYS);

        kyc.revokeInvestor(investor2);
        kyc.registerInvestor(investor2, KYCRegistry.KYCLevel.BASIC, INDONESIA, VALID_DAYS);

        // Should work now
        vm.prank(investor1);
        token.transfer(investor2, 100 ether);

        assertEq(token.balanceOf(investor2), 100 ether);
    }

    // ============================================
    // INTEGRATION TESTS: KYC REVOCATION
    // ============================================

    function test_TransferFailsAfterKYCRevoked() public {
        token.transfer(investor1, 500 ether);

        // Revoke KYC
        kyc.revokeInvestor(investor1);

        // Should fail
        vm.prank(investor1);
        vm.expectRevert("Not KYC verified");
        token.transfer(investor2, 100 ether);
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_TransferAmount(uint256 amount) public {
        // Bound amount to valid range (min 1 wei, max 1000 ether due to maxInvestment)
        amount = bound(amount, 1, 1000 ether);

        token.transfer(investor1, amount);

        assertEq(token.balanceOf(investor1), amount);
        assertEq(token.balanceOf(admin), TOTAL_TOKENS - amount);
    }

    function testFuzz_OwnershipPercent(uint256 balance) public {
        balance = bound(balance, 1, 1000 ether);

        token.transfer(investor1, balance);

        uint256 ownershipBps = token.getOwnershipPercent(investor1);
        uint256 expectedBps = (balance * 10000) / TOTAL_TOKENS;

        assertEq(ownershipBps, expectedBps);
    }

    function testFuzz_MultipleTransfers(uint256 amount1, uint256 amount2) public {
        // Bound amounts
        amount1 = bound(amount1, 1, 500 ether);
        amount2 = bound(amount2, 1, 500 ether);

        // Transfer to investor1
        token.transfer(investor1, amount1);

        // Transfer to investor2
        token.transfer(investor2, amount2);

        assertEq(token.balanceOf(investor1), amount1);
        assertEq(token.balanceOf(investor2), amount2);
        assertEq(token.balanceOf(admin), TOTAL_TOKENS - amount1 - amount2);
    }
}