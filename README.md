# Green Energy Certificates on Blockchain

**CSE 540: Engineering Blockchain Applications | Project 3 (Open Innovation)**

**Team G3:** Shri Nithya, Akash Radhakrishnan Jayasankar, Nithyashree Ravikumar, Mithun Menon, Lakshmi Chandana Koyya 

> Status: **Draft (Smart Contract Design milestone).** Contract interfaces, function signatures, and component outlines are complete. Function bodies marked `TODO` will be implemented in the next phase.

---

## 1. Project Description

When a solar or wind farm generates clean electricity, it receives **Renewable Energy Certificates (RECs)**, where one certificate represents 1 MWh. Companies buy these certificates to prove they use clean energy.

Today, two problems weaken trust in these certificates:

1. **Double counting:** certificates are tracked in separate registries, so the same certificate can be sold or claimed twice.
2. **False claims:** few checks confirm the meter data, so a producer can over report generation and receive certificates with no real clean energy behind them.

Our system solves both:

- A **blockchain registry** gives every certificate a unique ID and a permanent history (issued, transferred, retired). A retired certificate can never be transferred or claimed again.
- An **off-chain Data Checker** validates generation data **before** certificates are created and flags readings that do not make sense, such as solar power at night or output higher than the panels can produce.

### Stakeholders and Access Control

| Role | Who | Allowed actions |
|---|---|---|
| **Regulator** | Energy authority | Add, suspend, and reinstate members, set the Data Checker, review flagged readings |
| **Producer** | Registered solar or wind farm | Submit generation readings for its own farm only |
| **Data Checker** | Off-chain validation service (oracle) | Approve readings (issues certificates) or flag them |
| **Buyer** | Registered company | Receive, transfer, and retire certificates it owns |
| **Public** | Anyone | View any reading or certificate history |

**How members join:** a farm or company applies off chain, the regulator verifies its documents (licence, meter ID), and only then registers its wallet address on chain. No account can give itself a role.

### Architecture

```
            OFF CHAIN                                    ON CHAIN
 ┌────────────────────┐   ┌──────────────────┐   ┌──────────────────┐   ┌───────────────────────┐
 │ Solar data         │──▶│ Data Checker     │──▶│ RoleRegistry     │──▶│ CertificateRegistry   │
 │ (Kaggle / NREL)    │   │ (Python)         │   │ (who can do what)│   │ (issue, transfer,     │
 └────────────────────┘   └──────────────────┘   └──────────────────┘   │  retire certificates) │
                                                                         └───────────▲───────────┘
 ┌────────────────────┐                          ┌──────────────────┐                │
 │ Regulator, Producer│─────────────────────────▶│ Web interface    │────────────────┘
 │ Buyer, Public      │                          │ (lookup, actions)│
 └────────────────────┘                          └──────────────────┘
```

### Certificate Lifecycle

```
Producer submits reading ──▶ Data Checker validates
                                 │
                 ┌───────────────┴────────────────┐
              valid                          suspicious
                 │                                │
        approveReading()                   flagReading()
                 │                                │
       Certificates issued            Regulator reviews (approve / reject)
                 │
    transferCertificate() to a Buyer
                 │
    retireCertificate()  ──▶  locked forever (no double counting)
```

---

## 2. Repository Structure

```
green-energy-certificates/
├── contracts/
│   ├── interfaces/
│   │   ├── IRoleRegistry.sol          # Role and membership interface
│   │   └── ICertificateRegistry.sol   # Certificate lifecycle interface
│   ├── RoleRegistry.sol               # Access control (OpenZeppelin AccessControl)
│   └── CertificateRegistry.sol        # Readings and certificates
├── data-checker/
│   ├── checker.py                     # Plausibility rules and oracle logic
│   └── requirements.txt
├── scripts/
│   └── deploy.js                      # Deployment script (draft)
├── test/                              # Contract tests (next milestone)
├── frontend/                          # Web interface (next milestone)
├── data/                              # Dataset instructions
├── hardhat.config.js
├── package.json
├── .env.example                       # Template for private settings
└── README.md
```

---

## 3. Smart Contract Overview

### `RoleRegistry.sol`
Stores the role of every account and controls membership.

