// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "contracts/interfaces/ITutellusERC20.sol";
import "contracts/interfaces/ITutellusEnergy.sol";
import "contracts/interfaces/ITutellusRewardsVaultV2.sol";
import "contracts/interfaces/ITutellusManager.sol";
import "contracts/interfaces/ITutellusFactionManager.sol";
import "contracts/interfaces/ITutellusEnergyMultiplierManager.sol";
import "contracts/utils/UUPSUpgradeableByRole.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract TutellusLaunchpadStaking is UUPSUpgradeableByRole {
    bytes32 public constant LAUNCHPAD_ADMIN_ROLE =
        keccak256("LAUNCHPAD_ADMIN_ROLE");
    bytes32 public constant LAUNCHPAD_REWARDS = keccak256("LAUNCHPAD_REWARDS");

    bool public autoreward;

    address public token;

    uint256 public balance;
    uint256 public minFee;
    uint256 public maxFee;
    uint256 public accRewardsPerShare;

    uint256 internal _released;

    uint256 public lastUpdate;
    uint256 public feeInterval;
    uint256 public stakers;

    struct Data {
        uint256 amount;
        uint256 rewardDebt;
        uint256 notClaimed;
        uint256 endInterval;
        uint256 minFee;
        uint256 maxFee;
        uint256 feeInterval;
        uint256 energyDebt;
    }

    mapping(address => Data) public data;

    event Init(uint256 lastUpdate, address token);
    event Claim(address account);
    event Deposit(address account, uint256 amount, uint256 energyMinted);
    event Withdraw(
        address account,
        uint256 amount,
        uint256 burned,
        uint256 energyBurned
    );
    event Rewards(address account, uint256 amount);

    event SyncBalance(address account, uint256 amount);
    event ToggleAutoreward(bool autoreward);
    event Update(
        uint256 balance,
        uint256 accRewardsPerShare,
        uint256 lastUpdate,
        uint256 stakers
    );
    event UpdateData(
        address account,
        uint256 amount,
        uint256 rewardDebt,
        uint256 notClaimed,
        uint256 endInterval
    );
    event SetFees(uint256 minFee, uint256 maxFee, uint256 feeInterval);
    event Migrate(
        address from,
        address to,
        address account,
        uint256 amount,
        bytes response
    );

    modifier onlyFactionManager() {
        require(
            msg.sender ==
                ITutellusManager(config).get(keccak256("FACTION_MANAGER")),
            "TutellusLaunchpadStaking: only faction manager"
        );
        _;
    }

    function initialize(address tkn) public initializer {
        __AccessControlProxyPausable_init(msg.sender);
        // minFee = 1e17;
        // maxFee = 1e19;
        // feeInterval = 1296000;
        autoreward = true;
        lastUpdate = block.number;
        token = tkn;

        emit Init(lastUpdate, token);
    }

    modifier update() {
        ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(
            ITutellusManager(config).get(LAUNCHPAD_REWARDS)
        );
        uint256 released = rewardsInterface.released(address(this)) - _released;
        _released += released;
        if (balance > 0) {
            accRewardsPerShare += ((released * 1 ether) / balance);
        }
        lastUpdate = block.number;
        _;
    }

    // Updates rewards for an account
    function _updateRewards(address account) internal {
        Data storage user = data[account];
        uint256 diff = accRewardsPerShare - user.rewardDebt;
        user.notClaimed += (diff * user.amount) / 1 ether;
        user.rewardDebt = accRewardsPerShare;
    }

    // Sets maximum and minimum fees, and fees interval
    function setFees(
        uint256 minFee_,
        uint256 maxFee_,
        uint256 feeInterval_
    ) public onlyRole(LAUNCHPAD_ADMIN_ROLE) {
        require(
            minFee_ <= maxFee_,
            "TutellusLaunchpadStaking: mininum fee must be greater or equal than maximum fee"
        );
        require(
            maxFee_ <= 100 ether,
            "TutellusLaunchpadStaking: maxFee cannot exceed 100 ether"
        );
        minFee = minFee_;
        maxFee = maxFee_;
        feeInterval = feeInterval_;
        emit SetFees(minFee, maxFee, feeInterval);
    }

    // Deposits tokens for staking
    function deposit(address account, uint256 amount)
        public
        update
        onlyFactionManager
        returns (uint256)
    {
        require(
            amount > 0,
            "TutellusLaunchpadStaking: amount must be over zero"
        );

        ITutellusEnergy energyInterface = ITutellusEnergy(
            ITutellusManager(config).get(keccak256("ENERGY"))
        );

        Data storage user = data[account];

        _updateRewards(account);

        if (user.amount == 0) {
            stakers += 1;
        }

        user.endInterval = block.number + feeInterval;
        user.minFee = minFee;
        user.maxFee = maxFee;
        user.feeInterval = feeInterval;
        user.amount += amount;
        balance += amount;

        if (autoreward) {
            _reward(account);
        }

        uint256 energyMinted = (amount * _getEnergyMultiplier()) / 1 ether;
        uint256 energyScaled = energyInterface.scale(energyMinted);
        user.energyDebt += energyScaled;

        ITutellusFactionManager(msg.sender).depositFrom(account, amount, token);
        energyInterface.mintVariable(account, energyMinted);

        emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
        emit UpdateData(
            account,
            user.amount,
            user.rewardDebt,
            user.notClaimed,
            user.endInterval
        );
        emit Deposit(account, amount, energyMinted);
        return energyScaled;
    }

    // Withdraws tokens from staking
    function withdraw(address account, uint256 amount)
        public
        update
        onlyFactionManager
        returns (uint256, uint256)
    {
        require(
            amount > 0,
            "TutellusLaunchpadStaking: amount must be over zero"
        );
        Data storage user = data[account];

        require(
            amount <= user.amount,
            "TutellusLaunchpadStaking: user has not enough staking balance"
        );

        ITutellusERC20 tokenInterface = ITutellusERC20(token);
        ITutellusEnergy energyInterface = ITutellusEnergy(
            ITutellusManager(config).get(keccak256("ENERGY"))
        );

        uint256 energyShare = (amount * user.energyDebt) / user.amount;
        uint256 energyBurned = energyInterface.unscale(energyShare);
        uint256 energyBalance = energyInterface.balanceOf(account);

        require(
            energyBurned <= energyBalance,
            "TutellusLaunchpadStaking: need more energy to unstake"
        );

        user.energyDebt -= energyShare;
        energyInterface.burnVariable(account, energyBurned);

        _updateRewards(account);

        user.rewardDebt = accRewardsPerShare;
        user.amount -= amount;
        balance -= amount;

        if (user.amount == 0) {
            stakers -= 1;
        }

        uint256 burned = (amount * getFee(account)) / 1e20;

        if (autoreward) {
            _reward(account);
        }

        if (burned > 0) {
            amount -= burned;
            tokenInterface.burn(burned);
        }

        tokenInterface.transfer(account, amount);

        emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
        emit UpdateData(
            account,
            user.amount,
            user.rewardDebt,
            user.notClaimed,
            user.endInterval
        );
        emit Withdraw(account, amount, burned, energyBurned);
        return (amount, energyShare);
    }

    // Claims rewards
    function claim(address account) public update {
        Data storage user = data[account];

        _updateRewards(account);

        require(
            user.notClaimed > 0,
            "TutellusLaunchpadStaking: nothing to claim"
        );

        _reward(account);

        emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
        emit UpdateData(
            account,
            user.amount,
            user.rewardDebt,
            user.notClaimed,
            user.endInterval
        );
        emit Claim(account);
    }

    // Toggles autoreward
    function toggleAutoreward() public onlyRole(LAUNCHPAD_ADMIN_ROLE) {
        autoreward = !autoreward;
        emit ToggleAutoreward(autoreward);
    }

    function _reward(address account) internal {
        ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(
            ITutellusManager(config).get(LAUNCHPAD_REWARDS)
        );
        uint256 amount = data[account].notClaimed;
        if (amount > 0) {
            data[account].notClaimed = 0;
            rewardsInterface.distribute(account, amount);
            emit Rewards(account, amount);
        }
    }

    // Gets current fee for a user
    function getFee(address account) public view returns (uint256) {
        Data memory user = data[account];
        uint256 fee = block.number < user.endInterval
            ? user.feeInterval > 0
                ? (user.maxFee * (user.endInterval - block.number)) /
                    user.feeInterval
                : user.minFee
            : user.minFee;
        return fee > user.minFee ? fee : user.minFee;
    }

    // Gets blocks until endInverval
    function getBlocksLeft(address account) public view returns (uint256) {
        if (block.number > data[account].endInterval) {
            return 0;
        } else {
            return data[account].endInterval - block.number;
        }
    }

    // Gets user pending rewards
    function pendingRewards(address account) public view returns (uint256) {
        Data memory user = data[account];
        uint256 rewards = user.notClaimed;
        if (balance > 0) {
            ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(
                ITutellusManager(config).get(LAUNCHPAD_REWARDS)
            );
            uint256 released = rewardsInterface.released(address(this)) -
                _released;
            uint256 total = ((released * 1 ether) / balance);
            rewards +=
                ((accRewardsPerShare - user.rewardDebt + total) * user.amount) /
                1 ether;
        }
        return rewards;
    }

    // Gets user staking balance
    function getUserBalance(address account) public view returns (uint256) {
        Data memory user = data[account];
        return user.amount;
    }

    function getEnergyMultiplier() public view returns (uint256) {
        return _getEnergyMultiplier();
    }

    function _getEnergyMultiplier() internal view returns (uint256) {
        address _energyManager = ITutellusManager(config).get(
            keccak256("ENERGY_MULTIPLIER_MANAGER")
        );
        return
            ITutellusEnergyMultiplierManager(_energyManager)
                .getEnergyMultiplier(address(this));
    }

    /**
     * This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[45] private __gap;
}
