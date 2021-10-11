// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./IglooStrategyForPangolinStaking.sol";


 contract StrategyPefiUsdcPgnl  is IglooStrategyForPangolinStaking{
      
    using SafeERC20 for IERC20;
    address  IglooStrategyForPangolinStakingAddress;
   

    constructor(
        IglooMaster _iglooMaster,
        IERC20 _depositToken,
        uint256 _pid,
        IStakingRewards _stakingContract,
        IglooStrategyStorage _iglooStrategyStorage,
        address _iglooStrategyForPangolinStakingAddress
        ) 
        IglooStrategyForPangolinStaking(
        _iglooMaster,
        _depositToken,
         _pid,
         _stakingContract,
        _iglooStrategyStorage
        )
    {
       
         IglooStrategyForPangolinStakingAddress = _iglooStrategyForPangolinStakingAddress;
        
    }

 
   
    function deposit( uint256 amount) external {
        iglooMaster.deposit(pid, amount,  IglooStrategyForPangolinStakingAddress);
    }

  
    function withdraw(uint256 amountShares) external {
         iglooMaster.withdraw(pid, amountShares,  IglooStrategyForPangolinStakingAddress);
        
    }

   
    function harvest() override external {
         iglooMaster.harvest(pid, IglooStrategyForPangolinStakingAddress);
            }

   
    function withdrawAndHarvest(uint256 amountShares) external  {
         iglooMaster.withdrawAndHarvest(pid, amountShares, IglooStrategyForPangolinStakingAddress);
            }


   
}
