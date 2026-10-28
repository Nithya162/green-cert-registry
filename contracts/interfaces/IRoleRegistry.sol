// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRoleRegistry
 * @notice Interface for the contract that decides WHO is allowed to do WHAT.
 *
 * Roles in the system:
 *   - REGULATOR : the energy authority. Adds, suspends and reinstates members,
 *                 and reviews readings flagged by the Data Checker.
 *   - PRODUCER  : a registered solar or wind farm. Can submit generation readings
 *                 for its own farm only.
 *   - BUYER     : a company that buys and retires (uses) certificates.
 *   - CHECKER   : the off-chain Data Checker service (oracle). The only account
 *                 that can approve readings so certificates get issued.
 *
 * Joining the system: a farm or company applies off chain, the regulator verifies
 * its documents (licence, meter ID), and then calls registerProducer or registerBuyer.
 * Nobody can give themselves a role.
 */
interface IRoleRegistry {
    // ------------------------------------------------------------------
    // Data types
    // ------------------------------------------------------------------

    /// @notice Lifecycle status of a registered producer.
    enum ProducerStatus {
        None,       // never registered
        Active,     // allowed to submit readings
        Suspended   // blocked from submitting new readings (old records stay on chain)
    }

    /// @notice Details stored for each registered producer.
    struct Producer {
        string name;          // farm name, e.g. "Sunny Solar Farm"
        string meterId;       // ID of the verified generation meter
        string location;      // site location, used by the Data Checker for sunlight checks
        uint256 capacityKW;   // installed capacity, used to catch impossible readings
        ProducerStatus status;
        uint256 registeredAt; // block timestamp of registration
    }

    // ------------------------------------------------------------------
    // Events (form the public audit trail of membership changes)
    // ------------------------------------------------------------------

    event ProducerRegistered(address indexed producer, string name, string meterId, uint256 capacityKW);
    event BuyerRegistered(address indexed buyer, string name);
    event ProducerSuspended(address indexed producer, string reason);
    event ProducerReinstated(address indexed producer);
    event DataCheckerUpdated(address indexed oldChecker, address indexed newChecker);

    // ------------------------------------------------------------------
    // Membership management (REGULATOR only)
    // ------------------------------------------------------------------

    /// @notice Registers a verified farm as a producer.
    /// @dev Only REGULATOR. Reverts if the address is already registered.
    function registerProducer(
        address producer,
        string calldata name,
        string calldata meterId,
        string calldata location,
        uint256 capacityKW
    ) external;

    /// @notice Registers a verified company as a buyer.
    /// @dev Only REGULATOR.
    function registerBuyer(address buyer, string calldata name) external;

    /// @notice Blocks a producer from submitting new readings, e.g. after fake data.
    /// @dev Only REGULATOR. Existing certificates are NOT deleted.
    function suspendProducer(address producer, string calldata reason) external;

    /// @notice Lets a suspended producer submit readings again.
    /// @dev Only REGULATOR.
    function reinstateProducer(address producer) external;

    /// @notice Sets the account of the off-chain Data Checker (oracle).
    /// @dev Only REGULATOR. Removes the CHECKER role from the old account.
    function setDataChecker(address checker) external;

    // ------------------------------------------------------------------
    // Read-only helpers (used by CertificateRegistry and the web interface)
    // ------------------------------------------------------------------

    function isRegulator(address account) external view returns (bool);
    function isActiveProducer(address account) external view returns (bool);
    function isBuyer(address account) external view returns (bool);
    function isDataChecker(address account) external view returns (bool);
    function getProducer(address producer) external view returns (Producer memory);
}
