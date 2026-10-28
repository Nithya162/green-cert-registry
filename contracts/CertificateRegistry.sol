// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICertificateRegistry.sol";
import "./interfaces/IRoleRegistry.sol";

/**
 * @title CertificateRegistry
 * @notice Issues, transfers and retires green energy certificates.
 *         Every certificate has a unique ID and a full on-chain history,
 *         so the same certificate can never be claimed twice.
 * @dev DRAFT. Signatures, storage layout and access rules are defined.
 *      Bodies marked TODO will be completed in the implementation phase.
 *      All permission checks are delegated to RoleRegistry.
 */
contract CertificateRegistry is ICertificateRegistry {
    /// @notice Energy covered by one certificate (1 MWh).
    uint256 public constant KWH_PER_CERTIFICATE = 1000;

    /// @notice Contract that tells us each account's role.
    IRoleRegistry public immutable roles;

    // Readings by ID (IDs start at 1)
    mapping(uint256 => Reading) private _readings;
    uint256 private _readingCount;

    // Certificates by ID (IDs start at 1)
    mapping(uint256 => Certificate) private _certificates;
    uint256 private _certificateCount;

    // Certificate IDs currently held by each owner
    mapping(address => uint256[]) private _certificatesOf;

    // Leftover energy (below 1 MWh) waiting for the next certificate, per producer
    mapping(address => uint256) private _pendingEnergyKWh;

    // Raw-data hashes already submitted, blocks re-use of the same reading
    mapping(bytes32 => bool) private _usedDataHash;

    // ------------------------------------------------------------------
    // Access modifiers (each one asks RoleRegistry)
    // ------------------------------------------------------------------

    modifier onlyActiveProducer() {
        require(roles.isActiveProducer(msg.sender), "Not an active producer");
        _;
    }

    modifier onlyDataChecker() {
        require(roles.isDataChecker(msg.sender), "Not the data checker");
        _;
    }

    modifier onlyRegulator() {
        require(roles.isRegulator(msg.sender), "Not a regulator");
        _;
    }

    modifier onlyCertificateOwner(uint256 certificateId) {
        require(_certificates[certificateId].owner == msg.sender, "Not the certificate owner");
        _;
    }

    constructor(address roleRegistry) {
        require(roleRegistry != address(0), "RoleRegistry address required");
        roles = IRoleRegistry(roleRegistry);
    }

    // ------------------------------------------------------------------
    // Producer actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function submitReading(
        uint256 periodStart,
        uint256 periodEnd,
        uint256 energyKWh,
        bytes32 dataHash
    ) external override onlyActiveProducer returns (uint256 readingId) {
        require(periodEnd > periodStart, "Invalid period");
        require(energyKWh > 0, "Energy must be positive");
        require(!_usedDataHash[dataHash], "Reading already submitted");

        // TODO: mark dataHash as used
        // TODO: create Reading with status Pending, producer = msg.sender
        // TODO: emit ReadingSubmitted
        readingId = 0; // placeholder until implemented
    }

    // ------------------------------------------------------------------
    // Data Checker (oracle) actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function approveReading(uint256 readingId) external override onlyDataChecker {
        require(_readings[readingId].status == ReadingStatus.Pending, "Reading not pending");

        // TODO: set status Approved
        // TODO: call _issueCertificates(readingId)
        // TODO: emit ReadingApproved
    }

    /// @inheritdoc ICertificateRegistry
    function flagReading(uint256 readingId, string calldata reason) external override onlyDataChecker {
        require(_readings[readingId].status == ReadingStatus.Pending, "Reading not pending");

        // TODO: set status Flagged, store reason, emit ReadingFlagged
        reason;
    }

    // ------------------------------------------------------------------
    // Regulator actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function reviewFlaggedReading(uint256 readingId, bool approve) external override onlyRegulator {
        require(_readings[readingId].status == ReadingStatus.Flagged, "Reading not flagged");

        // TODO: if approve -> status Approved and _issueCertificates(readingId)
        //       else       -> status Rejected
        // TODO: emit FlaggedReadingReviewed
        approve;
    }

    // ------------------------------------------------------------------
    // Owner actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function transferCertificate(uint256 certificateId, address to)
        external override onlyCertificateOwner(certificateId)
    {
        require(_certificates[certificateId].status == CertificateStatus.Active, "Certificate already retired");
        require(roles.isBuyer(to), "Receiver is not a registered buyer");

        // TODO: move ID from sender's list to receiver's list, update owner
        // TODO: emit CertificateTransferred
    }

    /// @inheritdoc ICertificateRegistry
    function retireCertificate(uint256 certificateId, string calldata note)
        external override onlyCertificateOwner(certificateId)
    {
        require(_certificates[certificateId].status == CertificateStatus.Active, "Certificate already retired");

        // TODO: set status Retired, retiredBy = msg.sender, store note
        // TODO: emit CertificateRetired
        note;
    }

    // ------------------------------------------------------------------
    // Public lookups
    // ------------------------------------------------------------------

    function getReading(uint256 readingId) external view override returns (Reading memory) {
        return _readings[readingId];
    }

    function getCertificate(uint256 certificateId) external view override returns (Certificate memory) {
        return _certificates[certificateId];
    }

    function getCertificatesOf(address owner) external view override returns (uint256[] memory) {
        return _certificatesOf[owner];
    }

    function getPendingEnergyKWh(address producer) external view override returns (uint256) {
        return _pendingEnergyKWh[producer];
    }

    function totalCertificates() external view override returns (uint256) {
        return _certificateCount;
    }

    // ------------------------------------------------------------------
    // Internal logic
    // ------------------------------------------------------------------

    /**
     * @dev Adds the reading's energy to the producer's pending balance and
     *      issues one certificate for every full 1000 kWh. The remainder stays
     *      in the balance for the next reading.
     *      Example: balance 300 kWh + new reading 2500 kWh = 2800 kWh
     *               -> 2 certificates issued, 800 kWh carried forward.
     */
    function _issueCertificates(uint256 readingId) internal {
        // TODO: implement as described above, emitting CertificateIssued per certificate
        readingId;
    }
}
