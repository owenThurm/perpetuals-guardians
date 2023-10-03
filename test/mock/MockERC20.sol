// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    error MockERC20__AmountMustBeMoreThanZero();

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_amount == 0) {
            revert MockERC20__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
