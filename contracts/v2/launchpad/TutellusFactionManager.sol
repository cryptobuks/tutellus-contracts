// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import 'contracts/utils/UUPSUpgradeableByRole.sol';
import 'contracts/interfaces/ITutellusLaunchpadStaking.sol';
import 'contracts/interfaces/ITutellusFactionManager.sol';
import 'contracts/interfaces/ITutellusERC20.sol';
import 'contracts/interfaces/ITutellusManager.sol';
import 'contracts/interfaces/ITutellusWhitelist.sol';

contract TutellusFactionManager is ITutellusFactionManager, UUPSUpgradeableByRole {

    bytes32 public constant _FACTIONS_ADMIN_ROLE = keccak256('FACTIONS_ADMIN_ROLE');

    struct Faction {
        address stakingContract;
        address farmingContract;
    }

    mapping(bytes32=>Faction) public faction;
    mapping(address=>bytes32) public factionOf;
    mapping(address=>address) public authorized;
    mapping(address=>bool) public isFactionContract;

    modifier isWhitelisted (
        address account
    ) {
        address whitelist = ITutellusManager(config).get(keccak256("WHITELIST"));
        require(
            ITutellusWhitelist(whitelist).whitelisted(account),
            'TutellusFactionManager: address not whitelisted'
        );
        _;
    }

    modifier isAuthorized (
        address account
    ) {
        require(msg.sender == account || authorized[account] == msg.sender, 'TutellusFactionManager: account not authorized');
        _;
    }

    modifier checkFaction (
        bytes32 id,
        address account
    ) {
        if (factionOf[account] == 0x00) {
            factionOf[account] = id;
            _;
            emit FactionIn(id, account);
        } else {
            require(factionOf[account] == id, 'TutellusFactionManager: cant stake in multiple factions');
            _;
        }
    }

    modifier checkAfter (
        address account
    ) {
        _;
        bytes32 id = factionOf[account];
        ITutellusLaunchpadStaking stakingInterface = ITutellusLaunchpadStaking(faction[id].stakingContract);
        ITutellusLaunchpadStaking farmingInterface = ITutellusLaunchpadStaking(faction[id].farmingContract);

        if (stakingInterface.getUserBalance(account) + farmingInterface.getUserBalance(account) == 0) {
            factionOf[account] = 0x00;
            emit FactionOut(id, account);
        }
    }

    function authorize(
        address account
    ) public {
        authorized[msg.sender] = account;
    }

    function updateFaction (
        bytes32 id,
        address stakingContract,
        address farmingContract
    ) public onlyRole(_FACTIONS_ADMIN_ROLE) {
        faction[id] = Faction(stakingContract, farmingContract);
        isFactionContract[stakingContract] = true;
        isFactionContract[farmingContract] = true;
    }

    function stake (
        bytes32 id,
        address account,
        uint256 amount
    ) public
    isAuthorized(account)
    isWhitelisted(account)
    checkFaction(id, account)
    {
        ITutellusLaunchpadStaking(faction[id].stakingContract).deposit(account, amount);
        emit Stake(id, account, amount);
    }

    function stakeLP (
        bytes32 id,
        address account,
        uint256 amount
    ) public
    isAuthorized(account)
    isWhitelisted(account)
    checkFaction(id, account) {
        ITutellusLaunchpadStaking(faction[id].farmingContract).deposit(account, amount);
        emit StakeLP(id, account, amount);
    }

    function unstake (
        address account,
        uint256 amount
    ) public
    isAuthorized(account)
    checkAfter(account)
    {
        bytes32 id = factionOf[account];
        require(id != 0x00, 'TutellusFactionManager: cant unstake');
        ITutellusLaunchpadStaking(faction[id].stakingContract).withdraw(account, amount);
        emit Unstake(id, account, amount);
    }

    function unstakeLP (
        address account,
        uint256 amount
    ) public
    isAuthorized(account)
    checkAfter(account)
    {
        bytes32 id = factionOf[account];
        require(id != 0x00, 'TutellusFactionManager: cant unstakeLP');
        ITutellusLaunchpadStaking(faction[id].farmingContract).withdraw(account, amount);
        emit UnstakeLP(id, account, amount);
    }

    function migrateFaction (
        address account,
        bytes32 to
    ) public isAuthorized(account) {
        bytes32 id = factionOf[account];
        require(id != 0x00, 'TutellusFactionManager: cant migrate');
        require(faction[to].stakingContract != address(0) && faction[to].farmingContract != address(0), 'TutellusFactionManager: faction does not exist');

        ITutellusLaunchpadStaking stakingInterface = ITutellusLaunchpadStaking(faction[id].stakingContract);
        ITutellusLaunchpadStaking farmingInterface = ITutellusLaunchpadStaking(faction[id].farmingContract);

        uint256 stakingBalance = stakingInterface.getUserBalance(account);
        uint256 farmingBalance = farmingInterface.getUserBalance(account);
        uint256 newStakingAmount;
        uint256 newFarmingAmount;

        if (stakingBalance > 0) {
            newStakingAmount = stakingInterface.withdraw(account, stakingBalance);
            emit Unstake(id, account, stakingBalance);
        }

        if (farmingBalance > 0) {
            newFarmingAmount = farmingInterface.withdraw(account, farmingBalance);
            emit UnstakeLP(id, account, farmingBalance);
        }

        emit FactionOut(id, account);
        emit FactionIn(to, account);

        if (newStakingAmount > 0) {
            ITutellusLaunchpadStaking(faction[to].stakingContract).deposit(account, newStakingAmount);
            emit Stake(to, account, newStakingAmount);
        }

        if (newFarmingAmount > 0) {
            ITutellusLaunchpadStaking(faction[to].farmingContract).deposit(account, newFarmingAmount);
            emit StakeLP(to, account, newFarmingAmount);
        }

        factionOf[account] = to;
        emit Migrate(id, to, account);
    }

    function depositFrom (
        address account,
        uint256 amount,
        address token
    ) public {
        require(isFactionContract[msg.sender], 'TutellusFactionManager: deposit only callable by faction contract');
        ITutellusERC20 tokenInterace = ITutellusERC20(token);
        tokenInterace.transferFrom(account, msg.sender, amount);
    }

    function initialize () public initializer {
        __AccessControlProxyPausable_init(msg.sender);
    }
}