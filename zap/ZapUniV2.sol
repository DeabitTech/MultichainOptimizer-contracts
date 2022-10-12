// SPDX-License-Identifier: UNLICENSED


pragma solidity >=0.7.6;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/lib/contracts/libraries/Babylonian.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IVault is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function want() external pure returns (address);
    function token() external pure returns (address); 
}

interface IDyosToken is IERC20 {
    function mintDyos(address _to,uint256 _amount) external;
}

contract ZapUniswapV2 {
   using LowGasSafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IVault;
    using SafeERC20 for IDyosToken;

    IUniswapV2Router02 public immutable router;
    address public immutable WETH;
    IDyosToken public govToken;
    uint256 public constant minimumAmount = 1000;
    uint256 public constant fee = 1;

    constructor(address _router, address _WETH,IDyosToken _govToken) {
        router = IUniswapV2Router02(_router);
        WETH = _WETH;
        govToken = _govToken;
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function zapInETH (address dyosVault, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= minimumAmount, 'Dyos: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();

        _swapAndStake(dyosVault, tokenAmountOutMin, WETH);
    }

    function zapIn (address dyosVault, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= minimumAmount, 'Dyos: Insignificant input amount');
        require(IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, 'Dyos: Input token is not approved');

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(dyosVault, tokenAmountOutMin, tokenIn);
    }

    function zapOut (address dyosVault, uint256 withdrawAmount) external {
        (IVault vault, IUniswapV2Pair pair) = _getVaultPair(dyosVault);

        IERC20(dyosVault).safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

        if (pair.token0() != WETH && pair.token1() != WETH) {
            return _removeLiqudity(address(pair), msg.sender);
        }

        _removeLiqudity(address(pair), address(this));

        address[] memory tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();

        _returnAssets(tokens);
    }

    function zapOutAndSwap(address dyosVault, uint256 withdrawAmount, address desiredToken, uint256 desiredTokenOutMin) external {
        (IVault vault, IUniswapV2Pair pair) = _getVaultPair(dyosVault);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(token0 == desiredToken || token1 == desiredToken, 'Dyos: desired token not present in liqudity pair');

        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);
        _removeLiqudity(address(pair), address(this));

        address swapToken = token1 == desiredToken ? token0 : token1;
        address[] memory path = new address[](2);
        path[0] = swapToken;
        path[1] = desiredToken;

        _approveTokenIfNeeded(path[0], address(router));
        router.swapExactTokensForTokens(IERC20(swapToken).balanceOf(address(this)), desiredTokenOutMin, path, address(this), block.timestamp);

        _returnAssets(path);
    }

    function _removeLiqudity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function _getVaultPair (address dyosVault) private view returns (IVault vault, IUniswapV2Pair pair) {
        vault = IVault(dyosVault);
        pair = IUniswapV2Pair(vault.want());
        require(pair.factory() == router.factory(), 'Dyos: Incompatible liquidity pair factory');
    }

    function _swapAndStake(address dyosVault, uint256 tokenAmountOutMin, address tokenIn) private {
        (IVault vault, IUniswapV2Pair pair) = _getVaultPair(dyosVault);

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        require(reserveA > minimumAmount && reserveB > minimumAmount, 'Dyos: Liquidity pair reserves too low');

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Dyos: Input token not present in liqudity pair');

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = isInputA ? pair.token1() : pair.token0();

        uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
        uint256 swapAmountIn;
        if (isInputA) {
            swapAmountIn = _getSwapAmount(fullInvestment, reserveA, reserveB);
        } else {
            swapAmountIn = _getSwapAmount(fullInvestment, reserveB, reserveA);
        }

        _approveTokenIfNeeded(path[0], address(router));
        uint256[] memory swapedAmounts = router
            .swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), block.timestamp);

        _approveTokenIfNeeded(path[1], address(router));
        (,, uint256 amountLiquidity) = router
            .addLiquidity(path[0], path[1], fullInvestment.sub(swapedAmounts[0]), swapedAmounts[1], 1, 1, address(this), block.timestamp);

        _approveTokenIfNeeded(address(pair), address(vault));
        vault.deposit(amountLiquidity);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        govToken.safeTransfer(msg.sender,govToken.balanceOf(address(this)));
        _returnAssets(path);
    }

    function _returnAssets(address[] memory tokens) private {
        uint256 balance;
        for (uint256 i; i < tokens.length; i++) {
            balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == WETH) {
                    IWETH(WETH).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Beefy: ETH transfer failed');
                } else {
                    IERC20(tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    function _getSwapAmount(uint256 investmentA, uint256 reserveA, uint256 reserveB) private view returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;
        uint256 nominator = router.getAmountOut(halfInvestment, reserveA, reserveB);
        uint256 denominator = router.quote(halfInvestment, reserveA.add(halfInvestment), reserveB.sub(nominator));
        swapAmount = investmentA.sub(Babylonian.sqrt(halfInvestment * halfInvestment * nominator / denominator));
    }

    function estimateSwap(address dyosVault, address tokenIn, uint256 fullInvestmentIn) public view returns(uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        checkWETH();
        (, IUniswapV2Pair pair) = _getVaultPair(dyosVault);

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Dyos: Input token not present in liqudity pair');

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapAmountIn = _getSwapAmount(fullInvestmentIn, reserveA, reserveB);
        swapAmountOut = router.getAmountOut(swapAmountIn, reserveA, reserveB);
        swapTokenOut = isInputA ? pair.token1() : pair.token0();
    }

    function checkWETH() public view returns (bool isValid) {
        isValid = WETH == router.WETH();
        require(isValid, 'Dyos: WETH address not matching Router.WETH()');
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint).max);
        }
    }

}