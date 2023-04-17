// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./interfaces/IStarknetMessaging.sol";
import "./KassUtils.sol";
import "./factory/KassERC721.sol";
import "./factory/KassERC1155.sol";
import "./factory/KassERC1967Proxy.sol";
import "./KassStorage.sol";

abstract contract TokenDeployer is KassStorage {
    // CONSTRUCTOR

    function setDeployerImplementations() internal {
        if (_state.proxyImplementationAddress == address(0x0)) {
            _state.proxyImplementationAddress = address(
                new KassERC1967Proxy{ salt: keccak256("KassERC1967Proxy") }()
            );
        }

        if (_state.erc721ImplementationAddress == address(0x0)) {
            _state.erc721ImplementationAddress = address(
                new KassERC721{ salt: keccak256("KassERC721") }()
            );
        }

        if (_state.erc1155ImplementationAddress == address(0x0)) {
            _state.erc1155ImplementationAddress = address(
                new KassERC1155{ salt: keccak256("KassERC1155") }()
            );
        }
    }

    // GETTERS

    function computeL1TokenAddress(uint256 l2TokenAddress) public view returns (address addr) {
        bytes20 baseAddressBytes = bytes20(_state.proxyImplementationAddress);
        bytes20 deployerBytes = bytes20(address(this));

        assembly {
            let ptr := mload(0x40)

            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), baseAddressBytes)
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            mstore(add(ptr, 0x37), l2TokenAddress)

            let bytecodeHash := keccak256(ptr, 0x57)

            mstore(ptr, 0xff00000000000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x1), deployerBytes)
            mstore(add(ptr, 0x15), l2TokenAddress)
            mstore(add(ptr, 0x35), bytecodeHash)

            addr := keccak256(ptr, 0x55)
        }
    }

    function getNativeTokenAddres(address tokenAddress) internal view returns (uint256 nativeTokenAddress) {
        assembly {
            let ptr := mload(0x40)
            extcodecopy(tokenAddress, ptr, 0x37, 0x20)
            nativeTokenAddress := mload(ptr)
        }
    }

    function getL1TokenAddres(
        bytes32 nativeTokenAddress
    ) internal view returns (address l1TokenAddress, bool isNative) {
        if (Address.isContract(address(uint160(uint256(nativeTokenAddress))))) {
            l1TokenAddress = address(uint160(uint256(nativeTokenAddress)));
            isNative = true;
        } else {
            l1TokenAddress = computeL1TokenAddress(uint256(nativeTokenAddress));
            isNative = false;
        }
    }

    // INTERNALS

    /**
     * Modified https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol#L30
     * to support Create2.
     * @param salt Salt for CREATE2
     */
    function cloneProxy(bytes32 salt) private returns (address payable result) {
        bytes20 targetBytes = bytes20(_state.proxyImplementationAddress);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            mstore(add(clone, 0x37), salt) // append salt at the end of bytecode
            result := create2(0, clone, 0x57, salt)
        }
    }

    function cloneKassERC1155(bytes32 salt, bytes memory _calldata) internal returns (address payable result) {
        result = cloneProxy(salt);

        KassERC1967Proxy(result).initializeKassERC1967Proxy(
            _state.erc1155ImplementationAddress,
            abi.encodeWithSelector(KassERC1155.initialize.selector, _calldata)
        );
    }

    function cloneKassERC721(bytes32 salt, bytes memory _calldata) internal returns (address payable result) {
        result = cloneProxy(salt);

        KassERC1967Proxy(result).initializeKassERC1967Proxy(
            _state.erc721ImplementationAddress,
            abi.encodeWithSelector(KassERC721.initialize.selector, _calldata)
        );
    }
}
