// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface ILBFactory {
    function setPreset(
        uint16 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator,
        bool isOpen
    ) external;

    function setLBPairImplementation(address newLBPairImplementation) external;

    function addQuoteAsset(address quoteAsset) external;

    function createLBPair(address tokenX, address tokenY, uint24 activeId, uint16 binStep)
        external
        returns (address pair);
}

interface ILBPair {
    function initialize(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator,
        uint24 activeId
    ) external;

    function mint(address to, bytes32[] calldata liquidityConfigs, address refundTo)
        external
        returns (bytes32 amountsReceived, bytes32 amountsLeft, uint256[] memory liquidityMinted);

    function swap(bool swapForY, address to) external returns (bytes32 amountsOut);
}

abstract contract LBHelper is Test {
    ILBFactory lbFactory;

    function setUp() public virtual {
        address deployedAddr;
        // https://etherscan.io/address/0xDC8d77b69155c7E68A95a4fb0f06a71FF90B943a#readContract
        // relative to the root of the project
        bytes memory bytecode = vm.readFileBinary("./test/pool-bin/bin/LBFactory.bytecode");
        assembly {
            deployedAddr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        // vm.etch(address(lbFactory), deployedAddr.code);
        // lbFactory = ILBFactory(0xDC8d77b69155c7E68A95a4fb0f06a71FF90B943a);
        lbFactory = ILBFactory(deployedAddr);

        // set presets
        for (uint256 i = 1; i <= 100; ++i) {
            // add preset otherwise it will revert
            // set fee = 0 but period args with non zero to bypass LBPair__InvalidStaticFeeParameters
            lbFactory.setPreset(uint16(i), 0, 1, 1, 0, 0, 0, 0, true);
        }

        // set lbPair implementation
        address lbPairAddr;
        {
            // https://etherscan.io/address/0x7f89d5E94d6Bd0351426E113fde9eF9ea678c186#code
            // relative to the root of the project
            bytecode = vm.readFileBinary("./test/pool-bin/bin/LBPair.bytecode");
            assembly {
                // override constructor arguments to addr of LBFactory to bypass the check
                // posOfBytecode + 0x20 + length - 0x20
                let constructorArgStart := add(mload(bytecode), bytecode)
                mstore(constructorArgStart, deployedAddr)
                lbPairAddr := create(0, add(bytecode, 0x20), mload(bytecode))
            }
        }
        lbFactory.setLBPairImplementation(lbPairAddr);
    }
}
