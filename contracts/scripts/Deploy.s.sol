pragma solidity ^0.8.17;

import { IJBController } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import { UnumOptIn } from "../UnumOptIn.sol";
import 'forge-std/Script.sol';

contract DeployMainnet is Script {
    IJBController _controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);

    // Set me:
    uint256 _projectIdToOptIn = 0;
    uint256 _projectIdToLeave = 0;

    function run() external {
        UnumOptIn _optin = new UnumOptIn(_projectIdToOptIn, _projectIdToLeave, _controller);
        console.log(address(_optin));
    }
}

contract DeployGoerli is Script {
    IJBController _controller = IJBController(0x7Cb86D43B665196BC719b6974D320bf674AFb395);

    // Set me:
    uint256 _projectIdToOptIn = 281;
    uint256 _projectIdToLeave = 283;

    function run() external {
        vm.startBroadcast();
        UnumOptIn _optin = new UnumOptIn(_projectIdToOptIn, _projectIdToLeave, _controller);
        console.log(address(_optin));
    }
}