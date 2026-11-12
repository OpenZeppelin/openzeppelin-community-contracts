// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7 <0.9;
pragma experimental ABIEncoderV2;

import {AccessManagerLightUpgradeable} from "../access/manager/AccessManagerLightUpgradeable.sol";

contract AccessManagerLightUpgradeableWithInit is AccessManagerLightUpgradeable {
    constructor(address admin) payable initializer {
        __AccessManagerLight_init(admin);
    }
}
import {ERC7579MultisigUpgradeable} from "../account/modules/ERC7579MultisigUpgradeable.sol";

contract ERC7579MultisigUpgradeableWithInit is ERC7579MultisigUpgradeable {
    constructor() payable initializer {
        __ERC7579Multisig_init();
    }
}
import {ERC7579MultisigConfirmationUpgradeable} from "../account/modules/ERC7579MultisigConfirmationUpgradeable.sol";

contract ERC7579MultisigConfirmationUpgradeableWithInit is ERC7579MultisigConfirmationUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigConfirmation_init();
    }
}
import {ERC7579MultisigStorageUpgradeable} from "../account/modules/ERC7579MultisigStorageUpgradeable.sol";

contract ERC7579MultisigStorageUpgradeableWithInit is ERC7579MultisigStorageUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigStorage_init();
    }
}
import {ERC7579MultisigWeightedUpgradeable} from "../account/modules/ERC7579MultisigWeightedUpgradeable.sol";

contract ERC7579MultisigWeightedUpgradeableWithInit is ERC7579MultisigWeightedUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigWeighted_init();
    }
}
import {ERC7579SelectorExecutorUpgradeable} from "../account/modules/ERC7579SelectorExecutorUpgradeable.sol";

contract ERC7579SelectorExecutorUpgradeableWithInit is ERC7579SelectorExecutorUpgradeable {
    constructor() payable initializer {
        __ERC7579SelectorExecutor_init();
    }
}
import {ERC7579SignatureUpgradeable} from "../account/modules/ERC7579SignatureUpgradeable.sol";

contract ERC7579SignatureUpgradeableWithInit is ERC7579SignatureUpgradeable {
    constructor() payable initializer {
        __ERC7579Signature_init();
    }
}
import {RoleAccountUpgradeable} from "../account/RoleAccountUpgradeable.sol";

contract RoleAccountUpgradeableWithInit is RoleAccountUpgradeable {
    constructor() payable initializer {
        __RoleAccount_init();
    }
}
import {RoleAccountFactoryUpgradeable} from "../account/RoleAccountFactoryUpgradeable.sol";

contract RoleAccountFactoryUpgradeableWithInit is RoleAccountFactoryUpgradeable {
    constructor() payable initializer {
        __RoleAccountFactory_init();
    }
}
import {ERC7786OpenBridgeUpgradeable} from "../crosschain/ERC7786OpenBridgeUpgradeable.sol";

contract ERC7786OpenBridgeUpgradeableWithInit is ERC7786OpenBridgeUpgradeable {
    constructor(address owner_, address[] memory gateways_, uint8 threshold_) payable initializer {
        __ERC7786OpenBridge_init(owner_, gateways_, threshold_);
    }
}
import {WormholeGatewayAdapterUpgradeable, IWormholeRelayer} from "../crosschain/wormhole/WormholeGatewayAdapterUpgradeable.sol";

contract WormholeGatewayAdapterUpgradeableWithInit is WormholeGatewayAdapterUpgradeable {
    constructor(IWormholeRelayer wormholeRelayer, address initialOwner) payable initializer {
        __WormholeGatewayAdapter_init(wormholeRelayer, initialOwner);
    }
}
import {TimelockControllerEnumerableUpgradeable} from "../governance/TimelockControllerEnumerableUpgradeable.sol";

contract TimelockControllerEnumerableUpgradeableWithInit is TimelockControllerEnumerableUpgradeable {
    constructor() payable initializer {
        __TimelockControllerEnumerable_init();
    }
}
import {AccountZKEmailMockUpgradeable, IDKIMRegistry, IGroth16Verifier} from "./account/AccountZKEmailMockUpgradeable.sol";

contract AccountZKEmailMockUpgradeableWithInit is AccountZKEmailMockUpgradeable {
    constructor(
        bytes32 accountSalt_,
        IDKIMRegistry registry_,
        IGroth16Verifier groth16Verifier_
    ) payable initializer {
        __AccountZKEmailMock_init(accountSalt_, registry_, groth16Verifier_);
    }
}
import {ERC7579ExecutorMockUpgradeable} from "./account/modules/ERC7579ExecutorMocksUpgradeable.sol";

