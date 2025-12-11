import unittest
import time
import requests
import psycopg2
import os

class TestHealthMonitoring(unittest.TestCase):
    def setUp(self):
        self.db_conn = psycopg2.connect(os.getenv("DATABASE_URL"))
        self.metrics_url = "http://localhost:8080/metrics"

    def tearDown(self):
        self.db_conn.close()

    def test_health_checks_running(self):
        """Verify that health checks are being recorded in the database."""
        # Wait for a check cycle
        time.sleep(35)
        
        cur = self.db_conn.cursor()
        cur.execute("SELECT COUNT(*) FROM health_check_results WHERE check_timestamp > NOW() - INTERVAL '1 minute'")
        count = cur.fetchone()[0]
        self.assertTrue(count > 0, "No health checks recorded in the last minute")

    def test_metrics_emission(self):
        """Verify that Prometheus metrics are being exposed."""
        response = requests.get(self.metrics_url)
        self.assertEqual(response.status_code, 200)
        self.assertIn("dns_provider_health_score", response.text)
        self.assertIn("dns_query_duration_seconds", response.text)

if __name__ == '__main__':
    unittest.main()
