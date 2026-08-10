// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.7.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// prettier-ignore
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
// prettier-ignore
import {ERC20FlashMintUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";
import {ERC1363Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC1363Upgradeable.sol";
// prettier-ignore
import {ERC3009Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC3009Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

/// @dev Settings flag enabling a variable (vault-like) exchange rate between the underlying asset and the wrapper.
uint8 constant _VARIABLE_RATE_FLAG = 0x01;

/// @dev Settings flag enabling {IERC3156FlashLender} flash loans of the wrapper token.
uint8 constant _FLASH_MINT_FLAG = 0x02;

/**
 * @dev Wrapper for any {IERC20} token, deployable as a minimal clone by {ERC20UniversalWrapperFactory}.
 *
 * This contract is meant to be used as the implementation behind {Clones}' "clone with immutable args" proxies. It
 * has no constructor and no initializer: the underlying asset and the feature switches are not stored in storage,
 * but appended to the clone's bytecode and read back on demand by {_parseArgs}. Consequently, a given (asset,
 * settings) pair maps to a single deterministic wrapper address, and deploying a wrapper costs no storage writes.
 *
 * The wrapper exposes {IERC20Permit}, {IERC1363}, {IERC3009} and {IERC4626} on top of the wrapped asset. Two
 * behaviors are configurable per clone, through the settings byte:
 *
 * * {_VARIABLE_RATE_FLAG}: when unset, the wrapper behaves like a 1:1 wrapper (as {ERC20Wrapper} would). When set,
 *   the wrapper behaves like a normal {ERC4626} vault, whose exchange rate follows the assets it holds.
 * * {_FLASH_MINT_FLAG}: when set, the wrapper token can be flash-minted. This is only available for 1:1 wrappers,
 *   as flash minting shares would otherwise interfere with the vault's exchange rate.
 *
 * The name and symbol are derived from the underlying asset's metadata, and are therefore not stored either.
 *
 * NOTE: The underlying asset's metadata is read on every call to {name}, {symbol} and {decimals}. Wrapping an asset
 * whose {IERC20Metadata} functions revert (or are not implemented) will make {name} and {symbol} revert too.
 * {decimals} degrades gracefully to 18.
 */
contract ERC20UniversalWrapper is
    ERC20PermitUpgradeable,
    ERC20FlashMintUpgradeable,
    ERC1363Upgradeable,
    ERC3009Upgradeable,
    ERC4626Upgradeable
{
    /// @dev The clone's immutable args are missing or too short to hold the underlying asset and the settings byte.
    error MissingImmutableArgs();

    // No constructor + no initializer
    // ---
    // All storage variables usually set in the constructor are instead set via immutable args, which are read from
    // the clone's bytecode.

    // ===============================================================================================================
    // =                                          Overall wrapper behavior                                           =
    // ===============================================================================================================

    /// @dev Address of the underlying token being wrapped, read from the clone's immutable args.
    function asset() public view override returns (address _asset) {
        (_asset, ) = _parseArgs();
    }

    /// @dev Name of the wrapper: the underlying asset's name, prefixed with `"Wrapped "`.
    function name() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(asset()).name());
    }

    /// @dev Symbol of the wrapper: the underlying asset's symbol, prefixed with `"w"`.
    function symbol() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return string.concat("w", IERC20Metadata(asset()).symbol());
    }

    /// @dev Decimals of the wrapper, mirroring the underlying asset's decimals, or 18 if the asset doesn't expose any.
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        (bool success, uint8 _decimals) = SafeERC20.tryGetDecimals(IERC20Metadata(asset()));
        return (success ? _decimals : 18) + _decimalsOffset();
    }

    /// @dev EIP-712 domain name, matching {name} so that each clone gets its own domain separator.
    function _EIP712Name() internal view override returns (string memory) {
        return name();
    }

    /// @dev EIP-712 domain version.
    function _EIP712Version() internal pure override returns (string memory) {
        return "1";
    }

    // ===============================================================================================================
    // =                                              Feature switches                                               =
    // ===============================================================================================================

    /**
     * @dev See {ERC20FlashMint-maxFlashLoan}. Returns 0 unless this clone was deployed with the
     * {_FLASH_MINT_FLAG} setting, effectively disabling flash loans.
     */
    function maxFlashLoan(address token) public view override returns (uint256) {
        (, uint8 settings) = _parseArgs();
        return settings & _FLASH_MINT_FLAG == 0 ? 0 : super.maxFlashLoan(token);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction. Unless this
     * clone was deployed with the {_VARIABLE_RATE_FLAG} setting, the rate is fixed to 1:1.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        (, uint8 settings) = _parseArgs();
        return settings & _VARIABLE_RATE_FLAG == 0 ? assets : super._convertToShares(assets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction. Unless this
     * clone was deployed with the {_VARIABLE_RATE_FLAG} setting, the rate is fixed to 1:1.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        (, uint8 settings) = _parseArgs();
        return settings & _VARIABLE_RATE_FLAG == 0 ? shares : super._convertToAssets(shares, rounding);
    }

    /**
     * @dev Reads the clone's immutable args, and decodes them into the underlying asset's address and the settings
     * byte. Reverts with {MissingImmutableArgs} if the args are not exactly the expected 21 bytes, which notably
     * happens when calling the implementation contract directly instead of one of its clones.
     */
    function _parseArgs() private view returns (address underlying, uint8 settings) {
        bytes memory cloneArgs = Clones.fetchCloneArgs(address(this));
        require(cloneArgs.length == 21, MissingImmutableArgs());
        bytes21 data = bytes21(cloneArgs);
        return (address(bytes20(data)), uint8(bytes1(data << 160)));
    }
}

