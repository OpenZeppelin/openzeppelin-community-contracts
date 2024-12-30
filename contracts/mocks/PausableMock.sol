// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DefaultPausable} from "../utils/pausability/DefaultPausable.sol";

contract PausableMock is DefaultPausable {
    // solhint-disable-next-line openzeppelin/private-variables
    bool public drasticMeasureTaken;
    // solhint-disable-next-line openzeppelin/private-variables
    uint256 public count;

    constructor() {
        drasticMeasureTaken = false;
        count = 0;
    }

    function normalProcess() external whenNotPaused {
        count++;
    }

    function drasticMeasure() external whenPaused {
        drasticMeasureTaken = true;
    }

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }

    function pauseUntil(uint256 duration) external {
        _pauseUntil(uint48(duration));
    }

    function getPausedUntilDeadline() external view returns (uint256) {
        return _unpauseDeadline();
    }

    function getPausedUntilDeadlineAndTimestamp() external view returns (uint256, uint256) {
        return (_unpauseDeadline(), clock());
    }
}
