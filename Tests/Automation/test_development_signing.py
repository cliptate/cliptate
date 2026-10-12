"""Select a stable development certificate without using a distribution certificate."""

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("development_signing", ROOT / "scripts/development-signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class DevelopmentSigningTests(unittest.TestCase):
    def test_development_identity_is_selected_instead_of_developer_id(self):
        output = ('1) ' + 'A' * 40 + ' "Developer ID Application: Example (TEAM123456)"\n'
                  '2) ' + 'B' * 40 + ' "Apple Development: Example (TEAM123456)"\n')
        self.assertEqual(signing.select_identity(output), ('B' * 40, 'TEAM123456'))

    def test_team_selects_the_intended_development_identity(self):
        output = ('1) ' + 'A' * 40 + ' "Apple Development: One (TEAM123456)"\n'
                  '2) ' + 'B' * 40 + ' "Apple Development: Two (TEAM654321)"\n')
        self.assertEqual(signing.select_identity(output, 'TEAM654321'), ('B' * 40, 'TEAM654321'))
        with self.assertRaisesRegex(ValueError, 'explicitly'):
            signing.select_identity(output)

    def test_no_certificate_allows_public_source_builds(self):
        self.assertEqual(signing.select_identity('0 valid identities found'), ('-', ''))


if __name__ == "__main__":
    unittest.main()
