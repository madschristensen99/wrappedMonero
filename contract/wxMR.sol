// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title  Wrapped Monero (WXMR) – encrypted balances
 * @notice Decentralized bridge with threshold signature validation
 *         Two-step mint:
 *            1. user: requestMint(txId, txSecret, receiver)
 *            2. validators: confirmMintWithSig(threshold signature, amount)
 */
contract WrappedMonero is ERC20 {    
    /* --------------------------------------------------------------------------
                               VALIDATOR MANAGEMENT
    -------------------------------------------------------------------------- */
    struct ValidatorConfig {
        // Indexed (1,2,3...) for efficient storage
        mapping(uint256 => bool) validators;
        uint256 totalValidators;
        uint256 threshold;           // Number of required signatures + 1
        address mpcAddress;          // MPC-derived address for signatures
        bool paused;                 // Emergency pause switch
    }
    
    ValidatorConfig public validatorConfig;

    /* --------------------------------------------------------------------------
                               THRESHOLD SIGNATURE TYPES
    -------------------------------------------------------------------------- */
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }
    
    struct Operation {
        bytes32 operationHash;
        bytes32 signature;
        uint256 timestamp;
        bytes32 nonce;
    }
    
    mapping(address => bool) public authorizedMPCResults;

    /* --------------------------------------------------------------------------
                               ENCRYPTED STORAGE
    -------------------------------------------------------------------------- */
    euint64 private _totalSupplyEnc;
    mapping(address => euint64) private _balancesEnc;

    // decrypted caches
    euint64 private _lastDecryptedSupply;
    mapping(address => euint64) private _lastDecryptedBalance;

    /* --------------------------------------------------------------------------
                               MINT REQUESTS
    -------------------------------------------------------------------------- */
    mapping(bytes32 => address) public mintRequestReceiver; // txSecret => receiver
    mapping(bytes32 => bool) public mintSecretUsed;        // txSecret => spent

    /* -------------------------------- Events -------------------------------- */
    event MintRequested(bytes32 indexed txId, bytes32 indexed txSecret, address indexed receiver);
    event MintConfirmed(bytes32 indexed txSecret, address indexed receiver, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event ValidatorAdded(uint256 indexed validatorId);
    event ValidatorRemoved(uint256 indexed validatorId);
    event MPCAddressUpdated(address newMPCAddress);
    event Paused(address indexed pauser);
    event Unpaused(address indexed pauser);

    constructor() ERC20("Wrapped Monero", "WXMR") {
        _totalSupplyEnc = FHE.asEuint64(0);
        FHE.allowThis(_totalSupplyEnc);
        
        // Initialize validator configuration
        validatorConfig.totalValidators = 0;
        validatorConfig.threshold = 5; // Default for 7 validators (t+1 where t=4)
        validatorConfig.mpcAddress = address(0); // Must be set by admin
        validatorConfig.paused = false;
    }

    /* --------------------------------------------------------------------------
                             VALIDATOR MANAGEMENT
    -------------------------------------------------------------------------- */
    
    function isValidator(uint256 validatorId) public view returns (bool) {
        return validatorConfig.validators[validatorId];
    }
    
    function addValidator(uint256 validatorId) external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");
        require(!validatorConfig.validators[validatorId], "Already validator");
        require(validatorConfig.totalValidators < 7, "Validator limit reached");
        
        validatorConfig.validators[validatorId] = true;
        validatorConfig.totalValidators++;
        emit ValidatorAdded(validatorId);
    }
    
    function removeValidator(uint256 validatorId) external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");
        require(validatorConfig.validators[validatorId], "Not validator");
        require(validatorConfig.totalValidators > validatorConfig.threshold, "Would violate threshold");
        
        validatorConfig.validators[validatorId] = false;
        validatorConfig.totalValidators--;
        emit ValidatorRemoved(validatorId);
    }
    
    function setMPCAddress(address mpcAddress) external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");
        require(mpcAddress != address(0), "Invalid MPC address");
        
        validatorConfig.mpcAddress = mpcAddress;
        emit MPCAddressUpdated(mpcAddress);
    }
    
    function pause() external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");
        require(!validatorConfig.paused, "Already paused");
        validatorConfig.paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");
        require(validatorConfig.paused, "Not paused");
        validatorConfig.paused = false;
        emit Unpaused(msg.sender);
    }
    
    /* --------------------------------------------------------------------------
                    THRESHOLD SIGNATURE VERIFICATION
    -------------------------------------------------------------------------- */
    
    function verifyThresholdSignature(Operation calldata op, Signature calldata sig) internal returns (bool) {
        require(validatorConfig.mpcAddress != address(0), "MPC address not set");
        
        if (block.timestamp > op.timestamp + 15 minutes) {
            return false; // Stale signature
        }
        
        bytes32 message = keccak256(abi.encodePacked(op.operationHash, op.timestamp, op.nonce));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        
        address recovered = ecrecover(signedHash, sig.v, sig.r, sig.s);
        return recovered == validatorConfig.mpcAddress;
    }

    /* ----------------------------- 1. Request Mint -------------------------- */
    function requestMint(bytes32 txId, bytes32 txSecret, address receiver) external {
        require(!validatorConfig.paused, "Contract paused");
        require(receiver != address(0), "Bad receiver");
        require(mintRequestReceiver[txSecret] == address(0), "Request exists");
        require(!mintSecretUsed[txSecret], "Secret used");

        mintRequestReceiver[txSecret] = receiver;
        emit MintRequested(txId, txSecret, receiver);
    }
    
    /* --------------------------------------------------------------------------
                           2. VALIDATORS CONFIRM MINT (NEW)
    -------------------------------------------------------------------------- */
    function confirmMintWithSig(
        bytes32 txSecret,
        uint64 amount,
        Operation calldata op,
        Signature calldata sig
    ) external {
        require(!validatorConfig.paused, "Contract paused");
        require(verifyThresholdSignature(op, sig), "Invalid threshold signature");
        require(op.operationHash == keccak256(abi.encode(txSecret, amount)), "Invalid op hash");
        
        address receiver = mintRequestReceiver[txSecret];
        require(receiver != address(0), "Mint request not found");
        require(!mintSecretUsed[txSecret], "Secret already used");

        mintSecretUsed[txSecret] = true;
        delete mintRequestReceiver[txSecret];

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.add(_totalSupplyEnc, amtEnc);
        _balancesEnc[receiver] = FHE.add(_balancesEnc[receiver], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[receiver]);

        emit MintConfirmed(txSecret, receiver, amount);
    }

    /* --------------------------------------------------------------------------
                           AUTHORIZE VALIDATORS TO BURN (NEW)
    -------------------------------------------------------------------------- */
    function burnWithSig(uint64 amount, address from, Operation calldata op, Signature calldata sig) external {
        require(!validatorConfig.paused, "Contract paused");
        require(verifyThresholdSignature(op, sig), "Invalid threshold signature");
        require(op.operationHash == keccak256(abi.encode(from, amount)), "Invalid op hash");
        
        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.sub(_totalSupplyEnc, amtEnc);
        _balancesEnc[from] = FHE.sub(_balancesEnc[from], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[from]);

        emit Burn(from, amount);
    }

    /* --------------------------------------------------------------------------
                               LEGACY BURN (admin only)
    -------------------------------------------------------------------------- */
    function burn(uint64 amount) external {
        require(msg.sender == address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), "Not admin");

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.sub(_totalSupplyEnc, amtEnc);
        _balancesEnc[address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e)] = FHE.sub(_balancesEnc[address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e)], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e)]);

        emit Burn(address(0x37fD7F8e2865EF6F214D21C261833d6831D8205e), amount);
    }

    /* --------------------------------------------------------------------------
                         PUBLIC VIEW DECRYPTED CACHES
    -------------------------------------------------------------------------- */
    function totalSupply() public view override returns (uint256) {
        (uint256 v, bool ready) = FHE.getDecryptResultSafe(_lastDecryptedSupply);
        if (!ready) revert("Supply not decrypted");
        return v;
    }

    function balanceOf(address account) public view override returns (uint256) {
        (uint256 v, bool ready) = FHE.getDecryptResultSafe(_lastDecryptedBalance[account]);
        if (!ready) revert("Balance not decrypted");
        return v;
    }

    /* --------------------------------------------------------------------------
                         DECRYPT REFRESH (VALIDATOR APPROVED)
    -------------------------------------------------------------------------- */
    function decryptTotalSupply() external {
        require(!validatorConfig.paused, "Contract paused");
        _lastDecryptedSupply = _totalSupplyEnc;
        FHE.decrypt(_lastDecryptedSupply);
    }

    function decryptBalance(address account) external {
        require(!validatorConfig.paused, "Contract paused");
        _lastDecryptedBalance[account] = _balancesEnc[account];
        FHE.decrypt(_lastDecryptedBalance[account]);
    }

    /* --------------------------------------------------------------------------
                         ENCRYPTED TRANSFER
    -------------------------------------------------------------------------- */
    function transfer(address to, uint64 amount) public returns (bool) {
        require(!validatorConfig.paused, "Contract paused");
        require(to != address(0), "Cannot transfer to zero address");
        
        euint64 amtEnc = FHE.asEuint64(amount);
        _balancesEnc[msg.sender] = FHE.sub(_balancesEnc[msg.sender], amtEnc);
        _balancesEnc[to] = FHE.add(_balancesEnc[to], amtEnc);

        FHE.allowThis(_balancesEnc[msg.sender]);
        FHE.allowThis(_balancesEnc[to]);

        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
