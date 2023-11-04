// PiggyBank.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PiggyBank {
    address owner;
    uint256 balance;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function deposit() public payable {
        require(msg.value > 0, "You must send some ether to deposit");
        balance += msg.value;
    }

    function withdraw() public onlyOwner {
        require(balance > 0, "The Piggy Bank is empty");
        payable(owner).transfer(balance);
        balance = 0;
    }

    function getBalance() public view returns (uint256) {
        return balance;
    }
}

// PiggyBankFactory.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PiggyBank.sol";

contract PiggyBankFactory {
    address[] public deployedPiggyBanks;

    function createPiggyBank() public {
        address newPiggyBank = address(new PiggyBank());
        deployedPiggyBanks.push(newPiggyBank);
    }

    function getDeployedPiggyBanks() public view returns (address[] memory) {
        return deployedPiggyBanks;
    }
}
