pragma solidity ^0.8.16;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721Delegate.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateProjectDeployer.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateDeployer.sol';
import '@jbx-protocol/juice-721-delegate/contracts/JBTiered721DelegateStore.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol';

import './utils/TestBaseWorkflow.sol';

import '../UnumOptIn.sol';

contract TestUnumOptinE2E is TestBaseWorkflow {
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  uint256 projectIdCDAO2;
  uint256 projectIdUnum;

  IERC721 CDAO2NFT;
  IERC721 UNUMNFT;

  address reserveBeneficiary = makeAddr('reserveBeneficiary');
  string name = 'NFT';
  string symbol = 'SYM';
  string baseUri = 'https://ipfs.io/ipfs/';
  string contractUri = 'https://ipfs.io/ipfs/123';

  //QmWmyoMoctfbAaiEs2G46gpeUmhqFRDW6KWo64y5r581Vz
  bytes32 tokenUri = bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89);
  JBTiered721DelegateProjectDeployer deployer;

  function setUp() public override {
    super.setUp();

    JBTiered721Delegate noGovernance = new JBTiered721Delegate();
    JB721GlobalGovernance globalGovernance = new JB721GlobalGovernance();
    JB721TieredGovernance tieredGovernance = new JB721TieredGovernance();

    JBTiered721DelegateDeployer delegateDeployer = new JBTiered721DelegateDeployer(
      globalGovernance,
      tieredGovernance,
      noGovernance
    );

    deployer = new JBTiered721DelegateProjectDeployer(
      IJBController(_jbController),
      delegateDeployer,
      IJBOperatorStore(_jbOperatorStore)
    );

    (
      JBDeployTiered721DelegateData memory NFTRewardDeployerData,
      JBLaunchProjectData memory launchProjectData
    ) = createData();

    projectIdUnum = deployer.launchProjectFor(
      _projectOwner,
      NFTRewardDeployerData,
      launchProjectData
    );

    projectIdCDAO2 = deployer.launchProjectFor(
      _projectOwner,
      NFTRewardDeployerData,
      launchProjectData
    );

    // 5 first tier floors
    uint256 _amountNeeded = 50 + 40 + 30 + 20 + 10;
    uint16[] memory rawMetadata = new uint16[](5);

    // Mint one per tier for the first 5 tiers
    for (uint256 i = 0; i < 5; i++) {
      rawMetadata[i] = uint16(i + 1); // Not the tier 0
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

    vm.prank(_caller);
    _jbETHPaymentTerminal.pay{value: _amountNeeded}(
      projectIdCDAO2,
      _amountNeeded,
      address(0),
      _beneficiary,
      /* _minReturnedTokens */
      0,
      /* _preferClaimedTokens */
      false,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      metadata
    );

    CDAO2NFT = IERC721(_jbFundingCycleStore.currentOf(projectIdCDAO2).dataSource());
    UNUMNFT = IERC721(_jbFundingCycleStore.currentOf(projectIdUnum).dataSource());
  }

  function testOptinOneNFT() external {
    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _jbController);

    uint256 _tokenId = _generateTokenId(1, 1);

    vm.prank(_beneficiary);
    CDAO2NFT.approve(address(_optIn), _tokenId);

    vm.prank(_beneficiary);
    _optIn.optIn(_tokenId);

    // Check: first token of cdao2 is burned
    vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
    CDAO2NFT.ownerOf(_tokenId);

    // Check: _beneficiary own the first token of unum corresponding tier
    assertEq(UNUMNFT.ownerOf(_tokenId), _beneficiary);
  }


  // ----- internal helpers ------
  // Create launchProjectFor(..) payload
  function createData()
    internal
    returns (
      JBDeployTiered721DelegateData memory NFTRewardDeployerData,
      JBLaunchProjectData memory launchProjectData
    )
  {
    JB721TierParams[] memory tierParams = new JB721TierParams[](10);

    for (uint256 i; i < 10; i++) {
      tierParams[i] = JB721TierParams({
        contributionFloor: uint80((i + 1) * 10),
        lockedUntil: uint48(0),
        initialQuantity: uint40(10),
        votingUnits: uint16((i + 1) * 10),
        reservedRate: 0,
        reservedTokenBeneficiary: reserveBeneficiary,
        encodedIPFSUri: tokenUri,
        allowManualMint: false,
        shouldUseBeneficiaryAsDefault: false,
        transfersPausable: false
      });
    }

    NFTRewardDeployerData = JBDeployTiered721DelegateData({
      directory: _jbDirectory,
      name: name,
      symbol: symbol,
      fundingCycleStore: _jbFundingCycleStore,
      baseUri: baseUri,
      tokenUriResolver: IJBTokenUriResolver(address(0)),
      contractUri: contractUri,
      owner: _projectOwner,
      pricing: JB721PricingParams({
        tiers: tierParams,
        currency: 1,
        decimals: 18,
        prices: IJBPrices(address(0))
      }),
      reservedTokenBeneficiary: reserveBeneficiary,
      store: new JBTiered721DelegateStore(),
      flags: JBTiered721Flags({
        lockReservedTokenChanges: false,
        lockVotingUnitChanges: false,
        lockManualMintingChanges: true
      }),
      governanceType: JB721GovernanceType.NONE
    });

    launchProjectData = JBLaunchProjectData({
      projectMetadata: _projectMetadata,
      data: _data,
      metadata: _metadata,
      mustStartAtOrAfter: 0,
      groupedSplits: _groupedSplits,
      fundAccessConstraints: _fundAccessConstraints,
      terminals: _terminals,
      memo: ''
    });
  }

  // Generate tokenId's based on token number and tier
  function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
    return (_tierId * 1_000_000_000) + _tokenNumber;
  }
}
