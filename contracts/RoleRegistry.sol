// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IRoleRegistry.sol";

/**
 * @title RoleRegistry
 * @notice Stores the role of every account and enforces who can manage members.
 * @dev DRAFT. Function signatures and access rules are final for this milestone.
 *      Bodies marked TODO will be completed in the implementation phase.
 *      Built on OpenZeppelin AccessControl so role checks are audited and standard.
 */
contract RoleRegistry is AccessControl, IRoleRegistry {
    // Role identifiers (hashes are the standard OpenZeppelin pattern)
    bytes32 public constant REGULATOR_ROLE = keccak256("REGULATOR_ROLE");
    bytes32 public constant PRODUCER_ROLE  = keccak256("PRODUCER_ROLE");
    bytes32 public constant BUYER_ROLE     = keccak256("BUYER_ROLE");
    bytes32 public constant CHECKER_ROLE   = keccak256("CHECKER_ROLE");

    // Producer details by address
    mapping(address => Producer) private _producers;

    // Buyer display names by address
    mapping(address => string) private _buyerNames;

    // Current Data Checker account (only one at a time)
    address public dataChecker;

    /**
     * @param regulator The first regulator account. It also becomes the admin
     *        that can grant REGULATOR_ROLE to more regulators later.
     */
    constructor(address regulator) {
        require(regulator != address(0), "Regulator address required");
        _grantRole(DEFAULT_ADMIN_ROLE, regulator);
        _grantRole(REGULATOR_ROLE, regulator);
    }

    // ------------------------------------------------------------------
    // Membership management (REGULATOR only)
    // ------------------------------------------------------------------

    /// @inheritdoc IRoleRegistry
    function registerProducer(
        address producer,
        string calldata name,
        string calldata meterId,
        string calldata location,
        uint256 capacityKW
    ) external override onlyRole(REGULATOR_ROLE) {
        require(producer != address(0), "Invalid address");
        require(_producers[producer].status == ProducerStatus.None, "Already registered");
        require(capacityKW > 0, "Capacity must be positive");

        // TODO: store Producer struct with status Active and registeredAt = block.timestamp
        // TODO: grant PRODUCER_ROLE
        // TODO: emit ProducerRegistered
        name; meterId; location; // silence unused warnings in draft
    }

    /// @inheritdoc IRoleRegistry
    function registerBuyer(address buyer, string calldata name)
        external override onlyRole(REGULATOR_ROLE)
    {
        require(buyer!=address(0), "Invalid address");
        require(!hasRole(BUYER_ROLE, buyer), "Already a buyer");

        // TODO: save buyer name, grant BUYER_ROLE, emit BuyerRegistered
        name;
    }

    /// @inheritdoc IRoleRegistry
    function suspendProducer(address producer, string calldata reason)
        external override onlyRole(REGULATOR_ROLE)
    {
        require(_producers[producer].status == ProducerStatus.Active, "Producer not active");

        // TODO: set status to Suspended (role is kept so history stays linked)
        // TODO: emit ProducerSuspended(producer, reason)
        reason;
    }

    /// @inheritdoc IRoleRegistry
    function reinstateProducer(address producer) external override onlyRole(REGULATOR_ROLE) {
        require(_producers[producer].status == ProducerStatus.Suspended, "Producer not suspended");

        // TODO: set status back to Active, emit ProducerReinstated
    }

    /// @inheritdoc IRoleRegistry
    function setDataChecker(address checker) external override onlyRole(REGULATOR_ROLE) {
        require(checker != address(0), "Invalid address");

        // TODO: revoke CHECKER_ROLE from the old dataChecker (if any)
        // TODO: grant CHECKER_ROLE to the new checker and update dataChecker
        // TODO: emit DataCheckerUpdated(old, checker)
    }

    // ------------------------------------------------------------------
    // Read-only helpers
    // ------------------------------------------------------------------

    function isRegulator(address account) external view override returns (bool) {
        return hasRole(REGULATOR_ROLE, account);
    }

    /// @notice True only if the account is a producer AND not suspended.
    function isActiveProducer(address account) external view override returns (bool) {
        return hasRole(PRODUCER_ROLE, account)
            && _producers[account].status == ProducerStatus.Active;
    }

    function isBuyer(address account) external view override returns (bool) {
        return hasRole(BUYER_ROLE, account);
    }

    function isDataChecker(address account) external view override returns (bool) {
        return hasRole(CHECKER_ROLE, account);
    }

    function getProducer(address producer) external view override returns (Producer memory) {
        return _producers[producer];
    }

    // Future extension (noted in proposal): require 2 of 3 regulators to approve
    // membership changes, so no single regulator has full control.
}