contract ERC7579ExecutorMockUpgradeableWithInit is ERC7579ExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579ExecutorMock_init();
    }
}
import {ERC7579DelayedExecutorMockUpgradeable} from "./account/modules/ERC7579ExecutorMocksUpgradeable.sol";

contract ERC7579DelayedExecutorMockUpgradeableWithInit is ERC7579DelayedExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579DelayedExecutorMock_init();
    }
}
import {ERC7579FallbackHandlerMockUpgradeable} from "./account/modules/ERC7579FallbackHandlerMockUpgradeable.sol";

contract ERC7579FallbackHandlerMockUpgradeableWithInit is ERC7579FallbackHandlerMockUpgradeable {
    constructor() payable initializer {
        __ERC7579FallbackHandlerMock_init();
    }
}
import {ERC7579HookMockUpgradeable} from "./account/modules/ERC7579HookMockUpgradeable.sol";

contract ERC7579HookMockUpgradeableWithInit is ERC7579HookMockUpgradeable {
    constructor() payable initializer {
        __ERC7579HookMock_init();
    }
}
import {ERC7579ModuleMockUpgradeable} from "./account/modules/ERC7579ModuleMockUpgradeable.sol";

contract ERC7579ModuleMockUpgradeableWithInit is ERC7579ModuleMockUpgradeable {
    constructor(uint256 moduleTypeId) payable initializer {
        __ERC7579ModuleMock_init(moduleTypeId);
    }
}
import {ERC7579MultisigExecutorMockUpgradeable} from "./account/modules/ERC7579MultisigMocksUpgradeable.sol";

contract ERC7579MultisigExecutorMockUpgradeableWithInit is ERC7579MultisigExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigExecutorMock_init();
    }
}
import {ERC7579MultisigWeightedExecutorMockUpgradeable} from "./account/modules/ERC7579MultisigMocksUpgradeable.sol";

contract ERC7579MultisigWeightedExecutorMockUpgradeableWithInit is ERC7579MultisigWeightedExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigWeightedExecutorMock_init();
    }
}
import {ERC7579MultisigConfirmationExecutorMockUpgradeable} from "./account/modules/ERC7579MultisigMocksUpgradeable.sol";

contract ERC7579MultisigConfirmationExecutorMockUpgradeableWithInit is ERC7579MultisigConfirmationExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigConfirmationExecutorMock_init();
    }
}
import {ERC7579MultisigStorageExecutorMockUpgradeable} from "./account/modules/ERC7579MultisigMocksUpgradeable.sol";

contract ERC7579MultisigStorageExecutorMockUpgradeableWithInit is ERC7579MultisigStorageExecutorMockUpgradeable {
    constructor() payable initializer {
        __ERC7579MultisigStorageExecutorMock_init();
    }
}
import {AxelarGatewayMockUpgradeable} from "./crosschain/axelar/AxelarGatewayMockUpgradeable.sol";

contract AxelarGatewayMockUpgradeableWithInit is AxelarGatewayMockUpgradeable {
    constructor() payable initializer {
        __AxelarGatewayMock_init();
    }
}
import {ERC7786GatewayMockUpgradeable} from "./crosschain/ERC7786GatewayMockUpgradeable.sol";

contract ERC7786GatewayMockUpgradeableWithInit is ERC7786GatewayMockUpgradeable {
    constructor() payable initializer {
        __ERC7786GatewayMock_init();
    }
}
import {ERC7786RecipientInvalidMockUpgradeable} from "./crosschain/ERC7786RecipientInvalidMockUpgradeable.sol";

contract ERC7786RecipientInvalidMockUpgradeableWithInit is ERC7786RecipientInvalidMockUpgradeable {
    constructor() payable initializer {
        __ERC7786RecipientInvalidMock_init();
    }
}
import {ERC7786RecipientMockUpgradeable} from "./crosschain/ERC7786RecipientMockUpgradeable.sol";

contract ERC7786RecipientMockUpgradeableWithInit is ERC7786RecipientMockUpgradeable {
    constructor(address gateway_) payable initializer {
        __ERC7786RecipientMock_init(gateway_);
    }
}
import {ERC7786RecipientReturnBombMockUpgradeable} from "./crosschain/ERC7786RecipientReturnBombMockUpgradeable.sol";

contract ERC7786RecipientReturnBombMockUpgradeableWithInit is ERC7786RecipientReturnBombMockUpgradeable {
    constructor() payable initializer {
        __ERC7786RecipientReturnBombMock_init();
    }
}
import {ERC7786RecipientRevertMockUpgradeable} from "./crosschain/ERC7786RecipientRevertMockUpgradeable.sol";

contract ERC7786RecipientRevertMockUpgradeableWithInit is ERC7786RecipientRevertMockUpgradeable {
    constructor() payable initializer {
        __ERC7786RecipientRevertMock_init();
    }
}
import {WormholeRelayerMockUpgradeable} from "./crosschain/wormhole/WormholeRelayerMockUpgradeable.sol";

