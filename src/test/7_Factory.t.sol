/** 
    Created by Arcadia Finance
    https://www.arcadia.finance

    SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >0.8.10;

import "../../lib/forge-std/src/Test.sol";

import "../Factory.sol";
import "../Proxy.sol";
import "../Vault.sol";

import "../AssetRegistry/MainRegistry.sol";
import "../mockups/ERC20SolmateMock.sol";
import "../InterestRateModule.sol";
import "../Liquidator.sol";

import "../utils/Constants.sol";

interface IVaultExtra {
    function life() external view returns (uint256);

    function owner() external view returns (address);
}

contract factoryTest is Test {
    using stdStorage for StdStorage;

    Factory internal factoryContr;
    Vault internal vaultContr;
    InterestRateModule internal interestContr;
    Liquidator internal liquidatorContr;
    MainRegistry internal registryContr;
    MainRegistry internal registryContr2;
    ERC20Mock internal erc20Contr;
    address internal unprivilegedAddress1 = address(5);

    uint256[] emptyList = new uint256[](0);

    event VaultCreated(
        address indexed vaultAddress,
        address indexed owner,
        uint256 length
    );

    //this is a before
    constructor() {
        factoryContr = new Factory();
        vaultContr = new Vault();
        erc20Contr = new ERC20Mock("ERC20 Mock", "mERC20", 18);
        interestContr = new InterestRateModule();
        liquidatorContr = new Liquidator(
            address(factoryContr),
            0x0000000000000000000000000000000000000000
        );
        registryContr = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: address(erc20Contr),
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );

        factoryContr.setNewVaultInfo(
            address(registryContr),
            address(vaultContr),
            0x0000000000000000000000000000000000000000,
            address(interestContr),
            Constants.upgradeProof1To2
        );
        factoryContr.confirmNewVaultInfo();
        factoryContr.setLiquidator(address(liquidatorContr));

        registryContr.setFactory(address(factoryContr));
    }

    //this is a before each
    function setUp() public {}

    function getBytecode(address vaultLogic)
        public
        pure
        returns (bytes memory)
    {
        bytes memory bytecode = type(Proxy).creationCode;

        return abi.encodePacked(bytecode, abi.encode(vaultLogic));
    }

    function getAddress(bytes memory bytecode, uint256 _salt)
        public
        view
        returns (address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(bytecode)
            )
        );

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function testVaultIdStartFromZero() public {
        assertEq(factoryContr.allVaultsLength(), 0);
    }

    function testDeployVaultContractMappings(uint256 salt) public {
        uint256 amountBefore = factoryContr.allVaultsLength();

        address actualDeployed = factoryContr.createVault(
            salt,
            Constants.UsdNumeraire,
            0
        );
        assertEq(amountBefore + 1, factoryContr.allVaultsLength());
        assertEq(
            actualDeployed,
            factoryContr.allVaults(factoryContr.allVaultsLength() - 1)
        );
        assertEq(
            factoryContr.vaultIndex(actualDeployed),
            (factoryContr.allVaultsLength() - 1)
        );
    }

    function testDeployNewProxyWithLogic(uint256 salt) public {
        uint256 amountBefore = factoryContr.allVaultsLength();

        address actualDeployed = factoryContr.createVault(
            salt,
            Constants.UsdNumeraire,
            0
        );
        assertEq(amountBefore + 1, factoryContr.allVaultsLength());
        assertEq(IVaultExtra(actualDeployed).life(), 0);

        assertEq(IVaultExtra(actualDeployed).owner(), address(this));
    }

    function testDeployNewProxyWithLogicOwner(uint256 salt, address sender)
        public
    {
        uint256 amountBefore = factoryContr.allVaultsLength();
        vm.prank(sender);
        vm.assume(sender != address(0));
        address actualDeployed = factoryContr.createVault(
            salt,
            Constants.UsdNumeraire,
            0
        );
        assertEq(amountBefore + 1, factoryContr.allVaultsLength());
        assertEq(IVaultExtra(actualDeployed).life(), 0);

        assertEq(IVaultExtra(actualDeployed).owner(), address(sender));

        emit log_address(address(1));
    }

    function testSafeTransferVault(address sender) public {
        address receiver = unprivilegedAddress1;
        vm.assume(sender != address(0));

        vm.startPrank(sender);
        address vault = factoryContr.createVault(0, Constants.UsdNumeraire, 0);

        //Make sure index in erc721 == vaultIndex
        assertEq(IVault(vault).owner(), factoryContr.ownerOf(0));

        //Make sure vault itself is owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);

        //Transfer vault to another address
        factoryContr.safeTransferFrom(
            sender,
            receiver,
            factoryContr.vaultIndex(vault)
        );

        //Make sure vault itself is owned by receiver
        assertEq(IVault(vault).owner(), receiver);

        //Make sure erc721 is owned by receiver
        assertEq(
            factoryContr.ownerOf(factoryContr.vaultIndex(vault)),
            receiver
        );
        vm.stopPrank();
    }

    function testFailSafeTransferVaultByNonOwner(address sender) public {
        address receiver = unprivilegedAddress1;
        address vaultOwner = address(1);
        vm.assume(sender != address(0) && sender != vaultOwner);

        vm.startPrank(vaultOwner);
        address vault = factoryContr.createVault(0, Constants.UsdNumeraire, 0);
        vm.stopPrank();

        //Make sure index in erc721 == vaultIndex
        assertEq(IVault(vault).owner(), factoryContr.ownerOf(0));

        //Make sure vault itself is owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);

        //Transfer vault to another address
        vm.startPrank(sender);
        factoryContr.safeTransferFrom(
            vaultOwner,
            receiver,
            factoryContr.vaultIndex(vault)
        );
        vm.stopPrank();
    }

    function testTransferVault(address sender) public {
        address receiver = unprivilegedAddress1;
        vm.assume(sender != address(0));

        vm.startPrank(sender);
        address vault = factoryContr.createVault(0, Constants.UsdNumeraire, 0);

        //Make sure index in erc721 == vaultIndex
        assertEq(IVault(vault).owner(), factoryContr.ownerOf(0));

        //Make sure vault itself is owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);

        //Transfer vault to another address
        factoryContr.transferFrom(
            sender,
            receiver,
            factoryContr.vaultIndex(vault)
        );

        //Make sure vault itself is owned by receiver
        assertEq(IVault(vault).owner(), receiver);

        //Make sure erc721 is owned by receiver
        assertEq(
            factoryContr.ownerOf(factoryContr.vaultIndex(vault)),
            receiver
        );
        vm.stopPrank();
    }

    function testFailTransferVaultByNonOwner(address sender) public {
        address receiver = unprivilegedAddress1;
        address vaultOwner = address(1);
        vm.assume(sender != address(0) && sender != vaultOwner);

        vm.startPrank(vaultOwner);
        address vault = factoryContr.createVault(0, Constants.UsdNumeraire, 0);
        vm.stopPrank();

        //Make sure index in erc721 == vaultIndex
        assertEq(IVault(vault).owner(), factoryContr.ownerOf(0));

        //Make sure vault itself is owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);

        //Transfer vault to another address
        vm.startPrank(sender);
        factoryContr.transferFrom(
            vaultOwner,
            receiver,
            factoryContr.vaultIndex(vault)
        );
        vm.stopPrank();
    }

    function testTransferOwnership(address to) public {
        vm.assume(to != address(0));
        Factory factoryContr_m = new Factory();

        assertEq(address(this), factoryContr_m.owner());

        factoryContr_m.transferOwnership(to);
        assertEq(to, factoryContr_m.owner());
    }

    function testTransferOwnershipByNonOwner(address from) public {
        Factory factoryContr_m = new Factory();
        vm.assume(from != address(this) && from != address(factoryContr_m));

        address to = address(12345);

        assertEq(address(this), factoryContr_m.owner());

        vm.startPrank(from);
        vm.expectRevert("Ownable: caller is not the owner");
        factoryContr_m.transferOwnership(to);
        assertEq(address(this), factoryContr_m.owner());
    }

    //TODO: Odd test behavior
    function testFailTransferVaultNotOwner(address sender, address receiver)
        public
    {
        vm.assume(sender != address(0));
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(1));

        vm.prank(sender);
        address vault = factoryContr.createVault(0, Constants.UsdNumeraire, 0);

        //Make sure index in erc721 == vaultIndex
        assertEq(IVault(vault).owner(), factoryContr.ownerOf(0));

        //Make sure vault itself is owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);

        //Transfer vault to another address by not owner
        vm.startPrank(receiver);
        vm.expectRevert("NOT_AUHTORIZED");
        factoryContr.safeTransferFrom(
            sender,
            receiver,
            factoryContr.vaultIndex(vault)
        );
        vm.stopPrank();
        //Make sure vault itself is still owned by sender
        assertEq(IVault(vault).owner(), sender);

        //Make sure erc721 is still owned by sender
        assertEq(factoryContr.ownerOf(factoryContr.vaultIndex(vault)), sender);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    //Test addNumeraire
    function testNonRegistryAddsNumeraire(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(registryContr));
        vm.assume(unprivilegedAddress != address(this));
        vm.assume(unprivilegedAddress != address(factoryContr));
        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("FTRY_AN: Add Numeraires via MR");
        factoryContr.addNumeraire(2, address(erc20Contr));
        vm.stopPrank();
    }

    function testOldRegistryAddsNumeraire(address newNumeraire) public {
        registryContr2 = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: address(erc20Contr),
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );
        factoryContr.setNewVaultInfo(
            address(registryContr2),
            address(vaultContr),
            0x0000000000000000000000000000000000000000,
            address(interestContr),
            Constants.upgradeProof1To2
        );
        factoryContr.confirmNewVaultInfo();
        registryContr2.setFactory(address(factoryContr));

        vm.expectRevert("FTRY_AN: Add Numeraires via MR");
        registryContr.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newNumeraire,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );
    }

    function testLatestRegistryAddsNumeraire(address newStable) public {
        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(address(0), factoryContr.numeraireToStable(1));
        registryContr.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newStable,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );

        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(newStable, factoryContr.numeraireToStable(1));
    }

    //Test setNewVaultInfo
    function testNonOwnerSetsNewVaultInfo(address unprivilegedAddress) public {
        vm.assume(unprivilegedAddress != address(this));
        vm.assume(unprivilegedAddress != address(factoryContr));
        vm.assume(unprivilegedAddress != address(0));
        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        factoryContr.setNewVaultInfo(
            address(registryContr),
            address(vaultContr),
            0x0000000000000000000000000000000000000000,
            address(interestContr),
            Constants.upgradeProof1To2
        );
        vm.stopPrank();
    }

    function testOwnerSetsVaultInfoForFirstTime(
        address registry,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        factoryContr = new Factory();
        assertTrue(factoryContr.getVaultVersionRoot() == bytes32(0));
        assertTrue(!factoryContr.newVaultInfoSet());

        factoryContr.setNewVaultInfo(
            registry,
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.getVaultVersionRoot() == bytes32(0));
        assertTrue(factoryContr.newVaultInfoSet());
    }

    function testOwnerSetsNewVaultInfoWithIdenticalMainRegistry(
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        assertTrue(!factoryContr.newVaultInfoSet());
        factoryContr.setNewVaultInfo(
            address(registryContr),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.newVaultInfoSet());
    }

    function testOwnerSetsNewVaultInfoSecondTimeWithIdenticalMainRegistry(
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        assertTrue(!factoryContr.newVaultInfoSet());
        factoryContr.setNewVaultInfo(
            address(registryContr),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.newVaultInfoSet());
        factoryContr.setNewVaultInfo(
            address(registryContr),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.newVaultInfoSet());
    }

    function testOwnerSetsNewVaultInfoWithDifferentStableContractInMainRegistry(
        address randomStable,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        vm.assume(randomStable != address(erc20Contr));
        registryContr2 = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: randomStable,
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );
        vm.expectRevert("FTRY_SNVI:No match numeraires MR");
        factoryContr.setNewVaultInfo(
            address(registryContr2),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        vm.stopPrank();
    }

    function testOwnerSetsNewVaultWithInfoMissingNumeraireInMainRegistry(
        address newStable,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        vm.assume(newStable != address(0));

        registryContr.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newStable,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );
        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(newStable, factoryContr.numeraireToStable(1));

        registryContr2 = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: address(erc20Contr),
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );
        vm.expectRevert("FTRY_SNVI:No match numeraires MR");
        factoryContr.setNewVaultInfo(
            address(registryContr2),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
    }

    function testOwnerSetsNewVaultWithIdenticalNumerairesInMainRegistry(
        address newStable,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        registryContr.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newStable,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );
        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(newStable, factoryContr.numeraireToStable(1));

        registryContr2 = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: address(erc20Contr),
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );
        registryContr2.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newStable,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );
        factoryContr.setNewVaultInfo(
            address(registryContr2),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        factoryContr.confirmNewVaultInfo();
        registryContr2.setFactory(address(factoryContr));

        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(newStable, factoryContr.numeraireToStable(1));
    }

    function testOwnerSetsNewVaultWithMoreNumerairesInMainRegistry(
        address newStable,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(address(0), factoryContr.numeraireToStable(1));

        registryContr2 = new MainRegistry(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: address(erc20Contr),
                numeraireLabel: "USD",
                numeraireUnit: 1
            })
        );
        registryContr2.addNumeraire(
            MainRegistry.NumeraireInformation({
                numeraireToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                numeraireToUsdOracle: 0x0000000000000000000000000000000000000000,
                stableAddress: newStable,
                numeraireLabel: "ETH",
                numeraireUnit: uint64(10**Constants.ethDecimals)
            }),
            emptyList
        );
        factoryContr.setNewVaultInfo(
            address(registryContr2),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        factoryContr.confirmNewVaultInfo();
        registryContr2.setFactory(address(factoryContr));

        assertEq(address(erc20Contr), factoryContr.numeraireToStable(0));
        assertEq(newStable, factoryContr.numeraireToStable(1));
    }

    //Test confirmNewVaultInfo
    function testNonOwnerConfirmsNewVaultInfo(address unprivilegedAddress)
        public
    {
        vm.assume(
            unprivilegedAddress != address(0) &&
                unprivilegedAddress != address(this)
        );
        vm.startPrank(unprivilegedAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        factoryContr.confirmNewVaultInfo();
        vm.stopPrank();
    }

    function testOwnerConfirmsVaultInfoForFirstTime(
        address registry,
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        factoryContr = new Factory();
        assertTrue(factoryContr.getVaultVersionRoot() == bytes32(0));
        assertEq(0, factoryContr.latestVaultVersion());

        factoryContr.setNewVaultInfo(
            registry,
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.newVaultInfoSet());

        factoryContr.confirmNewVaultInfo();
        assertTrue(factoryContr.getVaultVersionRoot() == Constants.upgradeProof1To2);
        assertTrue(!factoryContr.newVaultInfoSet());
        assertEq(1, factoryContr.latestVaultVersion());
    }

    function testOwnerConfirmsNewVaultInfoWithIdenticalMainRegistry(
        address logic,
        address stakeContract,
        address interestModule
    ) public {
        vm.assume(logic != address(0));

        assertTrue(!factoryContr.newVaultInfoSet());
        assertEq(1, factoryContr.latestVaultVersion());

        factoryContr.setNewVaultInfo(
            address(registryContr),
            logic,
            stakeContract,
            interestModule,
            Constants.upgradeProof1To2
        );
        assertTrue(factoryContr.newVaultInfoSet());
        assertEq(1, factoryContr.latestVaultVersion());

        factoryContr.confirmNewVaultInfo();
        assertTrue(!factoryContr.newVaultInfoSet());
        assertEq(2, factoryContr.latestVaultVersion());
    }

    function testOwnerConfirmsVaultInfoWithoutNewVaultInfoSet() public {
        assertTrue(!factoryContr.newVaultInfoSet());
        assertEq(1, factoryContr.latestVaultVersion());

        factoryContr.confirmNewVaultInfo();
        assertTrue(!factoryContr.newVaultInfoSet());
        assertEq(1, factoryContr.latestVaultVersion());
    }

    function testCreateNonExistingVaultVersion(uint256 vaultVersion) public {
        uint256 currentVersion = factoryContr.latestVaultVersion();
        vm.assume(vaultVersion > currentVersion);

        vm.expectRevert("FTRY_CV: Unknown vault version");
        factoryContr.createVault(
            uint256(keccak256(abi.encodePacked(vaultVersion, block.timestamp))),
            0,
            vaultVersion
            );
    }

    function testBlockVaultVersion(uint16 vaultVersion) public {
        uint256 currentVersion = factoryContr.latestVaultVersion();
        vm.assume(vaultVersion <= currentVersion);
        vm.assume(vaultVersion != 0);
        factoryContr.blockVaultVersion(vaultVersion);

        assertTrue(factoryContr.vaultVersionBlocked(vaultVersion));
    }

    function testBlockNonExistingVaultVersion(uint16 vaultVersion) public {
        uint256 currentVersion = factoryContr.latestVaultVersion();
        vm.assume(vaultVersion > currentVersion || vaultVersion == 0);

        vm.expectRevert("FTRY_BVV: Invalid version");
        factoryContr.blockVaultVersion(vaultVersion);
    }

    function testBlockVaultVersionByNonOwner(uint16 vaultVersion, address sender) public {
        uint256 currentVersion = factoryContr.latestVaultVersion();
        vm.assume(vaultVersion <= currentVersion);
        vm.assume(vaultVersion != 0);

        vm.assume(sender != address(this));
        vm.startPrank(sender);
        vm.expectRevert("Ownable: caller is not the owner");
        factoryContr.blockVaultVersion(vaultVersion);
        vm.stopPrank();
    }

    function testCreateVaultFromBlockedVersion(uint16 vaultVersion, uint16 versionsToMake, uint16[] calldata versionsToBlock) public {
        vm.assume(versionsToBlock.length < 10 && versionsToBlock.length > 0);
        vm.assume(uint256(versionsToMake) + 1  < type(uint16).max);
        vm.assume(vaultVersion <= versionsToMake +1);
        for (uint i; i < versionsToMake; ++i) {
            factoryContr.setNewVaultInfo(
                address(registryContr),
                address(vaultContr),
                address(0),
                address(interestContr),
                Constants.upgradeProof1To2
            );
        }

        for (uint y; y < versionsToBlock.length; ++y) {
            if (versionsToBlock[y] == 0 || versionsToBlock[y] > factoryContr.latestVaultVersion()) continue;
            factoryContr.blockVaultVersion(versionsToBlock[y]);
        }

        for (uint z; z < versionsToBlock.length; ++z) {
            if (versionsToBlock[z] == 0 || versionsToBlock[z] > factoryContr.latestVaultVersion()) continue;
            vm.expectRevert("FTRY_CV: This vault version cannot be created");
            factoryContr.createVault(
                uint256(keccak256(abi.encodePacked(versionsToBlock[z], block.timestamp))),
                0,
                versionsToBlock[z]
                );
        }
    }
}
