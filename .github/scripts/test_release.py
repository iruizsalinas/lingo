import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import hex_release
from package_release import package_release
from release_version import bump_package, next_version


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="lingo-release-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / "mix.exs").write_text('defmodule Project do\n  @version "0.4.0"\nend\n')
        (self.root / "README.md").write_text('{:lingo, "~> 0.4.0"}\nHistorical 0.3.0 release\n')

    def artifacts(self):
        directory = self.root / ".release"
        directory.mkdir()
        (directory / "package.tar").write_bytes(b"package")
        (self.root / "doc").mkdir()
        (self.root / "doc/index.html").write_text("<html>docs</html>")
        with patch("package_release.subprocess.check_output", return_value="a" * 40):
            package_release(self.root)
        return directory

    def test_version_choices(self):
        for bump, expected in (("patch", "0.4.1"), ("minor", "0.5.0"), ("major", "1.0.0"), ("current", "0.4.0")):
            with self.subTest(bump=bump):
                self.assertEqual(next_version("0.4.0", bump), expected)
        for version, bump in (("0.4.0-rc.1", "patch"), ("01.0.0", "patch"), ("0.4.0", "invalid")):
            with self.subTest(version=version), self.assertRaises(ValueError):
                next_version(version, bump)

    def test_bump_updates_project_and_install_example(self):
        self.assertEqual(bump_package(self.root, "patch"), "0.4.1")
        self.assertIn('@version "0.4.1"', (self.root / "mix.exs").read_text())
        self.assertEqual((self.root / "README.md").read_text(), '{:lingo, "~> 0.4.1"}\nHistorical 0.3.0 release\n')

    def test_current_preserves_files(self):
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        bump_package(self.root, "current")
        self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)

    def test_missing_install_reference_fails_before_project_write(self):
        project = (self.root / "mix.exs").read_bytes()
        (self.root / "README.md").write_text("missing installation example")
        with self.assertRaises(ValueError):
            bump_package(self.root, "patch")
        self.assertEqual((self.root / "mix.exs").read_bytes(), project)

    def test_artifact_checks_commit_version_and_hashes(self):
        directory = self.artifacts()
        hex_release.validate_artifacts(directory, "0.4.0", "a" * 40)
        for version, commit in (("0.4.1", "a" * 40), ("0.4.0", "b" * 40)):
            with self.assertRaises(ValueError):
                hex_release.validate_artifacts(directory, version, commit)
        (directory / "package.tar").write_bytes(b"modified")
        with self.assertRaises(ValueError):
            hex_release.validate_artifacts(directory, "0.4.0", "a" * 40)

    def test_registry_404_is_missing_but_server_errors_stop(self):
        for status in (404, 401, 429, 503):
            error = urllib.error.HTTPError("https://hex.pm/test", status, "failure", {}, None)
            with patch("urllib.request.urlopen", side_effect=error):
                if status == 404:
                    self.assertIsNone(hex_release.get_release("0.4.1"))
                else:
                    with self.assertRaises(RuntimeError):
                        hex_release.get_release("0.4.1")

    def test_api_key_authentication_has_no_token_exchange(self):
        with patch.dict(os.environ, {"HEX_API_KEY": "test-api-key"}), patch("hex_release.request_json") as request, patch("builtins.print") as output:
            self.assertEqual(hex_release.authenticate(), "test-api-key")
            request.assert_not_called()
            output.assert_called_once_with("::add-mask::test-api-key", flush=True)

    def test_missing_or_invalid_api_key_is_rejected(self):
        for value in ("", " ", "key\nsecond-line", " key", "key "):
            with self.subTest(value=value), patch.dict(os.environ, {"HEX_API_KEY": value}), self.assertRaisesRegex(ValueError, "HEX_API_KEY"):
                hex_release.authenticate()

    def test_publishes_artifacts_and_retries_identical_package_without_replacing(self):
        directory = self.artifacts()
        checksum = hashlib.sha256(b"package").hexdigest()
        for existing, expected_calls in ((None, 2), ({"checksum": checksum}, 1)):
            with patch("hex_release.get_release", return_value=existing), patch("hex_release.authenticate", return_value="fake-token"), patch("hex_release.request_json", return_value={}) as request, patch("builtins.print"):
                hex_release.publish(directory, "0.4.0", "a" * 40)
                self.assertEqual(request.call_count, expected_calls)
                for call in request.call_args_list:
                    self.assertEqual(call.kwargs["headers"]["Authorization"], "fake-token")
                self.assertTrue(request.call_args.args[0].endswith("/0.4.0/docs"))
                if existing is None:
                    self.assertTrue(request.call_args_list[0].args[0].endswith("?replace=false"))
                    self.assertEqual(request.call_args_list[0].kwargs["data"], b"package")

    def test_conflicting_published_package_stops_before_authentication(self):
        directory = self.artifacts()
        with patch("hex_release.get_release", return_value={"checksum": "different"}), patch("hex_release.authenticate") as authenticate:
            with self.assertRaises(ValueError):
                hex_release.publish(directory, "0.4.0", "a" * 40)
            authenticate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
