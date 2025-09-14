// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title  Wrapped Monero (WXMR) – encrypted balances, 3-of-3 multisig confirmMint
 * @notice Two-step mint:
 *            1. user: requestMint(txSecret, receiver)
 *            2. operators: confirmMint(txSecret, amount, 3 sigs)
 */
contract WrappedMonero is ERC20 {
    /* --------------------------------------------------------------------------
                               IMMUTABLE SIGNERS
    -------------------------------------------------------------------------- */
    address private constant SIGNER_1 = 0x49a22328fecF3e43C4C0fEDfb7E5272248904E3E;
    address private constant SIGNER_2 = 0xDFdC570ec0586D5c00735a2277c21Dcc254B3917;
    address private constant SIGNER_3 = 0xf6Fe61C7b88eF0688B1b0A141D12e9B98dfE1cc4;

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

    /* --------------------------------------------------------------------------
                               OWNER
    -------------------------------------------------------------------------- */
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    /* --------------------------------------------------------------------------
                                 EVENTS
    -------------------------------------------------------------------------- */
    event MintRequested(bytes32 indexed txSecret, address indexed receiver);
    event MintConfirmed(bytes32 indexed txSecret, address indexed receiver, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    /* --------------------------------------------------------------------------
                               CONSTRUCTOR
    -------------------------------------------------------------------------- */
    constructor() ERC20("Wrapped Monero", "WXMR") {
        _owner = msg.sender;

        _totalSupplyEnc = FHE.asEuint64(0);
        FHE.allowThis(_totalSupplyEnc);
    }

    /* --------------------------------------------------------------------------
                              MULTISIG VERIFICATION
    -------------------------------------------------------------------------- */
    function _recover(
        bytes32 txSecret,
        uint64 amount,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        uint256 chainId;
        assembly { chainId := chainid() }
        bytes32 digest = keccak256(
            abi.encodePacked("WrappedMonero-confirmMint", chainId, nonce, txSecret, amount)
        );
        return ecrecover(digest, v, r, s);
    }

    /* --------------------------------------------------------------------------
                           1. USER REQUESTS MINT
    -------------------------------------------------------------------------- */
    function requestMint(bytes32 txSecret, address receiver) external {
        require(receiver != address(0), "Bad receiver");
        require(mintRequestReceiver[txSecret] == address(0), "Request already exists");
        require(!mintSecretUsed[txSecret], "Secret already used");

        mintRequestReceiver[txSecret] = receiver;
        emit MintRequested(txSecret, receiver);
    }

    /* --------------------------------------------------------------------------
                           2. OPERATORS CONFIRM MINT
    -------------------------------------------------------------------------- */
    uint256 private _confirmNonce;

    function confirmMint(
        bytes32 txSecret,
        uint64 amount,
        uint8[3] calldata v,
        bytes32[3] calldata r,
        bytes32[3] calldata s
    ) external {
        address receiver = mintRequestReceiver[txSecret];
        require(receiver != address(0), "Mint request not found");
        require(!mintSecretUsed[txSecret], "Secret already used");

        uint256 nonce = _confirmNonce++;
        require(
            _recover(txSecret, amount, nonce, v[0], r[0], s[0]) == SIGNER_1 &&
            _recover(txSecret, amount, nonce, v[1], r[1], s[1]) == SIGNER_2 &&
            _recover(txSecret, amount, nonce, v[2], r[2], s[2]) == SIGNER_3,
            "Invalid 3-of-3 multisig"
        );

        mintSecretUsed[txSecret] = true;           // mark spent
        delete mintRequestReceiver[txSecret];      // clean up

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.add(_totalSupplyEnc, amtEnc);
        _balancesEnc[receiver] = FHE.add(_balancesEnc[receiver], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[receiver]);

        emit MintConfirmed(txSecret, receiver, amount);
    }

    /* --------------------------------------------------------------------------
                                 BURN
    -------------------------------------------------------------------------- */
    uint256 private _burnNonce;

    function _recoverBurn(
        uint64 amount,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        uint256 chainId;
        assembly { chainId := chainid() }
        bytes32 digest = keccak256(
            abi.encodePacked("WrappedMonero-burn", chainId, nonce, msg.sender, amount)
        );
        return ecrecover(digest, v, r, s);
    }

    function burn(
        uint64 amount,
        uint8[3] calldata v,
        bytes32[3] calldata r,
        bytes32[3] calldata s
    ) external {
        uint256 nonce = _burnNonce++;
        require(
            _recoverBurn(amount, nonce, v[0], r[0], s[0]) == SIGNER_1 &&
            _recoverBurn(amount, nonce, v[1], r[1], s[1]) == SIGNER_2 &&
            _recoverBurn(amount, nonce, v[2], r[2], s[2]) == SIGNER_3,
            "Invalid 3-of-3 multisig"
        );

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.sub(_totalSupplyEnc, amtEnc);
        _balancesEnc[msg.sender] = FHE.sub(_balancesEnc[msg.sender], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[msg.sender]);

        emit Burn(msg.sender, amount);
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
                         OWNER-ONLY DECRYPT REFRESH
    -------------------------------------------------------------------------- */
    function decryptTotalSupply() external onlyOwner {
        _lastDecryptedSupply = _totalSupplyEnc;
        FHE.decrypt(_lastDecryptedSupply);
    }

    function decryptBalance(address account) external onlyOwner {
        _lastDecryptedBalance[account] = _balancesEnc[account];
        FHE.decrypt(_lastDecryptedBalance[account]);
    }

    /* --------------------------------------------------------------------------
                         ENCRYPTED TRANSFER
    -------------------------------------------------------------------------- */
    function transfer(address to, uint64 amount) public returns (bool) {
        euint64 amtEnc = FHE.asEuint64(amount);
        _balancesEnc[msg.sender] = FHE.sub(_balancesEnc[msg.sender], amtEnc);
        _balancesEnc[to] = FHE.add(_balancesEnc[to], amtEnc);

        FHE.allowThis(_balancesEnc[msg.sender]);
        FHE.allowThis(_balancesEnc[to]);

        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
