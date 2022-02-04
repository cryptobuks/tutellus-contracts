// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../utils/UUPSUpgradeableByRole.sol";
import "../interfaces/ITutellusERC20.sol";
import "../interfaces/ITutellusRewardsVaultV2.sol";
import "../interfaces/ITutellusManager.sol";

contract TutellusStakingV2 is UUPSUpgradeableByRole {

  bool public autoreward;

  address public token;

  uint256 public balance;
  uint256 public minFee;
  uint256 public maxFee;
  uint256 public accRewardsPerShare;

  uint256 internal _released;

  uint public lastUpdate;
  uint public feeInterval;
  uint public stakers;

  struct Data {
    uint256 amount;
    uint256 rewardDebt;
    uint256 notClaimed;
    uint endInterval;
    uint256 minFee;
    uint256 maxFee;
    uint256 feeInterval;
  }

  mapping(address=>Data) private data;

  event Claim(address account);
  event Deposit(address account, uint256 amount);
  event Withdraw(address account, uint256 amount, uint256 burned);
  event Rewards(address account, uint256 amount);

  event SyncBalance(address account, uint256 amount);
  event ToggleAutoreward(bool autoreward);
  event Update(uint256 balance, uint256 accRewardsPerShare, uint lastUpdate, uint stakers);
  event UpdateData(address account, uint256 amount, uint256 rewardDebt, uint256 notClaimed, uint endInterval);
  event SetFees(uint256 minFee, uint256 maxFee);
  event SetFeeInterval(uint feeInterval);
  event Migrate(address from, address to, address account, uint256 amount, bytes response);

  modifier update() {
    require(token != address(0), "TutellusStaking: token must be set");
    ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(ITutellusManager(config).get(keccak256("REWARDS")));
    uint256 released = rewardsInterface.released(address(this)) - _released;
    _released += released;
    if(balance > 0) {
      accRewardsPerShare += (released * 1 ether / balance);
    }
    lastUpdate = block.number;
    _;
  }

  // Updates rewards for an account
  function _updateRewards(address account) internal {
    Data storage user = data[account];
    uint256 diff = accRewardsPerShare - user.rewardDebt;
    user.notClaimed += diff * user.amount / 1 ether;
    user.rewardDebt = accRewardsPerShare;
  }

  // Sets maximum and minimum fees
  function setFees(uint256 minFee_, uint256 maxFee_) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(minFee_ <= maxFee_, "TutellusStakingV2: mininum fee must be greater or equal than maximum fee");
    require(minFee_ <= 1e20, "TutellusStakingV2: minFee cannot exceed 100 ether");
    require(maxFee_ <= 1e20, "TutellusStakingV2: maxFee cannot exceed 100 ether");
    minFee = minFee_;
    maxFee = maxFee_;
    emit SetFees(minFee, maxFee);
  }

  // Sets fee interval (blocks) for staking
  function setFeeInterval(uint feeInterval_) public onlyRole(DEFAULT_ADMIN_ROLE) {
    feeInterval = feeInterval_;
    emit SetFeeInterval(feeInterval);
  }

  // Deposits tokens for staking
  function deposit(address account, uint256 amount) public update whenNotPaused {
    require(amount > 0, "TutellusStakingV2: amount must be over zero");

    Data storage user = data[account];

    _updateRewards(account);

    if(user.amount == 0) {
      stakers += 1;
    }

    user.endInterval = block.number + feeInterval;
    user.minFee = minFee;
    user.maxFee = maxFee;
    user.feeInterval = feeInterval;
    user.amount += amount;
    balance += amount;

    ITutellusERC20 tokenInterface = ITutellusERC20(token);
    
    if(autoreward) {
      _reward(account);
    }

    require(tokenInterface.transferFrom(account, address(this), amount), "TutellusStakingV2: deposit transfer failed");

    emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
    emit UpdateData(account, user.amount, user.rewardDebt, user.notClaimed, user.endInterval);
    emit Deposit(account, amount);
  }

  function depositAll(address account) public {
    ITutellusERC20 tokenInterface = ITutellusERC20(token);
    uint256 amount = tokenInterface.balanceOf(account);
    deposit(account, amount);
  }

  // Withdraws tokens from staking
  function withdraw(uint256 amount) public update whenNotPaused returns (uint256) {
    require(amount > 0, "TutellusStakingV2: amount must be over zero");

    address account = msg.sender;
    Data storage user = data[account];

    require(amount <= user.amount, "TutellusStakingV2: user has not enough staking balance");

    _updateRewards(account);

    user.rewardDebt = accRewardsPerShare;
    user.amount -= amount;
    balance -= amount;

    if(user.amount == 0) {
      stakers -= 1;
    }

    ITutellusERC20 tokenInterface = ITutellusERC20(token);

    uint256 burned = amount * getFee(account) / 1e20;
    amount -= burned;

    if(autoreward) {
      _reward(account);
    }
    if(burned > 0){
      tokenInterface.burn(burned);
    }
    
    tokenInterface.transfer(account, amount);

    emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
    emit UpdateData(account, user.amount, user.rewardDebt, user.notClaimed, user.endInterval);
    emit Withdraw(account, amount, burned);
    return amount;
  }

  function withdrawAll() public whenNotPaused returns (uint256) {
    uint256 amount = getUserBalance(msg.sender);
    return withdraw(amount);
  }

  // Claims rewards
  function claim() public update whenNotPaused {
    address account = msg.sender;
    Data storage user = data[account];

    _updateRewards(account);

    require(user.notClaimed > 0, "TutellusStakingV2: nothing to claim");

    _reward(account);

    emit Update(balance, accRewardsPerShare, lastUpdate, stakers);
    emit UpdateData(account, user.amount, user.rewardDebt, user.notClaimed, user.endInterval);
    emit Claim(account);
  }

  // Toggles autoreward
  function toggleAutoreward() public onlyRole(DEFAULT_ADMIN_ROLE) {
    autoreward = !autoreward;
    emit ToggleAutoreward(autoreward);
  }

  function _reward(address account) internal {
    ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(ITutellusManager(config).get(keccak256("REWARDS")));
    uint256 amount = data[account].notClaimed;
    if(amount > 0) {
      data[account].notClaimed = 0;
      rewardsInterface.distribute(account, amount);
      emit Rewards(account, amount);
    }
  }

  // Gets current fee for a user
  function getFee(address account) public view returns(uint256) {
    Data memory user = data[account];
    uint256 fee = block.number < user.endInterval ? user.feeInterval > 0 ? user.maxFee * (user.endInterval - block.number) / user.feeInterval : user.minFee : user.minFee;
    return fee > user.minFee ? fee : user.minFee;
  }

  // Gets blocks until endInverval
  function getBlocksLeft(address account) public view returns (uint) {
    if(block.number > data[account].endInterval) {
      return 0;
    } else {
      return data[account].endInterval - block.number;
    }
  }

  // Gets user pending rewards
  function pendingRewards(address user_) public view returns(uint256) {
      Data memory user = data[user_];
      uint256 rewards = user.notClaimed;
      if(balance > 0){
        ITutellusRewardsVaultV2 rewardsInterface = ITutellusRewardsVaultV2(ITutellusManager(config).get(keccak256("REWARDS")));
        uint256 released = rewardsInterface.released(address(this)) - _released;
        uint256 total = (released * 1e18 / balance);
        rewards += (accRewardsPerShare - user.rewardDebt + total) * user.amount / 1e18;
      }
      return rewards;
  }

  function initialize(address token_) public initializer {
    __AccessControlProxyPausable_init(msg.sender);
    // minFee = 1e17;
    // maxFee = 1e19;
    // feeInterval = 1296000;
    autoreward = true;
    lastUpdate = block.number;
    token = token_;
  }

  // Gets token gap
  function getTokenGap() public view returns (uint256) {
    ITutellusERC20 tokenInterface = ITutellusERC20(token);
    uint256 tokenBalance = tokenInterface.balanceOf(address(this));
    return tokenBalance - balance;
  }

  // Synchronizes balance, transfering the gap to an external account
  function syncBalance(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
    ITutellusERC20 tokenInterface = ITutellusERC20(token);
    uint256 gap = getTokenGap();
    require(gap > 0, "TutellusStakingV2: there is no gap");
    tokenInterface.transfer(account, gap);
    emit SyncBalance(account, gap);
  }

  // Gets user staking balance
  function getUserBalance(address user_) public view returns(uint256) {
    Data memory user = data[user_];
    return user.amount;
  }

  function migrate(address to) public returns (bytes memory){
    address account = msg.sender;
    uint256 amount = withdraw(data[account].amount);
    (bool success, bytes memory response) = to.call(
          abi.encodeWithSignature("deposit(address,uint256)", account, amount)
      );
    require(success, 'TutellusStakingV2: migration failed');
    emit Migrate(address(this), to, account, amount, response);
    return response;
  }

  function emergencyWithdraw() public returns (uint256) {
    ITutellusERC20 tokenInterface = ITutellusERC20(token);
    data[msg.sender].amount -= data[msg.sender].amount;
    balance -= data[msg.sender].amount;
    tokenInterface.transfer(msg.sender, data[msg.sender].amount);
    return data[msg.sender].amount;
  }
}
