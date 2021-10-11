// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;



import "./IStakingRewards.sol";
import "./igloostrategybase.sol";


contract IglooStrategyForPangolinStaking is IglooStrategyBase {
    using SafeERC20 for IERC20;

    IERC20 public constant rewardToken = IERC20(0x60781C2586D68229fde47564546784ab3fACA982); //PNG token
    IStakingRewards public immutable stakingContract;
    IglooStrategyStorage public immutable iglooStrategyStorage;
    uint256 public immutable pid;
    //total harvested by the contract all time
    uint256 public totalHarvested;

    //total amount harvested by each user
    mapping(address => uint256) public harvested;

    event Harvest(address indexed caller, address indexed to, uint256 harvestedAmount);

    constructor(
        IglooMaster _iglooMaster,
        IERC20 _depositToken,
        uint256 _pid,
        IStakingRewards _stakingContract,
        IglooStrategyStorage _iglooStrategyStorage
        ) 
        IglooStrategyBase(_iglooMaster, _depositToken)
    {
        pid = _pid;
        stakingContract = _stakingContract;
        iglooStrategyStorage = _iglooStrategyStorage;
        _depositToken.safeApprove(address(_stakingContract), MAX_UINT);
    }

    //PUBLIC FUNCTIONS
    /**
    * @notice Reward token balance that can be claimed
    * @dev Staking rewards accrue to contract on each deposit/withdrawal
    * @return Unclaimed rewards
    */
    function checkReward() public view returns (uint256) {
        return stakingContract.earned(address(this));
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 userShares = iglooMaster.userShares(pid, user);
        uint256 unclaimedRewards = checkReward();
        uint256 rewardTokensPerShare = iglooStrategyStorage.rewardTokensPerShare();
        uint256 totalShares = iglooMaster.totalShares(pid);
        uint256 userRewardDebt = iglooStrategyStorage.rewardDebt(user);
        uint256 multiplier =  rewardTokensPerShare;
        if(totalShares > 0) {
            multiplier = multiplier + ((unclaimedRewards * ACC_PEFI_PRECISION) / totalShares);
        }
        uint256 totalRewards = (userShares * multiplier) / ACC_PEFI_PRECISION;
        uint256 userPendingRewards = (totalRewards >= userRewardDebt) ?  (totalRewards - userRewardDebt) : 0;
        return userPendingRewards;
    }

    function rewardTokens() external view virtual returns(address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        return(_rewardTokens);
    }

    function pendingTokens(uint256, address user, uint256) external view override
        returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = pendingRewards(user);
        return(_rewardTokens, _pendingAmounts);
    }

    //EXTERNAL FUNCTIONS
    function harvest() virtual external {
        _claimRewards();
        _harvest(msg.sender, msg.sender);
    }

    //OWNER-ONlY FUNCTIONS
    function deposit(address caller, address to, uint256 tokenAmount, uint256 shareAmount) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.stake(tokenAmount);
        }
        if (shareAmount > 0) {
            iglooStrategyStorage.increaseRewardDebt(to, shareAmount);
        }
    }

    function withdraw(address caller, address to, uint256 tokenAmount, uint256 shareAmount) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.withdraw(tokenAmount);
            depositToken.safeTransfer(to, tokenAmount);
        }
        if (shareAmount > 0) {
            iglooStrategyStorage.decreaseRewardDebt(to, shareAmount);
        }
    }

    function migrate(address newStrategy) external override onlyOwner {
        _claimRewards();
        uint256 toWithdraw = stakingContract.balanceOf(address(this));
        if (toWithdraw > 0) {
            stakingContract.withdraw(toWithdraw);
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 rewardsToTransfer = rewardToken.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            rewardToken.safeTransfer(newStrategy, rewardsToTransfer);
        }
        iglooStrategyStorage.transferOwnership(newStrategy);
    }

    function onMigration() external override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        stakingContract.stake(toStake);
    }

    function setAllowances() external override onlyOwner {
        depositToken.safeApprove(address(stakingContract), 0);
        depositToken.safeApprove(address(stakingContract), MAX_UINT);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {
        uint256 unclaimedRewards = checkReward();
        uint256 totalShares = iglooMaster.totalShares(pid);
        if (unclaimedRewards > 0 && totalShares > 0) {
            stakingContract.getReward();
            iglooStrategyStorage.increaseRewardTokensPerShare((unclaimedRewards * ACC_PEFI_PRECISION) / totalShares);
        }
    }

    function _harvest(address caller, address to) internal {
        uint256 userShares = iglooMaster.userShares(pid, caller);
        uint256 totalRewards = (userShares * iglooStrategyStorage.rewardTokensPerShare()) / ACC_PEFI_PRECISION;
        uint256 userRewardDebt = iglooStrategyStorage.rewardDebt(caller);
        uint256 userPendingRewards = (totalRewards >= userRewardDebt) ?  (totalRewards - userRewardDebt) : 0;
        iglooStrategyStorage.setRewardDebt(caller, userShares);
        if (userPendingRewards > 0) {
            totalHarvested += userPendingRewards;
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (userPendingRewards * performanceFeeBips) / MAX_BIPS;
                _safeRewardTokenTransfer(iglooMaster.performanceFeeAddress(), performanceFee);
                userPendingRewards = userPendingRewards - performanceFee;
            }
            harvested[to] += userPendingRewards;
            emit Harvest(caller, to, userPendingRewards);
            _safeRewardTokenTransfer(to, userPendingRewards);
        }
    }

    //internal wrapper function to avoid reverts due to rounding
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (amount > rewardTokenBal) {
            rewardToken.safeTransfer(user, rewardTokenBal);
        } else {
            rewardToken.safeTransfer(user, amount);
        }
    }
}