| Function | Who can call | Purpose |
|---|---|---|
| `registerProducer(address, name, meterId, location, capacityKW)` | Regulator | Add a verified farm |
| `registerBuyer(address, name)` | Regulator | Add a verified company |
| `suspendProducer(address, reason)` | Regulator | Block a producer caught cheating |
| `reinstateProducer(address)` | Regulator | Re-enable a suspended producer |
| `setDataChecker(address)` | Regulator | Set the oracle account |
| `isActiveProducer`, `isBuyer`, `isRegulator`, `isDataChecker`, `getProducer` | Anyone | Role lookups |

### `CertificateRegistry.sol`
Handles readings and the full certificate lifecycle. **1 certificate = 1 MWh**; energy below 1 MWh carries forward to the next reading.

| Function | Who can call | Purpose |
|---|---|---|
| `submitReading(periodStart, periodEnd, energyKWh, dataHash)` | Active producer | Submit generation data and its fingerprint |
| `approveReading(readingId)` | Data Checker | Approve and issue certificates |
| `flagReading(readingId, reason)` | Data Checker | Flag a suspicious reading |
| `reviewFlaggedReading(readingId, approve)` | Regulator | Final decision on a flagged reading |
| `transferCertificate(certificateId, to)` | Certificate owner | Sell to a registered buyer |
| `retireCertificate(certificateId, note)` | Certificate owner | Use the certificate (permanent) |
| `getReading`, `getCertificate`, `getCertificatesOf`, `getPendingEnergyKWh`, `totalCertificates` | Anyone | Public verification |

Every action emits an **event**, which forms the public audit trail of each certificate.

### Data Checker rules (`data-checker/checker.py`)

| Rule | Flags |
|---|---|
| Night generation | Power reported with no sunlight |
| Output vs. sunlight | Output too high for the measured sunlight |
| Capacity limit | Output above what installed panels can produce |
| Sudden spike | Output far above the farm's usual level |

---

## 4. Dependencies

| Tool | Version | Used for |
|---|---|---|
| [Node.js](https://nodejs.org) | 18 or newer | Running Hardhat |
| [Hardhat](https://hardhat.org) | 2.x | Compile, test, deploy contracts |
| [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/5.x/) | 5.x | Role-based access control |
| Solidity | 0.8.24 | Smart contract language |
| [Python](https://www.python.org) | 3.10 or newer | Data Checker |
| pandas, web3.py, python-dotenv | see `data-checker/requirements.txt` | Data handling and blockchain connection |
| [MetaMask](https://metamask.io) | latest | Wallet for test accounts |
| Sepolia test ETH | n/a | Paying gas on the test network (free from a faucet) |

---

## 5. Setup

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/green-energy-certificates.git
cd green-energy-certificates

# 2. Install smart contract dependencies
npm install

# 3. Compile the contracts
npx hardhat compile

# 4. Set up the Data Checker
cd data-checker
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
cd ..

# 5. Create your private settings file
cp .env.example .env            # then fill in your own values (never commit .env)
```

---

## 6. Usage and Deployment (draft)

> These steps describe the intended workflow. Details will be finalised in the implementation phase.

**Run on a local blockchain**
```bash
npx hardhat node                                   # starts a local test blockchain
npx hardhat run scripts/deploy.js --network localhost
```

**Deploy to the Sepolia test network**
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

**Planned workflow**
1. Deploy `RoleRegistry` with the regulator's address, then deploy `CertificateRegistry` with the `RoleRegistry` address.
2. Regulator registers producers and buyers, and sets the Data Checker account.
3. Producers submit readings built from the solar dataset.
4. Run the Data Checker to approve or flag each reading:
   ```bash
   python data-checker/checker.py
   ```
5. Buyers receive and retire certificates; anyone can look up a certificate's history in the web interface.

---

## 7. Dataset

We use public solar generation data (power output, irradiance, temperature). See [`data/README.md`](data/README.md) for download instructions.

---

## 8. Team

| Member | Role |
|---|---|
| Akash | Smart Contract Developer |
| Chandana | Testing and Documentation |
| Mithun | Frontend Developer (Ethers.js, MetaMask) |
| Nithya | Integration Developer (Web3.py connector) |
| Shri Nithya | Data Checker (Python, plausibility rules, hashing) |
