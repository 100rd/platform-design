"""
Integration tests for the OctoDNS-based DNS Sync system.

Tests cover:
- OctoDNS config YAML parsing and structural validation
- Zone file YAML parsing and DNS record validation
- Record type validation (A, AAAA, CNAME, MX, TXT, etc.)
- TTL validation and range checks
- Health-check canary record presence
- Zone consistency between config and zone files
- Edge cases: malformed YAML, missing fields, invalid IPs, invalid TTLs
"""

import ipaddress
import os
import re
import textwrap
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml


# ---------------------------------------------------------------------------
# Path fixtures
# ---------------------------------------------------------------------------

# Resolve paths relative to this test file so tests work regardless of cwd
_TESTS_DIR = Path(__file__).resolve().parent
_PROJECT_ROOT = _TESTS_DIR.parent.parent  # platform-design/
_DNS_SYNC_DIR = _PROJECT_ROOT / "dns-sync"
_CONFIG_PATH = _DNS_SYNC_DIR / "config" / "octodns-config.yaml"
_ZONES_DIR = _DNS_SYNC_DIR / "zones"


@pytest.fixture
def config_path():
    return _CONFIG_PATH


@pytest.fixture
def zones_dir():
    return _ZONES_DIR


@pytest.fixture
def config_data(config_path):
    """Load and parse the OctoDNS config YAML."""
    assert config_path.exists(), f"OctoDNS config not found at {config_path}"
    with open(config_path) as f:
        data = yaml.safe_load(f)
    assert data is not None, "OctoDNS config file is empty"
    return data


@pytest.fixture
def zone_files(zones_dir):
    """Return a dict mapping zone filename -> parsed YAML content."""
    assert zones_dir.exists(), f"Zones directory not found at {zones_dir}"
    result = {}
    for zone_file in sorted(zones_dir.glob("*.yaml")):
        with open(zone_file) as f:
            data = yaml.safe_load(f)
        result[zone_file.name] = data
    assert result, f"No zone YAML files found in {zones_dir}"
    return result


# ---------------------------------------------------------------------------
# Helper: synthetic zone data for edge-case tests
# ---------------------------------------------------------------------------

def _parse_zone_yaml(text):
    """Parse a zone YAML string, returning the dict."""
    return yaml.safe_load(text)


# ---------------------------------------------------------------------------
# Validators (reusable logic tested independently)
# ---------------------------------------------------------------------------

VALID_RECORD_TYPES = {"A", "AAAA", "CNAME", "MX", "TXT", "NS", "SRV", "CAA", "PTR", "SOA"}

# OctoDNS provider class pattern: module.ClassName
PROVIDER_CLASS_PATTERN = re.compile(r"^[a-zA-Z_][\w]*(\.[a-zA-Z_][\w]*)+$")


def validate_ipv4(value):
    """Return True if value is a valid IPv4 address."""
    try:
        ipaddress.IPv4Address(value)
        return True
    except (ipaddress.AddressValueError, ValueError):
        return False


def validate_ipv6(value):
    """Return True if value is a valid IPv6 address."""
    try:
        ipaddress.IPv6Address(value)
        return True
    except (ipaddress.AddressValueError, ValueError):
        return False


def validate_fqdn(value):
    """Return True if value looks like a fully-qualified domain name (ends with .)."""
    return isinstance(value, str) and value.endswith(".")


def validate_ttl(ttl):
    """TTL must be a positive integer, typically 60..86400."""
    return isinstance(ttl, int) and 1 <= ttl <= 604800  # max 7 days


