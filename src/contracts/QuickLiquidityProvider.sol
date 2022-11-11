// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

import './uniswap/UniswapV2Library.sol';

import "./AggregatorV3Interface.sol";
import "./ISBT721.sol";


interface IQuickLiquidityProvider {

    function swapRequest(bytes calldata message, bytes calldata signature) external payable;

    function settle(string calldata quoteId, address user, address settleAsset, uint256 settleAmount) external;

    function decline(string calldata quoteId, address user, address asset, uint256 fromAmount) external;

    function finalSettle(string calldata quoteId) external;
    
}


contract QuickLiquidityProvider is IQuickLiquidityProvider, Initializable, ReentrancyGuardUpgradeable {

    using ECDSA for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint;
    using SafeMath for uint256;

    struct LiquidityProvider {
        address lpIn;
        address lpOut;
        uint256 credit;
    }

    struct QuoteParameters {
        string quoteId;
        address fromAsset;
        address toAsset;
        uint256 fromAmount;
        uint256 toAmount;
        address lpIn;
        address user;
        uint tradeCompleteDeadline;
        uint quoteConfirmDeadline;
        address compensateToken;
        uint256 compensateAmount;
        uint mode;
    }

    struct QuoteInfo {
        string quoteId;
        address user;
        address lpIn;
        address lpOut;
        address fromAsset;
        address toAsset;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 tradeExpireAt;
        address compensateToken;
        uint256 compensateAmount;
        uint8 status; // 0: pending, 1: abnormal
        uint arrayIndex;
    }

    // uint8 public constant DECIMALS = 18;
    // address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    // address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    address private _owner;
    address private _pendingOwner;
    uint private _timeout;

    ISBT721 public babToken;
    bool public babSwitch;

    mapping(address => mapping(address => mapping(address => uint256))) public whitelistPairToIndex;

    mapping(address => uint256) public liquidityProviderSecure;     // out address => credit
    mapping(address => address) public liquidityProviderMap;        // in address => out address

    mapping(string => QuoteInfo) private quoteMap;
    string[] private quoteArray;

    mapping(address => uint256) public vaultMap;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipAccepted(address indexed previousOwner, address indexed newOwner);
    event BabTokenSet(address indexed babToken, bool value);

    event LiquidityProviderAdded(address indexed lpIn, address indexed lpOut, uint256 credit);
    event LiquidityProviderChanged(address indexed lpIn, address indexed lpOut, uint256 credit);
    event LiquidityProviderDeleted(address indexed lpIn, address indexed lpOut);
    event PairWhiteListAdded(address indexed lp, address token0, address token1);
    event PairWhiteListDeleted(address indexed lp, address token0, address token1);
    event QuoteAccepted(address indexed user, string quoteId);
    event QuoteRemoved(address indexed user, string quoteId);
    event SettlementDone(address indexed user, string quoteId, address asset, uint256 amount);
    event SettlementDecline(address indexed user, string quoteId, address asset, uint256 amount);
    
    function initialize(address owner_, address babToken_, bool babSwitch_) public initializer {
        _init(owner_, babToken_, babSwitch_);
    }

    function _init(address owner_, address babToken_, bool babSwitch_) internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
        _init_unchained(owner_, babToken_, babSwitch_);
    }

    function _init_unchained(address owner_, address babToken_, bool babSwitch_) internal onlyInitializing {
        require(owner_ != address(0), "QuickLiquidityProvider: owner is the zero address");
        _owner = owner_;
        babToken = ISBT721(babToken_);
        babSwitch = babSwitch_;
    }

    receive() external payable {
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "QuickLiquidityProvider: caller is not the owner");
        _;
    }

    modifier onlyLiquidityProvider() {
        require(liquidityProviderSecure[msg.sender] > 0, "QuickLiquidityProvider: caller is not the liqidity provider");
        _;
    }

    modifier onlyBabtUser() {
        require(!babSwitch || babToken.balanceOf(msg.sender) > 0, "QuickLiquidityProvider: caller is not a BABToken holder");
        _;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "QuickLiquidityProvider: new owner is the zero address");
        require(newOwner != _owner, "QuickLiquidityProvider: new owner is the same as the current owner");

        emit OwnershipTransferred(_owner, newOwner);
        _pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == _pendingOwner, "QuickLiquidityProvider: invalid new owner");
        emit OwnershipAccepted(_owner, _pendingOwner);
        _owner = _pendingOwner;
        _pendingOwner = address(0);
    }

    function setBabTokenAddress(address newBabToken) external onlyOwner {
        require(newBabToken != address(0), "QuickLiquidityProvider: new BAB token is the zero address");
        babToken = ISBT721(newBabToken);
        emit BabTokenSet(address(babToken), babSwitch);
    }

    function setBabTokenSwitch(bool value) external onlyOwner {
        babSwitch = value;
        emit BabTokenSet(address(babToken), babSwitch);
    }

    function addLiquidityProvider(address lpIn, address lpOut) external onlyOwner {
        require(lpIn != address(0) && lpOut != address(0), "QuickLiquidityProvider: address is the zero address");

        uint256 index2 = liquidityProviderSecure[lpOut];
        require(index2 == 0, "QuickLiquidityProvider: addressOut is already liquidity provider");

        liquidityProviderSecure[lpOut] = 1;
        liquidityProviderMap[lpIn] = lpOut;
        emit LiquidityProviderAdded(lpIn, lpOut, 1);
    }

    function deleteLiquidityProvider(address lpIn, address lpOut) external onlyOwner {
        require(lpIn != address(0) && lpOut != address(0), "DexLiquidityProvider: address is the zero address");
        
        uint256 index2 = liquidityProviderSecure[lpOut];
        require(index2 != 0, "QuickLiquidityProvider: addressOut is not liquidity provider");

        delete liquidityProviderSecure[lpOut];
        delete liquidityProviderMap[lpIn];
        emit LiquidityProviderDeleted(lpIn, lpOut);
    }

    function addVault(address token_, uint256 amount_) external nonReentrant onlyOwner {
        require(amount_ > 0, "QuickLiquidityProvider: vault value should above zero");
        IERC20Upgradeable(token_).safeTransferFrom(msg.sender, address(this), amount_);
        vaultMap[token_] = vaultMap[token_].add(amount_);
    }

    function removeVault(address token_, uint256 amount_) external nonReentrant onlyOwner {
        require(amount_ <= vaultMap[token_], "QuickLiquidityProvider: vault value should not below zero");
        IERC20Upgradeable(token_).safeTransfer(msg.sender, amount_);
        vaultMap[token_] = vaultMap[token_].sub(amount_);
    }

    function addPairWhitelist(address lp, address tokenA, address tokenB) external onlyOwner {
        require(tokenA != tokenB, 'QuickLiquidityProvider: identical token addresses');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(lp != address(0) && tokenA != address(0) && tokenB != address(0), 'QuickLiquidityProvider: zero address');
        require(whitelistPairToIndex[lp][token0][token1] == 0, 'QuickLiquidityProvider: pair exists'); // single check is sufficient
        
        emit PairWhiteListAdded(lp, token0, token1);
    }

    function removePairWhitelist(address lp, address tokenA, address tokenB) external onlyOwner {
        require(tokenA != tokenB, 'QuickLiquidityProvider: identical token addresses');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 index = whitelistPairToIndex[lp][token0][token1];
        require(index != 0, 'QuickLiquidityProvider: pair not exists'); // single check is sufficient

        delete whitelistPairToIndex[lp][token0][token1];
        emit PairWhiteListDeleted(lp, token0, token1);
    }

    function swapRequest(bytes calldata message, bytes calldata signature) external payable nonReentrant {
        address signer = _source(message, signature);
        QuoteParameters memory params = abi.decode(message, (QuoteParameters));
        string memory quoteId = params.quoteId;
        console.log("signer: ", signer);
        console.log("quoteId: ", quoteId);
        require(liquidityProviderMap[params.lpIn] != address(0), 'QuickLiquidityProvider: invalid liquidity provider');
        address lpOut = liquidityProviderMap[params.lpIn];
        require(params.quoteConfirmDeadline >= block.timestamp, 'QuickLiquidityProvider: EXPIRED');
        require(signer == lpOut, "QuickLiquidityProvider: invalid signer");
        require(quoteMap[quoteId].user == address(0), "QuickLiquidityProvider: duplicate quoteId");

        require(vaultMap[params.toAsset] >= params.toAmount, "QuickLiquidityProvider: vault does not have enough asset for swap. Please go to DexLiquidityProvider");

        quoteMap[quoteId].user = msg.sender;
        quoteMap[quoteId].lpIn = params.lpIn;
        quoteMap[quoteId].lpOut = lpOut;
        quoteMap[quoteId].quoteId = quoteId;
        quoteMap[quoteId].status = 0;
        quoteMap[quoteId].fromAsset = params.fromAsset;
        quoteMap[quoteId].toAsset = params.toAsset;
        quoteMap[quoteId].fromAmount = params.fromAmount;
        quoteMap[quoteId].toAmount = params.toAmount;
        quoteMap[quoteId].tradeExpireAt = params.tradeCompleteDeadline;
        quoteMap[quoteId].compensateToken = params.compensateToken;
        quoteMap[quoteId].compensateAmount = params.compensateAmount;
        quoteArray.push(quoteId);
        quoteMap[quoteId].arrayIndex = quoteArray.length;

        IERC20Upgradeable(params.fromAsset).safeTransferFrom(msg.sender, address(this), params.fromAmount);
        IERC20Upgradeable(params.toAsset).safeTransfer(msg.sender, params.toAmount);
        vaultMap[params.fromAsset] = vaultMap[params.fromAsset].add(params.fromAmount);
        vaultMap[params.toAsset] = vaultMap[params.toAsset].sub(params.toAmount);

        emit QuoteAccepted(msg.sender, quoteId);
    }

    function settle(string calldata quoteId, address user, address settleAsset, uint256 settleAmount) external nonReentrant onlyLiquidityProvider {
        require(quoteMap[quoteId].lpOut == msg.sender, "settlement error, wrong liquidity provider");
        require(quoteMap[quoteId].user == user, "settlement error, user error");
        require(quoteMap[quoteId].toAsset == settleAsset, "settlement error, settlement asset error");
        require(quoteMap[quoteId].toAmount == settleAmount, "settlement error, settlement amount error");
        require(quoteMap[quoteId].tradeExpireAt >= block.timestamp, "settlement error, trade expired");

        IERC20Upgradeable(settleAsset).safeTransferFrom(quoteMap[quoteId].lpIn, address(this), settleAmount);
        IERC20Upgradeable(quoteMap[quoteId].fromAsset).safeTransfer(msg.sender, quoteMap[quoteId].fromAmount);

        _removeRequest(quoteId);
        emit SettlementDone(user, quoteId, settleAsset, settleAmount);
    }

    function decline(string calldata quoteId, address user, address asset, uint256 fromAmount) external nonReentrant onlyLiquidityProvider {
        require(quoteMap[quoteId].lpOut == msg.sender, "settlement error, wrong liquidity provider");
        require(quoteMap[quoteId].user == user, "settlement error, user error");
        require(quoteMap[quoteId].fromAsset == asset, "settlement error, settlement asset error");
        require(quoteMap[quoteId].fromAmount == fromAmount, "settlement error, settlement amount error");
        require(quoteMap[quoteId].tradeExpireAt >= block.timestamp, "settlement error, trade expired");

        quoteMap[quoteId].status = 1;

        emit SettlementDecline(user, quoteId, asset, fromAmount);
    }

    function finalSettle(string calldata quoteId) external nonReentrant onlyOwner {
        require(quoteMap[quoteId].lpIn != address(0), "settlement error, liquidity provider in error");
        require(quoteMap[quoteId].lpOut != address(0), "settlement error, liquidity provider out error");
        require(quoteMap[quoteId].status == 1 || quoteMap[quoteId].tradeExpireAt < block.timestamp, "settlement error, quotation status normal");       

        IERC20Upgradeable(quoteMap[quoteId].toAsset).safeTransferFrom(quoteMap[quoteId].lpOut, address(this), quoteMap[quoteId].toAmount);
        IERC20Upgradeable(quoteMap[quoteId].fromAsset).safeTransfer(quoteMap[quoteId].lpIn, quoteMap[quoteId].fromAmount);
        _removeRequest(quoteId);
    }

    
    function _removeRequest(string memory quoteId) internal {
        _removeQuoteArrayById(quoteId);
        delete quoteMap[quoteId];
    }

    function _removeQuoteArrayById(string memory quoteId) internal {
        uint index = quoteMap[quoteId].arrayIndex;
        _removeQuoteArrayByIndex(index);
    }

    function _removeQuoteArrayByIndex(uint index) internal {
        string memory id = quoteArray[quoteArray.length - 1];
        quoteArray[index] = quoteArray[quoteArray.length - 1];
        quoteMap[id].arrayIndex = index;
        quoteArray.pop();
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "DexLiquidityProvider: transfer bnb failed");
    }

    function _source(bytes memory message, bytes memory signature) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ECDSA.recover(hash, signature);
    }

}