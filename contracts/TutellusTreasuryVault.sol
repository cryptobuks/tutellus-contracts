// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./utils/AccessControlProxyPausable.sol";
import "./TutellusStakingProxy.sol";
import "./interfaces/ITutellusERC20.sol";

contract TutellusYieldRewardsVault is AccessControlProxyPausable {

    address public token;
    address public treasury;

    uint256 private _released;
    uint private _startBlock;
    uint private _endBlock;
    uint private _increment;

    function released() public view returns (uint256) {
      return releasedRange(block.number, _startBlock);
    }

    function releasedRange(uint from, uint to) public view returns (uint256) {
      require(from < to, "TutellusYieldTutellusYieldRewardstoken: {from} is after {to}");
      if (to > _endBlock) to = _endBlock;
      if (from < _startBlock) from = _startBlock;
      uint256 comp0 = (_increment * ((to - _startBlock) ** 2)) / 2;
      uint256 comp1 = (_increment * ((from - _startBlock) ** 2)) / 2;
      return comp0 - comp1;
    }

    function updateTreasury(address treasury_) public onlyRole(DEFAULT_ADMIN_ROLE) {
      treasury = treasury_;
    }

    function claim() public onlyRole(DEFAULT_ADMIN_ROLE) {
      uint256 amount = released() - _released;
      require(amount > 0, "TutellusTreasuryVault: nothing to claim");
      ITutellusERC20 tokenInterface = ITutellusERC20(token);
      tokenInterface.transfer(treasury, amount);
    }

    // Initializes the contract
    function initialize(
      address rolemanager,
      address treasury_,
      address token_,
      uint256 amount, 
      uint blocks
) 
      public 
    {
      __TutellusYieldRewardsVault_init(
        rolemanager,
        treasury_,
        token_,
        amount, 
        blocks
      );
    }

    function __TutellusYieldRewardsVault_init(
      address rolemanager,
      address treasury_,
      address token_,
      uint256 amount, 
      uint blocks
    ) 
      internal 
      initializer 
    {
      __AccessControlProxyPausable_init(rolemanager);
      __TutellusYieldRewardsVault_init_unchained(
        treasury_,
        token_,
        amount, 
        blocks
      );
    }

    function __TutellusYieldRewardsVault_init_unchained(
      address treasury_,
      address token_,
      uint256 amount, 
      uint blocks
    ) 
      internal 
      initializer 
    {
        token = token_;
        treasury = treasury_;
        ITutellusERC20 tokenInterface = ITutellusERC20(token);
        tokenInterface.mint(address(this), amount);

        _startBlock = block.number;
        _endBlock = block.number + blocks;
        _increment = (2 * amount) / (blocks ** 2);
    }
}