def validate_record(record):
    """
    Validate a single DNS record dict from an OctoDNS zone file.
    Returns a list of error strings (empty means valid).
    """
    errors = []

    if not isinstance(record, dict):
        return [f"Record is not a dict: {record!r}"]

    rec_type = record.get("type")
    if rec_type not in VALID_RECORD_TYPES:
        errors.append(f"Invalid record type: {rec_type!r}")

    # TTL is optional but must be valid if present
    if "ttl" in record:
        if not validate_ttl(record["ttl"]):
            errors.append(f"Invalid TTL: {record['ttl']!r}")

    # Type-specific validation
    if rec_type == "A":
        value = record.get("value") or record.get("values")
        if isinstance(value, str):
            if not validate_ipv4(value):
                errors.append(f"Invalid IPv4 for A record: {value!r}")
        elif isinstance(value, list):
            for v in value:
                if not validate_ipv4(v):
                    errors.append(f"Invalid IPv4 for A record: {v!r}")
        else:
            errors.append("A record missing 'value' or 'values'")

    elif rec_type == "AAAA":
        value = record.get("value") or record.get("values")
        if isinstance(value, str):
            if not validate_ipv6(value):
                errors.append(f"Invalid IPv6 for AAAA record: {value!r}")
        elif isinstance(value, list):
            for v in value:
                if not validate_ipv6(v):
                    errors.append(f"Invalid IPv6 for AAAA record: {v!r}")

    elif rec_type == "CNAME":
        value = record.get("value")
        if not isinstance(value, str) or not value:
            errors.append(f"CNAME record missing or empty 'value': {value!r}")

    elif rec_type == "MX":
        values = record.get("values") or (
            [record.get("value")] if record.get("value") else []
        )
        if not values:
            errors.append("MX record missing 'value' or 'values'")
        for mx in (values if isinstance(values, list) else [values]):
            if isinstance(mx, dict):
                if "exchange" not in mx:
                    errors.append(f"MX record missing 'exchange': {mx!r}")
                if "preference" not in mx:
                    errors.append(f"MX record missing 'preference': {mx!r}")
                elif not isinstance(mx["preference"], int):
                    errors.append(
                        f"MX preference must be int: {mx['preference']!r}"
                    )

    elif rec_type == "TXT":
        value = record.get("value") or record.get("values")
        if value is None:
            errors.append("TXT record missing 'value' or 'values'")

    return errors


def validate_zone(zone_data):
    """
    Validate an entire zone file dict.
    Returns a list of (record_name, error_string) tuples.
    """
    issues = []
    if not isinstance(zone_data, dict):
        return [("_root", "Zone data is not a dict")]

    for name, records in zone_data.items():
        if not isinstance(records, list):
            issues.append((name, f"Records should be a list, got {type(records).__name__}"))
            continue
        for i, record in enumerate(records):
            for err in validate_record(record):
                issues.append((name, f"Record[{i}]: {err}"))

    return issues


# ---------------------------------------------------------------------------
# OctoDNS Config Validation Tests
# ---------------------------------------------------------------------------

