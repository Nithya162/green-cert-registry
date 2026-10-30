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

DRAFT: function signatures and rules are defined. Bodies marked TODO
will be completed in the implementation phase.
"""

from dataclasses import dataclass
from typing import List, Optional
import hashlib


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
    """Flags power reported when there is no sunlight (e.g. 2 am). """
    # TODO: if irradiance < NIGHT_IRRADIANCE_LIMIT and energy > NIGHT_POWER_LIMIT_KW -> return reason
    return None


def check_output_vs_sunlight(reading: Reading, capacity_kw: float) -> Optional[str]:
    """Flags output that is too high for the measured sunlight (e.g. cloudy day)."""
    # TODO: expected = capacity_kw * irradiance; compare with MAX_EFFICIENCY_RATIO
    return None


def check_capacity_limit(reading: Reading, capacity_kw: float) -> Optional[str]:
    """Flags output above what the installed panels can physically produce."""
    # TODO: energy_kwh per hour > capacity_kw * CAPACITY_MARGIN -> return reason
    return None


def check_sudden_spike(reading: Reading, recent_average_kwh: float) -> Optional[str]:
    """Flags output far above the farm's own recent average at the same hour."""
    # TODO: energy_kwh > recent_average_kwh * SPIKE_FACTOR -> return reason
    return None


def validate_reading(reading: Reading, capacity_kw: float, recent_average_kwh: float) -> CheckResult:
    """Runs every rule and combines the results."""
    # TODO: call each rule, collect non-empty reasons, return CheckResult
    raise NotImplementedError


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
    # TODO: implement for the evaluation phase
    raise NotImplementedError


if __name__ == "__main__":
    # TODO: load data/ CSVs, validate each reading, and submit decisions
    print("Data Checker draft. See README for planned usage.")
