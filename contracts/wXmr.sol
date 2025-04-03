// SPDX-License-Identifier: LGPLv3
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title WXMR
 * @dev Wrapped Monero token with fixed bridge address
 */
contract WXMR is ERC20, ERC20Burnable {
    address public immutable bridge;
    
    uint8 private constant _DECIMALS = 12; // XMR has 12 decimal places
    
    event MintedFromSwap(address indexed to, uint256 amount, bytes32 indexed swapId);
    event BurnedForSwap(address indexed from, uint256 amount, bytes32 indexed swapId);
    
    /**
     * @dev Constructor sets the bridge address which will have exclusive minting/burning privileges
     * @param bridgeAddress The address of the WXMRBridge contract
     */
    constructor(address bridgeAddress) ERC20("Wrapped Monero", "WXMR") {
        require(bridgeAddress != address(0), "Bridge address cannot be zero");
        bridge = bridgeAddress;
    }
    
    /**
     * @dev Override decimals to match Monero's 12 decimal places
     */
    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }
    
    /**
     * @dev Mint tokens from a swap, only callable by the bridge
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     * @param swapId The ID of the swap
     */
    function mintFromSwap(address to, uint256 amount, bytes32 swapId) external {
        require(msg.sender == bridge, "Only bridge can mint");
        _mint(to, amount);
        emit MintedFromSwap(to, amount, swapId);
    }
    
    /**
     * @dev Burn tokens for a swap, only callable by the bridge
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     * @param swapId The ID of the swap
     */
    function burnForSwap(address from, uint256 amount, bytes32 swapId) external {
        require(msg.sender == bridge, "Only bridge can burn");
        _burn(from, amount);
        emit BurnedForSwap(from, amount, swapId);
    }
}