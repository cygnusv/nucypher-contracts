// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../threshold/ITACoChildApplication.sol";

/**
 * @notice Contract for testing Coordinator contract
 */
contract ChildApplicationForCoordinatorMock is ITACoChildApplication {
    mapping(address => uint96) public authorizedStake;
    mapping(address => address) public operatorFromStakingProvider;
    mapping(address => address) public stakingProviderFromOperator;
    mapping(address => bool) public confirmations;

    function updateOperator(address _stakingProvider, address _operator) external {
        address oldOperator = operatorFromStakingProvider[_stakingProvider];
        stakingProviderFromOperator[oldOperator] = address(0);
        operatorFromStakingProvider[_stakingProvider] = _operator;
        stakingProviderFromOperator[_operator] = _stakingProvider;
    }

    function updateAuthorization(address _stakingProvider, uint96 _amount) external {
        authorizedStake[_stakingProvider] = _amount;
    }

    function confirmOperatorAddress(address _operator) external {
        confirmations[_operator] = true;
    }
}
