// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMasonry.sol";

/*

   _____  .__.__  .__  .__                           .__                ___________.__                                   
  /     \ |__|  | |  | |__| ____   ____ _____ _______|__| ____   ______ \_   _____/|__| ____ _____    ____   ____  ____  
 /  \ /  \|  |  | |  | |  |/  _ \ /    \\__  \\_  __ \  |/ __ \ /  ___/  |    __)  |  |/    \\__  \  /    \_/ ___\/ __ \ 
/    Y    \  |  |_|  |_|  (  <_> )   |  \/ __ \|  | \/  \  ___/ \___ \   |     \   |  |   |  \/ __ \|   |  \  \__\  ___/ 
\____|__  /__|____/____/__|\____/|___|  (____  /__|  |__|\___  >____  >  \___  /   |__|___|  (____  /___|  /\___  >___  >
        \/                            \/     \/              \/     \/       \/            \/     \/     \/     \/    \/ 


    https://millionaires.finance
*/

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply = [
        address(0x3a5208f5BF1A928FF66E0A71eEcA4e4B4A6dD24B) // HolyGenesisPool
    ];

    // core components
    address public holy;
    address public bholy;
    address public hxs;

    address public masonry;
    address public holyOracle;

    // price
    uint256 public holyPriceOne;
    uint256 public holyPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bholyDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 6 first epochs (2 days) with 3% expansion regardless of HOLY price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochHolyPrice;
    uint256 public maxDiscountRate; // when purchasing bholy
    uint256 public maxPremiumRate; // when redeeming bholy
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra HOLY during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBHolys(address indexed from, uint256 bholyAmount);
    event RedeemedBHolys(address indexed from, uint256 holyAmount, uint256 bholyAmount);
    event BoughtBHolys(address indexed from, uint256 holyAmount, uint256 bholyAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event MasonryFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getHolyPrice() > holyPriceCeiling) ? 0 : getHolyCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(holy).operator() == address(this) &&
                IBasisAsset(bholy).operator() == address(this) &&
                IBasisAsset(hxs).operator() == address(this) &&
                Operator(masonry).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getHolyPrice() public view returns (uint256 holyPrice) {
        try IOracle(holyOracle).consult(holy, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HOLY price from the oracle");
        }
    }

    function getHolyUpdatedPrice() public view returns (uint256 _holyPrice) {
        try IOracle(holyOracle).twap(holy, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult HOLY price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableHolyLeft() public view returns (uint256 _burnableHolyLeft) {
        uint256 _holyPrice = getHolyPrice();
        if (_holyPrice <= holyPriceOne) {
            uint256 _holySupply = getHolyCirculatingSupply();
            uint256 _bholyMaxSupply = _holySupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bholySupply = IERC20(bholy).totalSupply();
            if (_bholyMaxSupply > _bholySupply) {
                uint256 _maxMintableBHoly = _bholyMaxSupply.sub(_bholySupply);
                uint256 _maxBurnableHoly = _maxMintableBHoly.mul(_holyPrice).div(1e18);
                _burnableHolyLeft = Math.min(epochSupplyContractionLeft, _maxBurnableHoly);
            }
        }
    }

    function getRedeemableBHolys() public view returns (uint256 _redeemableBHolys) {
        uint256 _holyPrice = getHolyPrice();
        if (_holyPrice > holyPriceCeiling) {
            uint256 _totalHoly = IERC20(holy).balanceOf(address(this));
            uint256 _rate = getBHolyPremiumRate();
            if (_rate > 0) {
                _redeemableBHolys = _totalHoly.mul(1e18).div(_rate);
            }
        }
    }

    function getBHolyDiscountRate() public view returns (uint256 _rate) {
        uint256 _holyPrice = getHolyPrice();
        if (_holyPrice <= holyPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = holyPriceOne;
            } else {
                uint256 _bholyAmount = holyPriceOne.mul(1e18).div(_holyPrice); // to burn 1 HOLY
                uint256 _discountAmount = _bholyAmount.sub(holyPriceOne).mul(discountPercent).div(10000);
                _rate = holyPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBHolyPremiumRate() public view returns (uint256 _rate) {
        uint256 _holyPrice = getHolyPrice();
        if (_holyPrice > holyPriceCeiling) {
            uint256 _holyPricePremiumThreshold = holyPriceOne.mul(premiumThreshold).div(100);
            if (_holyPrice >= _holyPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _holyPrice.sub(holyPriceOne).mul(premiumPercent).div(10000);
                _rate = holyPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = holyPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _holy,
        address _bholy,
        address _hxs,
        address _holyOracle,
        address _masonry,
        uint256 _startTime
    ) public notInitialized {
        holy = _holy;
        bholy = _bholy;
        hxs = _hxs;
        holyOracle = _holyOracle;
        masonry = _masonry;
        startTime = _startTime;

        holyPriceOne = 10**18;
        holyPriceCeiling = holyPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 50 ether, 100 ether, 150 ether, 200 ether, 500 ether, 1000 ether, 2000 ether, 5000 ether];
        maxExpansionTiers = [300, 250, 200, 150, 125, 100, 90, 75, 50];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bholyDepletionFloorPercent = 10000; // 100% of BHoly supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for masonry
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn HOLY and mint bHOLY)
        maxDebtRatioPercent = 3500; // Upto 35% supply of bHOLY to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 6 epochs with 3% expansion
        bootstrapEpochs = 6;
        bootstrapSupplyExpansionPercent = 300;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(holy).balanceOf(address(this));

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setMasonry(address _masonry) external onlyOperator {
        masonry = _masonry;
    }

    function setHolyOracle(address _holyOracle) external onlyOperator {
        holyOracle = _holyOracle;
    }

    function setHolyPriceCeiling(uint256 _holyPriceCeiling) external onlyOperator {
        require(_holyPriceCeiling >= holyPriceOne && _holyPriceCeiling <= holyPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        holyPriceCeiling = _holyPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setBHolyDepletionFloorPercent(uint256 _bholyDepletionFloorPercent) external onlyOperator {
        require(_bholyDepletionFloorPercent >= 500 && _bholyDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bholyDepletionFloorPercent = _bholyDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= holyPriceCeiling, "_premiumThreshold exceeds holyPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateHolyPrice() internal {
        bool canUpdate = IOracle(holyOracle).canUpdate();
        if (canUpdate) {
            try IOracle(holyOracle).update() {} catch {}
        }
    }

    function getHolyCirculatingSupply() public view returns (uint256) {
        IERC20 holyErc20 = IERC20(holy);
        uint256 totalSupply = holyErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(holyErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBHolys(uint256 _holyAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_holyAmount > 0, "Treasury: cannot purchase bholys with zero amount");

        uint256 holyPrice = getHolyPrice();
        require(holyPrice == targetPrice, "Treasury: HOLY price moved");
        require(
            holyPrice < holyPriceOne, // price < $1
            "Treasury: holyPrice not eligible for bholy purchase"
        );

        require(_holyAmount <= epochSupplyContractionLeft, "Treasury: not enough bholy left to purchase");

        uint256 _rate = getBHolyDiscountRate();
        require(_rate > 0, "Treasury: invalid bholy rate");

        uint256 _bholyAmount = _holyAmount.mul(_rate).div(1e18);
        uint256 holySupply = getHolyCirculatingSupply();
        uint256 newBHolySupply = IERC20(bholy).totalSupply().add(_bholyAmount);
        require(newBHolySupply <= holySupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(holy).burnFrom(msg.sender, _holyAmount);
        IBasisAsset(bholy).mint(msg.sender, _bholyAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_holyAmount);
        _updateHolyPrice();

        emit BoughtBHolys(msg.sender, _holyAmount, _bholyAmount);
    }

    function redeemBHolys(uint256 _bholyAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bholyAmount > 0, "Treasury: cannot redeem bholys with zero amount");

        uint256 holyPrice = getHolyPrice();
        require(holyPrice == targetPrice, "Treasury: HOLY price moved");
        require(
            holyPrice > holyPriceCeiling, // price > $1.01
            "Treasury: holyPrice not eligible for bholy purchase"
        );

        uint256 _rate = getBHolyPremiumRate();
        require(_rate > 0, "Treasury: invalid bholy rate");

        uint256 _holyAmount = _bholyAmount.mul(_rate).div(1e18);
        require(IERC20(holy).balanceOf(address(this)) >= _holyAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _holyAmount));

        IBasisAsset(bholy).burnFrom(msg.sender, _bholyAmount);
        IERC20(holy).safeTransfer(msg.sender, _holyAmount);

        _updateHolyPrice();

        emit RedeemedBHolys(msg.sender, _holyAmount, _bholyAmount);
    }

    function _sendToMasonry(uint256 _amount) internal {
        IBasisAsset(holy).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(holy).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(holy).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(holy).safeApprove(masonry, 0);
        IERC20(holy).safeApprove(masonry, _amount);
        IMasonry(masonry).allocateSeigniorage(_amount);
        emit MasonryFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _holySupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_holySupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateHolyPrice();
        previousEpochHolyPrice = getHolyPrice();
        uint256 holySupply = getHolyCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 6 first epochs with 3% expansion
            _sendToMasonry(holySupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochHolyPrice > holyPriceCeiling) {
                // Expansion ($HOLY Price > 1 $FTM): there is some seigniorage to be allocated
                uint256 bholySupply = IERC20(bholy).totalSupply();
                uint256 _percentage = previousEpochHolyPrice.sub(holyPriceOne);
                uint256 _savedForBHoly;
                uint256 _savedForMasonry;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(holySupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bholySupply.mul(bholyDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForMasonry = holySupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = holySupply.mul(_percentage).div(1e18);
                    _savedForMasonry = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBHoly = _seigniorage.sub(_savedForMasonry);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBHoly = _savedForBHoly.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForMasonry > 0) {
                    _sendToMasonry(_savedForMasonry);
                }
                if (_savedForBHoly > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBHoly);
                    IBasisAsset(holy).mint(address(this), _savedForBHoly);
                    emit TreasuryFunded(block.timestamp, _savedForBHoly);
                }
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(holy), "holy");
        require(address(_token) != address(bholy), "bholy");
        require(address(_token) != address(hxs), "share");
        _token.safeTransfer(_to, _amount);
    }

    function masonrySetOperator(address _operator) external onlyOperator {
        IMasonry(masonry).setOperator(_operator);
    }

    function masonrySetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IMasonry(masonry).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function masonryAllocateSeigniorage(uint256 amount) external onlyOperator {
        IMasonry(masonry).allocateSeigniorage(amount);
    }

    function masonryGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IMasonry(masonry).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
