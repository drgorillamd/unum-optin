pragma solidity ^0.8.16;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721Delegate.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateProjectDeployer.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateDeployer.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateStore.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol';

import './utils/TestBaseWorkflow.sol';

import '../UnumOptIn.sol';

contract TestForkGoerli is Test {
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  // Fork goerli - need a .env or an env var GOERLI_RPC
  uint256 forkId = vm.createSelectFork(vm.envString('GOERLI_RPC'));

  address _caller = makeAddr('caller');
  address _beneficiary = makeAddr('beneficiary');

  IJBSingleTokenPaymentTerminal _terminal = IJBSingleTokenPaymentTerminal(0x55d4dfb578daA4d60380995ffF7a706471d7c719);

  IJBController _controller;
  IJBFundingCycleStore _fundingCycleStore;
  IJBSingleTokenPaymentTerminalStore _terminalStore;

  IJBTiered721DelegateStore _tiered721DelegateStore;

  IERC721 CDAO2NFT;
  IERC721 UNUMNFT;

  uint256 projectIdCDAO2 = 281;
  uint256 projectIdUnum = 283;
  
  uint256[] _tokenIds;

  function setUp() public {
    _controller = IJBController(JBPayoutRedemptionPaymentTerminal(address(_terminal)).directory().controllerOf(projectIdCDAO2));
    _terminalStore = JBPayoutRedemptionPaymentTerminal(address(_terminal)).store();
    _fundingCycleStore = _terminalStore.fundingCycleStore();
    
    _tiered721DelegateStore = IJBTiered721Delegate(_fundingCycleStore.currentOf(projectIdCDAO2).dataSource()).store();

    CDAO2NFT = IERC721(_fundingCycleStore.currentOf(projectIdCDAO2).dataSource());
    UNUMNFT = IERC721(_fundingCycleStore.currentOf(projectIdUnum).dataSource());

    // tiers: 0.1 - 1 - 10 - 100
    uint16[] memory rawMetadata = new uint16[](4);

    // Store the tiers we are going to mint
    JB721Tier[] memory tiers = _tiered721DelegateStore.tiers(address(CDAO2NFT), 0, 10);

    // Mint one per tier for the first 5 tiers
    for (uint256 i = 0; i < 4; i++) {
      rawMetadata[i] = uint16(i + 1); // Not the tier 0

      _tokenIds.push(_generateTokenId(i + 1, tiers[i].initialQuantity - tiers[i].remainingQuantity + 1));
    }

    // Encode it to metadata
    bytes memory metadata = abi.encode(
      bytes32(0),
      bytes32(0),
      type(IJB721Delegate).interfaceId,
      false,
      false,
      false,
      rawMetadata
    );

    vm.deal(_caller, 111.1 ether);
    vm.prank(_caller);
    _terminal.pay{value: 111.1 ether}({
      _projectId: projectIdCDAO2,
      _amount: 111.1 ether,
      _token: address(0),
      _beneficiary: _beneficiary,
      _minReturnedTokens: 0,
      _preferClaimedTokens: false,
      _memo: '...',
      _metadata: metadata
    });
  }

  /**
  * @notice Try opt-in'ing to unumDao, using multiple cdao2 NFT
  *         This should redeem and get eth from CDAO2 which are then used to mint one or many unum NFT
  */       
  function test_Optin_OptWithMultipleNFT() external {
    uint256 _treasuryCdao2Before = _terminalStore.balanceOf(_terminal, projectIdCDAO2);
    uint256 _treasuryUnumBefore = _terminalStore.balanceOf(_terminal, projectIdUnum);

    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _controller);

    for(uint i; i < 4; i++) {
      // Approve the optIn contract for each token to optin
      vm.prank(_beneficiary);
      CDAO2NFT.approve(address(_optIn), _tokenIds[i]);
    }

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_tokenIds);

    // Check: all the CDAO2 token are burned
    for(uint i; i < 4; i++) {
      vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
      CDAO2NFT.ownerOf(_tokenIds[i]);
    }

    // Check: _beneficiary own the first token of unum corresponding tier
    for(uint i; i < 4; i++) {
      assertEq(UNUMNFT.ownerOf(_tokenIds[i]), _beneficiary);
    }

    // Check: the redeemed part of the treasury is transfered from one project to the other
    uint256 _treasuryCdao2After = _terminalStore.balanceOf(_terminal, projectIdCDAO2);
    uint256 _treasuryUnumAfter = _terminalStore.balanceOf(_terminal, projectIdUnum);

    assertEq(_treasuryCdao2After, _treasuryCdao2Before - _treasuryUnumAfter);
    assertEq(_treasuryUnumAfter, _treasuryUnumBefore + (_treasuryCdao2Before - _treasuryCdao2After));
  }


  // ----- internal helpers ------

  // Generate tokenId's based on token number and tier
  function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
    return (_tierId * 1_000_000_000) + _tokenNumber;
  }
}
