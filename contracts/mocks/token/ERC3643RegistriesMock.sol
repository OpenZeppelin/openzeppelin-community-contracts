// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC735, IERC735ClaimIssuer} from "../../interfaces/IERC735.sol";
import {ERC3643ClaimTopicsRegistry} from "../../token/ERC20/extensions/ERC3643/ERC3643ClaimTopicsRegistry.sol";
import {ERC3643IdentityRegistry} from "../../token/ERC20/extensions/ERC3643/ERC3643IdentityRegistry.sol";
import {ERC3643IdentityRegistryStorage} from "../../token/ERC20/extensions/ERC3643/ERC3643IdentityRegistryStorage.sol";
import {ERC3643TrustedIssuersRegistry} from "../../token/ERC20/extensions/ERC3643/ERC3643TrustedIssuersRegistry.sol";

abstract contract ERC3643ClaimTopicsRegistryMock is ERC3643ClaimTopicsRegistry, Ownable {
    function _authorizeClaimTopicsUpdate() internal view override onlyOwner {}
}

abstract contract ERC3643TrustedIssuersRegistryMock is ERC3643TrustedIssuersRegistry, Ownable {
    function _authorizeIssuersUpdate() internal view override onlyOwner {}
}

abstract contract ERC3643IdentityRegistryStorageMock is ERC3643IdentityRegistryStorage, Ownable {
    function _authorizeRegistryBinding() internal view override onlyOwner {}
}

abstract contract ERC3643IdentityRegistryMock is ERC3643IdentityRegistry, Ownable {
    function _authorizeIdentityUpdate() internal view override onlyOwner {}

    function _authorizeRegistryUpdate() internal view override onlyOwner {}
}

contract ERC735IdentityMock is IERC735 {
    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    mapping(bytes32 claimId => Claim) private _claims;
    bool private _reverts;

    function setClaim(uint256 topic, address issuer, bytes memory signature, bytes memory data) public {
        _claims[keccak256(abi.encode(issuer, topic))] = Claim(topic, 1, issuer, signature, data, "");
    }

    function setClaimAt(bytes32 claimId, uint256 topic, address issuer) public {
        _claims[claimId] = Claim(topic, 1, issuer, "", "", "");
    }

    function setReverts(bool reverts) public {
        _reverts = reverts;
    }

    function getClaim(
        bytes32 claimId
    ) public view returns (uint256, uint256, address, bytes memory, bytes memory, string memory) {
        require(!_reverts);
        Claim storage claim = _claims[claimId];
        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }
}

contract ERC735ClaimIssuerMock is IERC735ClaimIssuer {
    enum Answer {
        Valid,
        Invalid,
        Revert,
        NonBoolean,
        Oversized
    }

    Answer private _answer;
    bytes32 private _expectedHash;

    function setAnswer(Answer answer) public {
        _answer = answer;
    }

    /// @dev Only claims whose `abi.encode(identity, topic, signature, data)` hashes to `expectedHash` are valid.
    function setExpectedClaim(address identity, uint256 topic, bytes memory signature, bytes memory data) public {
        _expectedHash = keccak256(abi.encode(identity, topic, signature, data));
    }

    function isClaimValid(
        address identity,
        uint256 topic,
        bytes calldata signature,
        bytes calldata data
    ) public view returns (bool) {
        Answer answer = _answer;
        if (answer == Answer.Revert) revert();
        if (answer == Answer.NonBoolean) {
            assembly ("memory-safe") {
                mstore(0, 2)
                return(0, 0x20)
            }
        }
        if (answer == Answer.Oversized) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(0, 0x40)
            }
        }
        return answer == Answer.Valid && keccak256(abi.encode(identity, topic, signature, data)) == _expectedHash;
    }
}