class TestOctoDNSConfig:
    """Validate the OctoDNS configuration file structure."""

    def test_config_file_exists(self, config_path):
        """Config file must exist on disk."""
        assert config_path.exists(), f"Missing config: {config_path}"

    def test_config_is_valid_yaml(self, config_path):
        """Config file must parse as valid YAML without errors."""
        with open(config_path) as f:
            data = yaml.safe_load(f)
        assert isinstance(data, dict)

    def test_config_has_providers_section(self, config_data):
        """Config must define a 'providers' section."""
        assert "providers" in config_data, "Missing 'providers' section"
        assert isinstance(config_data["providers"], dict)
        assert len(config_data["providers"]) > 0, "No providers defined"

    def test_config_has_zones_section(self, config_data):
        """Config must define a 'zones' section."""
        assert "zones" in config_data, "Missing 'zones' section"
        assert isinstance(config_data["zones"], dict)
        assert len(config_data["zones"]) > 0, "No zones defined"

    def test_provider_classes_are_valid(self, config_data):
        """Each provider must have a valid 'class' attribute."""
        for name, provider_cfg in config_data["providers"].items():
            assert "class" in provider_cfg, (
                f"Provider '{name}' missing 'class'"
            )
            cls = provider_cfg["class"]
            assert PROVIDER_CLASS_PATTERN.match(cls), (
                f"Provider '{name}' has invalid class format: {cls!r}"
            )

    def test_zone_names_end_with_dot(self, config_data):
        """OctoDNS zone names must be FQDNs (end with '.')."""
        for zone_name in config_data["zones"]:
            assert zone_name.endswith("."), (
                f"Zone name '{zone_name}' must end with '.'"
            )

    def test_zones_have_sources_and_targets(self, config_data):
        """Each zone must have 'sources' and 'targets' lists."""
        for zone_name, zone_cfg in config_data["zones"].items():
            assert "sources" in zone_cfg, (
                f"Zone '{zone_name}' missing 'sources'"
            )
            assert "targets" in zone_cfg, (
                f"Zone '{zone_name}' missing 'targets'"
            )
            assert isinstance(zone_cfg["sources"], list)
            assert isinstance(zone_cfg["targets"], list)
            assert len(zone_cfg["sources"]) > 0
            assert len(zone_cfg["targets"]) > 0

    def test_zone_sources_reference_known_providers(self, config_data):
        """Zone sources must reference providers defined in the config."""
        providers = set(config_data["providers"].keys())
        for zone_name, zone_cfg in config_data["zones"].items():
            for src in zone_cfg["sources"]:
                assert src in providers, (
                    f"Zone '{zone_name}' source '{src}' not in providers: {providers}"
                )

    def test_zone_targets_reference_known_providers(self, config_data):
        """Zone targets must reference providers defined in the config."""
        providers = set(config_data["providers"].keys())
        for zone_name, zone_cfg in config_data["zones"].items():
            for tgt in zone_cfg["targets"]:
                assert tgt in providers, (
                    f"Zone '{zone_name}' target '{tgt}' not in providers: {providers}"
                )

    def test_config_provider_has_cloudflare(self, config_data):
        """Platform requires Cloudflare as a DNS provider."""
        assert "cloudflare" in config_data["providers"]

    def test_config_provider_has_route53(self, config_data):
        """Platform requires Route53 as a DNS provider."""
        assert "route53" in config_data["providers"]

    def test_yaml_provider_has_directory(self, config_data):
        """The YAML source provider must specify a zone directory."""
        config_provider = config_data["providers"].get("config")
        assert config_provider is not None, "Missing 'config' YAML provider"
        assert "directory" in config_provider, (
            "YAML provider missing 'directory'"
        )


# ---------------------------------------------------------------------------
# Zone File Validation Tests
# ---------------------------------------------------------------------------

class TestZoneFiles:
    """Validate zone file structure and DNS record correctness."""

    def test_zone_directory_exists(self, zones_dir):
        """Zones directory must exist."""
        assert zones_dir.is_dir()

    def test_at_least_one_zone_file(self, zone_files):
        """There must be at least one zone file."""
        assert len(zone_files) > 0

    def test_zone_files_are_valid_yaml(self, zone_files):
        """Every zone file must be parseable YAML."""
        for filename, data in zone_files.items():
            assert data is not None, f"{filename} parsed to None"
            assert isinstance(data, dict), (
                f"{filename} root is not a dict: {type(data).__name__}"
            )

    def test_zone_files_pass_full_validation(self, zone_files):
        """Run complete record validation on every zone file."""
        all_issues = []
        for filename, data in zone_files.items():
            issues = validate_zone(data)
            for name, err in issues:
                all_issues.append(f"{filename}::{name} - {err}")

        assert all_issues == [], (
            "Zone validation errors:\n" + "\n".join(all_issues)
        )

    def test_health_check_record_exists(self, zone_files):
        """At least one zone must contain the _health-check canary record."""
        found = False
        for filename, data in zone_files.items():
            if "_health-check" in data:
                found = True
                records = data["_health-check"]
                txt_records = [r for r in records if r.get("type") == "TXT"]
                assert len(txt_records) > 0, (
                    f"{filename}: _health-check has no TXT record"
                )
        assert found, "No zone file contains a _health-check record"

    def test_health_check_ttl_is_low(self, zone_files):
        """The _health-check record should have a low TTL for fast detection."""
        for filename, data in zone_files.items():
            if "_health-check" in data:
                for record in data["_health-check"]:
                    if record.get("type") == "TXT" and "ttl" in record:
                        assert record["ttl"] <= 300, (
                            f"{filename}: _health-check TTL {record['ttl']} "
                            f"is too high for monitoring (should be <= 300)"
                        )

    def test_a_records_have_valid_ipv4(self, zone_files):
        """All A records must contain valid IPv4 addresses."""
        for filename, data in zone_files.items():
            for name, records in data.items():
                if not isinstance(records, list):
                    continue
                for record in records:
                    if record.get("type") != "A":
                        continue
                    value = record.get("value")
                    if value:
                        assert validate_ipv4(value), (
                            f"{filename}::{name} invalid IPv4: {value}"
                        )

    def test_cname_records_are_not_at_apex(self, zone_files):
        """CNAME records must not be at the zone apex (empty string key)."""
        for filename, data in zone_files.items():
            apex_records = data.get("", [])
            if not isinstance(apex_records, list):
                continue
            for record in apex_records:
                assert record.get("type") != "CNAME", (
                    f"{filename}: CNAME at zone apex is invalid per RFC 1034"
                )

    def test_ttls_are_within_range(self, zone_files):
        """All TTL values must be within a reasonable range (1 to 604800)."""
        for filename, data in zone_files.items():
            for name, records in data.items():
                if not isinstance(records, list):
                    continue
                for record in records:
                    if "ttl" in record:
                        assert validate_ttl(record["ttl"]), (
                            f"{filename}::{name} TTL {record['ttl']} out of range"
                        )

    def test_mx_records_have_preference(self, zone_files):
        """MX records must include both exchange and preference."""
        for filename, data in zone_files.items():
            for name, records in data.items():
                if not isinstance(records, list):
                    continue
                for record in records:
                    if record.get("type") != "MX":
                        continue
                    values = record.get("values", [])
                    for mx in values:
                        assert "exchange" in mx, (
                            f"{filename}::{name} MX missing 'exchange'"
                        )
                        assert "preference" in mx, (
                            f"{filename}::{name} MX missing 'preference'"
                        )


