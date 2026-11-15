// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IRoleRegistry.sol";

/**
 * @title RoleRegistry
 * @notice Stores the role of every account and enforces who can manage members.
 * @dev Built on OpenZeppelin AccessControl so role checks are audited and standard.
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

        // Save the farm's details and mark it Active
        _producers[producer] = Producer({
            name: name,
            meterId: meterId,
            location: location,
            capacityKW: capacityKW,
            status: ProducerStatus.Active,
            registeredAt: block.timestamp
        });

        // Give the farm the PRODUCER role so it can submit readings
        _grantRole(PRODUCER_ROLE, producer);

        // Record the registration in the public audit trail
        emit ProducerRegistered(producer, name, meterId, capacityKW);
    }

    /// @inheritdoc IRoleRegistry
    function registerBuyer(address buyer, string calldata name)
        external override onlyRole(REGULATOR_ROLE)
    {
        require(buyer!=address(0), "Invalid address");
        require(!hasRole(BUYER_ROLE, buyer), "Already a buyer");

        // Save the company name and give it the BUYER role
        _buyerNames[buyer] = name;
        _grantRole(BUYER_ROLE, buyer);

        emit BuyerRegistered(buyer, name);
    }

    /// @inheritdoc IRoleRegistry
    function suspendProducer(address producer, string calldata reason)
        external override onlyRole(REGULATOR_ROLE)
    {
        require(_producers[producer].status == ProducerStatus.Active, "Producer not active");

        // Block new readings. The role is kept so old certificates stay linked to this farm.
        _producers[producer].status = ProducerStatus.Suspended;

        emit ProducerSuspended(producer, reason);
    }

    /// @inheritdoc IRoleRegistry
    function reinstateProducer(address producer) external override onlyRole(REGULATOR_ROLE) {
        require(_producers[producer].status == ProducerStatus.Suspended, "Producer not suspended");

        // Allow the farm to submit readings again
        _producers[producer].status = ProducerStatus.Active;

        emit ProducerReinstated(producer);
    }

    /// @inheritdoc IRoleRegistry
    function setDataChecker(address checker) external override onlyRole(REGULATOR_ROLE) {
        require(checker != address(0), "Invalid address");

        address oldChecker = dataChecker;

        // Only one Data Checker at a time: remove the role from the old account first
        if (oldChecker != address(0)) {
            _revokeRole(CHECKER_ROLE, oldChecker);
        }

        _grantRole(CHECKER_ROLE, checker);
        dataChecker = checker;

        emit DataCheckerUpdated(oldChecker, checker);
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
