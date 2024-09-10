// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {ICAIP2Equivalence} from "../ICAIP2Equivalence.sol";

abstract contract AxelarGatewayBase is ICAIP2Equivalence, Ownable {
    event RegisteredRemoteGateway(string caip2, string gatewayAddress);
    event RegisteredCAIP2Equivalence(string caip2, string destinationChain);

    IAxelarGateway public immutable localGateway;

    mapping(string caip2 => string remoteGateway) private _remoteGateways;
    mapping(string caip2 => string destinationChain) private _equivalence;

    constructor(IAxelarGateway _gateway) {
        localGateway = _gateway;
    }

    function fromCAIP2(string memory caip2) public view returns (string memory) {
        return _equivalence[caip2];
    }

    function getRemoteGateway(string memory caip2) public view returns (string memory remoteGateway) {
        return _remoteGateways[caip2];
    }

    function registerCAIP2Equivalence(string calldata caip2, string calldata axelarSupported) public onlyOwner {
        require(bytes(_equivalence[caip2]).length == 0);
        _equivalence[caip2] = axelarSupported;
        emit RegisteredCAIP2Equivalence(caip2, axelarSupported);
    }

    function registerRemoteGateway(string calldata caip2, string calldata remoteGateway) public onlyOwner {
        require(bytes(_remoteGateways[caip2]).length == 0);
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}

// EVM (https://axelarscan.io/resources/chains?type=evm)
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("1"))] = "Ethereum";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("56"))] = "binance";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("137"))] = "Polygon";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("43114"))] = "Avalanche";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("250"))] = "Fantom";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("1284"))] = "Moonbeam";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("1313161554"))] = "aurora";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("42161"))] = "arbitrum";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("10"))] = "optimism";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("8453"))] = "base";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("5000"))] = "mantle";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("42220"))] = "celo";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("2222"))] = "kava";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("314"))] = "filecoin";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("59144"))] = "linea";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("2031"))] = "centrifuge";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("534352"))] = "scroll";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("13371"))] = "immutable";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("252"))] = "fraxtal";
// _equivalence[CAIP2.toString(bytes8("eip155"), bytes32("81457"))] = "blast";

// Cosmos (https://axelarscan.io/resources/chains?type=cosmos)
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('axelar-dojo-1'))] = 'Axelarnet';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('osmosis-1'))] = 'osmosis';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('cosmoshub-4'))] = 'cosmoshub';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('juno-1'))] = 'juno';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('emoney-3'))] = 'e-money';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('injective-1'))] = 'injective';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('crescent-1'))] = 'crescent';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('kaiyo-1'))] = 'kujira';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('secret-4'))] = 'secret-snip';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('secret-4'))] = 'secret';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('pacific-1'))] = 'sei';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('stargaze-1'))] = 'stargaze';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('mantle-1'))] = 'assetmantle';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('fetchhub-4'))] = 'fetch';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('kichain-2'))] = 'ki';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('evmos_9001-2'))] = 'evmos';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('xstaxy-1'))] = 'aura';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('comdex-1'))] = 'comdex';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('core-1'))] = 'persistence';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('regen-1'))] = 'regen';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('umee-1'))] = 'umee';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('agoric-3'))] = 'agoric';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('dimension_37-1'))] = 'xpla';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('acre_9052-1'))] = 'acre';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('stride-1'))] = 'stride';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('carbon-1'))] = 'carbon';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('sommelier-3'))] = 'sommelier';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('neutron-1'))] = 'neutron';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('reb_1111-1'))] = 'rebus';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('archway-1'))] = 'archway';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('pio-mainnet-1'))] = 'provenance';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('ixo-5'))] = 'ixo';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('migaloo-1'))] = 'migaloo';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('teritori-1'))] = 'teritori';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('haqq_11235-1'))] = 'haqq';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('celestia'))] = 'celestia';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('agamotto'))] = 'ojo';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('chihuahua-1'))] = 'chihuahua';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('ssc-1'))] = 'saga';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('dymension_1100-1'))] = 'dymension';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('fxcore'))] = 'fxcore';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('perun-1'))] = 'c4e';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('bitsong-2b'))] = 'bitsong';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('pirin-1'))] = 'nolus';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('lava-mainnet-1'))] = 'lava';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('phoenix-1'))] = 'terra-2';
// _equivalence[CAIP2.toString(bytes8('cosmos'), bytes32('columbus-5'))] = 'terra';"
