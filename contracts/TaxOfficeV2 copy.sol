// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./utils/SafeMath.sol";
import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";
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
contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public holy = address(0xecB47d5cC8f095D62FCEe7A6eF62e3E2b32207A5);
    address public wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public uniRouter = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(holy).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(holy).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(holy).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(holy).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(holy).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(holy).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyOperator {
        ITaxable(holy).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address) external onlyOperator returns (bool) {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(holy).isAddressExcluded(_address)) {
            return ITaxable(holy).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(holy).isAddressExcluded(_address)) {
            return ITaxable(holy).includeAddress(_address);
        }
    }

    function taxRate() external view returns (uint256) {
        return ITaxable(holy).taxRate();
    }

    function addLiquidityTaxFree(
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
        _excludeAddressFromTax(msg.sender);

        IERC20(holy).transferFrom(msg.sender, address(this), amtHoly);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(holy, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

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

    function addLiquidityETHTaxFree(
        uint256 amtHoly,
        uint256 amtHolyMin,
        uint256 amtFtmMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtHoly != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(holy).transferFrom(msg.sender, address(this), amtHoly);
        _approveTokenIfNeeded(holy, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtHoly;
        uint256 resultAmtFtm;
        uint256 liquidity;
        (resultAmtHoly, resultAmtFtm, liquidity) = IUniswapV2Router(uniRouter).addLiquidityETH{value: msg.value}(
            holy,
            amtHoly,
            amtHolyMin,
            amtFtmMin,
            msg.sender,
            block.timestamp
        );

        if(amtHoly.sub(resultAmtHoly) > 0) {
            IERC20(holy).transfer(msg.sender, amtHoly.sub(resultAmtHoly));
        }
        return (resultAmtHoly, resultAmtFtm, liquidity);
    }

    function setTaxableHolyOracle(address _holyOracle) external onlyOperator {
        ITaxable(holy).setHolyOracle(_holyOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(holy).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[msg.sender], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(holy).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOperator {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}