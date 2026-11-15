// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICertificateRegistry.sol";
import "./interfaces/IRoleRegistry.sol";

/**
 * @title CertificateRegistry
 * @notice Issues, transfers and retires green energy certificates.
 *         Every certificate has a unique ID and a full on-chain history,
 *         so the same certificate can never be claimed twice.
 * @dev All permission checks are delegated to RoleRegistry.
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

    /// @dev Unused storage slots look like a Pending reading, so check the ID is real.
    modifier readingExists(uint256 readingId) {
        require(readingId > 0 && readingId <= _readingCount, "Reading does not exist");
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

        // Remember this fingerprint so the same data can never be submitted again
        _usedDataHash[dataHash] = true;

        // Create the reading. It waits as Pending until the Data Checker decides.
        readingId = ++_readingCount;
        _readings[readingId] = Reading({
            id: readingId,
            producer: msg.sender,
            periodStart: periodStart,
            periodEnd: periodEnd,
            energyKWh: energyKWh,
            dataHash: dataHash,
            status: ReadingStatus.Pending,
            flagReason: ""
        });

        emit ReadingSubmitted(readingId, msg.sender, energyKWh, dataHash);
    }

    // ------------------------------------------------------------------
    // Data Checker (oracle) actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function approveReading(uint256 readingId) external override onlyDataChecker readingExists(readingId) {
        require(_readings[readingId].status == ReadingStatus.Pending, "Reading not pending");

        _readings[readingId].status = ReadingStatus.Approved;

        uint256 issued = _issueCertificates(readingId);

        emit ReadingApproved(readingId, issued);
    }

    /// @inheritdoc ICertificateRegistry
    function flagReading(uint256 readingId, string calldata reason) external override onlyDataChecker readingExists(readingId) {
        require(_readings[readingId].status == ReadingStatus.Pending, "Reading not pending");

        // No certificates are created. The regulator will review this reading.
        _readings[readingId].status = ReadingStatus.Flagged;
        _readings[readingId].flagReason = reason;

        emit ReadingFlagged(readingId, reason);
    }

    // ------------------------------------------------------------------
    // Regulator actions
    // ------------------------------------------------------------------

    /// @inheritdoc ICertificateRegistry
    function reviewFlaggedReading(uint256 readingId, bool approve) external override onlyRegulator readingExists(readingId) {
        require(_readings[readingId].status == ReadingStatus.Flagged, "Reading not flagged");

        if (approve) {
            // Regulator decided the reading is genuine after all
            _readings[readingId].status = ReadingStatus.Approved;
            _issueCertificates(readingId);
        } else {
            // Regulator confirmed it was fake: no certificates, ever
            _readings[readingId].status = ReadingStatus.Rejected;
        }

        emit FlaggedReadingReviewed(readingId, approve);
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

        // Change the owner and move the certificate between the two owners' lists
        _certificates[certificateId].owner = to;
        _removeFromOwner(msg.sender, certificateId);
        _certificatesOf[to].push(certificateId);

        emit CertificateTransferred(certificateId, msg.sender, to);
    }

    /// @inheritdoc ICertificateRegistry
    function retireCertificate(uint256 certificateId, string calldata note)
        external override onlyCertificateOwner(certificateId)
    {
        require(_certificates[certificateId].status == CertificateStatus.Active, "Certificate already retired");

        // Lock the certificate forever. This is what stops double counting:
        // every transfer and retire call checks that the status is still Active.
        Certificate storage cert = _certificates[certificateId];
        cert.status = CertificateStatus.Retired;
        cert.retiredBy = msg.sender;
        cert.retirementNote = note;

        emit CertificateRetired(certificateId, msg.sender, note);
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
    function _issueCertificates(uint256 readingId) internal returns (uint256 issued) {
        Reading storage reading = _readings[readingId];
        address producer = reading.producer;

        // Add the new energy to whatever was left over from earlier readings
        uint256 balance = _pendingEnergyKWh[producer] + reading.energyKWh;

        // One certificate for every full 1000 kWh
        issued = balance / KWH_PER_CERTIFICATE;

        // Keep the remainder (less than 1000 kWh) for the next reading
        _pendingEnergyKWh[producer] = balance % KWH_PER_CERTIFICATE;

        for (uint256 i = 0; i < issued; i++) {
            uint256 certId = ++_certificateCount;
            _certificates[certId] = Certificate({
                id: certId,
                readingId: readingId,
                producer: producer,
                owner: producer,          // the farm owns its certificates first
                issuedAt: block.timestamp,
                status: CertificateStatus.Active,
                retiredBy: address(0),
                retirementNote: ""
            });
            _certificatesOf[producer].push(certId);

            emit CertificateIssued(certId, readingId, producer);
        }
    }

    /// @dev Removes a certificate ID from an owner's list (swap with last, then pop).
    function _removeFromOwner(address owner, uint256 certificateId) internal {
        uint256[] storage list = _certificatesOf[owner];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == certificateId) {
                list[i] = list[list.length - 1];
                list.pop();
                return;
            }
        }
    }
}
