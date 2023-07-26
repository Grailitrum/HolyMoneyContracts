// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

/*

   _____  .__.__  .__  .__                           .__                ___________.__                                   
  /     \ |__|  | |  | |__| ____   ____ _____ _______|__| ____   ______ \_   _____/|__| ____ _____    ____   ____  ____  
 /  \ /  \|  |  | |  | |  |/  _ \ /    \\__  \\_  __ \  |/ __ \ /  ___/  |    __)  |  |/    \\__  \  /    \_/ ___\/ __ \ 
/    Y    \  |  |_|  |_|  (  <_> )   |  \/ __ \|  | \/  \  ___/ \___ \   |     \   |  |   |  \/ __ \|   |  \  \__\  ___/ 
\____|__  /__|____/____/__|\____/|___|  (____  /__|  |__|\___  >____  >  \___  /   |__|___|  (____  /___|  /\___  >___  >
        \/                            \/     \/              \/     \/       \/            \/     \/     \/     \/    \/ 


    https://millionaires.finance
*/

contract Hxs is ERC20Burnable, Operator {
    using SafeMath for uint256;

    // TOTAL MAX SUPPLY = 50,000 HXSs
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 40500 ether;


    bool public rewardPoolDistributed = false;

    constructor(

    ) ERC20("Holy Share", "HXS") {
        _mint(msg.sender, 9500 ether); // mint 9500 Hxs for initial pools deployment + treasury (dev/dao)
    }
    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