# ---------------------------------------------------------------------------
# Zone <-> Config Consistency Tests
# ---------------------------------------------------------------------------

class TestZoneConfigConsistency:
    """Ensure zone files and the OctoDNS config are aligned."""

    def test_each_config_zone_has_a_zone_file(self, config_data, zones_dir):
        """Every zone referenced in the config has a matching YAML file."""
        for zone_name in config_data.get("zones", {}):
            # Zone name is FQDN: "example.com." -> file "example.com.yaml"
            filename = zone_name.rstrip(".") + ".yaml"
            zone_path = zones_dir / filename
            assert zone_path.exists(), (
                f"Config references zone '{zone_name}' but "
                f"zone file {zone_path} not found"
            )

    def test_zone_files_are_referenced_in_config(self, config_data, zone_files):
        """Every zone file on disk should be referenced in the config."""
        config_zones = set()
        for zone_name in config_data.get("zones", {}):
            config_zones.add(zone_name.rstrip(".") + ".yaml")

        for filename in zone_files:
            assert filename in config_zones, (
                f"Zone file '{filename}' exists but is not referenced in config"
            )


# ---------------------------------------------------------------------------
# Synthetic / Edge Case Tests (no disk dependencies)
# ---------------------------------------------------------------------------

class TestRecordValidation:
    """Unit-level tests for the record and zone validators."""

    def test_valid_a_record(self):
        errors = validate_record({"type": "A", "value": "1.2.3.4", "ttl": 300})
        assert errors == []

    def test_invalid_a_record_ip(self):
        errors = validate_record({"type": "A", "value": "999.999.999.999"})
        assert any("Invalid IPv4" in e for e in errors)

    def test_a_record_missing_value(self):
        errors = validate_record({"type": "A"})
        assert any("missing" in e.lower() for e in errors)

    def test_valid_cname_record(self):
        errors = validate_record({
            "type": "CNAME",
            "value": "target.example.com.",
            "ttl": 300,
        })
        assert errors == []

    def test_cname_empty_value(self):
        errors = validate_record({"type": "CNAME", "value": ""})
        assert any("CNAME" in e for e in errors)

    def test_valid_mx_record(self):
        errors = validate_record({
            "type": "MX",
            "values": [{"exchange": "mail.example.com.", "preference": 10}],
        })
        assert errors == []

    def test_mx_missing_exchange(self):
        errors = validate_record({
            "type": "MX",
            "values": [{"preference": 10}],
        })
        assert any("exchange" in e for e in errors)

    def test_mx_missing_preference(self):
        errors = validate_record({
            "type": "MX",
            "values": [{"exchange": "mail.example.com."}],
        })
        assert any("preference" in e for e in errors)

    def test_valid_txt_record(self):
        errors = validate_record({
            "type": "TXT",
            "value": "v=spf1 include:_spf.google.com ~all",
        })
        assert errors == []

    def test_txt_missing_value(self):
        errors = validate_record({"type": "TXT"})
        assert any("TXT" in e for e in errors)

    def test_invalid_record_type(self):
        errors = validate_record({"type": "INVALID"})
        assert any("Invalid record type" in e for e in errors)

    def test_invalid_ttl_negative(self):
        errors = validate_record({"type": "A", "value": "1.2.3.4", "ttl": -1})
        assert any("Invalid TTL" in e for e in errors)

    def test_invalid_ttl_zero(self):
        errors = validate_record({"type": "A", "value": "1.2.3.4", "ttl": 0})
        assert any("Invalid TTL" in e for e in errors)

    def test_ttl_max_boundary(self):
        errors = validate_record({"type": "A", "value": "1.2.3.4", "ttl": 604800})
        assert errors == []

    def test_ttl_over_max(self):
        errors = validate_record({"type": "A", "value": "1.2.3.4", "ttl": 604801})
        assert any("Invalid TTL" in e for e in errors)

    def test_record_is_not_a_dict(self):
        errors = validate_record("not a dict")
        assert any("not a dict" in e for e in errors)

    def test_valid_aaaa_record(self):
        errors = validate_record({"type": "AAAA", "value": "2001:db8::1"})
        assert errors == []

    def test_invalid_aaaa_record(self):
        errors = validate_record({"type": "AAAA", "value": "not-ipv6"})
        assert any("Invalid IPv6" in e for e in errors)


