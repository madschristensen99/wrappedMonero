// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title  Wrapped Monero (WXMR)
 * @notice Encrypted balances via Fhenix FHE.
 *         Mint/burn guarded by 3-of-3 multisig (fixed wallets).
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
    event Mint(address indexed to, uint256 amount);
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
        address to,
        uint64 amount,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        uint256 chainId;
        assembly { chainId := chainid() }
        bytes32 digest = keccak256(
            abi.encodePacked("WrappedMonero", chainId, nonce, to, amount)
        );
        return ecrecover(digest, v, r, s);
    }

    /* --------------------------------------------------------------------------
                                 MINT
    -------------------------------------------------------------------------- */
    uint256 private _mintNonce;

    function mint(
        address to,
        uint64 amount,
        uint8[3] calldata v,
        bytes32[3] calldata r,
        bytes32[3] calldata s
    ) external {
        uint256 nonce = _mintNonce++;
        require(
            _recover(to, amount, nonce, v[0], r[0], s[0]) == SIGNER_1 &&
            _recover(to, amount, nonce, v[1], r[1], s[1]) == SIGNER_2 &&
            _recover(to, amount, nonce, v[2], r[2], s[2]) == SIGNER_3,
            "Invalid 3-of-3 multisig"
        );

        euint64 amtEnc = FHE.asEuint64(amount);
        _totalSupplyEnc = FHE.add(_totalSupplyEnc, amtEnc);
        _balancesEnc[to] = FHE.add(_balancesEnc[to], amtEnc);

        FHE.allowThis(_totalSupplyEnc);
        FHE.allowThis(_balancesEnc[to]);

        emit Mint(to, amount);
    }

    /* --------------------------------------------------------------------------
                                 BURN
    -------------------------------------------------------------------------- */
    uint256 private _burnNonce;

    function burn(
        uint64 amount,
        uint8[3] calldata v,
        bytes32[3] calldata r,
        bytes32[3] calldata s
    ) external {
        uint256 nonce = _burnNonce++;
        require(
            _recover(msg.sender, amount, nonce, v[0], r[0], s[0]) == SIGNER_1 &&
            _recover(msg.sender, amount, nonce, v[1], r[1], s[1]) == SIGNER_2 &&
            _recover(msg.sender, amount, nonce, v[2], r[2], s[2]) == SIGNER_3,
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
