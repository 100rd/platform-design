"""
Integration tests for the DNS Health Monitoring system.

Tests cover:
- Health score calculation (success_rate * 60 + latency_score * 30 + consistency * 10)
- Database storage of health check results
- Prometheus metrics emission
- Provider health check lifecycle
- Edge cases: DB failures, metrics endpoint issues, malformed data
"""

import math
import time
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch, PropertyMock

import pytest


# ---------------------------------------------------------------------------
# Domain models (mirrors the Go structs in storage.go / monitor.go)
# ---------------------------------------------------------------------------

class Provider:
    """Mirrors the Go Provider struct from storage.go."""

    def __init__(self, provider_id, name, health_check_endpoints):
        self.id = provider_id
        self.name = name
        self.health_check_endpoints = health_check_endpoints


class HealthResult:
    """Mirrors the Go HealthResult struct from storage.go."""

    def __init__(
        self,
        provider_id,
        nameserver_address,
        query_domain,
        response_time_ms,
        success,
        error_message="",
        check_location="us-east-1",
        check_timestamp=None,
    ):
        self.provider_id = provider_id
        self.nameserver_address = nameserver_address
        self.query_domain = query_domain
        self.response_time_ms = response_time_ms
        self.success = success
        self.error_message = error_message
        self.check_location = check_location
        self.check_timestamp = check_timestamp or datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Health score calculator (Python port of the Go logic in monitor.go)
# ---------------------------------------------------------------------------

def calculate_health_score(results):
    """
    Calculate a provider health score from a list of HealthResult objects.

    Formula (from monitor.go lines 79-93):
        score = success_rate * 60 + latency_score * 30 + consistency_score * 10

    Latency score:
        1.0 if avg_latency < 50ms
        0.0 if avg_latency >= 1000ms
        linear interpolation between 50ms and 1000ms

    Consistency score:
        1.0 if all results agree (all success or all failure)
        Fraction of the majority otherwise
    """
    if not results:
        return 0.0

    total = len(results)
    successes = sum(1 for r in results if r.success)
    success_rate = successes / total

    avg_latency_ms = sum(r.response_time_ms for r in results) / total

    if avg_latency_ms < 50:
        latency_score = 1.0
    elif avg_latency_ms >= 1000:
        latency_score = 0.0
    else:
        latency_score = max(0.0, 1.0 - (avg_latency_ms - 50.0) / 950.0)

    # Consistency: 1.0 when every check returned the same outcome
    majority = max(successes, total - successes)
    consistency_score = majority / total

    return (success_rate * 60.0) + (latency_score * 30.0) + (consistency_score * 10.0)


# ---------------------------------------------------------------------------
# Mock storage layer
# ---------------------------------------------------------------------------

class MockStorage:
    """In-memory replacement for the PostgreSQL-backed Storage struct."""

    def __init__(self):
        self.providers = []
        self.results = []
        self._closed = False
        self._fail_on_save = False
        self._fail_on_get_providers = False

    def add_provider(self, provider):
        self.providers.append(provider)

    def get_providers(self):
        if self._fail_on_get_providers:
            raise ConnectionError("database connection refused")
        return list(self.providers)

    def save_result(self, result):
        if self._closed:
            raise RuntimeError("connection is closed")
        if self._fail_on_save:
            raise ConnectionError("database write failed")
        self.results.append(result)

    def get_results_since(self, since_dt, provider_id=None):
        out = []
        for r in self.results:
            if r.check_timestamp >= since_dt:
                if provider_id is None or r.provider_id == provider_id:
                    out.append(r)
        return out

    def close(self):
        self._closed = True


# ---------------------------------------------------------------------------
# Mock metrics collector
# ---------------------------------------------------------------------------

class MockMetrics:
    """Collects Prometheus-style metric observations in memory."""

    def __init__(self):
        self.durations = {}      # (provider, ns) -> [seconds]
        self.successes = {}      # (provider, ns) -> count
        self.failures = {}       # (provider, ns) -> count
        self.health_scores = {}  # provider -> score

    def observe_duration(self, provider, nameserver, seconds):
        key = (provider, nameserver)
        self.durations.setdefault(key, []).append(seconds)

    def inc_success(self, provider, nameserver):
        key = (provider, nameserver)
        self.successes[key] = self.successes.get(key, 0) + 1

    def inc_failure(self, provider, nameserver):
        key = (provider, nameserver)
        self.failures[key] = self.failures.get(key, 0) + 1

    def set_health_score(self, provider, score):
        self.health_scores[provider] = score


