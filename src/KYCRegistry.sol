// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title KYCRegistry
 * @notice Manages KYC verification for IndonesiaPropertyToken
 * @dev Deploy this contract first, then use its address in PropertyToken
 *
 * Tutorial: https://docs.openzeppelin.com/contracts
 */
contract KYCRegistry {

    // ============ STATE VARIABLES ============

    address public admin;

    // KYC Levels
    enum KYCLevel {
        NONE,           // 0 - Belum KYC
        BASIC,          // 1 - KYC dasar (KTP)
        VERIFIED,       // 2 - KYC lengkap (KTP + NPWP)
        ACCREDITED      // 3 - Investor terakreditasi
    }

    struct Investor {
        KYCLevel level;
        uint256 expiryDate;
        uint16 countryCode;     // 360 = Indonesia
        bool isActive;
    }

    // Mapping: wallet address => investor data
    mapping(address => Investor) public investors;

    // Total registered investors
    uint256 public totalInvestors;

    // ============ EVENTS ============

    event InvestorRegistered(address indexed investor, KYCLevel level);
    event InvestorUpdated(address indexed investor, KYCLevel newLevel);
    event InvestorRevoked(address indexed investor);

    // ============ MODIFIERS ============

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor() {
        admin = msg.sender;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Register new investor after KYC verification
     * @param _investor Wallet address of investor
     * @param _level KYC level (1-3)
     * @param _countryCode Country code (360 for Indonesia)
     * @param _validDays How many days KYC is valid
     */
    function registerInvestor(
        address _investor,
        KYCLevel _level,
        uint16 _countryCode,
        uint256 _validDays
    ) external onlyAdmin {
        require(_investor != address(0), "Invalid address");
        require(_level != KYCLevel.NONE, "Invalid KYC level");
        require(!investors[_investor].isActive, "Already registered");

        investors[_investor] = Investor({
            level: _level,
            expiryDate: block.timestamp + (_validDays * 1 days),
            countryCode: _countryCode,
            isActive: true
        });

        totalInvestors++;
        emit InvestorRegistered(_investor, _level);
    }

    /**
     * @notice Update investor KYC level
     */
    function updateInvestor(
        address _investor,
        KYCLevel _newLevel
    ) external onlyAdmin {
        require(investors[_investor].isActive, "Not registered");
        investors[_investor].level = _newLevel;
        emit InvestorUpdated(_investor, _newLevel);
    }

    /**
     * @notice Revoke investor KYC (blacklist)
     */
    function revokeInvestor(address _investor) external onlyAdmin {
        require(investors[_investor].isActive, "Not registered");
        investors[_investor].isActive = false;
        totalInvestors--;
        emit InvestorRevoked(_investor);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Check if investor is verified and active
     */
    function isVerified(address _investor) public view returns (bool) {
        Investor memory inv = investors[_investor];

        if (!inv.isActive) return false;
        if (inv.level == KYCLevel.NONE) return false;
        if (block.timestamp > inv.expiryDate) return false;

        return true;
    }

    /**
     * @notice Check if investor meets minimum KYC level
     */
    function meetsLevel(
        address _investor,
        KYCLevel _requiredLevel
    ) public view returns (bool) {
        if (!isVerified(_investor)) return false;
        return uint8(investors[_investor].level) >= uint8(_requiredLevel);
    }

    /**
     * @notice Get investor details
     */
    function getInvestor(address _investor) external view returns (
        KYCLevel level,
        uint256 expiryDate,
        uint16 countryCode,
        bool isActive
    ) {
        Investor memory inv = investors[_investor];
        return (inv.level, inv.expiryDate, inv.countryCode, inv.isActive);
    }
}