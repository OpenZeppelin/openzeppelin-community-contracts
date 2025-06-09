// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// 0x00010000010114D8DA6BF26964AF9D7EED9E03E53415D37AA96045
// 0x000100022045296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef02005333498d5aea4ae009585c43f7b8c30df8e70187d4a713d134f977fc8dfe0b5
// 0x000100000014D8DA6BF26964AF9D7EED9E03E53415D37AA96045
// 0x000100022045296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef000
// 0x0001000002A4B114D8DA6BF26964AF9D7EED9E03E53415D37AA96045

library ERC7930 {
    using SafeCast for uint256;
    using Bytes for bytes;

    error ERC7930ParsingError(bytes);

    function formatV1(
        bytes2 chainType,
        bytes memory chainReference,
        bytes memory addr
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                bytes2(0x0001),
                chainType,
                chainReference.length.toUint8(),
                chainReference,
                addr.length.toUint8(),
                addr
            );
    }

    function formatEvmV1(uint256 chainid, address addr) internal pure returns (bytes memory) {
        if (chainid <= type(uint8).max)
            return abi.encodePacked(bytes2(0x0001), bytes2(0x0000), uint8(1), uint8(chainid), uint8(20), addr);
        if (chainid <= type(uint16).max)
            return abi.encodePacked(bytes2(0x0001), bytes2(0x0000), uint8(2), uint16(chainid), uint8(20), addr);
        if (chainid <= type(uint24).max)
            return abi.encodePacked(bytes2(0x0001), bytes2(0x0000), uint8(3), uint24(chainid), uint8(20), addr);
        else revert();
    }

    function parseV1(
        bytes memory self
    ) internal pure returns (bytes2 chainType, bytes memory chainReference, bytes memory addr) {
        bool success;
        (success, chainType, chainReference, addr) = tryParseV1(self);
        require(success, ERC7930ParsingError(self));
    }

    function parseV1Calldata(
        bytes calldata self
    ) internal pure returns (bytes2 chainType, bytes calldata chainReference, bytes calldata addr) {
        bool success;
        (success, chainType, chainReference, addr) = tryParseV1Calldata(self);
        require(success, ERC7930ParsingError(self));
    }

    function tryParseV1(
        bytes memory self
    ) internal pure returns (bool success, bytes2 chainType, bytes memory chainReference, bytes memory addr) {
        unchecked {
            success = true;
            if (self.length < 0x06) return (false, 0x0000, _emptyBytesMemory(), _emptyBytesMemory());

            bytes2 version = _readBytes2(self, 0x00);
            if (version != bytes2(0x0001)) return (false, 0x0000, _emptyBytesMemory(), _emptyBytesMemory());
            chainType = _readBytes2(self, 0x02);

            uint8 chainReferenceLength = uint8(self[0x04]);
            if (self.length < 0x06 + chainReferenceLength)
                return (false, 0x0000, _emptyBytesMemory(), _emptyBytesMemory());
            chainReference = self.slice(0x05, 0x05 + chainReferenceLength);

            uint8 addrLength = uint8(self[0x05 + chainReferenceLength]);
            if (self.length < 0x06 + chainReferenceLength + addrLength)
                return (false, 0x0000, _emptyBytesMemory(), _emptyBytesMemory());
            addr = self.slice(0x06 + chainReferenceLength, 0x06 + chainReferenceLength + addrLength);
        }
    }

    function tryParseV1Calldata(
        bytes calldata self
    ) internal pure returns (bool success, bytes2 chainType, bytes calldata chainReference, bytes calldata addr) {
        unchecked {
            success = true;
            if (self.length < 0x06) return (false, 0x0000, Calldata.emptyBytes(), Calldata.emptyBytes());

            bytes2 version = _readBytes2Calldata(self, 0x00);
            if (version != bytes2(0x0001)) return (false, 0x0000, Calldata.emptyBytes(), Calldata.emptyBytes());
            chainType = _readBytes2Calldata(self, 0x02);

            uint8 chainReferenceLength = uint8(self[0x04]);
            if (self.length < 0x06 + chainReferenceLength)
                return (false, 0x0000, Calldata.emptyBytes(), Calldata.emptyBytes());
            chainReference = self[0x05:0x05 + chainReferenceLength];

            uint8 addrLength = uint8(self[0x05 + chainReferenceLength]);
            if (self.length < 0x06 + chainReferenceLength + addrLength)
                return (false, 0x0000, Calldata.emptyBytes(), Calldata.emptyBytes());
            addr = self[0x06 + chainReferenceLength:0x06 + chainReferenceLength + addrLength];
        }
    }

    function _readBytes2(bytes memory buffer, uint256 offset) private pure returns (bytes2 value) {
        // This is not memory safe in the general case, but all calls to this private function are within bounds.
        assembly ("memory-safe") {
            value := shl(240, shr(240, mload(add(add(buffer, 0x20), offset))))
        }
    }

    function _readBytes2Calldata(bytes calldata buffer, uint256 offset) private pure returns (bytes2 value) {
        assembly ("memory-safe") {
            value := shl(240, shr(240, calldataload(add(buffer.offset, offset))))
        }
    }

    function _emptyBytesMemory() private pure returns (bytes memory result) {
        assembly ("memory-safe") {
            result := 0x60 // mload(0x60) is always 0
        }
    }
}
