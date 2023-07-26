// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./lib/SafeMath8.sol";
import "./owner/Operator.sol";
import "./interfaces/IOracle.sol";

/*

   _____  .__.__  .__  .__                           .__                ___________.__                                   
  /     \ |__|  | |  | |__| ____   ____ _____ _______|__| ____   ______ \_   _____/|__| ____ _____    ____   ____  ____  
 /  \ /  \|  |  | |  | |  |/  _ \ /    \\__  \\_  __ \  |/ __ \ /  ___/  |    __)  |  |/    \\__  \  /    \_/ ___\/ __ \ 
/    Y    \  |  |_|  |_|  (  <_> )   |  \/ __ \|  | \/  \  ___/ \___ \   |     \   |  |   |  \/ __ \|   |  \  \__\  ___/ 
\____|__  /__|____/____/__|\____/|___|  (____  /__|  |__|\___  >____  >  \___  /   |__|___|  (____  /___|  /\___  >___  >
        \/                            \/     \/              \/     \/       \/            \/     \/     \/     \/    \/ 


    https://millionaires.finance
*/

contract Holy is ERC20Burnable, Operator {
    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // Initial distribution for the first 48h genesis pools
    // total of holy we pay to users during genesis
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 8 ether;

    // DAO FUND INITIAL ALLOCATION IS 3 HOLY
    uint256 public constant INITIAL_DAOFUND_DISTRIBUTION = 3 ether;

    // price
    uint256 public holyPriceOne;


    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    /**
     * @notice Constructs the HOLY ERC-20 contract.
     */
    constructor() ERC20("Holy Token", "HOLY") {
        // Mints 3 HOLY to contract creator for initial pool setup
        holyPriceOne = 10**18;
        _mint(msg.sender, 3 ether);

    }

    /**
     * @notice Operator mints HOLY to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of HOLY to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _genesisPool,
        address _daoFund
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        require(_daoFund != address(0), "!_treasury");

        rewardPoolDistributed = true;
        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
        _mint(_daoFund, INITIAL_DAOFUND_DISTRIBUTION);

    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}