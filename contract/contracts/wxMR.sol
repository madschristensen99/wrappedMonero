// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title  Wrapped Monero (WXMR) – encrypted balances
 * @notice Single authority: 0x37fD7F8e2865EF6F214D21C261833d6831D8205e
 *         Two-step mint:
 *            1. user: requestMint(txSecret, receiver)
 *            2. authority: confirmMint(txSecret, amount)
 */
contract WrappedMonero is ERC20 {
    /* --------------------------------------------------------------------------
                               AUTHORITY
    -------------------------------------------------------------------------- */
    address public constant AUTHORITY = 0x37fD7F8e2865EF6F214D21C261833d6831D8205e;

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
                                 EVENTS
    -------------------------------------------------------------------------- */
    event MintRequested(bytes32 indexed txSecret, address indexed receiver);
    event MintConfirmed(bytes32 indexed txSecret, address indexed receiver, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    /* --------------------------------------------------------------------------
                               CONSTRUCTOR
    -------------------------------------------------------------------------- */
    constructor() ERC20("Wrapped Monero", "WXMR") {
        _totalSupplyEnc = FHE.asEuint64(0);
        FHE.allowThis(_totalSupplyEnc);
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
                           2. AUTHORITY CONFIRMS MINT
    -------------------------------------------------------------------------- */
    function confirmMint(bytes32 txSecret, uint64 amount) external {
        require(msg.sender == AUTHORITY, "Not authority");
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
                                 BURN
    -------------------------------------------------------------------------- */
    function burn(uint64 amount) external {
        require(msg.sender == AUTHORITY, "Not authority");

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.sub(_totalSupplyEnc, amtEnc);
        _balancesEnc[AUTHORITY] = FHE.sub(_balancesEnc[AUTHORITY], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[AUTHORITY]);

        emit Burn(AUTHORITY, amount);
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
                         AUTHORITY DECRYPT REFRESH
    -------------------------------------------------------------------------- */
    function decryptTotalSupply() external {
        require(msg.sender == AUTHORITY, "Not authority");
        _lastDecryptedSupply = _totalSupplyEnc;
        FHE.decrypt(_lastDecryptedSupply);
    }

    function decryptBalance(address account) external {
        require(msg.sender == AUTHORITY, "Not authority");
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