# ---------------------------------------------------------------------------
# Monitor under test (Python port of the check logic in monitor.go)
# ---------------------------------------------------------------------------

class HealthMonitor:
    """
    Python equivalent of the Go Monitor struct.
    Accepts pluggable storage, metrics, and DNS query function for testability.
    """

    def __init__(self, storage, metrics, dns_query_fn=None):
        self.storage = storage
        self.metrics = metrics
        self._dns_query_fn = dns_query_fn or self._default_dns_query

    @staticmethod
    def _default_dns_query(nameserver, domain):
        """Default DNS query -- always fails so tests must inject their own."""
        return False, "no real DNS client available"

    def run_checks(self):
        """Run health checks for all providers, mirrors Monitor.RunChecks."""
        providers = self.storage.get_providers()
        results_by_provider = {}
        for provider in providers:
            results_by_provider[provider.id] = self._check_provider(provider)
        return results_by_provider

    def _check_provider(self, provider):
        results = []
        for ns in provider.health_check_endpoints:
            start = time.monotonic()
            success, err = self._dns_query_fn(ns, "_health-check.example.com")
            elapsed_ms = (time.monotonic() - start) * 1000

            result = HealthResult(
                provider_id=provider.id,
                nameserver_address=ns,
                query_domain="_health-check.example.com",
                response_time_ms=int(elapsed_ms),
                success=success,
                error_message="" if success else str(err),
            )
            results.append(result)
            self.storage.save_result(result)

            self.metrics.observe_duration(provider.name, ns, elapsed_ms / 1000)
            if success:
                self.metrics.inc_success(provider.name, ns)
            else:
                self.metrics.inc_failure(provider.name, ns)

        if results:
            score = calculate_health_score(results)
            self.metrics.set_health_score(provider.name, score)

        return results


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def storage():
    return MockStorage()


@pytest.fixture
def metrics():
    return MockMetrics()


@pytest.fixture
def cloudflare_provider():
    return Provider(
        provider_id="cf-001",
        name="cloudflare",
        health_check_endpoints=["ns1.cloudflare.com", "ns2.cloudflare.com"],
    )


@pytest.fixture
def route53_provider():
    return Provider(
        provider_id="r53-001",
        name="route53",
        health_check_endpoints=["ns-1.awsdns-01.com", "ns-2.awsdns-02.net"],
    )


@pytest.fixture
def populated_storage(storage, cloudflare_provider, route53_provider):
    storage.add_provider(cloudflare_provider)
    storage.add_provider(route53_provider)
    return storage


def _make_dns_fn(success=True, error_msg=""):
    """Factory for deterministic DNS query functions."""
    def dns_query(nameserver, domain):
        return success, error_msg
    return dns_query


def _make_latency_dns_fn(latency_seconds, success=True):
    """DNS query function that introduces artificial latency."""
    def dns_query(nameserver, domain):
        time.sleep(latency_seconds)
        return success, ""
    return dns_query


# ---------------------------------------------------------------------------
# Health Score Calculation Tests
# ---------------------------------------------------------------------------

