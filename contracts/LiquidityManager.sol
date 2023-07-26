// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./utils/SafeMath.sol";
import "./owner/Operator.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

/*

   _____  .__.__  .__  .__                           .__                ___________.__                                   
  /     \ |__|  | |  | |__| ____   ____ _____ _______|__| ____   ______ \_   _____/|__| ____ _____    ____   ____  ____  
 /  \ /  \|  |  | |  | |  |/  _ \ /    \\__  \\_  __ \  |/ __ \ /  ___/  |    __)  |  |/    \\__  \  /    \_/ ___\/ __ \ 
/    Y    \  |  |_|  |_|  (  <_> )   |  \/ __ \|  | \/  \  ___/ \___ \   |     \   |  |   |  \/ __ \|   |  \  \__\  ___/ 
\____|__  /__|____/____/__|\____/|___|  (____  /__|  |__|\___  >____  >  \___  /   |__|___|  (____  /___|  /\___  >___  >
        \/                            \/     \/              \/     \/       \/            \/     \/     \/     \/    \/ 


    https://millionaires.finance
*/
contract LiquidityManager is Operator {
    using SafeMath for uint256;

    address public holy = address(0xecB47d5cC8f095D62FCEe7A6eF62e3E2b32207A5);
    address public uniRouter = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    function addLiquidityUnderPeg(
        address token,
        uint256 amtHoly,
        uint256 amtToken,
        uint256 amtHolyMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtHoly != 0 && amtToken != 0, "amounts can't be 0");

        IERC20(holy).transferFrom(msg.sender, address(this), amtHoly);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(holy, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        uint256 resultAmtHoly;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtHoly, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter).addLiquidity(
            holy,
            token,
            amtHoly,
            amtToken,
            amtHolyMin,
            amtTokenMin,
            msg.sender,
            block.timestamp
        );

        if(amtHoly.sub(resultAmtHoly) > 0) {
            IERC20(holy).transfer(msg.sender, amtHoly.sub(resultAmtHoly));
        }
        if(amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtHoly, resultAmtToken, liquidity);
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}