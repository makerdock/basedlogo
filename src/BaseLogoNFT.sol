// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBaseColors {
    function tokenIdToColor(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenAttributes(uint256 tokenId, string memory key) external view returns (string memory);
}

contract BaseLogoNFT is ERC721, Ownable {
    using Strings for uint256;

    // Constants
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MINT_PRICE = 0.001 ether;
    address public immutable BASE_COLORS_ADDRESS;
    
    // Token tracking
    uint256 private _currentTokenId;
    bool public isMintingEnabled = true;

    // Storage 
    mapping(uint256 => string) private _overlayChunks;
    mapping(uint256 => uint256) private _baseColorTokenIds;
    mapping(uint256 => bool) private _baseColorTokenIdUsed;
    uint256 private _chunkCount;
    
    // Track all minted tokenIds
    mapping(uint256 => bool) public mintedTokenIds;
    
    // Modifiable attributes
    mapping(uint256 => mapping(string => string)) private _tokenAttributes;
    mapping(uint256 => string[]) private _tokenTraits;

    // Events
    event TokenMinted(
        address indexed recipient, 
        uint256 indexed tokenId, 
        uint256 baseColorTokenId, 
        string baseColorName
    );
    event TokensBatchMinted(
        address indexed recipient,
        uint256[] tokenIds,
        uint256[] baseColorTokenIds
    );
    event OverlayChunkUpdated(uint256 indexed chunkIndex, string chunkData);
    event MintingToggled(bool enabled);
    event PaymentSplit(
        address indexed baseColorOwner, 
        address indexed contractOwner, 
        uint256 amount
    );
    event MetadataUpdate(uint256 _tokenId);

    constructor(address baseColorsAddress) ERC721("TestLogoNFT", "TLNFT") Ownable(msg.sender) {
        BASE_COLORS_ADDRESS = baseColorsAddress;
    }

    /**
     * @dev Mints a new token using a BaseColors token ID
     * @param baseColorTokenId The BaseColors token ID to use
     */
    function mint(uint256 baseColorTokenId) external payable {
        require(isMintingEnabled, "Minting is disabled");
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(_currentTokenId < MAX_SUPPLY, "Max supply reached");
        require(!_baseColorTokenIdUsed[baseColorTokenId], "Base color already used");
        require(isTokenIdEligible(baseColorTokenId), "TokenId not eligible for minting");

        // Get the BaseColors contract
        IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);

        // Verify the base color exists and get its name
        string memory baseColorHex = baseColors.tokenIdToColor(baseColorTokenId);
        require(bytes(baseColorHex).length > 0, "Base color does not exist");
        
        // Get the base color name
        string memory baseColorName = baseColors.tokenAttributes(baseColorTokenId, "Color Name");
        require(bytes(baseColorName).length > 0, "Base color name not found");

        // Get the owner of the base color for payment
        address baseColorOwner = baseColors.ownerOf(baseColorTokenId);

        // Split payment
        uint256 splitAmount = MINT_PRICE / 2;
        
        // Send payment to base color owner
        (bool success1, ) = payable(baseColorOwner).call{value: splitAmount}("");
        require(success1, "Payment to base color owner failed");
        
        // Send payment to contract owner
        (bool success2, ) = payable(owner()).call{value: splitAmount}("");
        require(success2, "Payment to contract owner failed");

        emit PaymentSplit(baseColorOwner, owner(), splitAmount);

        // Mint token
        _currentTokenId++;
        uint256 newItemId = _currentTokenId;
        
        _safeMint(msg.sender, newItemId);
        _baseColorTokenIds[newItemId] = baseColorTokenId;
        _baseColorTokenIdUsed[baseColorTokenId] = true;
        mintedTokenIds[baseColorTokenId] = true;

        // Set attributes
        _tokenTraits[newItemId].push("Base Color");
        _tokenAttributes[newItemId]["Base Color"] = baseColorName;

        emit TokenMinted(msg.sender, newItemId, baseColorTokenId, baseColorName);
    }

    /**
     * @dev Batch mints multiple tokens
     * @param baseColorTokenIds Array of BaseColors token IDs to use
     */
    function batchMint(uint256[] calldata baseColorTokenIds) external payable {
        require(isMintingEnabled, "Minting is disabled");
        uint256 quantity = baseColorTokenIds.length;
        require(msg.value >= MINT_PRICE * quantity, "Insufficient payment");
        require(_currentTokenId + quantity <= MAX_SUPPLY, "Would exceed max supply");

        uint256[] memory newTokenIds = new uint256[](quantity);

        for (uint256 i = 0; i < quantity; i++) {
            uint256 baseColorTokenId = baseColorTokenIds[i];
            require(!_baseColorTokenIdUsed[baseColorTokenId], "Base color already used");
            require(isTokenIdEligible(baseColorTokenId), "TokenId not eligible for minting");

            IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);
            string memory baseColorName = baseColors.tokenAttributes(baseColorTokenId, "Color Name");
            address baseColorOwner = baseColors.ownerOf(baseColorTokenId);

            // Split payment
            uint256 splitAmount = MINT_PRICE / 2;
            (bool success1, ) = payable(baseColorOwner).call{value: splitAmount}("");
            require(success1, "Payment to base color owner failed");
            (bool success2, ) = payable(owner()).call{value: splitAmount}("");
            require(success2, "Payment to contract owner failed");

            _currentTokenId++;
            uint256 newItemId = _currentTokenId;
            
            _safeMint(msg.sender, newItemId);
            _baseColorTokenIds[newItemId] = baseColorTokenId;
            _baseColorTokenIdUsed[baseColorTokenId] = true;
            mintedTokenIds[baseColorTokenId] = true;

            _tokenTraits[newItemId].push("Base Color");
            _tokenAttributes[newItemId]["Base Color"] = baseColorName;

            newTokenIds[i] = newItemId;

            emit PaymentSplit(baseColorOwner, owner(), splitAmount);
        }

        emit TokensBatchMinted(msg.sender, newTokenIds, baseColorTokenIds);
    }

    /**
     * @dev Burns a token
     * @param tokenId Token ID to burn
     */
    function burn(uint256 tokenId) external {
        require(tokenId <= _currentTokenId, "ColorNFT: nonexistent token");
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        uint256 baseColorTokenId = _baseColorTokenIds[tokenId];
        _burn(tokenId);
        delete _baseColorTokenIds[tokenId];
        delete _baseColorTokenIdUsed[baseColorTokenId];
        delete mintedTokenIds[baseColorTokenId];
    }

    /**
     * @dev Returns token URI with metadata
     * @param tokenId Token ID
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(tokenId <= _currentTokenId, "ColorNFT: nonexistent token");
        
        IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);
        uint256 baseColorTokenId = _baseColorTokenIds[tokenId];
        string memory color = baseColors.tokenIdToColor(baseColorTokenId);
        
        string memory svg = generateSVG(color);
        string memory attributes = generateAttributes(tokenId);
        
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "BaseLogoNFT #',
                            tokenId.toString(),
                            '", "description": "An NFT with a colored background and overlay image", "image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(svg)),
                            '", "attributes": ',
                            attributes,
                            "}"
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Checks if a BaseColors token ID is eligible for minting
     * @param tokenId The token ID to check
     * @return bool indicating if the token is eligible
     */
    function isTokenIdEligible(uint256 tokenId) public view returns (bool) {
        if (mintedTokenIds[tokenId]) {
            return false;
        }

        IBaseColors baseColors = IBaseColors(BASE_COLORS_ADDRESS);
        try baseColors.tokenIdToColor(tokenId) returns (string memory color) {
            return bytes(color).length > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev Generates SVG for token
     * @param color The background color
     */
    function generateSVG(string memory color) internal view returns (string memory) {
        string memory overlayBase64 = assembleOverlay();
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">',
                '<rect width="100" height="100" fill="',
                color,
                '"/>',
                '<image href="data:image/svg+xml;base64,',
                overlayBase64,
                '" width="100" height="100"/>',
                '</svg>'
            )
        );
    }

    /**
     * @dev Assembles overlay from chunks
     */
    function assembleOverlay() internal view returns (string memory) {
        string memory result = "";
        for (uint256 i = 0; i < _chunkCount; i++) {
            result = string(abi.encodePacked(result, _overlayChunks[i]));
        }
        return result;
    }

    /**
     * @dev Generates attributes JSON
     * @param tokenId The token ID
     */
    function generateAttributes(uint256 tokenId) internal view returns (string memory) {
        string memory attributes = "[";
        string[] memory traits = _tokenTraits[tokenId];
        
        for (uint256 i = 0; i < traits.length; i++) {
            string memory trait = traits[i];
            string memory value = _tokenAttributes[tokenId][trait];
            
            attributes = string(
                abi.encodePacked(
                    attributes,
                    '{"trait_type":"',
                    trait,
                    '","value":"',
                    value,
                    '"}'
                )
            );
            
            if (i < traits.length - 1) {
                attributes = string(abi.encodePacked(attributes, ","));
            }
        }
        
        return string(abi.encodePacked(attributes, "]"));
    }

    // Admin functions

    /**
     * @dev Sets an overlay chunk
     * @param chunkIndex The chunk index
     * @param chunkData The chunk data
     */
    function setOverlayChunk(uint256 chunkIndex, string calldata chunkData) external onlyOwner {
        _overlayChunks[chunkIndex] = chunkData;
        if (chunkIndex >= _chunkCount) {
            _chunkCount = chunkIndex + 1;
        }
        emit OverlayChunkUpdated(chunkIndex, chunkData);
    }

    /**
     * @dev Toggles minting status
     */
    function toggleMinting() external onlyOwner {
        isMintingEnabled = !isMintingEnabled;
        emit MintingToggled(isMintingEnabled);
    }

    // View functions

    function getOverlayChunk(uint256 chunkIndex) external view returns (string memory) {
        return _overlayChunks[chunkIndex];
    }

    function getChunkCount() external view returns (uint256) {
        return _chunkCount;
    }

    function getBaseColorTokenId(uint256 tokenId) external view returns (uint256) {
        require(tokenId <= _currentTokenId, "ColorNFT: nonexistent token");
        return _baseColorTokenIds[tokenId];
    }

    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
    }

    function isBaseColorUsed(uint256 baseColorTokenId) external view returns (bool) {
        return _baseColorTokenIdUsed[baseColorTokenId];
    }
}