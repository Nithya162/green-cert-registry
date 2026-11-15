// Interim demo: runs the full certificate story on a local blockchain.
//
// Run it with:   npx hardhat run scripts/demo.js
//
// Story:
//   1. Regulator deploys the system and registers members
//   2. Sunny Farm submits an honest reading, the Data Checker approves it
//   3. Certificates are issued (1 per 1000 kWh, remainder carried forward)
//   4. Sunny Farm sells a certificate to Company X, Company X retires it
//   5. Cheating attempts are blocked by the smart contracts
//   6. A suspicious reading is flagged and rejected by the regulator
const hre = require("hardhat");
const { ethers } = hre;

// Status labels matching the enums in ICertificateRegistry.sol
const READING_STATUS = ["Pending", "Approved", "Flagged", "Rejected"];
const CERT_STATUS = ["Active", "Retired"];

function step(title) {
  console.log("\n" + "=".repeat(64));
  console.log(title);
  console.log("=".repeat(64));
}

function short(addr) {
  return addr.slice(0, 6) + "..." + addr.slice(-4);
}

// Tries an action that SHOULD fail and prints the contract's error message.
async function expectBlocked(label, action) {
  try {
    const tx = await action();
    await tx.wait();
    console.log(`  [PROBLEM] ${label}: was NOT blocked`);
  } catch (err) {
    console.log(`  [BLOCKED] ${label}`);
    console.log(`            reason: ${cleanReason(err)}`);
  }
}

// Turns a raw blockchain error into the short message written in the contract.
function cleanReason(err) {
  const msg = err.shortMessage || err.reason || err.message || String(err);
  const text = msg.match(/reason string '([^']+)'/);
  if (text) return text[1];
  if (msg.includes("AccessControlUnauthorizedAccount")) return "Missing required role (OpenZeppelin AccessControl)";
  return msg.replace("execution reverted: ", "");
}

// Builds a fingerprint (hash) of raw meter data, the way the Data Checker will.
function dataHash(text) {
  return ethers.keccak256(ethers.toUtf8Bytes(text));
}