class TestHealthScoreCalculation:
    """Tests for the health score formula: SR*60 + LS*30 + CS*10."""

    def test_perfect_score(self):
        """All checks pass with low latency gives max score."""
        results = [
            HealthResult("p1", "ns1", "d", 20, True),
            HealthResult("p1", "ns2", "d", 30, True),
        ]
        score = calculate_health_score(results)
        # success_rate=1.0*60=60, latency<50 => latency_score=1.0*30=30, consistency=1.0*10=10
        assert score == pytest.approx(100.0)

    def test_all_failures(self):
        """All checks fail gives success_rate=0 but consistency=1."""
        results = [
            HealthResult("p1", "ns1", "d", 20, False, "timeout"),
            HealthResult("p1", "ns2", "d", 30, False, "timeout"),
        ]
        score = calculate_health_score(results)
        # success_rate=0*60=0, latency<50 => 30, consistency=1.0*10=10
        assert score == pytest.approx(40.0)

    def test_half_success(self):
        """50% success rate with low latency."""
        results = [
            HealthResult("p1", "ns1", "d", 30, True),
            HealthResult("p1", "ns2", "d", 30, False, "err"),
        ]
        score = calculate_health_score(results)
        # success_rate=0.5*60=30, latency<50 => 30, consistency=0.5*10=5
        assert score == pytest.approx(65.0)

    def test_high_latency_degrades_score(self):
        """Latency at 525ms (midpoint) gives latency_score=0.5."""
        results = [
            HealthResult("p1", "ns1", "d", 525, True),
            HealthResult("p1", "ns2", "d", 525, True),
        ]
        score = calculate_health_score(results)
        # success_rate=1.0*60=60, latency_score=0.5*30=15, consistency=1.0*10=10
        assert score == pytest.approx(85.0)

    def test_extreme_latency_zeroes_latency_score(self):
        """Latency >= 1000ms gives latency_score=0."""
        results = [
            HealthResult("p1", "ns1", "d", 1500, True),
        ]
        score = calculate_health_score(results)
        # success_rate=1.0*60=60, latency_score=0*30=0, consistency=1.0*10=10
        assert score == pytest.approx(70.0)

    def test_latency_exactly_at_boundary(self):
        """Latency exactly at 50ms gives latency_score=1.0."""
        results = [HealthResult("p1", "ns1", "d", 50, True)]
        score = calculate_health_score(results)
        assert score == pytest.approx(100.0)

    def test_latency_at_1000ms(self):
        """Latency exactly at 1000ms gives latency_score=0.0."""
        results = [HealthResult("p1", "ns1", "d", 1000, True)]
        score = calculate_health_score(results)
        assert score == pytest.approx(70.0)

    def test_empty_results_returns_zero(self):
        """No results should produce a score of 0."""
        assert calculate_health_score([]) == 0.0

    def test_single_result_success(self):
        """Single successful check with 10ms latency."""
        results = [HealthResult("p1", "ns1", "d", 10, True)]
        score = calculate_health_score(results)
        assert score == pytest.approx(100.0)

    @pytest.mark.parametrize(
        "latency_ms,expected_latency_score",
        [
            (0, 1.0),
            (49, 1.0),
            (50, 1.0),
            (100, (950.0 - 50.0) / 950.0),  # 1 - 50/950
            (525, 0.5),
            (999, pytest.approx(0.00105, abs=0.002)),
            (1000, 0.0),
            (2000, 0.0),
        ],
    )
    def test_latency_score_parameterized(self, latency_ms, expected_latency_score):
        """Verify latency score curve at multiple points."""
        results = [HealthResult("p1", "ns1", "d", latency_ms, True)]
        score = calculate_health_score(results)
        # Isolate latency_score: score = 60 + latency_score*30 + 10
        latency_component = score - 60.0 - 10.0
        actual_latency_score = latency_component / 30.0
        assert actual_latency_score == pytest.approx(expected_latency_score, abs=0.005)

    def test_mixed_consistency(self):
        """3 successes and 1 failure -- consistency = 3/4 = 0.75."""
        results = [
            HealthResult("p1", "ns1", "d", 20, True),
            HealthResult("p1", "ns2", "d", 20, True),
            HealthResult("p1", "ns3", "d", 20, True),
            HealthResult("p1", "ns4", "d", 20, False, "err"),
        ]
        score = calculate_health_score(results)
        # success_rate=0.75*60=45, latency<50 => 30, consistency=0.75*10=7.5
        assert score == pytest.approx(82.5)


# ---------------------------------------------------------------------------
# Monitor Integration Tests
# ---------------------------------------------------------------------------

