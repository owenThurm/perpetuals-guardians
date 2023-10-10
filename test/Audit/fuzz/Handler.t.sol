//SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployPerpetualGuardian} from "../../../script/DeployPerpetualGuardian.s.sol";

import {PerpetualGuardian} from "../../../src/PerpetualGuardian.sol";
import {MockV3Aggregator} from "../../mock/MockV3Aggregator.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

contract Handler is Test {
    PerpetualGuardian pG;

    constructor(PerpetualGuardian _pG) {
        pG = _pG;
    }
}
