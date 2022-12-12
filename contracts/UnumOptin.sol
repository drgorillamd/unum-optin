//SPDX-License-Identifier:  MIT
pragma solidity ^0.8.17;

import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";

import { IJBController } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import { IJBDirectory } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBRedemptionTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionTerminal.sol";
import { IJBFundingCycleStore } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import { JBTokens } from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import { JBFundingCycleMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";

import { IJB721Delegate } from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721Delegate.sol";


contract UnumOptIn {

    uint256 public immutable cdaoProjectId;

    uint256 public immutable unumProjectId;

    IERC721 public immutable CDAO2NFT;

    IERC721 public immutable UNUMNFT;

    IJBRedemptionTerminal public immutable CDAO2RedemptionTerminal;

    IJBPaymentTerminal public immutable UNUMPaymentTerminal;

    constructor(uint256 _unumProjectId, uint256 _cdaoProjectId , IJBController _controller) {
        unumProjectId = _unumProjectId;
        cdaoProjectId = _cdaoProjectId;

        // Get the current FC datasource address and primary terminals
        (, JBFundingCycleMetadata memory _metadataUnum) = _controller.currentFundingCycleOf(_unumProjectId);
        (, JBFundingCycleMetadata memory _metadataCdao) = _controller.currentFundingCycleOf(_cdaoProjectId);

        CDAO2NFT = IERC721(_metadataCdao.dataSource);
        UNUMNFT = IERC721(_metadataUnum.dataSource);


        IJBDirectory _directory = IJBDirectory(_controller.directory());

        UNUMPaymentTerminal = _directory.primaryTerminalOf(_unumProjectId, JBTokens.ETH);
        CDAO2RedemptionTerminal = IJBRedemptionTerminal(address(_directory.primaryTerminalOf(_cdaoProjectId, JBTokens.ETH)));
    }


    function optIn(uint256[] calldata _tokenIds) external {
        // Loop and redeem every NFT
    }

    function optIn(uint256 _tokenId) public {
        // Pull cdao2 NFT
        CDAO2NFT.transferFrom(msg.sender, address(this), _tokenId);
        
        // Approve the redemption delegate
        CDAO2NFT.approve(address(CDAO2RedemptionTerminal), _tokenId);

        // Redeem
        uint256 _reclaimedAmount = CDAO2RedemptionTerminal.redeemTokensOf(
            address(this),
            cdaoProjectId,
            0,
            JBTokens.ETH,
            0,
            payable(address(this)),
            "unumDao opt-in",
            bytes('')
        );
       
        bool _dontMint = false;
        bool _expectMintFromExtraFunds = true;
        bool _dontOverspend = true; 

        bytes memory _mintingMetadata = abi.encode(
            bytes32(0),
            bytes32(0),
            type(IJB721Delegate).interfaceId,
            _dontMint,
            _expectMintFromExtraFunds,
            _dontOverspend,
            new uint8[](0)
        );

        // Mint unumDao NFT with the ETH received
        UNUMPaymentTerminal.pay(
            unumProjectId,
            _reclaimedAmount,
            JBTokens.ETH,
            msg.sender,
            0,
            false,
            "opt-in from CDAO2",
            _mintingMetadata
        );
    }
}