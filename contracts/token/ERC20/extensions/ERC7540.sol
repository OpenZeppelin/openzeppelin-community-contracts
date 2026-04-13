// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20, IERC20Metadata, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {Memory} from "@openzeppelin/contracts/utils/Memory.sol";

import {IERC7540, IERC7540Operator, IERC7540Deposit, IERC7540Redeem} from "../../../interfaces/IERC7540.sol";

abstract contract ERC7540 is ERC165, ERC20, IERC4626, IERC7540 {
    using Math for uint256;

    IERC20 private immutable _asset;
    uint8 private immutable _underlyingDecimals;

    mapping(address owner => mapping(address controller => bool)) private _isOperator;
    uint256 private _totalPendingDepositAssets;
    uint256 private _totalPendingRedeemShares;

    /**
     * @dev Attempted to deposit more assets than the max amount for `receiver`.
     */
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    /**
     * @dev Attempted to mint more shares than the max amount for `receiver`.
     */
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);

    /**
     * @dev Attempted to withdraw more assets than the max amount for `owner`.
     */
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /**
     * @dev Attempted to redeem more shares than the max amount for `owner`.
     */
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    /// @dev The operator is not the caller or an operator of the controller
    error ERC7540InvalidOperator(address controller, address operator);

    error ERC7540DepositIsSync();
    error ERC7540DepositIsAsync();
    error ERC7540RedeemIsSync();
    error ERC7540RedeemIsAsync();
    error NotImplemented();

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC-20 or ERC-777).
     */
    constructor(IERC20 asset_) {
        require(_isDepositAsync() || _isRedeemAsync(), "ERC7540: async deposit or redeem required");
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(asset_);
        _underlyingDecimals = success ? assetDecimals : 18;
        _asset = asset_;
    }

    function _isDepositAsync() internal pure virtual returns (bool) {
        return false;
    }
    function _isRedeemAsync() internal pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _tryGetAssetDecimals(IERC20 asset_) private view returns (bool ok, uint8 assetDecimals) {
        Memory.Pointer ptr = Memory.getFreeMemoryPointer();
        (bool success, bytes32 returnedDecimals, ) = LowLevelCall.staticcallReturn64Bytes(
            address(asset_),
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        Memory.unsafeSetFreeMemoryPointer(ptr);

        return
            (success && LowLevelCall.returnDataSize() >= 32 && uint256(returnedDecimals) <= type(uint8).max)
                ? (true, uint8(uint256(returnedDecimals)))
                : (false, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC7540Operator).interfaceId ||
            (interfaceId == type(IERC7540Deposit).interfaceId && _isDepositAsync()) ||
            (interfaceId == type(IERC7540Redeem).interfaceId && _isRedeemAsync()) ||
            super.supportsInterface(interfaceId);
    }

    /// @dev See {_checkOperatorOrController}.
    modifier onlyOperatorOrController(bool async, address controller, address operator) {
        _checkOperatorOrController(async, controller, operator);
        _;
    }

    /// @inheritdoc IERC7540Operator
    function isOperator(address controller, address operator) public view returns (bool status) {
        return _isOperator[controller][operator];
    }

    /// @inheritdoc IERC7540Operator
    function setOperator(address operator, bool approved) public returns (bool) {
        _setOperator(_msgSender(), operator, approved);
        return true;
    }

    /**
     * @dev Set the `operator` status for the `controller` to the `approved` value
     *
     * Emits an {OperatorSet} event if the approval status changes.
     */
    function _setOperator(address controller, address operator, bool approved) internal {
        _isOperator[controller][operator] = approved;
        emit OperatorSet(controller, operator, approved);
    }

    /// @dev Reverts if the `operator` is not the caller or an operator of the `controller`
    function _checkOperatorOrController(bool async, address controller, address operator) internal view virtual {
        require(
            !async || controller == operator || isOperator(controller, operator),
            ERC7540InvalidOperator(controller, operator)
        );
    }

    /**
     * @dev Decimals are computed by adding the decimal offset on top of the underlying asset's decimals. This
     * "original" value is cached during construction of the vault contract. If this read operation fails (e.g., the
     * asset has not been created yet), a default of 18 is used to represent the underlying asset's decimals.
     *
     * See {IERC20Metadata-decimals}.
     */
    function decimals() public view virtual override(IERC20Metadata, ERC20) returns (uint8) {
        return _underlyingDecimals + _decimalsOffset();
    }

    /// @inheritdoc IERC4626
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - totalPendingDepositAssets();
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return super.totalSupply() + totalPendingRedeemShares();
    }

    /// @inheritdoc IERC7540Deposit
    function pendingDepositRequest(uint256 requestId, address controller) public view returns (uint256) {
        require(_isDepositAsync(), "ERC7540: deposit must be async");
        return _pendingDepositRequest(requestId, controller);
    }

    /// @inheritdoc IERC7540Deposit
    function claimableDepositRequest(uint256 requestId, address controller) public view returns (uint256) {
        require(_isDepositAsync(), "ERC7540: deposit must be async");
        return _claimableDepositRequest(requestId, controller);
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256 requestId, address controller) public view returns (uint256) {
        require(_isRedeemAsync(), "ERC7540: redeem must be async");
        return _pendingRedeemRequest(requestId, controller);
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256 requestId, address controller) public view returns (uint256) {
        require(_isRedeemAsync(), "ERC7540: redeem must be async");
        return _claimableRedeemRequest(requestId, controller);
    }

    function totalPendingDepositAssets() public view virtual returns (uint256) {
        return _totalPendingDepositAssets;
    }

    function totalPendingRedeemShares() public view virtual returns (uint256) {
        return _totalPendingRedeemShares;
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address owner) public view virtual returns (uint256) {
        return _isDepositAsync() ? _asyncMaxDeposit(owner) : type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function maxMint(address owner) public view virtual returns (uint256) {
        return _isDepositAsync() ? _asyncMaxMint(owner) : type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _isRedeemAsync() ? _asyncMaxWithdraw(owner) : previewRedeem(maxRedeem(owner));
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return _isRedeemAsync() ? _asyncMaxRedeem(owner) : balanceOf(owner);
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        require(!_isDepositAsync(), ERC7540DepositIsAsync());
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        require(!_isDepositAsync(), ERC7540DepositIsAsync());
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        require(!_isRedeemAsync(), ERC7540RedeemIsAsync());
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        require(!_isRedeemAsync(), ERC7540RedeemIsAsync());
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public virtual onlyOperatorOrController(_isDepositAsync(), owner, _msgSender()) returns (uint256) {
        require(_isDepositAsync(), ERC7540DepositIsSync());

        uint256 requestId = _requestDeposit(assets, controller, owner);

        // Must revert with ERC20InsufficientBalance or equivalent error if there's not enough balance.
        _transferIn(owner, assets);

        emit DepositRequest(controller, owner, requestId, _msgSender(), assets);
        return requestId;
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        return deposit(assets, receiver, _msgSender());
    }

    /// @inheritdoc IERC7540Deposit
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual onlyOperatorOrController(_isDepositAsync(), controller, _msgSender()) returns (uint256) {
        // Note: if _isDepositAsync is false, controller is ignored.
        uint256 maxAssets = maxDeposit(_isDepositAsync() ? controller : receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(_isDepositAsync() ? controller : receiver, assets, maxAssets);
        }

        uint256 shares = _isDepositAsync() ? _computeAsyncDeposit(assets, controller) : previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function _computeAsyncDeposit(uint256 assets, address controller) internal virtual returns (uint256) {
        return Math.mulDiv(assets, maxMint(controller), maxDeposit(controller), Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        return mint(shares, receiver, _msgSender());
    }

    /// @inheritdoc IERC7540Deposit
    function mint(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual onlyOperatorOrController(_isDepositAsync(), controller, _msgSender()) returns (uint256) {
        // Note: if _isDepositAsync is false, controller is ignored.
        uint256 maxShares = maxMint(_isDepositAsync() ? _msgSender() : receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(_isDepositAsync() ? _msgSender() : receiver, shares, maxShares);
        }

        uint256 assets = _isDepositAsync() ? _computeAsyncMint(shares, controller) : previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function _computeAsyncMint(uint256 shares, address controller) internal virtual returns (uint256) {
        return Math.mulDiv(shares, maxDeposit(controller), maxMint(controller), Math.Rounding.Ceil);
    }

    function requestRedeem(uint256 shares, address controller, address owner) public virtual returns (uint256) {
        require(_isRedeemAsync(), ERC7540RedeemIsSync());

        address sender = _msgSender();
        if (owner != sender && !isOperator(owner, sender)) {
            _spendAllowance(owner, sender, shares);
        }
        _burn(owner, shares);

        uint256 requestId = _requestRedeem(shares, controller, owner);

        emit RedeemRequest(controller, owner, requestId, _msgSender(), shares);
        return requestId;
    }

    /// @inheritdoc IERC4626
    function withdraw(
        uint256 assets,
        address receiver,
        address ownerOrController
    ) public virtual onlyOperatorOrController(_isRedeemAsync(), ownerOrController, _msgSender()) returns (uint256) {
        uint256 maxAssets = maxWithdraw(ownerOrController);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(ownerOrController, assets, maxAssets);
        }

        uint256 shares = _isRedeemAsync() ? _computeAsyncWithdraw(assets, ownerOrController) : previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, ownerOrController, assets, shares);
        return shares;
    }

    function _computeAsyncWithdraw(uint256 assets, address controller) internal virtual returns (uint256) {
        return Math.mulDiv(assets, maxRedeem(controller), maxWithdraw(controller), Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address ownerOrController
    ) public virtual onlyOperatorOrController(_isRedeemAsync(), ownerOrController, _msgSender()) returns (uint256) {
        uint256 maxShares = maxRedeem(ownerOrController);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(ownerOrController, shares, maxShares);
        }

        uint256 assets = _isRedeemAsync() ? _computeAsyncRedeem(shares, ownerOrController) : previewRedeem(shares);
        _withdraw(_msgSender(), receiver, ownerOrController, assets, shares);
        return assets;
    }

    function _computeAsyncRedeem(uint256 shares, address controller) internal virtual returns (uint256) {
        return Math.mulDiv(shares, maxWithdraw(controller), maxRedeem(controller), Math.Rounding.Floor);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _requestDeposit(
        uint256 assets,
        address /*controller*/,
        address /*owner*/
    ) internal virtual returns (uint256) {
        _totalPendingDepositAssets += assets;
        return 0;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        if (!_isDepositAsync()) {
            // slither-disable-next-line reentrancy-no-eth
            _transferIn(caller, assets);
        } else {
            _totalPendingDepositAssets -= assets;
        }
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _requestRedeem(
        uint256 shares,
        address /*controller*/,
        address /*owner*/
    ) internal virtual returns (uint256) {
        _totalPendingRedeemShares += shares;
        return 0;
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (!_isRedeemAsync() && caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If asset() is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        if (!_isRedeemAsync()) {
            _burn(owner, shares);
        } else {
            _totalPendingRedeemShares -= shares;
        }
        _transferOut(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Performs a transfer in of underlying assets. The default implementation uses `SafeERC20`. Used by {_deposit}.
    function _transferIn(address from, uint256 assets) internal virtual {
        SafeERC20.safeTransferFrom(IERC20(asset()), from, address(this), assets);
    }

    /// @dev Performs a transfer out of underlying assets. The default implementation uses `SafeERC20`. Used by {_withdraw}.
    function _transferOut(address to, uint256 assets) internal virtual {
        SafeERC20.safeTransfer(IERC20(asset()), to, assets);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    function _pendingDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _claimableDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _pendingRedeemRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _claimableRedeemRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _asyncMaxDeposit(address /*owner*/) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _asyncMaxMint(address /*owner*/) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _asyncMaxWithdraw(address /*owner*/) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
    function _asyncMaxRedeem(address /*owner*/) internal view virtual returns (uint256) {
        revert NotImplemented();
    }
}
