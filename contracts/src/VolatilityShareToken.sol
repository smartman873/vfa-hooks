// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VolatilityShareToken is ERC1155, Ownable {
    error OnlyMarket();
    error TransfersDisabled();

    address public market;
    bool public transfersEnabled;

    modifier onlyMarket() {
        if (msg.sender != market) {
            revert OnlyMarket();
        }
        _;
    }

    constructor(string memory baseUri, address initialOwner) ERC1155(baseUri) Ownable(initialOwner) {}

    function setMarket(address newMarket) external onlyOwner {
        require(newMarket != address(0), "zero market");
        market = newMarket;
    }

    function setTransfersEnabled(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
    }

    function mint(address to, uint256 id, uint256 amount) external onlyMarket {
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyMarket {
        _burn(from, id, amount);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert TransfersDisabled();
        }
        super._update(from, to, ids, values);
    }
}
