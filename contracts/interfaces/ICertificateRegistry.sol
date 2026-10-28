// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICertificateRegistry
 * @notice Interface for the contract that tracks every green energy certificate
 *         from the moment it is created until it is used (retired).
 *
 * Flow:
 *   1. A PRODUCER submits a generation reading (energy amount + hash of raw data).
 *   2. The off-chain Data Checker validates the raw data.
 *        - valid      -> CHECKER calls approveReading  -> certificates are issued
 *        - suspicious -> CHECKER calls flagReading     -> REGULATOR reviews it
 *   3. The owner can transfer certificates to a registered BUYER.
 *   4. The owner retires a certificate to claim the clean energy.
 *      A retired certificate can never be transferred or retired again,
 *      which prevents double counting.
 *
 * One certificate = 1 MWh (1000 kWh). Energy below 1 MWh is carried forward
 * in the producer's balance until enough is generated for the next certificate.
 */
interface ICertificateRegistry {
    // ------------------------------------------------------------------
    // Data types
    // ------------------------------------------------------------------

    /// @notice Where a submitted reading is in the validation process.
    enum ReadingStatus {
        Pending,   // submitted, waiting for the Data Checker
        Approved,  // passed checks, certificates issued
        Flagged,   // failed checks, waiting for regulator review
        Rejected   // regulator confirmed it was invalid
    }

    /// @notice A generation reading submitted by a producer.
    struct Reading {
        uint256 id;
        address producer;
        uint256 periodStart;  // start of the measured period (unix time)
        uint256 periodEnd;    // end of the measured period (unix time)
        uint256 energyKWh;    // energy the producer claims was generated
        bytes32 dataHash;     // hash of the raw meter and sunlight data, proves data was not edited later
        ReadingStatus status;
        string flagReason;    // filled in by the Data Checker when a reading is flagged
    }

    /// @notice Lifecycle status of a certificate.
    enum CertificateStatus {
        Active,   // can be transferred or retired
        Retired   // used to claim clean energy, permanently locked
    }

    /// @notice One green energy certificate (1 MWh).
    struct Certificate {
        uint256 id;           // unique certificate number
        uint256 readingId;    // reading that produced this certificate
        address producer;     // farm that generated the energy
        address owner;        // current owner
        uint256 issuedAt;     // block timestamp of issuance
        CertificateStatus status;
        address retiredBy;    // who used the certificate (zero if still active)
        string retirementNote;// e.g. "FY2026 Scope 2 claim"
    }

    // ------------------------------------------------------------------
    // Events (form the public history of every certificate)
    // ------------------------------------------------------------------

    event ReadingSubmitted(uint256 indexed readingId, address indexed producer, uint256 energyKWh, bytes32 dataHash);
    event ReadingApproved(uint256 indexed readingId, uint256 certificatesIssued);
    event ReadingFlagged(uint256 indexed readingId, string reason);
    event FlaggedReadingReviewed(uint256 indexed readingId, bool approved);
    event CertificateIssued(uint256 indexed certificateId, uint256 indexed readingId, address indexed producer);
    event CertificateTransferred(uint256 indexed certificateId, address indexed from, address indexed to);
    event CertificateRetired(uint256 indexed certificateId, address indexed owner, string note);

    // ------------------------------------------------------------------
    // Producer actions
    // ------------------------------------------------------------------

    /// @notice Submits a generation reading for validation.
    /// @dev Only an ACTIVE PRODUCER, and only for itself. Reverts if the same
    ///      dataHash was already submitted, so one reading cannot be used twice.
    /// @return readingId ID of the new reading.
    function submitReading(
        uint256 periodStart,
        uint256 periodEnd,
        uint256 energyKWh,
        bytes32 dataHash
    ) external returns (uint256 readingId);

    // ------------------------------------------------------------------
    // Data Checker (oracle) actions
    // ------------------------------------------------------------------

    /// @notice Approves a reading that passed off-chain checks and issues certificates.
    /// @dev Only CHECKER. Reading must be Pending. Adds energy to the producer's
    ///      balance and issues one certificate per full 1000 kWh.
    function approveReading(uint256 readingId) external;

    /// @notice Flags a suspicious reading (e.g. power at night, output above capacity).
    /// @dev Only CHECKER. No certificates are issued for a flagged reading.
    function flagReading(uint256 readingId, string calldata reason) external;

    // ------------------------------------------------------------------
    // Regulator actions
    // ------------------------------------------------------------------

    /// @notice Final decision on a flagged reading after manual review.
    /// @dev Only REGULATOR. approve = true issues certificates, false marks it Rejected.
    function reviewFlaggedReading(uint256 readingId, bool approve) external;

    // ------------------------------------------------------------------
    // Owner actions
    // ------------------------------------------------------------------

    /// @notice Transfers a certificate to a registered buyer (a sale).
    /// @dev Only the current owner. Certificate must be Active. Receiver must be a BUYER.
    function transferCertificate(uint256 certificateId, address to) external;

    /// @notice Retires (uses) a certificate to claim the clean energy.
    /// @dev Only the current owner. After this the certificate is locked forever.
    function retireCertificate(uint256 certificateId, string calldata note) external;

    // ------------------------------------------------------------------
    // Public lookups (anyone can verify)
    // ------------------------------------------------------------------

    function getReading(uint256 readingId) external view returns (Reading memory);
    function getCertificate(uint256 certificateId) external view returns (Certificate memory);
    function getCertificatesOf(address owner) external view returns (uint256[] memory);
    function getPendingEnergyKWh(address producer) external view returns (uint256);
    function totalCertificates() external view returns (uint256);
}
