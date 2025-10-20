// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// If your foundry.toml uses: src = "src"
import {ERC8004BatchDeployer} from "./ERC8004BatchDeployer.sol";
import {IdentityRegistryUpgradeable} from "src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "src/ValidationRegistryUpgradeable.sol";

/**
 * One-command end-to-end deployment:
 * - Broadcasts ONE tx to deploy ERC8004BatchDeployer, which internally deploys and initializes
 *   all implementations and proxies.
 * - Reads back addresses and verifies versions/identity registries via view calls.
 */
contract DeployImplementations is Script {
    function run() external {
        console2.log(
            "Deploying ERC-8004 Upgradeable Contracts (single tx via batch deployer)"
        );
        console2.log(
            "====================================================================="
        );

        // Single broadcast: deploy batch deployer (one on-chain tx)
        ERC8004BatchDeployer batch;
        vm.startBroadcast();
        batch = new ERC8004BatchDeployer();
        vm.stopBroadcast();

        // Fetch addresses
        address idImpl = batch.identityImpl();
        address idProxy = batch.identityProxy();
        address repImpl = batch.reputationImpl();
        address repProxy = batch.reputationProxy();
        address valImpl = batch.validationImpl();
        address valProxy = batch.validationProxy();

        // Verify via calls
        console2.log("Verifying deployments...");
        console2.log("=========================");

        string memory identityVersion = IdentityRegistryUpgradeable(idProxy)
            .getVersion();
        console2.log("IdentityRegistry version:", identityVersion);

        string memory reputationVersion = ReputationRegistryUpgradeable(
            repProxy
        ).getVersion();
        address reputationIdentityRegistry = ReputationRegistryUpgradeable(
            repProxy
        ).getIdentityRegistry();
        console2.log("ReputationRegistry version:", reputationVersion);
        console2.log(
            "ReputationRegistry identityRegistry:",
            reputationIdentityRegistry
        );

        string memory validationVersion = ValidationRegistryUpgradeable(
            valProxy
        ).getVersion();
        address validationIdentityRegistry = ValidationRegistryUpgradeable(
            valProxy
        ).getIdentityRegistry();
        console2.log("ValidationRegistry version:", validationVersion);
        console2.log(
            "ValidationRegistry identityRegistry:",
            validationIdentityRegistry
        );
        console2.log("");

        // Summary
        console2.log("Deployment Summary");
        console2.log("==================");
        console2.log("IdentityRegistry Proxy:", idProxy);
        console2.log("ReputationRegistry Proxy:", repProxy);
        console2.log("ValidationRegistry Proxy:", valProxy);
        console2.log("");
        console2.log("Implementation Addresses:");
        console2.log("IdentityRegistry Implementation:", idImpl);
        console2.log("ReputationRegistry Implementation:", repImpl);
        console2.log("ValidationRegistry Implementation:", valImpl);
        console2.log("");
        console2.log(
            unicode"✅ All contracts deployed successfully (single tx)!"
        );
    }
}
