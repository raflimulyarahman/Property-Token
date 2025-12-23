// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IndonesiaPropertyToken
 * @notice ERC-20 token representing fractional ownership of Indonesian real estate
 * @dev Implements compliance checks via KYCRegistry
 *
 * Reference: https://www.erc3643.org/
 */
contract IndonesiaPropertyToken {

    // ============ TOKEN METADATA ============

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    // ============ PROPERTY INFO ============

    struct PropertyInfo {
        string propertyName;        // "Apartemen Sudirman Tower"
        string location;            // "Jakarta Selatan"
        uint256 totalValue;         // Total property value in IDR
        uint256 totalTokens;        // Total tokens representing 100%
        string legalDocument;       // IPFS hash of legal docs
        bool isActive;
    }

    PropertyInfo public property;

    // ============ COMPLIANCE ============

    address public admin;
    address public kycRegistry;     // KYCRegistry contract address

    mapping(address => bool) public frozen;     // Frozen accounts
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    // Investment limits
    uint256 public minInvestment = 1 ether;         // Min 1 token
    uint256 public maxInvestment = 1000 ether;      // Max 1000 tokens

    // ============ EVENTS ============

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AccountFrozen(address indexed account, string reason);
    event AccountUnfrozen(address indexed account);
    event PropertyUpdated(string propertyName, uint256 totalValue);

    // ============ MODIFIERS ============

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier notFrozen(address _account) {
        require(!frozen[_account], "Account is frozen");
        _;
    }

    modifier onlyVerified(address _account) {
        require(_isVerified(_account), "Not KYC verified");
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Deploy property token
     * @param _name Token name (e.g., "Sudirman Tower Token")
     * @param _symbol Token symbol (e.g., "SDMN")
     * @param _kycRegistry Address of deployed KYCRegistry
     * @param _propertyName Name of the property
     * @param _location Property location
     * @param _totalValue Total property value in IDR
     * @param _totalTokens Total tokens to mint (representing 100%)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _kycRegistry,
        string memory _propertyName,
        string memory _location,
        uint256 _totalValue,
        uint256 _totalTokens
    ) {
        require(_kycRegistry != address(0), "Invalid KYC registry");

        name = _name;
        symbol = _symbol;
        admin = msg.sender;
        kycRegistry = _kycRegistry;

        property = PropertyInfo({
            propertyName: _propertyName,
            location: _location,
            totalValue: _totalValue,
            totalTokens: _totalTokens,
            legalDocument: "",
            isActive: true
        });

        // Mint all tokens to admin initially
        totalSupply = _totalTokens;
        balances[msg.sender] = _totalTokens;
        emit Transfer(address(0), msg.sender, _totalTokens);
    }

    // ============ ERC-20 FUNCTIONS ============

    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    /**
     * @notice Transfer tokens with compliance checks
     * @dev Both sender and receiver must be KYC verified and not frozen
     */
    function transfer(
        address _to,
        uint256 _value
    )
        public
        notFrozen(msg.sender)
        notFrozen(_to)
        returns (bool)
    {
        require(_to != address(0), "Invalid recipient");
        require(_isVerified(msg.sender), "Not KYC verified");
        require(_isVerified(_to), "Not KYC verified");
        require(balances[msg.sender] >= _value, "Insufficient balance");

        // Check investment limits for receiver
        uint256 newBalance = balances[_to] + _value;
        require(newBalance <= maxInvestment, "Exceeds max investment");

        balances[msg.sender] -= _value;
        balances[_to] += _value;

        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        public
        notFrozen(_from)
        notFrozen(_to)
        returns (bool)
    {
        require(_to != address(0), "Invalid recipient");
        require(_isVerified(_from), "Not KYC verified");
        require(_isVerified(_to), "Not KYC verified");
        require(balances[_from] >= _value, "Insufficient balance");
        require(allowances[_from][msg.sender] >= _value, "Insufficient allowance");

        uint256 newBalance = balances[_to] + _value;
        require(newBalance <= maxInvestment, "Exceeds max investment");

        balances[_from] -= _value;
        balances[_to] += _value;
        allowances[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);
        return true;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Freeze account (for AML/compliance)
     */
    function freezeAccount(
        address _account,
        string calldata _reason
    ) external onlyAdmin {
        frozen[_account] = true;
        emit AccountFrozen(_account, _reason);
    }

    /**
     * @notice Unfreeze account
     */
    function unfreezeAccount(address _account) external onlyAdmin {
        frozen[_account] = false;
        emit AccountUnfrozen(_account);
    }

    /**
     * @notice Force transfer (for legal compliance, recovery)
     */
    function forceTransfer(
        address _from,
        address _to,
        uint256 _value
    ) external onlyAdmin {
        require(balances[_from] >= _value, "Insufficient balance");

        balances[_from] -= _value;
        balances[_to] += _value;

        emit Transfer(_from, _to, _value);
    }

    /**
     * @notice Update property legal documents
     */
    function setLegalDocument(string calldata _ipfsHash) external onlyAdmin {
        property.legalDocument = _ipfsHash;
    }

    /**
     * @notice Update investment limits
     */
    function setInvestmentLimits(
        uint256 _min,
        uint256 _max
    ) external onlyAdmin {
        require(_min < _max, "Invalid limits");
        minInvestment = _min;
        maxInvestment = _max;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get ownership percentage
     */
    function getOwnershipPercent(address _owner) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        return (balances[_owner] * 10000) / totalSupply; // Returns basis points (100% = 10000)
    }

    /**
     * @notice Get token value in IDR
     */
    function getTokenValueIDR() public view returns (uint256) {
        if (property.totalTokens == 0) return 0;
        return property.totalValue / (property.totalTokens / 1 ether);
    }

    /**
     * @notice Check if transfer would be allowed
     */
    function canTransfer(
        address _from,
        address _to,
        uint256 _value
    ) public view returns (bool, string memory) {
        if (frozen[_from]) return (false, "Sender is frozen");
        if (frozen[_to]) return (false, "Receiver is frozen");
        if (!_isVerified(_from)) return (false, "Sender not KYC verified");
        if (!_isVerified(_to)) return (false, "Receiver not KYC verified");
        if (balances[_from] < _value) return (false, "Insufficient balance");
        if (balances[_to] + _value > maxInvestment) return (false, "Exceeds max investment");

        return (true, "Transfer allowed");
    }

    // ============ INTERNAL FUNCTIONS ============

    function _isVerified(address _account) internal view returns (bool) {
        // Admin is always verified
        if (_account == admin) return true;

        // Check KYC registry
        (bool success, bytes memory data) = kycRegistry.staticcall(
            abi.encodeWithSignature("isVerified(address)", _account)
        );

        if (!success) return false;
        return abi.decode(data, (bool));
    }
}