// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library HookAddressMiner {
    error HookSaltNotFound();

    function find(
        address deployer,
        uint160 requiredFlags,
        uint160 flagMask,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes32 initCodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));

        for (uint256 i = 0; i < 1_000_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(deployer, salt, initCodeHash);
            if ((uint160(hookAddress) & flagMask) == requiredFlags) {
                return (hookAddress, salt);
            }
        }

        revert HookSaltNotFound();
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        private
        pure
        returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