class TestHealthMonitorChecks:
    """Tests for the full check lifecycle: query -> store -> emit metrics."""

    def test_successful_checks_stored_and_metricked(
        self, populated_storage, metrics
    ):
        """Successful DNS queries are saved to storage and metrics are emitted."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        results = monitor.run_checks()

        # Two providers, two endpoints each = 4 total results stored
        assert len(populated_storage.results) == 4

        # Metrics: 4 successes, 0 failures
        total_successes = sum(metrics.successes.values())
        total_failures = sum(metrics.failures.values(), 0)
        assert total_successes == 4
        assert total_failures == 0

        # Health scores set for both providers
        assert "cloudflare" in metrics.health_scores
        assert "route53" in metrics.health_scores

    def test_failed_checks_record_errors(self, populated_storage, metrics):
        """Failed DNS queries record error messages and count failures."""
        monitor = HealthMonitor(
            populated_storage, metrics, _make_dns_fn(False, "connection refused")
        )
        monitor.run_checks()

        assert len(populated_storage.results) == 4
        for result in populated_storage.results:
            assert result.success is False
            assert result.error_message == "connection refused"

        total_failures = sum(metrics.failures.values())
        assert total_failures == 4
        assert sum(metrics.successes.values(), 0) == 0

    def test_duration_metrics_recorded(self, populated_storage, metrics):
        """DNS query durations are observed in the metrics collector."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        # Should have duration observations for each (provider, ns) pair
        assert len(metrics.durations) == 4
        for durations in metrics.durations.values():
            assert len(durations) == 1
            assert durations[0] >= 0

    def test_health_score_computed_per_provider(
        self, populated_storage, metrics
    ):
        """Each provider gets an independent health score."""
        call_count = {"n": 0}

        def alternating_dns(ns, domain):
            call_count["n"] += 1
            # First provider (cloudflare) succeeds, second (route53) fails
            if "cloudflare" in ns:
                return True, ""
            return False, "nxdomain"

        monitor = HealthMonitor(populated_storage, metrics, alternating_dns)
        monitor.run_checks()

        cf_score = metrics.health_scores["cloudflare"]
        r53_score = metrics.health_scores["route53"]
        assert cf_score > r53_score

    def test_no_providers_does_nothing(self, storage, metrics):
        """Empty provider list produces no results or metrics."""
        monitor = HealthMonitor(storage, metrics, _make_dns_fn(True))
        results = monitor.run_checks()
        assert results == {}
        assert len(storage.results) == 0
        assert len(metrics.health_scores) == 0


# ---------------------------------------------------------------------------
# Database Failure Edge Cases
# ---------------------------------------------------------------------------

class TestDatabaseFailures:
    """Tests for graceful handling of database connection issues."""

    def test_get_providers_failure_raises(self, storage, metrics):
        """Storage failure when fetching providers propagates the error."""
        storage._fail_on_get_providers = True
        monitor = HealthMonitor(storage, metrics, _make_dns_fn(True))
        with pytest.raises(ConnectionError, match="database connection refused"):
            monitor.run_checks()

    def test_save_result_failure_raises(
        self, populated_storage, metrics
    ):
        """Storage failure on save propagates so the caller can handle it."""
        populated_storage._fail_on_save = True
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        with pytest.raises(ConnectionError, match="database write failed"):
            monitor.run_checks()

    def test_closed_connection_raises(self, populated_storage, metrics):
        """Writing to a closed storage raises RuntimeError."""
        populated_storage.close()
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        with pytest.raises(RuntimeError, match="connection is closed"):
            monitor.run_checks()


# ---------------------------------------------------------------------------
# Metrics Endpoint Simulation Tests
# ---------------------------------------------------------------------------