contract WormholeRelayerMockUpgradeableWithInit is WormholeRelayerMockUpgradeable {
    constructor(uint16 localChainId) payable initializer {
        __WormholeRelayerMock_init(localChainId);
    }
}
import {MyERC7579SocialRecoveryUpgradeable} from "./docs/account/modules/MyERC7579SocialRecoveryUpgradeable.sol";

contract MyERC7579SocialRecoveryUpgradeableWithInit is MyERC7579SocialRecoveryUpgradeable {
    constructor() payable initializer {
        __MyERC7579SocialRecovery_init();
    }
}
import {MyERC7786GatewaySourceUpgradeable} from "./docs/crosschain/MyERC7786GatewaySourceUpgradeable.sol";

contract MyERC7786GatewaySourceUpgradeableWithInit is MyERC7786GatewaySourceUpgradeable {
    constructor() payable initializer {
        __MyERC7786GatewaySource_init();
    }
}
import {MyStablecoinAllowlistUpgradeable} from "./docs/MyStablecoinAllowlistUpgradeable.sol";

contract MyStablecoinAllowlistUpgradeableWithInit is MyStablecoinAllowlistUpgradeable {
    constructor(address initialAuthority) payable initializer {
        __MyStablecoinAllowlist_init(initialAuthority);
    }
}
import {ERC7739ECDSAUpgradeable} from "./docs/utils/cryptography/ERC7739SignerECDSAUpgradeable.sol";

contract ERC7739ECDSAUpgradeableWithInit is ERC7739ECDSAUpgradeable {
    constructor(address signerAddr) payable initializer {
        __ERC7739ECDSA_init(signerAddr);
    }
}
import {MyContractDomainUpgradeable} from "./docs/utils/cryptography/MyContractDomainUpgradeable.sol";

contract MyContractDomainUpgradeableWithInit is MyContractDomainUpgradeable {
    constructor() payable initializer {
        __MyContractDomain_init();
    }
}
import {ERC7913VerifierMockUpgradeable} from "./ERC7913VerifierMockUpgradeable.sol";

contract ERC7913VerifierMockUpgradeableWithInit is ERC7913VerifierMockUpgradeable {
    constructor() payable initializer {
        __ERC7913VerifierMock_init();
    }
}
import {ERC20CollateralMockUpgradeable} from "./token/ERC20CollateralMockUpgradeable.sol";

contract ERC20CollateralMockUpgradeableWithInit is ERC20CollateralMockUpgradeable {
    constructor(
        uint48 liveness_,
        string memory name_,
        string memory symbol_
    ) payable initializer {
        __ERC20CollateralMock_init(liveness_, name_, symbol_);
    }
}
import {ERC20CustodianMockUpgradeable} from "./token/ERC20CustodianMockUpgradeable.sol";

contract ERC20CustodianMockUpgradeableWithInit is ERC20CustodianMockUpgradeable {
    constructor(address custodian, string memory name_, string memory symbol_) payable initializer {
        __ERC20CustodianMock_init(custodian, name_, symbol_);
    }
}
import {ERC20uRWAMockUpgradeable} from "./token/ERC20uRWAMockUpgradeable.sol";

contract ERC20uRWAMockUpgradeableWithInit is ERC20uRWAMockUpgradeable {
    constructor(address freezer, address enforcer) payable initializer {
        __ERC20uRWAMock_init(freezer, enforcer);
    }
}
import {ERC7540AdminMockUpgradeable} from "./token/ERC7540AdminMockUpgradeable.sol";

contract ERC7540AdminMockUpgradeableWithInit is ERC7540AdminMockUpgradeable {
    constructor(address tmpShareHolder) payable initializer {
        __ERC7540AdminMock_init(tmpShareHolder);
    }
}
import {ERC7540DelayMockUpgradeable} from "./token/ERC7540DelayMockUpgradeable.sol";

contract ERC7540DelayMockUpgradeableWithInit is ERC7540DelayMockUpgradeable {
    constructor() payable initializer {
        __ERC7540DelayMock_init();
    }
}
import {ERC7540DelayShareOriginMockUpgradeable} from "./token/ERC7540DelayMockUpgradeable.sol";

contract ERC7540DelayShareOriginMockUpgradeableWithInit is ERC7540DelayShareOriginMockUpgradeable {
    constructor() payable initializer {
        __ERC7540DelayShareOriginMock_init();
    }
}
import {ERC7540DelayShareDestinationMockUpgradeable} from "./token/ERC7540DelayMockUpgradeable.sol";

