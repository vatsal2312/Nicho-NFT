/**
 * Submitted for verification at BscScan.com on 2022-04-2
 */

// File: contracts/NichoNFT.sol
// SPDX-License-Identifier: MIT


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

pragma solidity >=0.6.0 <0.9.0;

// This is for other NFT contract
interface IOERC721{
    function tokenURI(uint256 tokenId) external view returns (string memory);

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId) external view returns (address operator);
}

contract NichoNFT is ERC721Enumerable, Ownable {

    // CommissionFee percent is 1.5%
    uint256 public commissionFee = 15;
    uint256 public denominator = 10;

    struct Item {
        uint256 id;
        address creater;
        string uri;
    }
    // token address => tokenId => item
    mapping (address => mapping(uint256 => Item)) public Items;

    address payable public _feeAddress;
    // user wallet => inBlackList  for charity
    mapping (address => bool) public whitelist;

    // token address => tokenId => inBlackList
    mapping (address => mapping(uint =>  bool)) public blackList;
    // token address => tokenId => price
    mapping (address => mapping (uint => uint)) public price;
    // token address => tokenId => isListed?
    mapping (address => mapping(uint => bool)) public listedMap;

    event Purchase(address tokenAddress, address indexed previousOwner, address indexed newOwner, uint price, uint nftID, string uri);

    event Added(address indexed minter, address tokenAddress, uint price, uint nftID, string uri);

    event PriceUpdate(address tokenAddress, address indexed owner, uint oldPrice, uint newPrice, uint nftID);

    event UpdateListStatus(address tokenAddress, address indexed owner, uint nftID, bool isListed);

    event UpdateBlackList(address tokenAddress, uint256 nftID, bool isBlackList);

    constructor(address _owner) ERC721("NichoNFT", "NICHO") {
        require(_owner != address(0x0), "Invalid address");
        _feeAddress = payable(_owner);
    }

    modifier notBlackList(address tokenAddress, uint256 _tokenId) {
        require(blackList[tokenAddress][_tokenId] == false, "TokenId is in blackList");
        _;
    }

    // Create item
    function mint(string memory _tokenURI, address _toAddress, uint _price) public returns (uint) {
        require(_toAddress != address(0x0), "Invalid address");

        uint _tokenId = totalSupply(); 
        price[address(this)][_tokenId] = _price;
        listedMap[address(this)][_tokenId] = true;

        _safeMint(_toAddress, _tokenId);
        
        Item storage item = Items[address(this)][_tokenId];
        item.uri = _tokenURI;
        item.id = _tokenId;
        item.creater = _toAddress;

        emit Added(_toAddress, address(this), _price, _tokenId, _tokenURI);

        return _tokenId;
    }

    function addItemToMarket(address tokenAddress, uint256 tokenId, uint256 askingPrice) external {
        require(Items[tokenAddress][tokenId].creater == address(0), "Item is already up sale");

        IOERC721 tokenContract = IOERC721(tokenAddress);
        require(tokenContract.ownerOf(tokenId) == msg.sender, "Not right to add nft");
        require(tokenContract.getApproved(tokenId) == address(this));

        Item storage item = Items[tokenAddress][tokenId];
        item.uri = tokenContract.tokenURI(tokenId);
        item.id = tokenId;
        item.creater = msg.sender;

        price[tokenAddress][tokenId] = askingPrice;
        listedMap[tokenAddress][tokenId] = true;

        emit Added(msg.sender, tokenAddress, askingPrice, tokenId, tokenContract.tokenURI(tokenId));
    }

    // Batch creation
    function batchMint(string memory _tokenURI, address _toAddress, uint _price, uint _amount) external {
        require(_amount > 0, "wrong amount");

        for(uint idx = 0; idx < _amount; idx++) {
            mint(_tokenURI, _toAddress, _price);
        }
    }

    function tokenURI(uint256 tokenId) public view  override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return Items[address(this)][tokenId].uri;
    }

    // TokenId
    function buy(address tokenAddress, uint _id) notBlackList(tokenAddress, _id) external payable {
        _validate(tokenAddress, _id);
        IOERC721 tokenContract = IOERC721(tokenAddress);

        address _previousOwner = tokenContract.ownerOf(_id);
        address _newOwner = msg.sender;

        _trade(tokenAddress, _id);

        emit Purchase(tokenAddress, _previousOwner, _newOwner, price[tokenAddress][_id], _id, tokenContract.tokenURI(_id));
    }

    function _validate(address tokenAddress, uint _id) internal {
        IOERC721 tokenContract = IOERC721(tokenAddress);
        bool isItemListed = listedMap[tokenAddress][_id];
        require(isItemListed, "Item not listed currently");
        require(msg.value >= price[tokenAddress][_id], "Error, the amount is lower");
        require(msg.sender != tokenContract.ownerOf(_id), "Can not buy what you own");
    }

    function _trade(address tokenAddress, uint _id) internal {
        IOERC721 tokenContract = IOERC721(tokenAddress);
        
        bool isInWhiteList = whitelist[msg.sender] || whitelist[tokenContract.ownerOf(_id)];

        address payable _buyer = payable(msg.sender);
        address payable _owner = payable(tokenContract.ownerOf(_id));

        if (tokenAddress == address(this)) _transfer(_owner, _buyer, _id);
        else tokenContract.safeTransferFrom(_owner, msg.sender, _id);

        // commission cut
        uint _commissionValue = price[tokenAddress][_id] * commissionFee / denominator / 100 ;

        if (isInWhiteList) _commissionValue = 0;

        uint _sellerValue = price[tokenAddress][_id] - _commissionValue;

        _owner.transfer(_sellerValue);

        if (_commissionValue > 0) {
            _feeAddress.transfer(_commissionValue);
        }

        // If buyer sent more than price, we send them back their rest of funds
        if (msg.value > price[tokenAddress][_id]) {
            _buyer.transfer(msg.value - price[tokenAddress][_id]);
        }

        listedMap[tokenAddress][_id] = false;
    }

    // Update owner's NFT price
    function updatePrice(address tokenAddress, uint _tokenId, uint _price) notBlackList(tokenAddress, _tokenId) public returns (bool) {
        uint oldPrice = price[tokenAddress][_tokenId];
        IOERC721 tokenContract = IOERC721(tokenAddress);
        
        require(oldPrice != _price, "This price already set");
        require(msg.sender == tokenContract.ownerOf(_tokenId), "Error, you are not the owner");
        price[tokenAddress][_tokenId] = _price;

        emit PriceUpdate(tokenAddress, msg.sender, oldPrice, _price, _tokenId);
        return true;
    }

    function updateListingStatus(address tokenAddress, uint _tokenId, bool shouldBeListed) notBlackList(tokenAddress, _tokenId) public returns (bool) {
        IOERC721 tokenContract = IOERC721(tokenAddress);
        require(msg.sender == tokenContract.ownerOf(_tokenId), "Error, you are not the owner");
        require(listedMap[tokenAddress][_tokenId] != shouldBeListed, "The status is going to be same");

        listedMap[tokenAddress][_tokenId] = shouldBeListed;

        emit UpdateListStatus(tokenAddress, msg.sender, _tokenId, shouldBeListed);

        return true;
    }

    // Update the fee address
    function updateFeeAddress(address newFeeAddress) external onlyOwner {
        require(_feeAddress != newFeeAddress, "Fee address: already set");
        require(newFeeAddress != address(0x0), "Zero address is not allowed for fee address");

        _feeAddress = payable(newFeeAddress);
    }

    // BlackList
    function addBlackList(address tokenAddress, uint256 _tokenId) external onlyOwner {
        require(blackList[tokenAddress][_tokenId] == false, "Already in blacklist");
        blackList[tokenAddress][_tokenId] = true;

        listedMap[tokenAddress][_tokenId] = false;
        emit UpdateListStatus(tokenAddress, msg.sender, _tokenId, false);
        emit UpdateBlackList(tokenAddress, _tokenId, true);
    }

    function removeBlackList(address tokenAddress, uint256 _tokenId) external onlyOwner {
        require(blackList[tokenAddress][_tokenId], "Not exist in blacklist");

        blackList[tokenAddress][_tokenId] = false;

        emit UpdateBlackList(tokenAddress, _tokenId, false);
    }

    // WhiteList
    function addWhiteList(address charity) external onlyOwner {
        require(whitelist[charity] == false, "Already in whitelist");
        whitelist[charity] = true;
    }

    function removeWhiteList(address charity) external onlyOwner {
        require(whitelist[charity] == true, "Already in whitelist");
        whitelist[charity] = false;
    }

    // Withdraw ERC20 tokens
    // For unusual case, if customers sent their any ERC20 tokens into marketplace, we need to send it back to them
    function withdrawTokens(address _token, uint256 _amount) external onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "Wrong amount");

        IERC20(_token).transfer(msg.sender, _amount);
    }
}
