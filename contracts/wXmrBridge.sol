// SPDX-License-Identifier: LGPLv3
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IWXMR {
    function mintFromSwap(address to, uint256 amount, bytes32 swapId) external;
    function burnForSwap(address from, uint256 amount, bytes32 swapId) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title WXMRBridge
 * @dev Bridge contract to handle atomic swaps between WXMR and XMR using time-locked addresses
 * Simplified version with fixed fee and streamlined role structure
 */
contract WXMRBridge is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SWAP_FACILITATOR_ROLE = keccak256("SWAP_FACILITATOR_ROLE");
    
    IWXMR public wxmrToken;
    bool public tokenInitialized = false;
    
    // Fixed fee of 27 basis points (0.27%)
    uint256 public constant FEE_PERCENTAGE = 27; // 0.27% fee (scaled by 10^4)
    
    // Fee collection
    uint256 public accumulatedFees;
    uint256 public constant MAX_ACCUMULATED_FEES = 1000 * 1e12; // Cap on accumulated fees (1000 XMR)
    
    // Liquidity pool parameters
    uint256 public minLiquidity = 1 * 1e12; // Minimum liquidity required (1 XMR)
    uint256 public maxDailyMint = 10 * 1e12; // Maximum daily mint (10 XMR)
    uint256 public dailyMinted = 0;
    uint256 public lastResetTime = block.timestamp;
    
    // Reserve tracking
    uint256 public totalReserve; // Total XMR in reserve
    uint256 public totalLiquidityCommitted; // Total liquidity committed by providers
    
    // Default timelock duration in seconds (24 hours)
    uint256 public defaultTimelockDuration = 24 hours;
    uint256 public minTimelockDuration = 1 hours;
    uint256 public maxTimelockDuration = 7 days;
    
    // Mapping from swap IDs to pending swaps
    mapping(bytes32 => TimeLockSwap) public pendingSwaps;
    
    // Stores liquidity provider information
    mapping(address => LiquidityProvider) public liquidityProviders;
    EnumerableSet.AddressSet private liquidityProviderSet;
    
    // Limit to one active liquidity pool per address
    uint256 public maxPoolsPerAddress = 1;
    
    // Minimum liquidity required per provider
    uint256 public minLiquidityPerProvider = 0.1 * 1e12; // 0.1 XMR
    
    // Cooldown period for liquidity withdrawals
    uint256 public liquidityWithdrawalCooldown = 1 days;
    
    // Authorized signers for verification
    mapping(address => bool) public authorizedSigners;
    
    struct TimeLockSwap {
        address recipient;          // The EVM address receiving WXMR or that sent WXMR
        uint256 amount;             // Amount of XMR/WXMR being swapped
        bool isXmrToEvm;            // Direction of the swap
        uint256 timestamp;          // When the swap was initiated
        bool completed;             // Whether the swap has been completed
        bool refunded;              // Whether the swap has been refunded
        bytes32 timelockId;         // Identifier for the time-locked address
        bytes32 secretHash;         // Hash of the secret needed to unlock funds
        uint256 timelockExpiryTime; // When the time-lock expires
        string xmrAddress;          // Monero address (for EVM->XMR)
        bytes32 timelockProof;      // Proof that the time-lock address was properly set up
        address initiator;          // Address that initiated this swap
        bytes signature;            // Signature for verification
        uint256 minAmountOut;       // Minimum amount out (slippage protection)
    }
    
    struct LiquidityProvider {
        uint256 xmrCommitted;      // Amount of XMR committed to the protocol
        uint256 wxmrHolding;       // Amount of WXMR tokens held
        uint256 pendingDeposits;   // Number of pending deposits
        uint256 accumulatedFees;   // Fees accumulated for this provider
        bool isActive;             // Whether the provider is active
        uint256 lastWithdrawalTime; // Last time liquidity was withdrawn
    }
    
    // Events
    event SwapInitiatedToEVM(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount, 
        bytes32 timelockId, 
        uint256 timelockExpiryTime,
        address initiator
    );
    
    event SwapCompletedToEVM(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount, 
        bytes32 secret
    );
    
    event SwapInitiatedToXMR(
        bytes32 indexed swapId, 
        address indexed sender, 
        uint256 amount, 
        string xmrAddress, 
        bytes32 timelockId, 
        uint256 timelockExpiryTime,
        address initiator
    );
    
    event SwapCompletedToXMR(
        bytes32 indexed swapId, 
        bytes32 indexed secret
    );
    
    event SwapRefunded(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount
    );
    
    event LiquidityAdded(
        address indexed provider, 
        uint256 xmrAmount, 
        uint256 wxmrAmount
    );
    
    event LiquidityRemoved(
        address indexed provider, 
        uint256 xmrAmount, 
        uint256 wxmrAmount
    );
    
    event TokenInitialized(address indexed admin, address tokenAddress);
    
    event FeesDistributed(uint256 totalFees, uint256 providersRewarded);
    
    event FeesClaimed(address indexed provider, uint256 amount);
    
    event ExpiredSwapCleaned(bytes32 indexed swapId);
    
    event AuthorizedSignerAdded(address indexed signer);
    event AuthorizedSignerRemoved(address indexed signer);
    event LiquidityParametersUpdated(uint256 newMinLiquidity, uint256 newMaxDailyMint);
    event TimelockDurationUpdated(uint256 newDuration);
    event MaxPoolsPerAddressUpdated(uint256 newMaxPools);
    
    /**
     * @dev Modifier to check if a swap exists and is not completed or refunded
     * @param swapId The ID of the swap
     */
    modifier validSwap(bytes32 swapId) {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        require(swap.timestamp > 0, "Swap does not exist");
        require(!swap.completed, "Swap already completed");
        require(!swap.refunded, "Swap already refunded");
        _;
    }
    
    /**
     * @dev Modifier to check if the token has been initialized
     */
    modifier initialized() {
        require(tokenInitialized, "Token not initialized");
        _;
    }
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SWAP_FACILITATOR_ROLE, msg.sender);
        
        // Add the deployer as an authorized signer
        authorizedSigners[msg.sender] = true;
        emit AuthorizedSignerAdded(msg.sender);
    }
    
    /**
     * @dev Initialize the WXMR token address
     * @param _wxmrAddress The address of the WXMR token contract
     */
    function initializeToken(address _wxmrAddress) external onlyRole(ADMIN_ROLE) {
        require(!tokenInitialized, "Token already initialized");
        require(_wxmrAddress != address(0), "Invalid token address");
        
        wxmrToken = IWXMR(_wxmrAddress);
        tokenInitialized = true;
        
        emit TokenInitialized(msg.sender, _wxmrAddress);
    }
    
    /**
     * @dev Add an authorized signer
     * @param signer The address to add as an authorized signer
     */
    function addAuthorizedSigner(address signer) external onlyRole(ADMIN_ROLE) {
        require(signer != address(0), "Invalid signer address");
        require(!authorizedSigners[signer], "Signer already authorized");
        
        authorizedSigners[signer] = true;
        
        emit AuthorizedSignerAdded(signer);
    }
    
    /**
     * @dev Remove an authorized signer
     * @param signer The address to remove as an authorized signer
     */
    function removeAuthorizedSigner(address signer) external onlyRole(ADMIN_ROLE) {
        require(authorizedSigners[signer], "Signer not authorized");
        
        authorizedSigners[signer] = false;
        
        emit AuthorizedSignerRemoved(signer);
    }
    
    /**
     * @dev Update liquidity parameters
     * @param _minLiquidity New minimum liquidity
     * @param _maxDailyMint New maximum daily mint
     */
    function updateLiquidityParameters(uint256 _minLiquidity, uint256 _maxDailyMint) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        minLiquidity = _minLiquidity;
        maxDailyMint = _maxDailyMint;
        
        emit LiquidityParametersUpdated(_minLiquidity, _maxDailyMint);
    }
    
    /**
     * @dev Update timelock duration
     * @param _defaultTimelockDuration New default timelock duration
     */
    function updateTimelockDuration(uint256 _defaultTimelockDuration) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_defaultTimelockDuration >= minTimelockDuration, "Duration too short");
        require(_defaultTimelockDuration <= maxTimelockDuration, "Duration too long");
        
        defaultTimelockDuration = _defaultTimelockDuration;
        
        emit TimelockDurationUpdated(_defaultTimelockDuration);
    }
    
    /**
     * @dev Update max pools per address
     * @param _maxPoolsPerAddress New max pools per address
     */
    function updateMaxPoolsPerAddress(uint256 _maxPoolsPerAddress) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_maxPoolsPerAddress > 0, "Max pools must be > 0");
        
        maxPoolsPerAddress = _maxPoolsPerAddress;
        
        emit MaxPoolsPerAddressUpdated(_maxPoolsPerAddress);
    }
    
    /**
     * @dev Distribute accumulated fees to liquidity providers proportionally
     */
    function distributeFees() external nonReentrant onlyRole(ADMIN_ROLE) initialized {
        require(accumulatedFees > 0, "No fees to distribute");
        require(totalLiquidityCommitted > 0, "No liquidity providers");
        
        uint256 totalFees = accumulatedFees;
        // Set accumulated fees to 0 first to prevent reentrancy
        accumulatedFees = 0;
        
        uint256 providersRewarded = 0;
        
        // Distribute fees proportionally to liquidity providers by calculating shares
        for (uint256 i = 0; i < liquidityProviderSet.length(); i++) {
            address provider = liquidityProviderSet.at(i);
            LiquidityProvider storage lp = liquidityProviders[provider];
            
            if (lp.isActive && lp.xmrCommitted > 0) {
                // Calculate provider's share of fees based on their proportion of total liquidity
                uint256 providerShare = (totalFees * lp.xmrCommitted) / totalLiquidityCommitted;
                
                if (providerShare > 0) {
                    lp.accumulatedFees += providerShare;
                    providersRewarded++;
                }
            }
        }
        
        emit FeesDistributed(totalFees, providersRewarded);
    }
    
    /**
     * @dev Allow a liquidity provider to claim their accumulated fees
     */
    function claimFees() external nonReentrant initialized {
        LiquidityProvider storage lp = liquidityProviders[msg.sender];
        require(lp.isActive, "Not an active liquidity provider");
        require(lp.accumulatedFees > 0, "No fees to claim");
        
        uint256 feeAmount = lp.accumulatedFees;
        // Set fees to 0 first to prevent reentrancy
        lp.accumulatedFees = 0;
        
        // Generate a unique ID for this fee claim
        bytes32 feeClaimId = keccak256(abi.encodePacked(
            "FEE_CLAIM",
            msg.sender,
            feeAmount,
            block.timestamp
        ));
        
        // Mint the fee amount as WXMR to the provider
        wxmrToken.mintFromSwap(msg.sender, feeAmount, feeClaimId);
        
        emit FeesClaimed(msg.sender, feeAmount);
    }
    
    /**
     * @dev Clean up an expired swap
     * @param swapId The ID of the swap to clean up
     */
    function cleanExpiredSwap(bytes32 swapId) external onlyRole(ADMIN_ROLE) validSwap(swapId) {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        
        // Check if the timelock has expired
        require(block.timestamp > swap.timelockExpiryTime, "Swap not expired yet");
        
        // Check if this is a liquidity deposit
        if (keccak256(abi.encodePacked(swap.xmrAddress)) == keccak256(abi.encodePacked("LIQUIDITY"))) {
            // Reduce pending deposit count
            LiquidityProvider storage lp = liquidityProviders[swap.recipient];
            if (lp.pendingDeposits > 0) {
                lp.pendingDeposits--;
            }
        }
        
        // Mark as cleaned up (use refunded flag for this purpose)
        swap.refunded = true;
        
        emit ExpiredSwapCleaned(swapId);
    }
    
    /**
     * @dev Initiate a XMR->EVM swap using a time-locked Monero address
     * @param recipient The recipient of the WXMR tokens
     * @param amount The amount of XMR being swapped
     * @param timelockId The identifier for the time-locked Monero address
     * @param secretHash Hash of the secret used to unlock the time-locked address
     * @param timelockProof Proof that the time-lock was properly set up
     * @param timelockExpiry Timestamp when the time-lock expires
     * @param signature Signature for authentication
     */
    function initiateXmrToEvmSwap(
        address recipient, 
        uint256 amount, 
        bytes32 timelockId,
        bytes32 secretHash,
        bytes32 timelockProof,
        uint256 timelockExpiry,
        bytes calldata signature
    ) 
        external 
        onlyRole(SWAP_FACILITATOR_ROLE)
        initialized
        returns (bytes32)
    {
        require(amount > 0, "Amount must be greater than zero");
        require(timelockExpiry > block.timestamp, "Timelock already expired");
        require(isValidEvmAddress(recipient), "Invalid recipient address");
        
        // Create the message hash for signature verification
        bytes32 messageHash = keccak256(abi.encodePacked(
            recipient,
            amount,
            timelockId,
            secretHash,
            timelockExpiry
        ));
        
        // Verify the signature comes from an authorized signer
        address signer = verifySignature(messageHash, signature);
        require(authorizedSigners[signer], "Signature not from authorized signer");
        
        // Calculate fee and final amount using fixed fee percentage
        uint256 fee = (amount * FEE_PERCENTAGE) / 10000;
        uint256 finalAmount = amount - fee;
        
        // Prevent fee accumulation overflow
        require(accumulatedFees + fee <= MAX_ACCUMULATED_FEES, "Fee accumulation limit reached");
        
        // Accumulate fees for later distribution
        accumulatedFees += fee;
        
        bytes32 swapId = keccak256(abi.encodePacked(
            recipient,
            amount,
            timelockId,
            secretHash,
            block.timestamp
        ));
        
        // Ensure swap doesn't already exist
        require(pendingSwaps[swapId].timestamp == 0, "Swap already exists");
        
        pendingSwaps[swapId] = TimeLockSwap({
            recipient: recipient,
            amount: finalAmount,
            isXmrToEvm: true,
            timestamp: block.timestamp,
            completed: false,
            refunded: false,
            timelockId: timelockId,
            secretHash: secretHash,
            timelockExpiryTime: timelockExpiry,
            xmrAddress: "",
            timelockProof: timelockProof,
            initiator: msg.sender,
            signature: signature,
            minAmountOut: finalAmount // No slippage for this direction
        });
        
        emit SwapInitiatedToEVM(
            swapId, 
            recipient, 
            finalAmount, 
            timelockId, 
            timelockExpiry,
            msg.sender
        );
        
        return swapId;
    }
    
    /**
     * @dev Complete a XMR->EVM swap by revealing the secret
     * @param swapId The ID of the swap
     * @param secret The secret that unlocks the time-locked Monero address
     */
    function completeXmrToEvmSwap(bytes32 swapId, bytes32 secret) 
        external 
        nonReentrant
        initialized
        validSwap(swapId)
    {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        require(swap.isXmrToEvm, "Not an XMR to EVM swap");
        
        // Verify the secret matches the hash
        require(keccak256(abi.encodePacked(secret)) == swap.secretHash, "Invalid secret");
        
        // Verify the swap hasn't expired
        require(block.timestamp < swap.timelockExpiryTime, "Swap has expired");
        
        // Reset daily mint limit if needed
        if (block.timestamp - lastResetTime >= 1 days) {
            dailyMinted = 0;
            lastResetTime = block.timestamp;
        }
        
        // Check daily mint limit
        require(dailyMinted + swap.amount <= maxDailyMint, "Daily mint limit reached");
        
        // Update state before external calls to prevent reentrancy
        swap.completed = true;
        dailyMinted += swap.amount;
        totalReserve += swap.amount;
        
        // Mint WXMR tokens to the recipient
        wxmrToken.mintFromSwap(swap.recipient, swap.amount, swapId);
        
        emit SwapCompletedToEVM(swapId, swap.recipient, swap.amount, secret);
    }
    
    /**
     * @dev Initiate a WXMR->XMR swap
     * @param amount The amount of WXMR to swap
     * @param xmrAddress The Monero address to receive the funds
     * @param timelockId Identifier for the time-locked Monero address
     * @param secretHash Hash of the secret needed to claim the XMR
     * @param minAmountOut Minimum amount to receive after fees (slippage protection)
     */
    function initiateEvmToXmrSwap(
        uint256 amount, 
        string calldata xmrAddress,
        bytes32 timelockId,
        bytes32 secretHash,
        uint256 minAmountOut
    ) 
        external 
        nonReentrant
        initialized
        returns (bytes32)
    {
        require(amount > 0, "Amount must be greater than zero");
        require(wxmrToken.balanceOf(msg.sender) >= amount, "Insufficient WXMR balance");
        require(isValidMoneroAddress(xmrAddress), "Invalid Monero address");
        
        // Calculate fee and final amount using fixed fee percentage
        uint256 fee = (amount * FEE_PERCENTAGE) / 10000;
        uint256 finalAmount = amount - fee;
        
        // Slippage protection
        require(finalAmount >= minAmountOut, "Slippage limit exceeded");
        
        // Prevent fee accumulation overflow
        require(accumulatedFees + fee <= MAX_ACCUMULATED_FEES, "Fee accumulation limit reached");
        
        // Accumulate fees for later distribution
        accumulatedFees += fee;
        
        // Calculate timelock expiry
        uint256 timelockExpiry = block.timestamp + defaultTimelockDuration;
        
        // Generate a unique swap ID
        bytes32 swapId = keccak256(abi.encodePacked(
            msg.sender,
            amount,
            xmrAddress,
            timelockId,
            secretHash,
            block.timestamp
        ));
        
        // Create the swap record before external calls to prevent reentrancy
        pendingSwaps[swapId] = TimeLockSwap({
            recipient: msg.sender,
            amount: finalAmount,
            isXmrToEvm: false,
            timestamp: block.timestamp,
            completed: false,
            refunded: false,
            timelockId: timelockId,
            secretHash: secretHash,
            timelockExpiryTime: timelockExpiry,
            xmrAddress: xmrAddress,
            timelockProof: bytes32(0), // Will be set by the operator
            initiator: msg.sender,
            signature: new bytes(0),   // No signature yet
            minAmountOut: minAmountOut
        });
        
        // Update total reserve
        if (totalReserve >= finalAmount) {
            totalReserve -= finalAmount;
        } else {
            totalReserve = 0;
        }
        
        // Burn WXMR tokens after state updates to prevent reentrancy
        wxmrToken.burnForSwap(msg.sender, amount, swapId);
        
        emit SwapInitiatedToXMR(
            swapId, 
            msg.sender, 
            finalAmount, 
            xmrAddress, 
            timelockId, 
            timelockExpiry,
            msg.sender
        );
        
        return swapId;
    }
    
    /**
     * @dev Set the timelock proof for an EVM->XMR swap with signature verification
     * @param swapId The ID of the swap
     * @param timelockProof Proof that the time-locked Monero address was set up
     * @param signature Signature for verification
     */
    function setTimelockProof(
        bytes32 swapId, 
        bytes32 timelockProof, 
        bytes calldata signature
    ) 
        external 
        onlyRole(SWAP_FACILITATOR_ROLE)
        initialized
        validSwap(swapId)
    {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        require(!swap.isXmrToEvm, "Not an EVM to XMR swap");
        require(swap.timelockProof == bytes32(0), "Timelock proof already set");
        
        // Create the message hash for signature verification
        bytes32 messageHash = keccak256(abi.encodePacked(
            swapId,
            timelockProof
        ));
        
        // Verify the signature comes from an authorized signer
        address signer = verifySignature(messageHash, signature);
        require(authorizedSigners[signer], "Signature not from authorized signer");
        
        swap.timelockProof = timelockProof;
        swap.signature = signature;
    }
    
    /**
     * @dev Complete an EVM->XMR swap by revealing the secret
     * @param swapId The ID of the swap
     * @param secret The secret that unlocks the time-locked Monero address
     */
    function completeEvmToXmrSwap(bytes32 swapId, bytes32 secret) 
        external 
        nonReentrant
        initialized
        validSwap(swapId)
    {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        require(!swap.isXmrToEvm, "Not an EVM to XMR swap");
        require(swap.timelockProof != bytes32(0), "Timelock proof not set");
        
        // Verify the secret matches the hash
        require(keccak256(abi.encodePacked(secret)) == swap.secretHash, "Invalid secret");
        
        // Verify the swap hasn't expired
        require(block.timestamp < swap.timelockExpiryTime, "Swap has expired");
        
        // Update state
        swap.completed = true;
        
        emit SwapCompletedToXMR(swapId, secret);
    }
    
    /**
     * @dev Refund a swap after the timelock has expired
     * @param swapId The ID of the swap to refund
     */
    function refundExpiredSwap(bytes32 swapId) 
        external 
        nonReentrant
        initialized
        validSwap(swapId)
    {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        
        // Only the recipient or the original initiator can refund
        require(
            swap.recipient == msg.sender || swap.initiator == msg.sender, 
            "Not authorized to refund"
        );
        
        // Check if the timelock has expired
        require(block.timestamp > swap.timelockExpiryTime, "Timelock not expired yet");
        
        // Mark as refunded before external calls to prevent reentrancy
        swap.refunded = true;
        
        if (swap.isXmrToEvm) {
            // For XMR->EVM swaps, no action needed on Ethereum side
            // The user can claim their refund on the Monero side after timelock expires
        } else {
            // For EVM->XMR swaps, mint new WXMR tokens back to the user
            totalReserve += swap.amount;
            wxmrToken.mintFromSwap(swap.recipient, swap.amount, swapId);
        }
        
        emit SwapRefunded(swapId, swap.recipient, swap.amount);
    }
    
    /**
     * @dev Add liquidity to the system (requires proof of XMR deposit)
     * @param xmrAmount The amount of XMR committed
     * @param timelockId Identifier of the time-locked deposit
     * @param secretHash Hash of the secret used for the time-lock
     * @param timelockProof Proof that the time-lock was properly set up
     * @param signature Signature for verification
     */
    function addLiquidity(
        uint256 xmrAmount,
        bytes32 timelockId,
        bytes32 secretHash,
        bytes32 timelockProof,
        bytes calldata signature
    ) 
        external 
        nonReentrant
        initialized
        returns (bytes32)
    {
        require(xmrAmount >= minLiquidityPerProvider, "Amount below minimum required");
        
        LiquidityProvider storage lp = liquidityProviders[msg.sender];
        
        // Check if this user already has an active pool or is within limits
        if (lp.isActive) {
            require(lp.pendingDeposits < maxPoolsPerAddress, "Too many pending deposits");
        }
        
        // Create the message hash for signature verification
        bytes32 messageHash = keccak256(abi.encodePacked(
            msg.sender,
            xmrAmount,
            timelockId,
            secretHash
        ));
        
        // Verify the signature comes from an authorized signer
        address signer = verifySignature(messageHash, signature);
        require(authorizedSigners[signer], "Signature not from authorized signer");
        
        bytes32 depositId = keccak256(abi.encodePacked(
            "LIQUIDITY", 
            msg.sender, 
            xmrAmount,
            timelockId,
            block.timestamp
        ));
        
        // Create a pseudo-swap for the liquidity deposit
        uint256 timelockExpiry = block.timestamp + defaultTimelockDuration;
        
        pendingSwaps[depositId] = TimeLockSwap({
            recipient: msg.sender,
            amount: xmrAmount,
            isXmrToEvm: true, // Treated as an XMR->EVM swap
            timestamp: block.timestamp,
            completed: false,
            refunded: false,
            timelockId: timelockId,
            secretHash: secretHash,
            timelockExpiryTime: timelockExpiry,
            xmrAddress: "LIQUIDITY", // Mark as liquidity deposit
            timelockProof: timelockProof,
            initiator: msg.sender,
            signature: signature,
            minAmountOut: xmrAmount // No slippage for liquidity
        });
        
        // Increment pending deposits counter
        lp.pendingDeposits++;
        
        return depositId;
    }
    
    /**
     * @dev Complete liquidity addition by revealing the secret
     * @param depositId The ID of the liquidity deposit
     * @param secret The secret that unlocks the time-locked deposit
     */
    function completeLiquidityDeposit(bytes32 depositId, bytes32 secret)
        external
        nonReentrant
        initialized
        validSwap(depositId)
    {
        TimeLockSwap storage deposit = pendingSwaps[depositId];
        
        require(deposit.recipient == msg.sender, "Not the deposit owner");
        require(keccak256(abi.encodePacked(deposit.xmrAddress)) == 
                keccak256(abi.encodePacked("LIQUIDITY")), "Not a liquidity deposit");
        
        // Verify the secret matches the hash
        require(keccak256(abi.encodePacked(secret)) == deposit.secretHash, "Invalid secret");
        
        // Verify the deposit hasn't expired
        require(block.timestamp < deposit.timelockExpiryTime, "Deposit has expired");
        
        address provider = deposit.recipient;
        uint256 xmrAmount = deposit.amount;
        
        LiquidityProvider storage lp = liquidityProviders[provider];
        
        // Update state before external calls to prevent reentrancy
        deposit.completed = true;
        
        if (!lp.isActive) {
            lp.isActive = true;
            liquidityProviderSet.add(provider);
        }
        
        lp.xmrCommitted += xmrAmount;
        totalLiquidityCommitted += xmrAmount;
        totalReserve += xmrAmount;
        
        // Decrement pending deposits counter
        if (lp.pendingDeposits > 0) {
            lp.pendingDeposits--;
        }
        
        // Mint WXMR equivalent to the provider
        wxmrToken.mintFromSwap(provider, xmrAmount, depositId);
        lp.wxmrHolding += xmrAmount;
        
        emit LiquidityAdded(provider, xmrAmount, xmrAmount);
    }
    
    /**
     * @dev Remove liquidity from the system
     * @param xmrAmount The amount of XMR to withdraw
     */
    function removeLiquidity(uint256 xmrAmount) 
        external 
        nonReentrant
        initialized
    {
        LiquidityProvider storage lp = liquidityProviders[msg.sender];
        require(lp.isActive, "Not a liquidity provider");
        require(xmrAmount > 0 && xmrAmount <= lp.xmrCommitted, "Invalid amount");
        
        // Check cooldown period
        require(
            block.timestamp >= lp.lastWithdrawalTime + liquidityWithdrawalCooldown, 
            "Withdrawal cooldown period not elapsed"
        );
        
        // Check if remaining liquidity meets minimum requirements
        uint256 remainingLiquidity = lp.xmrCommitted - xmrAmount;
        bool removingAll = remainingLiquidity == 0;
        
        if (!removingAll) {
            require(remainingLiquidity >= minLiquidityPerProvider, "Remaining amount below minimum");
        }
        
        // Check if the removal would break the global minimum liquidity
        require(totalReserve - xmrAmount >= minLiquidity, "Would break minimum liquidity");
        
        // Validate user's WXMR balance
        require(wxmrToken.balanceOf(msg.sender) >= xmrAmount, "Insufficient WXMR balance");
        
        // Generate withdrawal ID
        bytes32 withdrawalId = keccak256(abi.encodePacked(
            "LIQUIDITY_REMOVAL", 
            msg.sender, 
            xmrAmount,
            block.timestamp
        ));
        
        // Update state before external calls to prevent reentrancy
        lp.xmrCommitted -= xmrAmount;
        lp.wxmrHolding -= xmrAmount;
        totalReserve -= xmrAmount;
        totalLiquidityCommitted -= xmrAmount;
        lp.lastWithdrawalTime = block.timestamp;
        
        // If provider has no more committed XMR, remove from active providers list
        if (lp.xmrCommitted == 0) {
            lp.isActive = false;
            liquidityProviderSet.remove(msg.sender);
        }
        
        // Burn WXMR tokens after state updates
        wxmrToken.burnForSwap(msg.sender, xmrAmount, withdrawalId);
        
        emit LiquidityRemoved(msg.sender, xmrAmount, xmrAmount);
    }
    
    /**
     * @dev Get details of a time-locked swap
     * @param swapId The ID of the swap
     */
    function getSwapDetails(bytes32 swapId) 
        external 
        view 
        returns (
            address recipient,
            uint256 amount,
            bool isXmrToEvm,
            uint256 timestamp,
            bool completed,
            bool refunded,
            bytes32 timelockId,
            uint256 timelockExpiryTime,
            string memory xmrAddress,
            address initiator,
            uint256 minAmountOut
        ) 
    {
        TimeLockSwap storage swap = pendingSwaps[swapId];
        
        return (
            swap.recipient,
            swap.amount,
            swap.isXmrToEvm,
            swap.timestamp,
            swap.completed,
            swap.refunded,
            swap.timelockId,
            swap.timelockExpiryTime,
            swap.xmrAddress,
            swap.initiator,
            swap.minAmountOut
        );
    }
    
    /**
     * @dev Get liquidity provider details
     */
    function getLiquidityProviderDetails(address provider)
        external
        view
        returns (
            uint256 xmrCommitted,
            uint256 wxmrHolding,
            uint256 pendingDeposits,
            uint256 providerFees,
            bool isActive,
            uint256 lastWithdrawal
        )
    {
        LiquidityProvider storage lp = liquidityProviders[provider];
        
        return (
            lp.xmrCommitted,
            lp.wxmrHolding,
            lp.pendingDeposits,
            lp.accumulatedFees,
            lp.isActive,
            lp.lastWithdrawalTime
        );
    }
    
    /**
     * @dev Get the total number of active liquidity providers
     */
    function getTotalActiveLiquidityProviders() 
        external 
        view 
        returns (uint256) 
    {
        return liquidityProviderSet.length();
    }
    
    /**
     * @dev Get a list of active liquidity providers with pagination
     * @param start Starting index
     * @param limit Maximum number of items to return
     */
    function getActiveLiquidityProviders(uint256 start, uint256 limit) 
        external 
        view 
        returns (address[] memory) 
    {
        uint256 end = start + limit;
        if (end > liquidityProviderSet.length()) {
            end = liquidityProviderSet.length();
        }
        
        address[] memory providers = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            providers[i - start] = liquidityProviderSet.at(i);
        }
        
        return providers;
    }
    
    /**
     * @dev Verify a signature and return the signer
     * @param messageHash The message hash that was signed
     * @param signature The signature to verify
     * @return The address that signed the message
     */
    function verifySignature(bytes32 messageHash, bytes memory signature) 
        public 
        pure 
        returns (address) 
    {
        // Prefix the hash according to EIP-191 to create an Ethereum signed message
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        // Use OpenZeppelin's ECDSA library to safely recover the signer
        return ECDSA.recover(ethSignedMessageHash, signature);
    }
    
    /**
     * @dev Verify that a secret matches a given hash
     * @param secretHash The hash to compare against
     * @param secret The secret to verify
     * @return Whether the secret matches the hash
     */
    function verifySecret(bytes32 secretHash, bytes32 secret) 
        public 
        pure 
        returns (bool) 
    {
        return keccak256(abi.encodePacked(secret)) == secretHash;
    }
    
    /**
     * @dev Validate a Monero address format
     * @param xmrAddress The Monero address to validate
     * @return Whether the address format is valid
     */
    function isValidMoneroAddress(string calldata xmrAddress) 
        public 
        pure 
        returns (bool) 
    {
        // Basic validation: check length and starting character
        bytes memory addressBytes = bytes(xmrAddress);
        
        // Monero addresses must not be empty
        if (addressBytes.length == 0) {
            return false;
        }
        
        // Most Monero addresses are 95 characters long
        // Some subaddresses can be 106 characters
        // Integrated addresses are 106 characters
        if (addressBytes.length != 95 && addressBytes.length != 106) {
            return false;
        }
        
        // Standard addresses start with '4', subaddresses with '8', integrated addresses with '4'
        bytes1 firstChar = addressBytes[0];
        if (firstChar != 0x34 && firstChar != 0x38) { // '4' or '8'
            return false;
        }
        
        // Check that all characters are valid base58 characters
        // Base58 alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
        for (uint i = 0; i < addressBytes.length; i++) {
            bytes1 char = addressBytes[i];
            
            // Check if character is in the valid range
            bool isValid = 
                (char >= 0x31 && char <= 0x39) || // 1-9
                (char >= 0x41 && char <= 0x48) || // A-H
                (char >= 0x4A && char <= 0x4E) || // J-N
                (char >= 0x50 && char <= 0x5A) || // P-Z
                (char >= 0x61 && char <= 0x6B) || // a-k
                (char >= 0x6D && char <= 0x7A);   // m-z
                
            // Exclude: 0, I, O, l
            bool isExcluded = 
                char == 0x30 || // 0
                char == 0x49 || // I
                char == 0x4F || // O
                char == 0x6C;   // l
                
            if (!isValid || isExcluded) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @dev Validate an EVM/Ethereum address
     * @param addr The address to validate
     * @return Whether the address is valid
     */
    function isValidEvmAddress(address addr) 
        public 
        pure 
        returns (bool) 
    {
        // Basic validation: ensure the address is not zero
        return addr != address(0);
    }
}
