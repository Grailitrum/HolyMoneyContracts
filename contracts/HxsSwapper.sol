// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IZapper.sol";

import "./owner/Operator.sol";

contract HxsSwapper is Operator {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public holy;
    address public hxs;
    address public bholy;

    address public holyOracle;
    address public hxsOracle;
    address public treasury;
    address public zapper;

    

    mapping (address => bool) public useNativeRouter;

    event BHolySwapPerformed(address indexed sender, uint256 bholyAmount, uint256 hxsAmount);


    constructor(
        address _holy,
        address _bholy,
        address _hxs,
        address _holyOracle,
        address _hxsOracle,
        address _treasury,
        address _zapper
    ) {
        holy = _holy;
        bholy = _bholy;
        hxs = _hxs;
        holyOracle = _holyOracle;
        hxsOracle = _hxsOracle;
        treasury = _treasury;
        zapper = _zapper;
    }
   modifier whitelist(address route) {
        require(useNativeRouter[route], "route not allowed");
        _;
    }

     function _approveTokenIfNeeded(address token, address router) private {
        if (IERC20(token).allowance(address(this), router) == 0) {
            IERC20(token).safeApprove(router, type(uint256).max);
        }
    }

    function getHolyPrice() public view returns (uint256 holyPrice) {
        try IOracle(holyOracle).consult(holy, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HOLY price from the oracle");
        }
    }
    function getHxsPrice() public view returns (uint256 hxsPrice) {
        try IOracle(hxsOracle).consult(hxs, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HXS price from the oracle");
        }
    }
    function redeemBHolys(uint256 _bholyAmount, uint256 holyPrice) private returns (uint256) {

         IERC20(bholy).safeTransferFrom(msg.sender, address(this), _bholyAmount);
         _approveTokenIfNeeded(bholy, treasury);
       
        try ITreasury(treasury).redeemBHolys(_bholyAmount, holyPrice) {
        } catch {
            revert("Treasury: cant redeem bholys");
        }
        return getHolyBalance();
    }

    function swap(address _in, uint256 amount, address out, address recipient, address routerAddr, uint256 minAmountOfHxs) private returns (uint256) {
        
        IERC20(holy).safeTransferFrom(address(this), zapper, amount);
        _approveTokenIfNeeded(holy, routerAddr);
        
         try IZapper(zapper)._swap(_in, amount, out, recipient, routerAddr , minAmountOfHxs) returns (uint256 _hxsAmount) {
             require( _hxsAmount >= minAmountOfHxs, "amt < minAmountNeeded");
            return uint256(_hxsAmount);
        } catch {
            revert("Treasury: failed to get HXS price");
        }
    }
   

    function estimateAmountOfHxs(uint256 _bholyAmount) external view returns (uint256) {
        uint256 hxsAmountPerHoly = getHxsAmountPerHoly();
        return _bholyAmount.mul(hxsAmountPerHoly).div(1e18);
    }

    function swapBHolyToHxs(uint256 _bholyAmount, address routerAddr, uint256 minAmountofHxs) external whitelist(routerAddr) {
        //check if we have the amount of bholys we want to swap
        require(getBHolyBalance(msg.sender) >= _bholyAmount, "Not enough BHoly in wallet");
        
       // send bholy to treasury(call redeem bholys in treasury) and receive holy back
        uint256 holyPrice = getHolyPrice();
        uint256 holyToSwap = redeemBHolys(_bholyAmount, holyPrice);
       // check if we received holy(should be more than bholys because of higher rate in redeem in treasury)
       require ( holyToSwap >= _bholyAmount, "redeem bholys reverted"); 
       // swap holy to hxs
        uint256 hxsReceived = swap(holy, holyToSwap, hxs, msg.sender, routerAddr, minAmountofHxs);

        emit BHolySwapPerformed(msg.sender, _bholyAmount, hxsReceived);
    }


    function getHolyBalance() public view returns (uint256) {
        return IERC20(holy).balanceOf(address(this));
    }
    function getHxsBalance() public view returns (uint256) {
        return IERC20(hxs).balanceOf(address(this));
    }

    function getBHolyBalance(address _user) public view returns (uint256) {
        return IERC20(bholy).balanceOf(_user);
    }
    
    function getHxsAmountPerHoly() public view returns (uint256) {
        uint256 holyPrice = getHolyPrice();
        uint256 hxsPrice = getHxsPrice();
        return holyPrice.mul(1e18).div(hxsPrice);
    }
    function setUseNativeRouter(address router) external onlyOwner {
        useNativeRouter[router] = true;
    }

    function removeNativeRouter(address router) external onlyOwner {
        useNativeRouter[router] = false;
    }

}