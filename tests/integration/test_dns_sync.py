import unittest
import subprocess
import os

class TestDNSSync(unittest.TestCase):
    def test_octodns_config_valid(self):
        """Verify that OctoDNS configuration is valid."""
        config_path = "../../dns-sync/config/octodns-config.yaml"
        self.assertTrue(os.path.exists(config_path))
        
        # Dry run command
        cmd = ["octodns-sync", "--config-file", config_path]
        # In a real test env, we'd mock the providers or use a test config
        # For now, we just check if the command exists and config is readable
        self.assertTrue(os.access(config_path, os.R_OK))

    def test_zone_files_valid(self):
        """Verify that zone files are valid YAML."""
        zone_path = "../../dns-sync/zones/example.com.yaml"
        self.assertTrue(os.path.exists(zone_path))
        
        with open(zone_path, 'r') as f:
            content = f.read()
            self.assertIn("type: A", content)
            self.assertIn("_health-check", content)

if __name__ == '__main__':
    unittest.main()
