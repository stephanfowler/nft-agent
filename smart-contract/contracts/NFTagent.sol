// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

/**
 *  @title NFT Smart Contract
 *  @author Stephan Fowler
 *  @notice ERC721 contract for stand-alone NFT collections with lazy-minting capability
 *  @dev Enables lazy-minting by any user via precomputed signatures
 */
contract NFTagent is ERC721, ERC721Burnable, EIP712 {

    event IdRevoked(uint256 tokenId);
    event IdFloorSet(uint256 idFloor);
    event Receipt(uint256 value);
    event Withdrawal(uint256 value);

    address public immutable owner;
    uint256 public totalSupply = 0;
    uint256 public idFloor = 0;
    
    mapping(uint256 => string) private tokenURIs;
    mapping(uint256 => bool) private revokedIds;

    /**
     *  @dev Constructor immutably sets "owner" to the message sender; be sure to deploy contract using the account of the creator/artist/brand/etc. 
     *  @param name ERC721 token name
     *  @param symbol ERC721 token symbol
     */
    constructor(
        string memory name,
        string memory symbol
    ) 
        ERC721(name, symbol) 
        EIP712("NFTagent", "1.0.0")
    {
        owner = _msgSender();
    }

    receive() external payable {
        emit Receipt(msg.value);
    }

    function withdraw() external {
        require(_msgSender() == owner, "unauthorized to withdraw");
        uint256 balance = address(this).balance;
        (bool success, ) = _msgSender().call{ value : balance }("");
        require(success, "transfer failed");
        emit Withdrawal(balance);
    }

    /**
     *  @notice Minting by the agent only
     *  @param recipient The recipient of the NFT
     *  @param id The intended token Id
     *  @param uri The intended token URI
     */
    function mintAuthorized(address recipient, uint256 id, string memory uri) external {
        require(_msgSender() == owner, "unauthorized to mint");
        require(vacant(id));
        _mint(recipient, id, uri);
    }

    /**
     *  @notice Minting by any caller
     *  @dev Enables "lazy" minting by any user who can provide an agent's signature for the specified params and value
     *  @param id The intended token Id
     *  @param uri The intended token URI
     *  @param signature The ERC712 signature of the hash of message value, id, and uri
     */
    function mint(uint256 id, string memory uri, bytes calldata signature) external payable {
        require(mintable(msg.value, id, uri, signature));
        _mint(_msgSender(), id, uri);
    }

    /**
     *  @notice Checks availability for minting and validity of a signature
     *  @dev Typically run before offering a mint option to users
     *  @param weiPrice The advertised price of the token
     *  @param id The intended token Id
     *  @param uri The intended token URI
     *  @param signature The ERC712 signature of the hash of weiPrice, id, and uri
     */
    function mintable(uint256 weiPrice, uint256 id, string memory uri, bytes calldata signature) public view returns (bool) {
        require(vacant(id));
        require(owner == ECDSA.recover(_hash(weiPrice, id, uri), signature), 'signature invalid or signer unauthorized');
        return true;
    }

    /**
     *  @notice Checks the availability of a token Id
     *  @dev Reverts if the Id is previously minted, revoked, or burnt
     *  @param id The token Id
     */
    function vacant(uint256 id) public view returns(bool) {
        require(!_exists(id), "tokenId already minted");
        require(id >= idFloor, "tokenId below floor");
        require(!revokedIds[id], "tokenId revoked or burnt");
        return true;
    }

    /**
     *  @notice Revokes a specified token Id, to disable any signatures that include it
     *  @param id The token Id that can no longer be minted
     */
    function revokeId(uint256 id) external {
        require(_msgSender() == owner, "unauthorized to revoke id");
        require(vacant(id));
        revokedIds[id] = true;
        IdRevoked(id);
    }

    /**
     *  @notice Revokes token Ids below a given floor, to disable any signatures that include them
     *  @param floor The floor for token Ids minted from now onward
     */
    function setIdFloor(uint256 floor) external {
        require(_msgSender() == owner, "unauthorized to set idFloor");
        require(floor > idFloor, "must exceed current floor");
        idFloor = floor;
        IdFloorSet(idFloor);
    }

    /**
     *  @notice Returns the token URI, given the token Id
     *  @param id The token Id
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        return tokenURIs[id];
    }

    /**
     *  @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Minting also increments totalSupply
     */
    function _mint(address recipient, uint256 id, string memory uri) internal {
        _safeMint(recipient, id);
        _setTokenURI(id, uri);
        totalSupply += 1;
    }

    /**
     * @dev Recreates the hash that the signer (may have) signed
     */
    function _hash(uint256 weiPrice, uint256 id, string memory uri) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("NFT(uint256 weiPrice,uint256 tokenId,string tokenURI)"),
            weiPrice,
            id,
            keccak256(bytes(uri))
        )));
    }

    /**
     * @dev record a token's URI against its Id
     */
    function _setTokenURI(uint256 id, string memory uri) internal {
        require(bytes(uri).length != 0, "tokenURI cannot be empty");
        tokenURIs[id] = uri;
    }

     /**
     * @dev burn a token and prevent the reuse of its Id
     */
    function _burn(uint256 id) internal override {
        super._burn(id);
        delete tokenURIs[id];
        revokedIds[id] = true;
        totalSupply -= 1;
    }
}