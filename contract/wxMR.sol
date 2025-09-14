// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {Permissioned, Permission} from "../../../access/Permissioned.sol";

import {IFHERC20} from "./IFHERC20.sol";

error ErrorInsufficientFunds();
error ERC20InvalidApprover(address);
error ERC20InvalidSpender(address);

/**
 * @title  Wrapped Monero (WXMR) – encrypted balances
 * @notice Single authority: 0x37fD7F8e2865EF6F214D21C261833d6831D8205e
 *         Two-step mint:
 *            1. user: requestMint(txSecret, receiver)
 *            2. authority: confirmMint(txSecret, amount)
 */
contract WrappedMonero is ERC20, Permissioned {
    /* --------------------------------------------------------------------------
                               AUTHORITY
    -------------------------------------------------------------------------- */
    address public constant AUTHORITY = 0x37fD7F8e2865EF6F214D21C261833d6831D8205e;

    /* --------------------------------------------------------------------------
                               ENCRYPTED STORAGE
    -------------------------------------------------------------------------- */
    euint64 private _totalSupplyEnc;
    mapping(address => euint64) private _balancesEnc;

    /* --------------------------------------------------------------------------
                               MINT REQUESTS
    -------------------------------------------------------------------------- */
    mapping(bytes32 => address) public mintRequestReceiver; // txSecret => receiver
    mapping(bytes32 => bool) public mintSecretUsed;        // txSecret => spent

    /* -------------------------------- Events -------------------------------- */
    event MintRequested(bytes32 indexed txId, bytes32 indexed txSecret, address indexed receiver);
    event MintConfirmed(bytes32 indexed txSecret, address indexed receiver, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor() ERC20("Wrapped Monero", "WXMR") {
        _totalSupplyEnc = FHE.asEuint64(0);
        FHE.allowThis(_totalSupplyEnc);
    }

    /* ----------------------------- 1. Request Mint -------------------------- */
    function requestMint(bytes32 txId, bytes32 txSecret, address receiver) external {
        require(receiver != address(0), "Bad receiver");
        require(mintRequestReceiver[txSecret] == address(0), "Request exists");
        require(!mintSecretUsed[txSecret], "Secret used");

        mintRequestReceiver[txSecret] = receiver;
        emit MintRequested(txId, txSecret, receiver);
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
                         PUBLIC VIEW – ENCRYPTED ONLY
    -------------------------------------------------------------------------- */
    /// @dev Reverts on-plaintext balanceOf to enforce privacy
    function balanceOf(address) public pure override returns (uint256) {
        revert("Balance is encrypted");
    }

    /// @dev Reverts on-plaintext totalSupply to enforce privacy
    function totalSupply() public pure override returns (uint256) {
        revert("Total supply is encrypted");
    }

    /* --------------------------------------------------------------------------
                         OWNER-CONTROLLED DECRYPTION
    -------------------------------------------------------------------------- */
    /// @notice Returns the encrypted balance ciphertext.
    ///         Frontend must seal it with cofhejs.seal() before unsealing.
    function balanceOfEncrypted(
        address account,
        Permission calldata auth
    ) external view onlyPermitted(auth, account) returns (euint64) {
        return _balancesEnc[account];
    }

    /// @notice Returns the encrypted total-supply ciphertext.
    function totalSupplyEncrypted(
        Permission calldata auth
    ) external view onlyPermitted(auth, AUTHORITY) returns (euint64) {
        return _totalSupplyEnc;
    }
    /* --------------------------------------------------------------------------
                         ENCRYPTED TRANSFER
    -------------------------------------------------------------------------- */
    function transfer(address to, uint64 amount) external returns (bool) {
        euint64 amtEnc = FHE.asEuint64(amount);
        _balancesEnc[msg.sender] = FHE.sub(_balancesEnc[msg.sender], amtEnc);
        _balancesEnc[to] = FHE.add(_balancesEnc[to], amtEnc);

        FHE.allowThis(_balancesEnc[msg.sender]);
        FHE.allowThis(_balancesEnc[to]);

        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
