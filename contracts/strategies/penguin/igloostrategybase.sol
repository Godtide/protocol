// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;



import "./safeERC20.sol";
import "./Ownable.sol";
import "./iigloostrategy.sol";
import "./iglooMasterV2.sol";


contract IglooStrategyBase is IIglooStrategy, Ownable {
    using SafeERC20 for IERC20;

    IglooMaster public immutable iglooMaster;
    IERC20 public immutable depositToken;
    uint256 public performanceFeeBips = 1000;
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 internal constant ACC_PEFI_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;

    constructor(
        IglooMaster _iglooMaster,
        IERC20 _depositToken
        ){
        iglooMaster = _iglooMaster;
        depositToken = _depositToken;
        transferOwnership(address(_iglooMaster));
    }

    //returns zero address and zero tokens since base strategy does not distribute rewards
    function pendingTokens(uint256, address, uint256) external view virtual override 
        returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = 0;
        return(_rewardTokens, _pendingAmounts);
    }

    function deposit(address, address, uint256, uint256) external virtual override onlyOwner {
    }

    function withdraw(address, address to, uint256 tokenAmount, uint256) external virtual override onlyOwner {
        if (tokenAmount > 0) {
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function inCaseTokensGetStuck(IERC20 token, address to, uint256 amount) external virtual override onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");
        require(address(token) != address(depositToken), "cannot recover deposit token");
        token.safeTransfer(to, amount);
    }

    function setAllowances() external virtual override onlyOwner {
    }

    /**
     * @notice Revoke token allowance
     * @param token address
     * @param spender address
     */
    function revokeAllowance(address token, address spender) external virtual override onlyOwner {
        IERC20(token).safeApprove(spender, 0);
    }

    function migrate(address newStrategy) external virtual override onlyOwner {
        uint256 toTransfer = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(newStrategy, toTransfer);
    }

    function onMigration() external virtual override onlyOwner {
    }

    function transferOwnership(address newOwner) public virtual override(Ownable, IIglooStrategy) onlyOwner {
        Ownable.transferOwnership(newOwner);
    }

    function setPerformanceFeeBips(uint256 newPerformanceFeeBips) external virtual override onlyOwner {
        require(newPerformanceFeeBips <= MAX_BIPS, "input too high");
        performanceFeeBips = newPerformanceFeeBips;
    }
}