/**
 * @dev Factory for {ERC20UniversalWrapper} clones.
 *
 * Deploying this factory also deploys the single {ERC20UniversalWrapper} implementation that all wrappers delegate
 * to. Wrappers are then deployed as "clones with immutable args", using a zero salt, which makes the resulting
 * address a pure function of the implementation, the underlying asset and the settings. Deployment is therefore
 * permissionless and idempotent: anyone can deploy the wrapper for a given configuration, but only once. Use
 * {predict} to compute that address ahead of (or without) deployment.
 */
contract ERC20UniversalWrapperFactory {
    /// @dev A variable rate wrapper was requested alongside flash minting, which are mutually exclusive.
    error IncompatibleSettings();

    /// @dev Address of the {ERC20UniversalWrapper} implementation that every wrapper deployed here delegates to.
    address public immutable implementation = address(new ERC20UniversalWrapper());

    /// @dev A wrapper for `underlying`, with the given `settings`, was deployed at `wrapper`.
    event ERC20UniversalWrapperDeployed(address indexed wrapper, address indexed underlying, uint8 settings);

    /**
     * @dev Deploys the {ERC20UniversalWrapper} for the given `underlying` token and settings, and returns its
     * address.
     *
     * Setting `variableRate` makes the wrapper behave like a normal {ERC4626} vault instead of a 1:1 wrapper.
     * Setting `flashMintable` enables flash minting of the wrapper token. These two options are mutually exclusive.
     *
     * NOTE: This reverts if the corresponding wrapper was already deployed. Since the address only depends on the
     * arguments, that existing wrapper (retrievable using {predict}) is exactly the one this call would produce.
     */
    function deploy(address underlying, bool variableRate, bool flashMintable) external returns (address) {
        // prepare settings
        uint8 settings = _makeSettings(variableRate, flashMintable);

        // deploy wrapper
        address instance = Clones.cloneDeterministicWithImmutableArgs(
            implementation,
            abi.encodePacked(underlying, settings),
            bytes32(0)
        );

        emit ERC20UniversalWrapperDeployed(instance, underlying, settings);
        return instance;
    }

    /**
     * @dev Returns the address at which the {ERC20UniversalWrapper} for the given `underlying` token and settings
     * is (or would be) deployed. See {deploy} for the meaning of `variableRate` and `flashMintable`.
     */
    function predict(address underlying, bool variableRate, bool flashMintable) external view returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                implementation,
                abi.encodePacked(underlying, _makeSettings(variableRate, flashMintable)),
                bytes32(0)
            );
    }

    /**
     * @dev Packs the feature switches into the settings byte stored in the clone's immutable args. Reverts with
     * {IncompatibleSettings} if the requested combination is invalid: a variable rate wrapper cannot be flash
     * mintable, as flash minting shares would interfere with the vault's exchange rate.
     */
    function _makeSettings(bool variableRate, bool flashMintable) private pure returns (uint8 settings) {
        require(!variableRate || !flashMintable, IncompatibleSettings());
        return (variableRate ? _VARIABLE_RATE_FLAG : 0) | (flashMintable ? _FLASH_MINT_FLAG : 0);
    }
}
