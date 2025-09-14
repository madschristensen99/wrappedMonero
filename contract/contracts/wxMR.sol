// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRiscZeroVerifier {
    function verify(
        bytes calldata seal,
        bytes32 imageId,
        bytes32 journalDigest
    ) external view returns (bool);
}

contract WxMR is ERC20 {
    mapping(bytes32 => bool) public spent;
    address public verifier;
    bytes32 public immutable imageId;

    event Mint(bytes32 indexed KI, address indexed to, uint256 amount);
    event Burn(bytes32 indexed eventId, address indexed from, uint256 amount);

    constructor(
        address _verifier,
        bytes32 _imageId,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        verifier = _verifier;
        imageId = _imageId;
    }

    function mint(
        bytes calldata seal,
        uint256 amount,
        bytes32 KI_hash,
        bytes32 amount_commit
    ) external {
        bytes32 journalDigest = keccak256(abi.encodePacked(
            KI_hash,
            amount_commit,
            uint8(1)
        ));
        
        require(
            IRiscZeroVerifier(verifier).verify(seal, imageId, journalDigest),
            "invalid receipt"
        );
        require(!spent[KI_hash], "KI spent");
        
        spent[KI_hash] = true;
        _mint(msg.sender, amount);
        
        emit Mint(KI_hash, msg.sender, amount);
    }

    function burn(uint256 amount) external {
        bytes32 eventId = keccak256(
            abi.encodePacked(
                block.timestamp,
                block.number,
                msg.sender,
                amount
            )
        );
        
        _burn(msg.sender, amount);
        emit Burn(eventId, msg.sender, amount);
    }

    // Allow updating verifier contract address
    function setVerifier(address _verifier) external {
        require(msg.sender == owner(), "Only owner");
        verifier = _verifier;
    }

    // Owner functions placeholder - in production use proper ownership
    address private _owner;
    
    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
}