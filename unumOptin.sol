pragma solidity ^0.8.17;

import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721";

import { IJBPaymentTerminal } from "@jbx-protocol/juicebox/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBRedemptionTerminal } from "@jbx-protocol/juicebox/contracts/interfaces/IJBRedemptionTerminal.sol";
import { IJBFundingCycleStore } from "@jbx-protocol/juicebox/contracts/interfaces/IJBFundingCycleStore.sol";


contract UnumOptIn {

    uint256 public immutable cdaoProjectId;

    uint256 public immutable unumProjectId;

    IERC721 public immutable CDAO2NFT;

    IERC721 public immutable UNUMNFT;

    IJBRedemptionTerminal public immutable CDAO2RedemptionTerminal;

    IJBPaymentTerminal public immutable UNUMPaymentTerminal;

    constructor(uint256 _unumProjectId, uint256 _cdaoProjectId ) {
        unumProjectId = _unumProjectId;
        cdaoProjectId = _cdaoProjectId;

        // Get the current FC datasource address and primary terminals
    }


    function optIn(uint256[] calldata _tokenIds) external {
        // Loop and redeem every NFT
    }

    function optIn(uint256 _tokenId) public {
        // Pull cdao2 NFT

        // Approve the redemption delegate

        // Redeem

        // Mint unumDao NFT with the ETH received
    }
}