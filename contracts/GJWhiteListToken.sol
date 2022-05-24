// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GJWhiteListToken is ERC20, Ownable {
		
	address public distributor;
	constructor( 
		string memory name_, 
		string memory symbol_, 
		uint256 supply_,
		address mintTo_) ERC20(name_, symbol_) {
		_mint(mintTo_, supply_);
		distributor = mintTo_;

	}

	function setDistributor(address newDistributor) external onlyOwner {
		require(newDistributor != address(0));
		distributor = newDistributor;
	}

	function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
		require(msg.sender == distributor, "Transfers not allowed");		
		super.transfer(recipient, amount);
		return true;
	}

	function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
		require(sender == distributor, "Transfers not allowed");		
		super.transferFrom(sender, recipient, amount);
		return true;
	}

	function burn(uint256 amount) external {
		require(balanceOf(msg.sender) >= amount, "Not enough tokens to burn");
		_burn(msg.sender, amount);
	}

}