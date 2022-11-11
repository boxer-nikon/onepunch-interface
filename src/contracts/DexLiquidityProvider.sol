// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

import './uniswap/UniswapV2Library.sol';
import "./AggregatorV3Interface.sol";
import "./DexBase.sol";


interface IDexLiquidityProvider {

    function swapRequest(bytes calldata message, bytes calldata signature) external payable;

    function settle(string calldata quoteId, address user, address settleAsset, uint256 settleAmount) external;

    function decline(string calldata quoteId, address user, address asset, uint256 fromAmount) external;

    function calculateCompensate(address user, string[] memory idArray) external view returns (uint256); 

    function compensate(string[] memory idArray) external;
}


contract DexLiquidityProvider is DexBase, IDexLiquidityProvider, Initializable, ReentrancyGuardUpgradeable {

    using ECDSA for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // uint8 public constant DECIMALS = 18;
    // address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    // address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    uint private _timeout;

    address public compensateToken;

    mapping(address => mapping(address => mapping(address => uint256))) public whitelistPairToIndex;

    mapping(address => uint256) public liquidityProviderSecure;     // out address => credit
    mapping(address => uint256) public liquidityProviderPending;    // out address => pending number

    mapping(string => QuoteInfo) private quoteMap;

    event SecureFundAdded(address indexed lpOut, address token, uint256 amount);
    event SecureFundRemoved(address indexed lpOut, address token, uint256 amount);
    event PairWhiteListAdded(address indexed lp, address token0, address token1);
    event PairWhiteListDeleted(address indexed lp, address token0, address token1);
    event QuoteAccepted(address indexed user, string quoteId);
    event QuoteRemoved(address indexed user, string quoteId);
    event SettlementDone(address indexed user, string quoteId, address asset, uint256 amount);
    event SettlementDecline(address indexed user, string quoteId, address asset, uint256 amount);
    
    function initialize(address owner_, address babToken_, bool babSwitch_, address compensateToken_) public initializer {
        _init(owner_, babToken_, babSwitch_, compensateToken_);
    }

    function _init(address owner_, address babToken_, bool babSwitch_, address compensateToken_) internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
        _init_unchained(owner_, babToken_, babSwitch_, compensateToken_);
    }

    function _init_unchained(address owner_, address babToken_, bool babSwitch_, address compensateToken_) internal onlyInitializing {
        require(owner_ != address(0), "DexLiquidityProvider: owner is the zero address");
        _owner = owner_;
        babToken = ISBT721(babToken_);
        babSwitch = babSwitch_;
        compensateToken = compensateToken_;
    }

    receive() external payable {
    }

    function quoteQuery(string memory quoteId) external view returns (QuoteInfo memory info) {
        return quoteMap[quoteId];
    }

    function addLiquidityProvider(address lpIn, address lpOut) external onlyOwner {
        require(lpIn != address(0) && lpOut != address(0), "DexLiquidityProvider: address is the zero address");

        uint256 index2 = liquidityProviders[lpOut];
        require(index2 == 0, "DexLiquidityProvider: addressOut is already liquidity provider");

        liquidityProviders[lpOut] = 1;
        liquidityProviderMap[lpIn] = lpOut;
        emit LiquidityProviderAdded(lpIn, lpOut, 1);
    }

    function deleteLiquidityProvider(address lpIn, address lpOut) external onlyOwner {
        require(lpIn != address(0) && lpOut != address(0), "DexLiquidityProvider: address is the zero address");
        
        uint256 index2 = liquidityProviderSecure[lpOut];
        require(index2 != 0, "DexLiquidityProvider: addressOut is not liquidity provider");

        IERC20Upgradeable(compensateToken).safeTransfer(lpOut, liquidityProviderSecure[lpOut]);

        delete liquidityProviders[lpOut];
        delete liquidityProviderMap[lpIn];
        delete liquidityProviderSecure[lpOut];
        delete liquidityProviderPending[lpOut];
        emit LiquidityProviderDeleted(lpIn, lpOut);
    }

    function addSecureFund(address token_, uint256 amount_) external nonReentrant onlyLiquidityProvider {
        require(amount_ > 0, "DexLiquidityProvider: secure fund should above zero");
        require(token_ == compensateToken, "DexLiquidityProvider: not same compensation token");
        IERC20Upgradeable(token_).safeTransferFrom(msg.sender, address(this), amount_);
        liquidityProviderSecure[msg.sender] = liquidityProviderSecure[msg.sender] + amount_;
        emit SecureFundAdded(msg.sender, token_, amount_);
    }

    function removeSecureFund(address token_, uint256 amount_) external nonReentrant onlyLiquidityProvider {
        require(amount_ <= liquidityProviderSecure[msg.sender], "DexLiquidityProvider: secure fund should above zero");
        require(token_ == compensateToken, "DexLiquidityProvider: not same compensation token");
        IERC20Upgradeable(token_).safeTransfer(msg.sender, amount_);
        liquidityProviderSecure[msg.sender] = liquidityProviderSecure[msg.sender] - amount_;
        emit SecureFundRemoved(msg.sender, token_, amount_);
    }

    function addPairWhitelist(address lp, address tokenA, address tokenB) external onlyOwner {
        require(tokenA != tokenB, 'DexLiquidityProvider: identical token addresses');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(lp != address(0) && tokenA != address(0) && tokenB != address(0), 'DexLiquidityProvider: zero address');
        require(whitelistPairToIndex[lp][token0][token1] == 0, 'DexLiquidityProvider: pair exists'); // single check is sufficient
        
        emit PairWhiteListAdded(lp, token0, token1);
    }

    function removePairWhitelist(address lp, address tokenA, address tokenB) external onlyOwner {
        require(tokenA != tokenB, 'DexLiquidityProvider: identical token addresses');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 index = whitelistPairToIndex[lp][token0][token1];
        require(index != 0, 'DexLiquidityProvider: pair not exists'); // single check is sufficient

        delete whitelistPairToIndex[lp][token0][token1];
        emit PairWhiteListDeleted(lp, token0, token1);
    }

    function swapRequest(bytes calldata message, bytes calldata signature) external payable nonReentrant {
        address signer = _source(message, signature);
        console.log("signer: ", signer);
        QuoteParameters memory params = abi.decode(message, (QuoteParameters));
        string memory quoteId = params.quoteId;
        console.log("quoteId: ", quoteId);
        require(params.mode == 1, 'DexLiquidityProvider: wrong settlement mode');
        require(liquidityProviderMap[params.lpIn] != address(0), 'DexLiquidityProvider: invalid liquidity provider');
        address lpOut = liquidityProviderMap[params.lpIn];
        require(params.quoteConfirmDeadline >= block.timestamp, 'DexLiquidityProvider: EXPIRED');
        require(signer == lpOut, "DexLiquidityProvider: invalid signer");
        require(quoteMap[quoteId].user == address(0), "DexLiquidityProvider: duplicate quoteId");
        
        uint256 targetSecure = liquidityProviderPending[lpOut] + params.compensateAmount;
        require(targetSecure < liquidityProviderSecure[lpOut], "DexLiquidityProvider: liquidity provider has not enough secure fund");

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

        liquidityProviderPending[lpOut] = targetSecure;

        IERC20Upgradeable(params.fromAsset).safeTransferFrom(msg.sender, address(this), params.fromAmount);

        emit QuoteAccepted(msg.sender, quoteId);
    }

    function settle(string calldata quoteId, address user, address settleAsset, uint256 settleAmount) external nonReentrant onlyLiquidityProvider {
        console.log(quoteMap[quoteId].lpOut);
        require(quoteMap[quoteId].lpOut == msg.sender, "settlement error, wrong liquidity provider");
        require(quoteMap[quoteId].user == user, "settlement error, user error");
        require(quoteMap[quoteId].toAsset == settleAsset, "settlement error, settlement asset error");
        require(quoteMap[quoteId].toAmount == settleAmount, "settlement error, settlement amount error");
        require(quoteMap[quoteId].tradeExpireAt >= block.timestamp, "settlement error, trade expired");

        liquidityProviderPending[msg.sender] = Math.max(liquidityProviderPending[msg.sender] - quoteMap[quoteId].compensateAmount, 0);
        IERC20Upgradeable(settleAsset).safeTransferFrom(msg.sender, user, settleAmount);
        IERC20Upgradeable(quoteMap[quoteId].fromAsset).safeTransfer(quoteMap[quoteId].lpIn, quoteMap[quoteId].fromAmount);
        
        _removeRequest(quoteId);
        emit SettlementDone(user, quoteId, settleAsset, settleAmount);
    }

    function decline(string calldata quoteId, address user, address asset, uint256 fromAmount) external nonReentrant onlyLiquidityProvider {
        require(quoteMap[quoteId].lpOut == msg.sender, "settlement error, wrong liquidity provider");
        require(quoteMap[quoteId].user == user, "settlement error, user error");
        require(quoteMap[quoteId].fromAsset == asset, "settlement error, settlement asset error");
        require(quoteMap[quoteId].fromAmount == fromAmount, "settlement error, settlement amount error");
        require(quoteMap[quoteId].tradeExpireAt >= block.timestamp, "settlement error, trade expired");
       
        IERC20Upgradeable(asset).safeTransfer(user, fromAmount);
         _compensateChange(quoteId);

        _declineRequest(quoteId);
        emit SettlementDecline(user, quoteId, asset, fromAmount);
    }

    function calculateCompensate(address user_, string[] memory idArray) public view returns (uint256) {
        uint256 amount = 0;
        for (uint i = 0; i < idArray.length; i++) {
            string memory id = idArray[i];
            if (quoteMap[id].user != address(0) && quoteMap[id].user == user_) {
                if (block.timestamp > quoteMap[id].tradeExpireAt || quoteMap[id].status == 1) {
                    amount = amount + quoteMap[id].compensateAmount;
                }
            }
        }
        return amount;
    }

    function compensate(string[] memory idArray) external nonReentrant {
        uint256 amount = calculateCompensate(msg.sender, idArray);
        require(amount > 0, "DexLiquidityProvider: compensate amount should above zero.");
        IERC20Upgradeable(compensateToken).safeTransfer(msg.sender, amount);
        // remove quotations and 
        for (uint i = 0; i < idArray.length; i++) {
            string memory id = idArray[i];
            if (quoteMap[id].user != address(0) && quoteMap[id].user == msg.sender) {
                if (block.timestamp > quoteMap[id].tradeExpireAt || quoteMap[id].status == 1) {
                    _compensateChange(id);
                    _removeRequest(id);
                }
            }
        }
    }

    function _compensateChange(string memory quoteId) internal {
        address lpOut = quoteMap[quoteId].lpOut;
        liquidityProviderPending[lpOut] = Math.max(liquidityProviderPending[lpOut] - quoteMap[quoteId].compensateAmount, 0);
        liquidityProviderSecure[lpOut] = Math.max(liquidityProviderSecure[lpOut] - quoteMap[quoteId].compensateAmount, 0);
    }

    function _removeRequest(string memory quoteId) internal {
        quoteMap[quoteId].status = 2;
    }

    function _declineRequest(string memory quoteId) internal {
        quoteMap[quoteId].status = 1;
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