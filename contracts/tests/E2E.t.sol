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

  /**
    @notice Test setup: launch 2 nft project (cdao2 and unum) and mint 5 NFT in cdao2
  */
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

    // 4 first tier floors
    uint256 _amountNeeded = 111.1 ether;
    uint16[] memory rawMetadata = new uint16[](4);

    // Mint one per tier for the first 5 tiers
    for (uint256 i = 0; i < 4; i++) {
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

    vm.deal(_caller, 111.1 ether);
    vm.prank(_caller);
    _jbETHPaymentTerminal.pay{value: _amountNeeded}({
      _projectId: projectIdCDAO2,
      _amount: _amountNeeded,
      _token: address(0),
      _beneficiary: _beneficiary,
      _minReturnedTokens: 0,
      _preferClaimedTokens: false,
      _memo: '...',
      _metadata: metadata
    });

    CDAO2NFT = IERC721(_jbFundingCycleStore.currentOf(projectIdCDAO2).dataSource());
    UNUMNFT = IERC721(_jbFundingCycleStore.currentOf(projectIdUnum).dataSource());
  }

  /**
  * @notice Try opt-in'ing to unumDao, using an cdao2 NFT
  *         This should redeem and get eth from CDAO2 which are then used to mint a unum NFT
  */        
  function test_Optin_OptWithOneNFT() external {
    uint256 _treasuryCdao2Before = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumBefore = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _jbController);

    // The token which is going to be redeemed
    uint256 _tokenId = _generateTokenId(1, 1);

    uint256[] memory _tokenIds = new uint256[](1);
    _tokenIds[0] = _tokenId;

    // The optin contract needs to pull it -> approval needed
    vm.prank(_beneficiary);
    CDAO2NFT.approve(address(_optIn), _tokenId);

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_tokenIds);

    // Check: first token of cdao2 is burned
    vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
    CDAO2NFT.ownerOf(_tokenId);

    // Check: _beneficiary own the first token of unum corresponding tier
    assertEq(UNUMNFT.ownerOf(_tokenId), _beneficiary);

    // Check: 1/5 of the eth is transfered from one project to the other
    uint256 _treasuryCdao2After = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumAfter = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    assertEq(_treasuryCdao2After, _treasuryCdao2Before - _treasuryUnumAfter);
    assertEq(_treasuryUnumAfter, _treasuryUnumBefore + (_treasuryCdao2Before - _treasuryCdao2After));
  }

  /**
  * @notice Try opt-in'ing to unumDao, using multiple cdao2 NFT
  *         This should redeem and get eth from CDAO2 which are then used to mint one or many unum NFT
  */       
  function test_Optin_OptWithMultipleNFT(uint8 _nbOfNft) external {
    vm.assume(_nbOfNft > 0 && _nbOfNft <= 4);

    uint256 _treasuryCdao2Before = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumBefore = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _jbController);

    // Store the tokenIds and approve them
    uint256[] memory _tokenIds = new uint256[](_nbOfNft);
    for(uint i; i < _nbOfNft; i++) {
      _tokenIds[i] = _generateTokenId(i + 1, 1);

      // Approve the optIn contract for each token to optin
      vm.prank(_beneficiary);
      CDAO2NFT.approve(address(_optIn), _tokenIds[i]);
    }

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_tokenIds);

    // Check: all the CDAO2 token are burned
    for(uint i; i < _nbOfNft; i++) {
      vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
      CDAO2NFT.ownerOf(_tokenIds[i]);
    }

    // Check: _beneficiary own the first token of unum corresponding tier
    for(uint i; i < _nbOfNft; i++) {
      assertEq(UNUMNFT.ownerOf(_tokenIds[i]), _beneficiary);
    }

    // Check: the redeemed part of the treasury is transfered from one project to the other
    uint256 _treasuryCdao2After = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumAfter = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    assertEq(_treasuryCdao2After, _treasuryCdao2Before - _treasuryUnumAfter);
    assertEq(_treasuryUnumAfter, _treasuryUnumBefore + (_treasuryCdao2Before - _treasuryCdao2After));
  }

  /**
  * @notice Try opt-in'ing to unumDao, using an cdao2 NFT, when there are extra funds in the cdao2 treasury
  *         This should redeem and get the whole treasury
  */       
  function test_Optin_OptWhenCdao2HasExtraFunds(uint32 _amountAddedWithoutMint) external {
    uint256 _nbOfNft = 4; // redeem all the NFT, to transfer the whole treasury
    vm.assume(_amountAddedWithoutMint > 10);

    // Add fund to cdao2 using addtoBalance
    vm.prank(_beneficiary);
    _jbETHPaymentTerminal.addToBalanceOf{value: _amountAddedWithoutMint}({
      _projectId: projectIdCDAO2,
      _amount: _amountAddedWithoutMint,
      _token: JBTokens.ETH,
      _memo: "take my $",
      _metadata: new bytes(0)
    });

    // the cdao2 treasury
    uint256 _totalTreasuryBalance = _amountAddedWithoutMint;

    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _jbController);

    // Store the tokenIds and approve them
    uint256[] memory _tokenIds = new uint256[](_nbOfNft);
    for(uint i; i < _nbOfNft; i++) {
      _tokenIds[i] = _generateTokenId(i + 1, 1);

      // Approve the optIn contract for each token to optin
      vm.prank(_beneficiary);
      CDAO2NFT.approve(address(_optIn), _tokenIds[i]);

      // Add the amount used to mint to the total treasury (ie 0.1 - 1 - 10 - 100 eth)
      _totalTreasuryBalance += 0.1 ether * 10**i;
    }

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_tokenIds);

    // Check: all the CDAO2 token are burned
    for(uint i; i < _nbOfNft; i++) {
      vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
      CDAO2NFT.ownerOf(_tokenIds[i]);
    }

    // Check: _beneficiary own the first token of unum corresponding tier
    for(uint i; i < _nbOfNft; i++) {
      assertEq(UNUMNFT.ownerOf(_tokenIds[i]), _beneficiary);
    }

    // Check: unumDao received the whole treasury via the redemption/mint
    assertEq(_jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum), _totalTreasuryBalance);
  }

  /**
  * @notice Try opt-in'ing to unumDao, using an cdao2 NFT, when there are mints to unumDao in parallel
  */   
  function test_Optin_OptWithMultipleNFTWhileMinting() external {
    vm.deal(_caller, 1.1 ether);
    uint256 _treasuryCdao2Before = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumBefore = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    UnumOptIn _optIn = new UnumOptIn(projectIdUnum, projectIdCDAO2, _jbController);

    // Mint a first token to unumDao 
    uint16[] memory rawMetadata = new uint16[](1);
    rawMetadata[0] = uint16(1);

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
    _jbETHPaymentTerminal.pay{value: 0.1 ether}({
      _projectId: projectIdUnum,
      _amount: 0.1 ether,
      _token: address(0),
      _beneficiary: _beneficiary,
      _minReturnedTokens: 0,
      _preferClaimedTokens: false,
      _memo: '...',
      _metadata: metadata
    });

    // Start by redeeming from 2 tiers
    uint256[] memory _tokenIds = new uint256[](2);
    _tokenIds[0] = _generateTokenId(1, 1);
    _tokenIds[1] = _generateTokenId(3, 1);

    // Approve the optIn contract for each token to optin
    vm.startPrank(_beneficiary);
    CDAO2NFT.approve(address(_optIn), _tokenIds[0]);
    CDAO2NFT.approve(address(_optIn), _tokenIds[1]);
    vm.stopPrank();

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_tokenIds);

    // Check: all the CDAO2 token are burned
    for(uint i; i < 2; i++) {
      vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
      CDAO2NFT.ownerOf(_tokenIds[i]);
    }

    // Check: _beneficiary own the token of unum corresponding tier
    assertEq(UNUMNFT.ownerOf(_generateTokenId(1, 2)), _beneficiary);
    assertEq(UNUMNFT.ownerOf(_generateTokenId(3, 1)), _beneficiary);

    // Mint a second token to unumDao
    rawMetadata[0] = uint16(2);

    // Encode it to metadata
    metadata = abi.encode(
      bytes32(0),
      bytes32(0),
      type(IJB721Delegate).interfaceId,
      false,
      false,
      false,
      rawMetadata
    );

    vm.prank(_caller);
    _jbETHPaymentTerminal.pay{value: 1 ether}({
      _projectId: projectIdUnum,
      _amount: 1 ether,
      _token: address(0),
      _beneficiary: _beneficiary,
      _minReturnedTokens: 0,
      _preferClaimedTokens: false,
      _memo: '...',
      _metadata: metadata
    });

    // Redeem the 2 tiers left
    uint256[] memory _secondTokenIds = new uint256[](2);
    _secondTokenIds[0] = _generateTokenId(2, 1); // already a token in second tier
    _secondTokenIds[1] = _generateTokenId(4, 1);

    // Approve the optIn contract for each token to optin
    vm.startPrank(_beneficiary);
    CDAO2NFT.approve(address(_optIn), _secondTokenIds[0]);
    CDAO2NFT.approve(address(_optIn), _secondTokenIds[1]);
    vm.stopPrank();

    // Test: trigger the optin
    vm.prank(_beneficiary);
    _optIn.optIn(_secondTokenIds);

    // Check: all the CDAO2 token are burned
    for(uint i; i < 2; i++) {
      vm.expectRevert(abi.encodeWithSelector(ERC721.INVALID_TOKEN_ID.selector));
      CDAO2NFT.ownerOf(_secondTokenIds[i]);
    }

    // Check: _beneficiary own the first token of unum corresponding tier
    assertEq(UNUMNFT.ownerOf(_generateTokenId(2, 2)), _beneficiary); // already a token in second tier
    assertEq(UNUMNFT.ownerOf(_generateTokenId(4, 1)), _beneficiary); // already a token in second tier

    // Check: the redeemed part of the treasury is transfered from one project to the other + the amount coming from the extra mints
    uint256 _treasuryCdao2After = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdCDAO2);
    uint256 _treasuryUnumAfter = _jbPaymentTerminalStore.balanceOf(_jbETHPaymentTerminal, projectIdUnum);

    assertEq(_treasuryCdao2After, _treasuryCdao2Before - (_treasuryUnumAfter - 1.1 ether));
    assertEq(_treasuryUnumAfter, _treasuryUnumBefore + (_treasuryCdao2Before - _treasuryCdao2After) + 1.1 ether);
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
    JB721TierParams[] memory tierParams = new JB721TierParams[](4);

    for (uint256 i; i < 4; i++) {
      tierParams[i] = JB721TierParams({
        contributionFloor: uint80(0.1 ether * 10**i),
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