contract ERC7540DelayShareDestinationMockUpgradeableWithInit is ERC7540DelayShareDestinationMockUpgradeable {
    constructor() payable initializer {
        __ERC7540DelayShareDestinationMock_init();
    }
}
import {ERC7540EpochMockUpgradeable} from "./token/ERC7540EpochMockUpgradeable.sol";

contract ERC7540EpochMockUpgradeableWithInit is ERC7540EpochMockUpgradeable {
    constructor(address tmpShareHolder) payable initializer {
        __ERC7540EpochMock_init(tmpShareHolder);
    }
}
import {ERC7540SyncDepositMockUpgradeable} from "./token/ERC7540SyncDepositMockUpgradeable.sol";

contract ERC7540SyncDepositMockUpgradeableWithInit is ERC7540SyncDepositMockUpgradeable {
    constructor() payable initializer {
        __ERC7540SyncDepositMock_init();
    }
}
import {ERC7540SyncMockUpgradeable} from "./token/ERC7540SyncMockUpgradeable.sol";

contract ERC7540SyncMockUpgradeableWithInit is ERC7540SyncMockUpgradeable {
    constructor() payable initializer {
        __ERC7540SyncMock_init();
    }
}
import {ERC7540SyncRedeemMockUpgradeable} from "./token/ERC7540SyncRedeemMockUpgradeable.sol";

contract ERC7540SyncRedeemMockUpgradeableWithInit is ERC7540SyncRedeemMockUpgradeable {
    constructor() payable initializer {
        __ERC7540SyncRedeemMock_init();
    }
}
import {ZKEmailGroth16VerifierMockUpgradeable} from "./utils/cryptography/ZKEmailGroth16VerifierMockUpgradeable.sol";

contract ZKEmailGroth16VerifierMockUpgradeableWithInit is ZKEmailGroth16VerifierMockUpgradeable {
    constructor() payable initializer {
        __ZKEmailGroth16VerifierMock_init();
    }
}
import {ERC20AllowlistUpgradeable} from "../token/ERC20/extensions/ERC20AllowlistUpgradeable.sol";

contract ERC20AllowlistUpgradeableWithInit is ERC20AllowlistUpgradeable {
    constructor() payable initializer {
        __ERC20Allowlist_init();
    }
}
import {ERC20BlocklistUpgradeable} from "../token/ERC20/extensions/ERC20BlocklistUpgradeable.sol";

contract ERC20BlocklistUpgradeableWithInit is ERC20BlocklistUpgradeable {
    constructor() payable initializer {
        __ERC20Blocklist_init();
    }
}
import {ERC20FreezableUpgradeable} from "../token/ERC20/extensions/ERC20FreezableUpgradeable.sol";

contract ERC20FreezableUpgradeableWithInit is ERC20FreezableUpgradeable {
    constructor() payable initializer {
        __ERC20Freezable_init();
    }
}
import {ERC20RestrictedUpgradeable} from "../token/ERC20/extensions/ERC20RestrictedUpgradeable.sol";

contract ERC20RestrictedUpgradeableWithInit is ERC20RestrictedUpgradeable {
    constructor() payable initializer {
        __ERC20Restricted_init();
    }
}
import {ERC4626FeesUpgradeable} from "../token/ERC20/extensions/ERC4626FeesUpgradeable.sol";

contract ERC4626FeesUpgradeableWithInit is ERC4626FeesUpgradeable {
    constructor() payable initializer {
        __ERC4626Fees_init();
    }
}
import {DKIMRegistryUpgradeable} from "../utils/cryptography/DKIMRegistryUpgradeable.sol";

contract DKIMRegistryUpgradeableWithInit is DKIMRegistryUpgradeable {
    constructor() payable initializer {
        __DKIMRegistry_init();
    }
}
import {SignerAccessManagedUpgradeable} from "../utils/cryptography/signers/SignerAccessManagedUpgradeable.sol";

contract SignerAccessManagedUpgradeableWithInit is SignerAccessManagedUpgradeable {
    constructor(address accessManager_, uint64 roleId_) payable initializer {
        __SignerAccessManaged_init(accessManager_, roleId_);
    }
}
import {SignerZKEmailUpgradeable} from "../utils/cryptography/signers/SignerZKEmailUpgradeable.sol";

contract SignerZKEmailUpgradeableWithInit is SignerZKEmailUpgradeable {
    constructor() payable initializer {
        __SignerZKEmail_init();
    }
}
import {ERC7913ZKEmailVerifierUpgradeable} from "../utils/cryptography/verifiers/ERC7913ZKEmailVerifierUpgradeable.sol";

contract ERC7913ZKEmailVerifierUpgradeableWithInit is ERC7913ZKEmailVerifierUpgradeable {
    constructor() payable initializer {
        __ERC7913ZKEmailVerifier_init();
    }
}