class TestZoneValidation:
    """Tests for whole-zone validation on synthetic data."""

    def test_valid_zone(self):
        zone = _parse_zone_yaml(textwrap.dedent("""\
            '':
              - type: A
                value: 1.2.3.4
                ttl: 300
            www:
              - type: CNAME
                value: example.com.
                ttl: 300
        """))
        issues = validate_zone(zone)
        assert issues == []

    def test_zone_with_invalid_record(self):
        zone = _parse_zone_yaml(textwrap.dedent("""\
            bad:
              - type: A
                value: not-an-ip
        """))
        issues = validate_zone(zone)
        assert len(issues) > 0
        assert any("Invalid IPv4" in err for _, err in issues)

    def test_zone_root_is_not_dict(self):
        issues = validate_zone("just a string")
        assert len(issues) == 1
        assert issues[0][0] == "_root"

    def test_zone_records_not_a_list(self):
        zone = {"www": "should be a list"}
        issues = validate_zone(zone)
        assert len(issues) == 1
        assert "list" in issues[0][1].lower()

    def test_empty_zone_is_valid(self):
        """An empty zone dict has no records to validate."""
        issues = validate_zone({})
        assert issues == []


class TestIPValidation:
    """Tests for IP address validators."""

    @pytest.mark.parametrize("ip", ["1.2.3.4", "0.0.0.0", "255.255.255.255", "10.0.0.1"])
    def test_valid_ipv4(self, ip):
        assert validate_ipv4(ip) is True

    @pytest.mark.parametrize("ip", ["256.1.1.1", "abc", "", "1.2.3", "1.2.3.4.5"])
    def test_invalid_ipv4(self, ip):
        assert validate_ipv4(ip) is False

    @pytest.mark.parametrize("ip", ["::1", "2001:db8::1", "fe80::1%eth0"])
    def test_valid_ipv6(self, ip):
        assert validate_ipv6(ip) is True

    @pytest.mark.parametrize("ip", ["not-ipv6", "1.2.3.4", ""])
    def test_invalid_ipv6(self, ip):
        assert validate_ipv6(ip) is False


class TestFQDNValidation:
    """Tests for FQDN validation helper."""

    def test_fqdn_with_dot(self):
        assert validate_fqdn("example.com.") is True

    def test_fqdn_without_dot(self):
        assert validate_fqdn("example.com") is False

    def test_fqdn_not_a_string(self):
        assert validate_fqdn(123) is False

    def test_fqdn_empty(self):
        assert validate_fqdn("") is False
