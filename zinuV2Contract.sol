// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
/*

███████ ██ ███    ██ ██    ██ 
   ███  ██ ████   ██ ██    ██ 
  ███   ██ ██ ██  ██ ██    ██ 
 ███    ██ ██  ██ ██ ██    ██ 
███████ ██ ██   ████  ██████  
                                       
Linktree: 
https://linktr.ee/ZombieInu

Website: 
https://wearezinu.com

Telegram: 
https://t.me/zombieinuofficial

Discord: 
https://discord.com/invite/wearezinu

Medium: 
https://medium.com/@ZombieInu

OpenSea: 
https://opensea.io/collection/zombiemobsecretsociety

Whitepaper: 
https://app.pitch.com/app/presentation/58d34159-9a3a-4898-b6e7-5c63bc85304b/1f5600fb-72bf-4d68-abaf-173a4b6c56aa

*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    
}

contract ZINU is Context, IERC20, Ownable {
    
    using SafeMath for uint256;

    string private constant _name = "ZINU";
    string private constant _symbol = "ZINU";
    uint8 private constant _decimals = 9;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _tTotal; //Total Supply
    uint256 private _tBurned; //Total Burned

    uint256 public maxSwapAmount;
    uint256 public maxHodlAmount;
    uint256 public contractSwapThreshold;
    uint256 public buybackThreshold;

    //Buy Fees
    uint256 private bBurnFee; 
    uint256 private bLPFee; 
    uint256 private bMarketingFee; 
    uint256 private bBuybackFee; 

    //Sell Fee
    uint256 private sBurnFee; 
    uint256 private sLPFee; 
    uint256 private sMarketingFee; 
    uint256 private sBuybackFee; 

    //Early Max Sell Fee (Decay)
    uint256 private sEarlySellFee;
    
    //Previous Fee 
    uint256 private pBurnFee = rBurnFee;
    uint256 private pLPFee = rLPFee;
    uint256 private pMarketingFee = rMarketingFee;
    uint256 private pBuybackFee = rBuybackFee;
    uint256 private pEarlySellFee = rEarlySellFee;

    //Real Fee
    uint256 private rBurnFee;
    uint256 private rLPFee;
    uint256 private rMarketingFee;
    uint256 private rBuybackFee;
    uint256 private rEarlySellFee;

    struct FeeBreakdown {
        uint256 tBurn;
        uint256 tLiq;
        uint256 tMarket;
        uint256 tBuyback;
        uint256 tEarlySell;
        uint256 tAmount;
    }

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) public preTrader;
    mapping(address => bool) public bots;

    address payable private _taxWallet1;
    address payable private _taxWallet2;

    address private _buybackTokenReceiver;
    address private _lpTokensReceiver;
    
    IUniswapV2Router02 private uniswapV2Router;
    address public uniswapV2Pair;

    bool private contractSwapEnabled;
    bool private contractSwapping;

    //Decaying Tax Logic
    uint256 private decayTaxExpiration;
    mapping(address => uint256) private buyTracker;
    mapping(address => uint256) private lastBuyTimestamp;
    mapping(address => uint256) private sellTracker;

    bool private tradingOpen;

    modifier lockSwap {
        contractSwapping = true;
        _;
        contractSwapping = false;
    }

    constructor() {

        //Initialize numbers for token
        _tTotal = 1000000000 * 10**9; //Total Supply
        maxSwapAmount = _tTotal.mul(10).div(10000); //0.1%
        maxHodlAmount = _tTotal.mul(100).div(10000); //1%
        contractSwapThreshold = _tTotal.mul(10).div(10000); //0.1%
        buybackThreshold = 10; //10 wei

        //Buy Fees
        bBurnFee = 100; 
        bLPFee = 100; 
        bMarketingFee = 200; 
        bBuybackFee = 100; 

        //Sell Fee
        sBurnFee = 100; 
        sLPFee = 100; 
        sMarketingFee = 200; 
        sBuybackFee = 100; 
        sEarlySellFee = 700;
            
        _taxWallet1 = payable(0x1ac943b22593464FBd00ae0dC07F98e1F881bd01);
        _taxWallet2 = payable(0x6A53c4cde998556F8507240F9A431D5Baa9072eC);
        _buybackTokenReceiver = 0xD951bf2928c9aDc3BE5C4B310F93A7bb37223454;
        _lpTokensReceiver = 0x1ac943b22593464FBd00ae0dC07F98e1F881bd01;

        contractSwapEnabled = true;
        tradingOpen = false;
        contractSwapping = false;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[_taxWallet1] = true;
        _isExcludedFromFee[_taxWallet2] = true;
        _isExcludedFromFee[_buybackTokenReceiver] = true;
        _isExcludedFromFee[_lpTokensReceiver] = true;
        _isExcludedFromFee[address(this)] = true;
        preTrader[owner()] = true;

        //initialie decay tax
        decayTaxExpiration = 8 days;

        emit Transfer(address(0), _msgSender(), _tTotal);

    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function totalBurned() public view returns (uint256) {
        return _tBurned;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender,_msgSender(),_allowances[sender][_msgSender()].sub(amount,"ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function removeAllFee() private {
        if (rBurnFee == 0 && rLPFee == 0 && rMarketingFee == 0 && rBuybackFee == 0 && rEarlySellFee == 0) return;
        
        pBurnFee = rBurnFee;
        pLPFee = rLPFee;
        pMarketingFee = rMarketingFee;
        pBuybackFee = rBuybackFee;
        pEarlySellFee = rEarlySellFee;

        rBurnFee = 0;
        rLPFee = 0;
        rMarketingFee = 0;
        rBuybackFee = 0;
        rEarlySellFee = 0;
    }
    
    function restoreAllFee() private {
        rBurnFee = pBurnFee;
        rLPFee = pLPFee;
        rMarketingFee = pMarketingFee;
        rBuybackFee = pBuybackFee;
        rEarlySellFee = pEarlySellFee;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) private {

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!bots[from] && !bots[to], "You are blacklisted");

        bool takeFee = true;

        if (from != owner() && to != owner() && !preTrader[from] && !preTrader[to] && from != address(this) && to != address(this)) {

            //Trade start check
            if (!tradingOpen) {
                require(preTrader[from], "TOKEN: This account cannot send tokens until trading is enabled");
            }

            //Max wallet Limit
            if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
                require(balanceOf(to).add(amount) < maxHodlAmount, "TOKEN: Balance exceeds wallet size!");
            }
            
            //Max txn amount limit
            require(amount <= maxSwapAmount, "TOKEN: Max Transaction Limit");

            //Set Fee for Buys
            if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
                rBurnFee = bBurnFee;
                rLPFee = bLPFee;
                rMarketingFee = bMarketingFee;
                rBuybackFee = bBuybackFee;
                rEarlySellFee = 0;
            }
                
            //Set Fee for Sells
            if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
                rBurnFee = sBurnFee;
                rLPFee = sLPFee;
                rMarketingFee = sMarketingFee;
                rBuybackFee = sBuybackFee;
                rEarlySellFee = sEarlySellFee;
            }
           
            if(!contractSwapping && contractSwapEnabled && from != uniswapV2Pair) {

                uint256 contractTokenBalance = balanceOf(address(this));

                if(contractTokenBalance >= maxSwapAmount) {
                    contractTokenBalance = maxSwapAmount;
                }
                
                if (contractTokenBalance > contractSwapThreshold) {
                    processDistributions(contractTokenBalance);
                }

            }
            
        }

        //No tax on Transfer Tokens
        if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
            takeFee = false;
        }

        _tokenTransfer(from, to, amount, takeFee);

    }

    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        
        if(!takeFee) {
            removeAllFee();
        }

        //Define Fee amounts
        FeeBreakdown memory fees;
        fees.tBurn = amount.mul(rBurnFee).div(10000);
        fees.tLiq = amount.mul(rLPFee).div(10000);
        fees.tMarket = amount.mul(rMarketingFee).div(10000);
        fees.tBuyback = amount.mul(rBuybackFee).div(10000);

        fees.tEarlySell = 0;
        if(rEarlySellFee > 0) {
            uint256 finalEarlySellFee = getUserEarlySellTax(sender, amount, rEarlySellFee);
            fees.tEarlySell = amount.mul(finalEarlySellFee).div(10000);
        }

        //Calculate total fee amount
        uint256 totalFeeAmount = fees.tBurn.add(fees.tLiq).add(fees.tBuyback).add(fees.tMarket).add(fees.tEarlySell);
        fees.tAmount = amount.sub(totalFeeAmount);

        //Update balances
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(fees.tAmount);
        _balances[address(this)] = _balances[address(this)].add(totalFeeAmount);
        
        emit Transfer(sender, recipient, fees.tAmount);
        if(totalFeeAmount > 0) {
            emit Transfer(sender, address(this), totalFeeAmount);
        }
        restoreAllFee();

        //Update decay tax for user
        //Set for Buys
        if(sender == uniswapV2Pair && recipient != address(uniswapV2Router)) {
            buyTracker[recipient] += amount;
            lastBuyTimestamp[recipient] = block.timestamp;
        }
            
        //Set for Sells
        if (recipient == uniswapV2Pair && sender != address(uniswapV2Router)) {
            sellTracker[sender] += amount;
        }

        // if the sell tracker equals or exceeds the amount of tokens bought,
        // reset all variables here which resets the time-decaying sell tax logic.
        if(sellTracker[sender] >= buyTracker[sender]) {
            resetBuySellDecayTax(sender);
        }
        
        // handles transferring to a fresh wallet or wallet that hasn't bought tokens before
        if(lastBuyTimestamp[recipient] == 0) {
            resetBuySellDecayTax(recipient);
        }

    }
    
    /// @notice Get user decayed tax
    function getUserEarlySellTax(address _seller, uint256 _sellAmount, uint256 _earlySellFee) public view returns (uint256) {
        uint256 _tax = _earlySellFee;

        if(lastBuyTimestamp[_seller] == 0) {
            return _tax;
        }

        if(sellTracker[_seller] + _sellAmount > buyTracker[_seller]) {
            return _tax;
        }

        if(block.timestamp > getSellEarlyExpiration(_seller)) {
            return 0;
        }

        uint256 _secondsAfterBuy = block.timestamp - lastBuyTimestamp[_seller];
        return (_tax * (decayTaxExpiration - _secondsAfterBuy)) / decayTaxExpiration;
    }

    function getSellEarlyExpiration(address _seller) private  view returns (uint256) {
        return lastBuyTimestamp[_seller] == 0 ? 0 : lastBuyTimestamp[_seller] + decayTaxExpiration;
    }

    function resetBuySellDecayTax(address _user) private {
        buyTracker[_user] = balanceOf(_user);
        lastBuyTimestamp[_user] = block.timestamp;
        sellTracker[_user] = 0;
    }

    //Buyback Module
    function buyBackTokens() private lockSwap {
        if(address(this).balance > 0) {
    	    swapETHForTokens(address(this).balance);
        }
    }

    function swapETHForTokens(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0, // accept any amount of Tokens
            path,
            _buybackTokenReceiver, //Send bought tokens to this address
            block.timestamp.add(300)
        );
    }

    function swapTokensForEth(uint256 tokenAmount) private lockSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            _lpTokensReceiver,
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        _taxWallet1.transfer(amount.div(2));
        _taxWallet2.transfer(amount.div(2));
    }

    //True Burn
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _tTotal = _tTotal.sub(amount);
        _tBurned = _tBurned.add(amount);
        
        emit Transfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function processDistributions(uint256 tokens) private {

        uint256 totalTokensFee = sBurnFee + sMarketingFee + sLPFee + sBuybackFee;

        //Get tokens to stay in contract
        uint tokensForLP = (tokens * sLPFee / totalTokensFee)/2; //alf of tokens goes to LP and another half as ETH
        uint tokensForBurn = (tokens * sBurnFee / totalTokensFee);

        //Get tokens to swap for ETH
        uint tokensForETHSwap = tokens - (tokensForBurn + tokensForBurn);

        //Swap for eth
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokensForETHSwap);
        uint256 newETHBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForMarketing = newETHBalance * sMarketingFee / (totalTokensFee - (sLPFee/2) - sBurnFee);
        uint256 ethForLP = newETHBalance * (sLPFee/2) / (totalTokensFee - (sLPFee/2) - sBurnFee);

        //Send eth share to distribute to tax wallets        
        sendETHToFee(ethForMarketing);
        //Send lp share along with tokens to add LP
        addLiquidity(tokensForLP, ethForLP);
        //Burn
        _burn(address(this), tokensForBurn);

        //Leave the remaining eth in contract itself for buybacking
        //Process buyback
        if(address(this).balance >= buybackThreshold) {
            buyBackTokens();
        }

    }
    
    /// @notice Manually convert tokens in contract to Eth
    function manualswap() external {
        require(_msgSender() == _taxWallet1 || _msgSender() == _taxWallet2 || _msgSender() == owner());
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance > 0) {
            swapTokensForEth(contractBalance);
        }
    }

    /// @notice Manually send ETH in contract to marketing wallets
    function manualsend() external {
        require(_msgSender() == _taxWallet1 || _msgSender() == _taxWallet2 || _msgSender() == owner());
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            sendETHToFee(contractETHBalance);
        }
    }

    /// @notice Manually execute buyback with Eth availabe in contract
    function manualBuyBack() external {
        require(_msgSender() == _taxWallet1 || _msgSender() == _taxWallet2 || _msgSender() == owner());
        require(address(0).balance > 0, "No ETH in contract to buyback");
        buyBackTokens();
    }

    receive() external payable {}

    /// @notice Add an address to a pre trader
    function allowPreTrading(address account, bool allowed) public onlyOwner {
        require(preTrader[account] != allowed, "TOKEN: Already enabled.");
        preTrader[account] = allowed;
    }

    /// @notice Add multiple address to exclude/include fee
    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = excluded;
        }
    }

    /// @notice Block address from transfer
    function blockMultipleBots(address[] calldata _bots, bool status) public onlyOwner {
        for(uint256 i = 0; i < _bots.length; i++) {
            bots[_bots[i]] = status;
        }
    }

    /// @notice Enable disable trading
    function setTrading(bool _tradingOpen) public onlyOwner {
        tradingOpen = _tradingOpen;
    }

    /// @notice Enable/Disable contract fee distribution
    function toggleContractSwap(bool _contractSwapEnabled) public onlyOwner {
        contractSwapEnabled = _contractSwapEnabled;
    }

    //Settings: Limits
    /// @notice Set maximum wallet limit
    function setMaxHodlAmount(uint256 _maxHodlAmount) public onlyOwner() {
        require(_maxHodlAmount > _tTotal.div(1000), "Amount must be greater than 0.1% of supply");
        maxHodlAmount = _maxHodlAmount;
    }

    /// @notice Set max amount a user can buy/sell/transfer
    function setMaxSwapAmount(uint256 _maxSwapAmount) public onlyOwner() {
        require(_maxSwapAmount > _tTotal.div(1000), "Amount must be greater than 0.1% of supply");
        maxSwapAmount = _maxSwapAmount;
    }

    /// @notice Set Contract swap amount threshold
    function setcontractSwapThreshold(uint256 _contractSwapThreshold) public onlyOwner() {
        contractSwapThreshold = _contractSwapThreshold;
    }

    /// @notice Set buyback threshold
    function setBuyBackThreshold(uint256 _buybackThreshold) public onlyOwner {
        buybackThreshold = _buybackThreshold;
    }

    /// @notice Set wallets
    function setWallets(address taxWallet1, address taxWallet2, address lpTokensReceiver, address buybackTokenReceiver) public onlyOwner {
        _taxWallet1 = payable(taxWallet1);
        _taxWallet2 = payable(taxWallet2);
        _lpTokensReceiver = lpTokensReceiver;
        _buybackTokenReceiver = buybackTokenReceiver;
    }

    /// @notice Setup fee in rate of 100 (If 1%, then set 100)
    function setBuyFee(uint256 _bBurnFee, uint256 _bMarketingFee, uint256 _bLPFee, uint256 _bBuybackFee) public onlyOwner {
        
        //Hard cap check to prevent honeypot
        require(_bBurnFee <= 2000, "Hard cap 20%");
        require(_bMarketingFee <= 2000, "Hard cap 20%");
        require(_bLPFee <= 2000, "Hard cap 20%");
        require(_bBuybackFee <= 2000, "Hard cap 20%");
        
        bBurnFee = _bBurnFee;
        bMarketingFee = _bMarketingFee;
        bLPFee = _bLPFee;
        bBuybackFee = _bBuybackFee;
    
    }

    /// @notice Setup fee in rate of 100 (If 1%, then set 100)
    function setSellFee(uint256 _sBurnFee, uint256 _sMarketingFee, uint256 _sLPFee, uint256 _sBuybackFee, uint256 _sEarlySellFee, uint256 _decayTaxExpiration) public onlyOwner {
        
        //Hard cap check to prevent honeypot
        require(_sBurnFee <= 2000, "Hard cap 20%");
        require(_sMarketingFee <= 2000, "Hard cap 20%");
        require(_sLPFee <= 2000, "Hard cap 20%");
        require(_sBuybackFee <= 2000, "Hard cap 20%");
        require(_sEarlySellFee <= 2000, "Hard cap 20%");
        
        sBurnFee = _sBurnFee;
        sMarketingFee = _sMarketingFee;
        sLPFee = _sLPFee;
        sBuybackFee = _sBuybackFee;
        sEarlySellFee = _sEarlySellFee;
        decayTaxExpiration = 1 days * _decayTaxExpiration;
    
    }

    function readFees() external view returns (uint _totalBuyFee, uint _totalSellFee, uint _burnFeeBuy, uint _burnFeeSell, uint _marketingFeeBuy, uint _marketingFeeSell, uint _liquidityFeeBuy, uint _liquidityFeeSell, uint _buybackFeeBuy, uint _buybackFeeSell, uint maxEarlySellFee) {
        return (
            bBurnFee+bMarketingFee+bLPFee+bBuybackFee,
            sBurnFee+sMarketingFee+sLPFee+sBuybackFee+sEarlySellFee,
            bBurnFee,
            sBurnFee,
            bMarketingFee,
            sMarketingFee,
            bLPFee,
            sLPFee,
            bBuybackFee,
            sBuybackFee,
            sEarlySellFee
        );
    }

    /// @notice Airdropper inbuilt
    function multiSend(address[] calldata addresses, uint256[] calldata amounts, bool overrideTracker, uint256 trackerTimestamp) external {
        require(addresses.length == amounts.length, "Must be the same length");
        for(uint256 i = 0; i < addresses.length; i++){
            _transfer(_msgSender(), addresses[i], amounts[i] * 10**_decimals);

            //Suppose to airdrop holders who bought long back and don't want to reset their decaytax
            if(overrideTracker) {
                //Override buytracker
                buyTracker[addresses[i]] += amounts[i];
                lastBuyTimestamp[addresses[i]] = trackerTimestamp;
            }
        }
    }
    
}