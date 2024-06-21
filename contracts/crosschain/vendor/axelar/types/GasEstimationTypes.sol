// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title GasEstimationType
 * @notice This enum represents the gas estimation types for different chains.
 */
enum GasEstimationType {
    Default,
    OptimismEcotone,
    OptimismBedrock,
    Arbitrum,
    Scroll
}

/**
 * @title GasInfo
 * @notice This struct represents the gas pricing information for a specific chain.
 * @dev Smaller uint types are used for efficient struct packing to save storage costs.
 */
struct GasInfo {
    /// @dev Custom gas pricing rule, such as L1 data fee on L2s
    uint64 gasEstimationType;
    /// @dev Scalar value needed for specific gas estimation types, expected to be less than 1e10
    uint64 l1FeeScalar;
    /// @dev Axelar base fee for cross-chain message approval on destination, in terms of source native gas token
    uint128 axelarBaseFee;
    /// @dev Gas price of destination chain, in terms of the source chain token, i.e dest_gas_price * dest_token_market_price / src_token_market_price
    uint128 relativeGasPrice;
    /// @dev Needed for specific gas estimation types. Blob base fee of destination chain, in terms of the source chain token, i.e dest_blob_base_fee * dest_token_market_price / src_token_market_price
    uint128 relativeBlobBaseFee;
    /// @dev Axelar express fee for express execution, in terms of source chain token
    uint128 expressFee;
}
