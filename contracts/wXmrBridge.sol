// SPDX-License-Identifier: LGPLv3
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IWXMR {
    function mintFromSwap(address to, uint256 amount, bytes32 swapId) external;
    function burnForSwap(address from, uint256 amount, bytes32 swapId) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title WXMRBridge
 * @dev Bridge contract to handle atomic swaps between WXMR and XMR using hash time-locked contracts
 * Eliminates trusted signers and facilitators by using cryptographic hash preimages
 */
contract WXMRBridge is AccessControl, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    IWXMR public wxmrToken;
    bool public tokenInitialized = false;
    
    // Fixed fee of 27 basis points (0.27%)
    uint256 public constant FEE_PERCENTAGE = 27; // 0.27% fee (scaled by 10^4)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Minimum amount for any swap to ensure fee calculations make sense
    uint256 public constant MIN_SWAP_AMOUNT = 0.001 * 1e12; // 0.001 XMR
    
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
    uint256 public minTimelockDuration = 10 minutes;
    uint256 public maxTimelockDuration = 7 days;
    
    // Mapping from swap IDs to pending swaps
    mapping(bytes32 => AtomicSwap) public pendingSwaps;
    
    // Stores liquidity provider information
    mapping(address => LiquidityProvider) public liquidityProviders;
    EnumerableSet.AddressSet private liquidityProviderSet;
    
    // Strict limit of one active liquidity pool per address
    uint256 public constant MAX_POOLS_PER_ADDRESS = 1;
    
    // Minimum liquidity required per provider
    uint256 public minLiquidityPerProvider = 0.1 * 1e12; // 0.1 XMR
    
    // Cooldown periods for liquidity operations
    uint256 public liquidityWithdrawalCooldown = 1 days;
    uint256 public liquidityAdditionCooldown = 12 hours; // New: cooldown after withdrawal before adding
    
    // Nonce tracking for swap ID uniqueness
    mapping(address => uint256) public userNonces;
    
    // Swap states
    enum SwapState {
        INVALID,
        INITIATED,
        CONFIRMED,
        COMPLETED,
        REFUNDED
    }
    
    struct AtomicSwap {
        address initiator;          // The party that initiated the swap
        address recipient;          // The recipient of the WXMR tokens or refund
        uint256 amount;             // Amount of XMR/WXMR being swapped
        bool isXmrToEvm;            // Direction of the swap
        uint256 initTimestamp;      // When the swap was initiated
        SwapState state;            // Current state of the swap
        bytes32 hashLock;           // Hash of the secret needed to unlock funds
        uint256 timelock;           // When the timelock expires
        string xmrAddress;          // Monero address (for EVM->XMR)
        uint256 minAmountOut;       // Minimum amount out (slippage protection)
    }
    
    struct LiquidityProvider {
        uint256 xmrCommitted;      // Amount of XMR committed to the protocol
        uint256 accumulatedFees;   // Fees accumulated for this provider
        bool isActive;             // Whether the provider is active
        uint256 lastWithdrawalTime; // Last time liquidity was withdrawn
    }
    
    // Events
    event SwapInitiatedToEVM(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount,
        bytes32 hashLock, 
        uint256 timelock
    );
    
    event SwapConfirmed(
        bytes32 indexed swapId,
        address confirmer
    );
    
    event SwapCompletedToEVM(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount, 
        bytes32 secret // Changed to reveal the actual secret
    );
    
    event SwapInitiatedToXMR(
        bytes32 indexed swapId, 
        address indexed sender, 
        uint256 amount, 
        string xmrAddress, 
        bytes32 hashLock, 
        uint256 timelock
    );
    
    event SwapCompletedToXMR(
        bytes32 indexed swapId, 
        bytes32 secret // Actual secret, required for cross-chain operations
    );
    
    event SwapRefunded(
        bytes32 indexed swapId, 
        address indexed recipient, 
        uint256 amount
    );
    
    event LiquidityAdded(
        address indexed provider, 
        uint256 xmrAmount
    );
    
    event LiquidityRemoved(
        address indexed provider, 
        uint256 xmrAmount
    );
    
    event TokenInitialized(address indexed admin, address tokenAddress);
    
    event FeesDistributed(uint256 totalFees, uint256 providersRewarded);
    
    event FeesClaimed(address indexed provider, uint256 amount);
    
    event LiquidityParametersUpdated(uint256 newMinLiquidity, uint256 newMaxDailyMint);
    event TimelockDurationUpdated(uint256 newDuration);
    
    /**
     * @dev Modifier to check if a swap exists and is in a valid state
     * @param swapId The ID of the swap
     */
    modifier validSwap(bytes32 swapId) {
        AtomicSwap storage swap = pendingSwaps[swapId];
        require(swap.initTimestamp > 0, "Swap does not exist");
        require(swap.state != SwapState.COMPLETED && swap.state != SwapState.REFUNDED, "Swap already completed or refunded");
        _;
    }
    
    /**
     * @dev Modifier to check if the token has been initialized
     */
    modifier initialized() {
        require(tokenInitialized, "Token not initialized");
        _;
    }
    
    /**
     * @dev Modifier to ensure amount is above minimum threshold
     */
    modifier validAmount(uint256 amount) {
        require(amount >= MIN_SWAP_AMOUNT, "Amount below minimum threshold");
        _;
    }
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
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
    * @dev Distribute accumulated fees to liquidity providers proportionally
    */
    function distributeFees() external nonReentrant onlyRole(ADMIN_ROLE) initialized {
        require(accumulatedFees > 0, "No fees to distribute");
        require(totalLiquidityCommitted > 0, "No liquidity providers");

        // Store the fees amount and reset accumulated fees BEFORE any calculations or external calls
        uint256 totalFees = accumulatedFees;
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
            block.timestamp,
            userNonces[msg.sender]++
        ));
        
        // Mint the fee amount as WXMR to the provider
        wxmrToken.mintFromSwap(msg.sender, feeAmount, feeClaimId);
        
        emit FeesClaimed(msg.sender, feeAmount);
    }
    
    /**
     * @dev First phase of XMR->EVM swap: Anyone can initiate a swap by providing a hashlock.
     * This function doesn't require validation since the XMR hasn't been sent yet.
     * @param recipient The recipient of the WXMR tokens
     * @param amount The amount of XMR to be swapped
     * @param hashLock Hash of the secret that will be used to claim the funds
     * @param timelock Duration in seconds until the swap expires
     * @param minAmountOut Minimum amount to receive after fees (slippage protection)
     */
    function initiateXmrToEvmSwap(
        address recipient, 
        uint256 amount,
        bytes32 hashLock,
        uint256 timelock,
        uint256 minAmountOut
    ) 
        external 
        nonReentrant
        initialized
        validAmount(amount)
        returns (bytes32)
    {
        require(timelock >= minTimelockDuration && timelock <= maxTimelockDuration, "Invalid timelock duration");
        require(hashLock != bytes32(0), "Invalid hashlock");
        require(recipient != address(0), "Invalid recipient address");
        
        // Calculate fee and final amount using fixed fee percentage
        uint256 fee = (amount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        
        // Ensure fee is reasonable and non-zero
        require(fee > 0, "Fee calculation error");
        
        uint256 finalAmount = amount - fee;
        
        // Apply slippage protection
        require(finalAmount >= minAmountOut, "Slippage limit exceeded");
        
        // Prevent fee accumulation overflow
        require(accumulatedFees + fee <= MAX_ACCUMULATED_FEES, "Fee accumulation limit reached");
        
        // Generate a unique swap ID using nonce system
        uint256 nonce = userNonces[msg.sender]++;
        
        bytes32 swapId = keccak256(abi.encodePacked(
            msg.sender,
            recipient,
            amount,
            hashLock,
            block.timestamp,
            nonce
        ));
        
        // Ensure swap doesn't already exist (redundant with nonce but adds safety)
        require(pendingSwaps[swapId].initTimestamp == 0, "Swap already exists");
        
        uint256 swapTimelock = block.timestamp + timelock;
        
        pendingSwaps[swapId] = AtomicSwap({
            initiator: msg.sender,
            recipient: recipient,
            amount: finalAmount,
            isXmrToEvm: true,
            initTimestamp: block.timestamp,
            state: SwapState.INITIATED,
            hashLock: hashLock,
            timelock: swapTimelock,
            xmrAddress: "",
            minAmountOut: minAmountOut
        });
        
        // Accumulate fees for later distribution
        accumulatedFees += fee;
        
        emit SwapInitiatedToEVM(
            swapId, 
            recipient, 
            finalAmount, 
            hashLock, 
            swapTimelock
        );
        
        return swapId;
    }
    
    /**
     * @dev Second phase of XMR->EVM swap: Confirm that XMR has been received
     * @param swapId The ID of the swap
     */
    function confirmXmrToEvmSwap(bytes32 swapId)
        external
        nonReentrant
        initialized
        validSwap(swapId)
    {
        AtomicSwap storage swap = pendingSwaps[swapId];
        require(swap.isXmrToEvm, "Not an XMR to EVM swap");
        require(swap.state == SwapState.INITIATED, "Swap not in initiated state");
        
        // Update swap state
        swap.state = SwapState.CONFIRMED;
        
        emit SwapConfirmed(swapId, msg.sender);
    }
    
    /**
     * @dev Complete a XMR->EVM swap by revealing the secret
     * @param swapId The ID of the swap
     * @param secret The secret that unlocks the funds (preimage of hashLock)
     */
    function completeXmrToEvmSwap(bytes32 swapId, bytes32 secret) 
        external 
        nonReentrant
        initialized
        validSwap(swapId)
    {
        AtomicSwap storage swap = pendingSwaps[swapId];
        require(swap.isXmrToEvm, "Not an XMR to EVM swap");
        require(swap.state == SwapState.CONFIRMED, "Swap not in confirmed state");

        // Verify the secret matches the hash
        bytes32 secretHash = keccak256(abi.encodePacked(secret));
        require(secretHash == swap.hashLock, "Invalid secret");

        // Verify the swap hasn't expired
        require(block.timestamp < swap.timelock, "Swap has expired");
    
        // Update swap state before external calls
        swap.state = SwapState.COMPLETED;
    
        // Verify there's sufficient liquidity
        require(totalReserve >= swap.amount, "Insufficient liquidity");
    
        // Process the swap
        totalReserve -= swap.amount;
    
        // Reset daily limits if needed
        if (block.timestamp > lastResetTime + 1 days) {
            dailyMinted = 0;
            lastResetTime = block.timestamp;
        }
    
        // Check daily mint limits
        require(dailyMinted + swap.amount <= maxDailyMint, "Daily mint limit exceeded");
        dailyMinted += swap.amount;
    
        // Mint tokens to the recipient
        wxmrToken.mintFromSwap(swap.recipient, swap.amount, swapId);
    
        // Emit event with the actual secret for cross-chain verification
        emit SwapCompletedToEVM(
            swapId, 
            swap.recipient, 
            swap.amount, 
            secret // Actual secret for cross-chain verification
        );
    }
    
    /**
     * @dev Initiate a WXMR->XMR swap
     * @param amount The amount of WXMR to swap
     * @param xmrAddress The Monero address to receive the funds
     * @param hashLock Hash of the secret needed to claim the XMR
     * @param minAmountOut Minimum amount to receive after fees (slippage protection)
     */
    function initiateEvmToXmrSwap(
        uint256 amount, 
        string calldata xmrAddress,
        bytes32 hashLock,
        uint256 minAmountOut
    ) 
        external 
        nonReentrant
        initialized
        validAmount(amount)
        returns (bytes32)
    {
        require(wxmrToken.balanceOf(msg.sender) >= amount, "Insufficient WXMR balance");
        require(isValidMoneroAddress(xmrAddress), "Invalid Monero address");
        require(hashLock != bytes32(0), "Invalid hashlock");
        
        // Calculate fee and final amount using fixed fee percentage
        uint256 fee = (amount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        
        // Ensure fee is reasonable and non-zero
        require(fee > 0, "Fee calculation error");
        
        uint256 finalAmount = amount - fee;
        
        // Slippage protection
        require(finalAmount >= minAmountOut, "Slippage limit exceeded");
        
        // Prevent fee accumulation overflow
        require(accumulatedFees + fee <= MAX_ACCUMULATED_FEES, "Fee accumulation limit reached");
        
        // Accumulate fees for later distribution
        accumulatedFees += fee;
        
        // Calculate timelock expiry
        uint256 timelockExpiry = block.timestamp + defaultTimelockDuration;
        
        // Generate a unique swap ID using nonce system
        uint256 nonce = userNonces[msg.sender]++;
        
        bytes32 swapId = keccak256(abi.encodePacked(
            msg.sender,
            amount,
            xmrAddress,
            hashLock,
            block.timestamp,
            nonce
        ));
        
        // Create the swap record before external calls to prevent reentrancy
        pendingSwaps[swapId] = AtomicSwap({
            initiator: msg.sender,
            recipient: msg.sender,
            amount: finalAmount,
            isXmrToEvm: false,
            initTimestamp: block.timestamp,
            state: SwapState.INITIATED,
            hashLock: hashLock,
            timelock: timelockExpiry,
            xmrAddress: xmrAddress,
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
            hashLock, 
            timelockExpiry
        );
        
        return swapId;
    }
    
    /**
     * @dev Complete a EVM->XMR swap by revealing the secret
     * @param swapId The ID of the swap
     * @param secret The secret that unlocks the funds (preimage of hashLock)
     */
    function completeEvmToXmrSwap(bytes32 swapId, bytes32 secret) 
        external 
        nonReentrant
        initialized
        validSwap(swapId)
    {
        AtomicSwap storage swap = pendingSwaps[swapId];
        require(!swap.isXmrToEvm, "Not an EVM to XMR swap");
        require(swap.state == SwapState.INITIATED, "Swap not in initiated state");
    
        // Verify the secret matches the hash
        require(keccak256(abi.encodePacked(secret)) == swap.hashLock, "Invalid secret");
    
        // Verify the swap hasn't expired
        require(block.timestamp < swap.timelock, "Swap has expired");
    
        // Update state
        swap.state = SwapState.COMPLETED;
    
        // Emit event with the actual secret for cross-chain verification
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
        AtomicSwap storage swap = pendingSwaps[swapId];
        
        // Only the initiator or recipient can refund
        require(
            swap.recipient == msg.sender || swap.initiator == msg.sender, 
            "Not authorized to refund"
        );
        
        // Check if the timelock has expired
        require(block.timestamp > swap.timelock, "Timelock not expired yet");
        
        // Mark as refunded before external calls to prevent reentrancy
        swap.state = SwapState.REFUNDED;
        
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
     * @dev Add liquidity to the system using hash time-locked contracts
     * @param xmrAmount The amount of XMR committed
     * @param hashLock Hash of the secret used for verification
     */
    function initiateAddLiquidity(
        uint256 xmrAmount,
        bytes32 hashLock
    ) 
        external 
        nonReentrant
        initialized
        validAmount(xmrAmount)
        returns (bytes32)
    {
        require(xmrAmount >= minLiquidityPerProvider, "Amount below minimum required");
        require(hashLock != bytes32(0), "Invalid hashlock");
        
        LiquidityProvider storage lp = liquidityProviders[msg.sender];
        
        // Enforce strict one pool per address limit
        if (lp.isActive) {
            // If user already has liquidity, they can only add more to the same pool
            // No pending deposits allowed
            require(lp.xmrCommitted > 0, "Already have active liquidity");
        }
        
        // Check cooldown period if user recently withdrew liquidity
        require(
            block.timestamp >= lp.lastWithdrawalTime + liquidityAdditionCooldown,
            "Still in cooling period after withdrawal"
        );
        
        // Generate a unique nonce for this deposit
        uint256 nonce = userNonces[msg.sender]++;
        
        bytes32 depositId = keccak256(abi.encodePacked(
            "LIQUIDITY", 
            msg.sender, 
            xmrAmount,
            hashLock,
            block.timestamp,
            nonce
        ));
        
        // Create a pseudo-swap for the liquidity deposit
        uint256 timelockExpiry = block.timestamp + defaultTimelockDuration;
        
        pendingSwaps[depositId] = AtomicSwap({
            initiator: msg.sender,
            recipient: msg.sender,
            amount: xmrAmount,
            isXmrToEvm: true, // Treated as an XMR->EVM swap
            initTimestamp: block.timestamp,
            state: SwapState.INITIATED,
            hashLock: hashLock,
            timelock: timelockExpiry,
            xmrAddress: "LIQUIDITY", // Mark as liquidity deposit
            minAmountOut: xmrAmount // No slippage for liquidity
        });
        
        return depositId;
    }
    
    /**
     * @dev Confirm that XMR has been sent to the liquidity pool
     * @param depositId The ID of the liquidity deposit
     */
    function confirmLiquidityDeposit(bytes32 depositId) 
        external 
        nonReentrant
        initialized
        validSwap(depositId)
    {
        AtomicSwap storage deposit = pendingSwaps[depositId];
        
        // Use direct comparison for constant strings
        require(
            keccak256(bytes(deposit.xmrAddress)) == keccak256(bytes("LIQUIDITY")), 
            "Not a liquidity deposit"
        );
        require(deposit.state == SwapState.INITIATED, "Deposit not in initiated state");
        
        // Update deposit state
        deposit.state = SwapState.CONFIRMED;
        
        emit SwapConfirmed(depositId, msg.sender);
    }
    
    /**
     * @dev Complete liquidity addition by revealing the secret
     * @param depositId The ID of the liquidity deposit
     * @param secret The secret that verifies the XMR deposit
     */
    function completeLiquidityDeposit(bytes32 depositId, bytes32 secret)
        external
        nonReentrant
        initialized
        validSwap(depositId)
    {
        AtomicSwap storage deposit = pendingSwaps[depositId];
        
        require(deposit.recipient == msg.sender, "Not the deposit owner");
        // Use direct comparison for constant strings
        require(
            keccak256(bytes(deposit.xmrAddress)) == keccak256(bytes("LIQUIDITY")), 
            "Not a liquidity deposit"
        );
        require(deposit.state == SwapState.CONFIRMED, "Deposit not confirmed");
        
        // Verify the secret matches the hash
        require(keccak256(abi.encodePacked(secret)) == deposit.hashLock, "Invalid secret");
        
        // Verify the deposit hasn't expired
        require(block.timestamp < deposit.timelock, "Deposit has expired");
        
        address provider = deposit.recipient;
        uint256 xmrAmount = deposit.amount;
        
        LiquidityProvider storage lp = liquidityProviders[provider];
        
        // Update state before external calls to prevent reentrancy
        deposit.state = SwapState.COMPLETED;
        
        if (!lp.isActive) {
            lp.isActive = true;
            liquidityProviderSet.add(provider);
        }
        
        lp.xmrCommitted += xmrAmount;
        totalLiquidityCommitted += xmrAmount;
        totalReserve += xmrAmount;
        
        // Mint WXMR equivalent to the provider
        wxmrToken.mintFromSwap(provider, xmrAmount, depositId);
        
        emit LiquidityAdded(provider, xmrAmount);
    }
    
    /**
     * @dev Remove liquidity from the system
     * @param xmrAmount The amount of XMR to withdraw
     */
    function removeLiquidity(uint256 xmrAmount) 
        external 
        nonReentrant
        initialized
        validAmount(xmrAmount)
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
        
        // Generate a unique withdrawal ID
        uint256 nonce = userNonces[msg.sender]++;
        
        bytes32 withdrawalId = keccak256(abi.encodePacked(
            "LIQUIDITY_REMOVAL", 
            msg.sender, 
            xmrAmount,
            block.timestamp,
            nonce
        ));
        
        // Update state before external calls to prevent reentrancy
        lp.xmrCommitted -= xmrAmount;
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
        
        emit LiquidityRemoved(msg.sender, xmrAmount);
    }
    
    /**
     * @dev Get details of a time-locked swap
     * @param swapId The ID of the swap
     */
    function getSwapDetails(bytes32 swapId) 
        external 
        view 
        returns (
            address initiator,
            address recipient,
            uint256 amount,
            bool isXmrToEvm,
            uint256 initTimestamp,
            SwapState state,
            bytes32 hashLock,
            uint256 timelock,
            string memory xmrAddress,
            uint256 minAmountOut
        ) 
    {
        AtomicSwap storage swap = pendingSwaps[swapId];
        
        return (
            swap.initiator,
            swap.recipient,
            swap.amount,
            swap.isXmrToEvm,
            swap.initTimestamp,
            swap.state,
            swap.hashLock,
            swap.timelock,
            swap.xmrAddress,
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
            uint256 providerFees,
            bool isActive,
            uint256 lastWithdrawal
        )
    {
        LiquidityProvider storage lp = liquidityProviders[provider];
        
        return (
            lp.xmrCommitted,
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
     * @dev Verify if a secret matches a given hash lock
     * @param hashLock The hash to verify against
     * @param secret The secret to check
     * @return Whether the secret matches the hash lock
     */
    function verifySecret(bytes32 hashLock, bytes32 secret) 
        public 
        pure 
        returns (bool) 
    {
        return keccak256(abi.encodePacked(secret)) == hashLock;
    }
    
    /**
     * @dev Get the next nonce for a user
     * @param user The address to get the nonce for
     * @return The next nonce for the user
     */
    function getNextNonce(address user)
        external
        view
        returns (uint256)
    {
        return userNonces[user];
    }
    
    /**
     * @dev Validate a Monero address format with improved checks
     * @param xmrAddress The Monero address to validate
     * @return Whether the address format is valid
     */
    function isValidMoneroAddress(string calldata xmrAddress) 
        public 
        pure 
        returns (bool) 
    {
        bytes memory addressBytes = bytes(xmrAddress);
    
        // Monero addresses must not be empty
        if (addressBytes.length == 0) {
            return false;
        }
    
        // Check address length based on type
        // Standard addresses: 95 characters
        // Integrated addresses or subaddresses: 106 characters
        if (addressBytes.length != 95 && addressBytes.length != 106) {
            return false;
        }
    
        // Check address prefix is valid:
        // - Standard addresses start with '4'
        // - Subaddresses start with '8'
        bytes1 firstChar = addressBytes[0];
    
        // For standard addresses (95 chars)
        if (addressBytes.length == 95) {
            // Primary address must start with 4
            if (firstChar != 0x34) { // '4'
                return false;
            }
        } 
        // For subaddresses or integrated addresses (106 chars)
        else {
            // Subaddresses start with 8, integrated addresses with 4
            if (firstChar != 0x38 && firstChar != 0x34) { // '8' or '4'
                return false;
            }
        }
    
        // Define valid and invalid characters
        bytes memory validChars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        bool isValid;
    
        // Check each character against valid Base58 alphabet
        for (uint i = 0; i < addressBytes.length; i++) {
            isValid = false;
        
            for (uint j = 0; j < validChars.length; j++) {
                if (addressBytes[i] == validChars[j]) {
                    isValid = true;
                    break;
                }
            }
        
            if (!isValid) {
                return false;
            }
        }
    
        return true;
    }
}
