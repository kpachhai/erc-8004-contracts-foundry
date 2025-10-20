// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// If your foundry.toml uses: src = "src"
import {ERC1967Proxy} from "src/ERC1967Proxy.sol";
import {IdentityRegistryUpgradeable} from "src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "src/ValidationRegistryUpgradeable.sol";

/**
 * Deploys:
 *  - IdentityRegistryUpgradeable impl + ERC1967Proxy with initialize()
 *  - ReputationRegistryUpgradeable impl + ERC1967Proxy with initialize(identity)
 *  - ValidationRegistryUpgradeable impl + ERC1967Proxy with initialize(identity)
 * All within a single transaction (the constructor).
 */
contract ERC8004BatchDeployer {
    address public identityImpl;
    address public identityProxy;

    address public reputationImpl;
    address public reputationProxy;

    address public validationImpl;
    address public validationProxy;

    event Deployed(
        address identityImpl,
        address identityProxy,
        address reputationImpl,
        address reputationProxy,
        address validationImpl,
        address validationProxy
    );

    constructor() {
        // 1) Identity impl
        IdentityRegistryUpgradeable idImpl = new IdentityRegistryUpgradeable();
        identityImpl = address(idImpl);

        // Identity proxy with initialize()
        bytes memory idInit = abi.encodeWithSelector(IdentityRegistryUpgradeable.initialize.selector);
        ERC1967Proxy idProxy = new ERC1967Proxy(identityImpl, idInit);
        identityProxy = address(idProxy);

        // 2) Reputation impl
        ReputationRegistryUpgradeable repImpl = new ReputationRegistryUpgradeable();
        reputationImpl = address(repImpl);

        // Reputation proxy with initialize(identityProxy)
        bytes memory repInit = abi.encodeWithSelector(
            ReputationRegistryUpgradeable.initialize.selector,
            identityProxy
        );
        ERC1967Proxy repProxy = new ERC1967Proxy(reputationImpl, repInit);
        reputationProxy = address(repProxy);

        // 3) Validation impl
        ValidationRegistryUpgradeable valImpl = new ValidationRegistryUpgradeable();
        validationImpl = address(valImpl);

        // Validation proxy with initialize(identityProxy)
        bytes memory valInit = abi.encodeWithSelector(
            ValidationRegistryUpgradeable.initialize.selector,
            identityProxy
        );
        ERC1967Proxy valProxy = new ERC1967Proxy(validationImpl, valInit);
        validationProxy = address(valProxy);

        emit Deployed(identityImpl, identityProxy, reputationImpl, reputationProxy, validationImpl, validationProxy);
    }
}