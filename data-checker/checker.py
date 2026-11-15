"""
Data Checker (off-chain oracle)

Validates solar generation readings BEFORE any certificate is created.
A blockchain keeps records safe from later edits, but it cannot tell whether
the data was true when it was entered. This service fills that gap.

Flow:
    1. Load hourly generation and weather (sunlight) data for a producer.
    2. Run plausibility rules on each reading.
    3. Valid reading      -> call CertificateRegistry.approveReading(readingId)
       Suspicious reading -> call CertificateRegistry.flagReading(readingId, reason)

Status: the four plausibility rules and validate_reading are implemented.
Sending decisions to the blockchain (submit_decision) is in progress.

Run a quick demo on sample readings:
    python data-checker/checker.py
"""

from dataclasses import dataclass
from typing import List, Optional
import hashlib
import random


# ----------------------------------------------------------------------
# Thresholds for the plausibility rules (to be tuned on the dataset)
# ----------------------------------------------------------------------
NIGHT_IRRADIANCE_LIMIT = 0.01      # sunlight below this counts as "no sun"
NIGHT_POWER_LIMIT_KW = 0.5         # power above this at night is suspicious
MAX_EFFICIENCY_RATIO = 1.2         # output vs. expected output from sunlight
CAPACITY_MARGIN = 1.05             # output may not exceed 105% of installed capacity
SPIKE_FACTOR = 3.0                 # output more than 3x the farm's usual level


@dataclass
class Reading:
    """One hourly generation reading from a producer."""
    producer_address: str
    timestamp: str          # ISO time of the reading
    energy_kwh: float       # energy the producer reports
    irradiance: float       # sunlight level from the weather sensor
    module_temp_c: Optional[float] = None


@dataclass
class CheckResult:
    """Outcome of validating one reading."""
    is_valid: bool
    reasons: List[str]      # empty when valid, otherwise why it was flagged


# ----------------------------------------------------------------------
# Plausibility rules (each returns a reason string if the rule fails)
# ----------------------------------------------------------------------

def check_night_generation(reading: Reading) -> Optional[str]:
    """Flags power reported when there is no sunlight (e.g. 2 am)."""
    if reading.irradiance < NIGHT_IRRADIANCE_LIMIT and reading.energy_kwh > NIGHT_POWER_LIMIT_KW:
        return f"Night generation: {reading.energy_kwh} kWh reported with no sunlight"
    return None


def check_output_vs_sunlight(reading: Reading, capacity_kw: float) -> Optional[str]:
    """Flags output that is too high for the measured sunlight (e.g. cloudy day)."""
    # Irradiance is in kW/m2, where 1.0 is full sun. A farm in full sun makes
    # roughly its capacity, so expected output is capacity x irradiance.
    expected_kwh = capacity_kw * reading.irradiance
    if reading.irradiance >= NIGHT_IRRADIANCE_LIMIT and reading.energy_kwh > expected_kwh * MAX_EFFICIENCY_RATIO:
        return (f"Output too high for sunlight: {reading.energy_kwh} kWh reported, "
                f"about {expected_kwh:.0f} kWh expected")
    return None


def check_capacity_limit(reading: Reading, capacity_kw: float) -> Optional[str]:
    """Flags output above what the installed panels can physically produce."""
    # For an hourly reading, kWh can never be more than the kW capacity (plus a small margin)
    limit = capacity_kw * CAPACITY_MARGIN
    if reading.energy_kwh > limit:
        return f"Above capacity: {reading.energy_kwh} kWh in one hour, limit is {limit:.0f} kWh"
    return None


def check_sudden_spike(reading: Reading, recent_average_kwh: float) -> Optional[str]:
    """Flags output far above the farm's own recent average at the same hour."""
    if recent_average_kwh > 0 and reading.energy_kwh > recent_average_kwh * SPIKE_FACTOR:
        return (f"Sudden spike: {reading.energy_kwh} kWh is more than {SPIKE_FACTOR:.0f}x "
                f"the usual {recent_average_kwh:.0f} kWh")
    return None