async function main() {
  // Five test accounts provided by the local Hardhat blockchain
  const [regulator, checker, sunnyFarm, companyX, shadyFarm] = await ethers.getSigners();
  const names = new Map([
    [regulator.address, "Regulator"],
    [checker.address, "Data Checker"],
    [sunnyFarm.address, "Sunny Farm"],
    [companyX.address, "Company X"],
    [shadyFarm.address, "Shady Farm"],
  ]);
  const who = (a) => names.get(a) || short(a);

  // ------------------------------------------------------------------
  step("STEP 1  Deploy contracts");
  const roles = await (await ethers.getContractFactory("RoleRegistry")).deploy(regulator.address);
  await roles.waitForDeployment();
  const certs = await (await ethers.getContractFactory("CertificateRegistry")).deploy(await roles.getAddress());
  await certs.waitForDeployment();
  console.log(`  RoleRegistry        at ${await roles.getAddress()}`);
  console.log(`  CertificateRegistry at ${await certs.getAddress()}`);
  console.log(`  Regulator account   ${short(regulator.address)}`);

  // ------------------------------------------------------------------
  step("STEP 2  Regulator registers members (after off-chain verification)");
  await (await roles.registerProducer(sunnyFarm.address, "Sunny Farm", "MTR-1001", "Phoenix, AZ", 500)).wait();
  console.log(`  Registered PRODUCER  Sunny Farm   (meter MTR-1001, 500 kW)`);
  await (await roles.registerBuyer(companyX.address, "Company X")).wait();
  console.log(`  Registered BUYER     Company X`);
  await (await roles.setDataChecker(checker.address)).wait();
  console.log(`  Set DATA CHECKER     ${short(checker.address)}`);

  console.log("\n  Access check: only the regulator can add members");
  await expectBlocked("Sunny Farm tries to register itself as a buyer", () =>
    roles.connect(sunnyFarm).registerBuyer(sunnyFarm.address, "Fake Buyer")
  );

  // ------------------------------------------------------------------
  step("STEP 3  Sunny Farm submits a reading, Data Checker approves it");
  const day = 86400;
  const t0 = 1767225600; // 1 Jan 2026, used as a fixed example period
  await (await certs.connect(sunnyFarm).submitReading(t0, t0 + day, 2500, dataHash("sunny-2026-01-01"))).wait();
  let r = await certs.getReading(1);
  console.log(`  Reading #1  ${r.energyKWh} kWh  status: ${READING_STATUS[r.status]}`);

  await (await certs.connect(checker).approveReading(1)).wait();
  r = await certs.getReading(1);
  console.log(`  Data Checker approved reading #1  status: ${READING_STATUS[r.status]}`);
  console.log(`  Certificates issued: ${await certs.totalCertificates()}  (1 per 1000 kWh)`);
  console.log(`  Leftover carried forward: ${await certs.getPendingEnergyKWh(sunnyFarm.address)} kWh`);
  console.log(`  Sunny Farm owns certificates: [${(await certs.getCertificatesOf(sunnyFarm.address)).join(", ")}]`);

  // ------------------------------------------------------------------
  step("STEP 4  Sunny Farm sells certificate #1 to Company X");
  await (await certs.connect(sunnyFarm).transferCertificate(1, companyX.address)).wait();
  let c = await certs.getCertificate(1);
  console.log(`  Certificate #1 owner: ${who(c.owner)}  status: ${CERT_STATUS[c.status]}`);

  step("STEP 5  Company X retires (uses) certificate #1");
  await (await certs.connect(companyX).retireCertificate(1, "FY2026 clean energy claim")).wait();
  c = await certs.getCertificate(1);
  console.log(`  Certificate #1 status: ${CERT_STATUS[c.status]}  retired by: ${who(c.retiredBy)}`);
  console.log(`  Note: "${c.retirementNote}"`);

  // ------------------------------------------------------------------
  step("STEP 6  Cheating attempts");
  await expectBlocked("Sunny Farm tries to sell certificate #1 again (not the owner)", () =>
    certs.connect(sunnyFarm).transferCertificate(1, companyX.address)
  );
  await expectBlocked("Company X tries to retire certificate #1 a second time", () =>
    certs.connect(companyX).retireCertificate(1, "double claim")
  );
  await expectBlocked("Sunny Farm re-submits the same data (same fingerprint)", () =>
    certs.connect(sunnyFarm).submitReading(t0, t0 + day, 2500, dataHash("sunny-2026-01-01"))
  );
  await expectBlocked("Unregistered Shady Farm tries to submit a reading", () =>
    certs.connect(shadyFarm).submitReading(t0, t0 + day, 9000, dataHash("shady-data"))
  );
  await expectBlocked("Sunny Farm tries to approve its own reading", () =>
    certs.connect(sunnyFarm).approveReading(1)
  );
  await expectBlocked("Sunny Farm tries to sell certificate #2 to an unregistered account", () =>
    certs.connect(sunnyFarm).transferCertificate(2, shadyFarm.address)
  );

  // ------------------------------------------------------------------
  step("STEP 7  Suspicious reading is flagged, regulator rejects it");
  await (await certs.connect(sunnyFarm).submitReading(t0 + day, t0 + 2 * day, 3000, dataHash("sunny-night-spike"))).wait();
  await (await certs.connect(checker).flagReading(2, "Power reported at 02:00 with zero sunlight")).wait();
  r = await certs.getReading(2);
  console.log(`  Reading #2  ${r.energyKWh} kWh  status: ${READING_STATUS[r.status]}`);
  console.log(`  Reason: ${r.flagReason}`);
  console.log(`  Certificates still: ${await certs.totalCertificates()}  (none created for a flagged reading)`);

  await (await certs.connect(regulator).reviewFlaggedReading(2, false)).wait();
  r = await certs.getReading(2);
  console.log(`  Regulator reviewed reading #2  status: ${READING_STATUS[r.status]}`);

  await (await roles.suspendProducer(sunnyFarm.address, "Submitted implausible data")).wait();
  console.log(`  Regulator suspended Sunny Farm`);
  await expectBlocked("Suspended Sunny Farm tries to submit another reading", () =>
    certs.connect(sunnyFarm).submitReading(t0 + 2 * day, t0 + 3 * day, 1000, dataHash("after-suspension"))
  );

  // ------------------------------------------------------------------
  step("FINAL STATE");
  const total = Number(await certs.totalCertificates());
  for (let id = 1; id <= total; id++) {
    const cert = await certs.getCertificate(id);
    console.log(`  Certificate #${id}  owner: ${who(cert.owner).padEnd(10)}  status: ${CERT_STATUS[cert.status]}`);
  }
  console.log("\nDemo complete.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});