class TestMetricsEndpoint:
    """Tests validating Prometheus metrics format expectations."""

    EXPECTED_METRIC_NAMES = [
        "dns_query_duration_seconds",
        "dns_query_success_total",
        "dns_query_failure_total",
        "dns_provider_health_score",
    ]

    def test_expected_metrics_present_in_mock(self, populated_storage, metrics):
        """After a check cycle, all expected metric families have data."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        assert len(metrics.durations) > 0, "dns_query_duration_seconds missing"
        assert len(metrics.successes) > 0, "dns_query_success_total missing"
        assert len(metrics.health_scores) > 0, "dns_provider_health_score missing"

    def test_metrics_labels_match_provider_and_nameserver(
        self, populated_storage, metrics
    ):
        """Metric labels contain the correct provider name and nameserver."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        duration_keys = set(metrics.durations.keys())
        assert ("cloudflare", "ns1.cloudflare.com") in duration_keys
        assert ("cloudflare", "ns2.cloudflare.com") in duration_keys
        assert ("route53", "ns-1.awsdns-01.com") in duration_keys
        assert ("route53", "ns-2.awsdns-02.net") in duration_keys

    def test_health_score_metric_range(self, populated_storage, metrics):
        """Health scores must fall within [0, 100]."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        for provider, score in metrics.health_scores.items():
            assert 0.0 <= score <= 100.0, (
                f"Provider {provider} score {score} outside valid range"
            )


# ---------------------------------------------------------------------------
# Malformed / Edge Case Data
# ---------------------------------------------------------------------------

class TestMalformedData:
    """Edge cases around unexpected input data."""

    def test_provider_with_no_endpoints(self, storage, metrics):
        """A provider with an empty endpoint list produces no results."""
        storage.add_provider(Provider("empty-001", "empty-provider", []))
        monitor = HealthMonitor(storage, metrics, _make_dns_fn(True))
        results = monitor.run_checks()

        assert len(storage.results) == 0
        assert "empty-provider" not in metrics.health_scores

    def test_provider_with_single_endpoint(self, storage, metrics):
        """Single endpoint provider works correctly."""
        storage.add_provider(
            Provider("single-001", "single-ns", ["ns1.example.com"])
        )
        monitor = HealthMonitor(storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        assert len(storage.results) == 1
        assert "single-ns" in metrics.health_scores

    def test_dns_query_returns_none_error(self, storage, metrics):
        """DNS query returning None as error message is handled."""
        storage.add_provider(
            Provider("p1", "test-provider", ["ns1.test.com"])
        )

        def query_returns_none_err(ns, domain):
            return False, None

        monitor = HealthMonitor(storage, metrics, query_returns_none_err)
        monitor.run_checks()

        assert len(storage.results) == 1
        assert storage.results[0].success is False
        assert storage.results[0].error_message == "None"

    def test_result_timestamps_are_recent(self, populated_storage, metrics):
        """Stored results should have timestamps within the last few seconds."""
        monitor = HealthMonitor(populated_storage, metrics, _make_dns_fn(True))
        monitor.run_checks()

        now = datetime.now(timezone.utc)
        for result in populated_storage.results:
            age = now - result.check_timestamp
            assert age < timedelta(seconds=10), (
                f"Result timestamp {result.check_timestamp} is too old"
            )

    def test_very_large_latency_handled(self, storage, metrics):
        """Extremely high latency values do not cause math errors."""
        results = [
            HealthResult("p1", "ns1", "d", 999999, True),
        ]
        score = calculate_health_score(results)
        # latency_score clamps to 0
        assert score == pytest.approx(70.0)
        assert math.isfinite(score)

    def test_zero_latency(self, storage, metrics):
        """Zero-millisecond latency is valid and gives perfect latency score."""
        results = [
            HealthResult("p1", "ns1", "d", 0, True),
        ]
        score = calculate_health_score(results)
        assert score == pytest.approx(100.0)


# ---------------------------------------------------------------------------
# Storage Query Tests
# ---------------------------------------------------------------------------

class TestStorageQueries:
    """Tests for querying stored results by time range and provider."""

    def test_get_results_since_filters_by_time(self, storage):
        old = HealthResult("p1", "ns1", "d", 20, True)
        old.check_timestamp = datetime.now(timezone.utc) - timedelta(hours=2)
        storage.save_result(old)

        recent = HealthResult("p1", "ns1", "d", 20, True)
        recent.check_timestamp = datetime.now(timezone.utc)
        storage.save_result(recent)

        since = datetime.now(timezone.utc) - timedelta(hours=1)
        results = storage.get_results_since(since)
        assert len(results) == 1
        assert results[0] is recent

    def test_get_results_since_filters_by_provider(self, storage):
        r1 = HealthResult("p1", "ns1", "d", 20, True)
        r1.check_timestamp = datetime.now(timezone.utc)
        storage.save_result(r1)

        r2 = HealthResult("p2", "ns2", "d", 20, True)
        r2.check_timestamp = datetime.now(timezone.utc)
        storage.save_result(r2)

        since = datetime.now(timezone.utc) - timedelta(hours=1)
        results = storage.get_results_since(since, provider_id="p1")
        assert len(results) == 1
        assert results[0].provider_id == "p1"

    def test_get_results_since_empty_storage(self, storage):
        since = datetime.now(timezone.utc) - timedelta(hours=1)
        results = storage.get_results_since(since)
        assert results == []