def validate_reading(reading: Reading, capacity_kw: float, recent_average_kwh: float) -> CheckResult:
    """Runs every rule and combines the results."""
    checks = [
        check_night_generation(reading),
        check_output_vs_sunlight(reading, capacity_kw),
        check_capacity_limit(reading, capacity_kw),
        check_sudden_spike(reading, recent_average_kwh),
    ]
    reasons = [r for r in checks if r is not None]
    return CheckResult(is_valid=len(reasons) == 0, reasons=reasons)


# ----------------------------------------------------------------------
# Helpers for the blockchain side
# ----------------------------------------------------------------------

def hash_raw_data(rows: List[Reading]) -> str:
    """
    Creates the fingerprint (dataHash) of the raw data behind a submission.
    Stored on chain so anyone can later prove the data was not edited.
    """
    # TODO: serialise rows in a fixed order and hash with keccak256 to match Solidity
    payload = "|".join(f"{r.timestamp},{r.energy_kwh},{r.irradiance}" for r in rows)
    return "0x" + hashlib.sha256(payload.encode()).hexdigest()  # placeholder hash


def submit_decision(reading_id: int, result: CheckResult) -> None:
    """
    Sends the decision to CertificateRegistry using Web3.py.
    approveReading(reading_id) if valid, otherwise flagReading(reading_id, reason).
    """
    # TODO: connect with web3.py using RPC URL and checker private key from .env
    raise NotImplementedError


def inject_fake_readings(rows: List[Reading],fraction: float = 0.05) -> List[Reading]:
    """
    Evaluation helper: changes a small share of real readings into fake ones
    (power at night, doubled output, sudden spikes) to measure how many the
    checker catches.
    """
    rng = random.Random(42)  # fixed seed so results can be repeated
    faked = []
    for r in rows:
        if rng.random() < fraction:
            kind = rng.choice(["night", "double", "spike"])
            if kind == "night":
                r = Reading(r.producer_address, r.timestamp, max(r.energy_kwh, 50.0), 0.0, r.module_temp_c)
            elif kind == "double":
                r = Reading(r.producer_address, r.timestamp, r.energy_kwh * 2, r.irradiance, r.module_temp_c)
            else:
                r = Reading(r.producer_address, r.timestamp, r.energy_kwh * 4 + 100, r.irradiance, r.module_temp_c)
        faked.append(r)
    return faked


def _demo() -> None:
    """Checks a few sample readings for a 500 kW farm and prints the decision for each."""
    capacity_kw = 500
    usual_kwh = 300  # the farm's typical output around midday
    farm = "0xSunnyFarm"
    samples = [
        ("Sunny midday, normal output", Reading(farm, "2026-01-01T12:00", 380, 0.85)),
        ("Cloudy afternoon, low output", Reading(farm, "2026-01-01T15:00", 90, 0.20)),
        ("2 am, power reported",         Reading(farm, "2026-01-02T02:00", 120, 0.00)),
        ("Cloudy, but full output",      Reading(farm, "2026-01-02T13:00", 450, 0.15)),
        ("More than panels can make",    Reading(farm, "2026-01-02T12:00", 900, 1.00)),
    ]
    print(f"Data Checker demo  (farm capacity {capacity_kw} kW, usual output {usual_kwh} kWh)\n")
    for label, reading in samples:
        result = validate_reading(reading, capacity_kw, usual_kwh)
        decision = "APPROVE" if result.is_valid else "FLAG"
        print(f"[{decision:7}] {label}: {reading.energy_kwh} kWh, sunlight {reading.irradiance}")
        for reason in result.reasons:
            print(f"           - {reason}")
    print(f"\nData fingerprint of these readings: {hash_raw_data([r for _, r in samples])[:20]}...")


if __name__ == "__main__":
    _demo()
