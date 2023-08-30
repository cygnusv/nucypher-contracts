// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../contracts/coordination/ITACoRootToChild.sol";

/**
 * @notice Contract for testing TACo child application contract
 */
contract RootApplicationForTACoChildApplicationMock {
    ITACoRootToChild public childApplication;

    mapping(address => bool) public confirmations;

    function setChildApplication(ITACoRootToChild _childApplication) external {
        childApplication = _childApplication;
    }

    function updateOperator(address _stakingProvider, address _operator) external {
        childApplication.updateOperator(_stakingProvider, _operator);
    }

    function updateAuthorization(address _stakingProvider, uint96 _amount) external {
        childApplication.updateAuthorization(_stakingProvider, _amount);
    }

    function confirmOperatorAddress(address _operator) external {
        confirmations[_operator] = true;
    }

    function resetConfirmation(address _operator) external {
        confirmations[_operator] = false;
    }
}
