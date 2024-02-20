// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./IFeeModel.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FlatRateFeeModel
 * @notice FlatRateFeeModel
 */
contract FlatRateFeeModel is IFeeModel {
    IERC20 public immutable currency;
    uint256 public immutable feeRatePerSecond;

    constructor(IERC20 _currency, uint256 _feeRatePerSecond) {
        require(_feeRatePerSecond > 0, "Invalid fee rate");
        currency = _currency;
        feeRatePerSecond = _feeRatePerSecond;
    }

    function getRitualInitiationCost(
        uint16 size,
        address[] calldata providers,
        uint32 duration
    ) public view returns (uint256) {
        require(size > 0, "Invalid ritual size");
        require(duration > 0, "Invalid ritual duration");
        uint256 buffer = providers.length - size;  // Implicitly requires that providers.length >= size     
        uint256 baseFee = feeRatePerSecond * size * duration;
        uint256 bufferFee = feeRatePerSecond * buffer * 1 days;
        return baseFee + bufferFee;
    }

    // TODO: Validate if this is enough to remove griefing attacks
    function feeDeduction(uint256, uint256) public pure returns (uint256) {
        return 0;
    }
}
