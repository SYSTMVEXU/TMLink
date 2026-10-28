import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from github_actions import GitHubActions, GitHubBuildError


class GitHubActionsTests(unittest.TestCase):
    def setUp(self):
        with patch("github_actions.shutil.which", return_value="/test/gh"):
            self.github = GitHubActions()

    def test_missing_cli_explains_one_time_setup(self):
        with patch("github_actions.shutil.which", return_value=None):
            with self.assertRaisesRegex(GitHubBuildError, "gh auth login"):
                GitHubActions()

    def test_cli_failure_does_not_print_api_payloads(self):
        result = subprocess.CompletedProcess([], 1, "sensitive-payload", "sensitive-token")
        with patch("github_actions.subprocess.run", return_value=result):
            with self.assertRaises(GitHubBuildError) as caught:
                self.github.command(["api", "example"])
        self.assertNotIn("sensitive", str(caught.exception))

    def test_dispatch_sends_inputs_through_stdin_and_correlates_request(self):
        self.github.command = Mock(return_value="")
        request_id = self.github.dispatch("release.yml", "main", {"target": "macos"})
        arguments = self.github.command.call_args.args[0]
        parameters = json.loads(self.github.command.call_args.kwargs["input_data"])
        self.assertIn("--json", arguments)
        self.assertEqual(parameters, {"target": "macos", "request_id": request_id})
        self.assertEqual(len(request_id), 32)

    def test_wait_selects_only_its_own_run(self):
        self.github.json_command = Mock(return_value=[
            {"displayTitle": "Local build someone-else", "databaseId": 1},
            {"displayTitle": "Local build ours", "databaseId": 2, "headSha": "expected",
             "status": "completed", "conclusion": "success"},
        ])
        self.assertEqual(self.github.wait("release.yml", "ours", "expected"), 2)

    def test_wrong_commit_or_failed_workflow_never_returns_an_artifact_source(self):
        for commit, conclusion in (("unexpected", "success"), ("expected", "failure")):
            self.github.json_command = Mock(return_value=[{
                "displayTitle": "Local build ours", "databaseId": 2,
                "headSha": commit, "status": "completed", "conclusion": conclusion,
            }])
            with self.assertRaises(GitHubBuildError):
                self.github.wait("release.yml", "ours", "expected")

    def test_environment_approval_waits_then_downloads_only_after_success(self):
        self.github.json_command = Mock(side_effect=[
            [{"displayTitle": "Local build ours", "databaseId": 2,
              "headSha": "expected", "status": "waiting", "conclusion": None}],
            {"headSha": "expected", "status": "completed", "conclusion": "success"},
        ])
        with patch("github_actions.time.sleep") as sleep:
            self.assertEqual(self.github.wait("release.yml", "ours", "expected"), 2)
            sleep.assert_called_once_with(5)

    def test_expired_wait_does_not_select_old_runs(self):
        with self.assertRaisesRegex(GitHubBuildError, "Timed out"):
            self.github.wait("release.yml", "ours", "expected", timeout=0)

    def test_download_selects_exact_run_and_artifact(self):
        self.github.command = Mock(return_value="")
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "download"
            self.github.download(123, "ATS-macos", destination)
            self.assertTrue(destination.is_dir())
            arguments = self.github.command.call_args.args[0]
            self.assertEqual(arguments[:3], ["run", "download", "123"])
            self.assertEqual(arguments[arguments.index("--name") + 1], "ATS-macos")


if __name__ == "__main__":
    unittest.main()
