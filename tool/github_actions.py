"""Authenticated workflow dispatch/download helpers; never reads secret values."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

from build_release import child_environment


class GitHubBuildError(Exception):
    pass


class GitHubActions:
    def __init__(self, repo="SYSTMVEXU/TMLink"):
        if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*", repo):
            raise GitHubBuildError("Use a GitHub repository in OWNER/REPO format.")
        self.repo = repo
        self.executable = shutil.which("gh")
        if not self.executable:
            raise GitHubBuildError("Install GitHub CLI (on macOS: brew install gh), then run gh auth login.")
        self.environment = child_environment(dict(os.environ))
        # API trace output can expose request data. Use normal CLI output only.
        self.environment.pop("GH_DEBUG", None)

    def command(self, arguments, input_data=None):
        try:
            result = subprocess.run(
                [self.executable, *arguments], input=input_data,
                capture_output=True, text=True, env=self.environment, timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise GitHubBuildError("GitHub CLI could not complete the request. Check access and retry.") from None
        if result.returncode:
            # CLI errors can contain API payloads; use a safe diagnostic instead.
            raise GitHubBuildError(
                "GitHub CLI rejected the request. Check gh auth status, repository permissions, and that the workflow is pushed to the default branch."
            )
        return result.stdout

    def json_command(self, arguments):
        try:
            return json.loads(self.command(arguments))
        except json.JSONDecodeError:
            raise GitHubBuildError("GitHub returned an unreadable response.") from None

    def default_branch(self):
        self.command(["auth", "status", "--hostname", "github.com"])
        data = self.json_command(["api", f"repos/{self.repo}"])
        branch = data.get("default_branch")
        if not isinstance(branch, str) or not branch:
            raise GitHubBuildError("GitHub did not return a default branch.")
        return branch

    def branch_commit(self, branch):
        # URL-encode branch names, including slashes, as a path component.
        from urllib.parse import quote
        data = self.json_command(["api", f"repos/{self.repo}/commits/{quote(branch, safe='')}"])
        commit = data.get("sha", "")
        if not re.fullmatch(r"[a-f0-9]{40}", commit):
            raise GitHubBuildError("GitHub did not return a valid commit.")
        return commit

    def dispatch(self, workflow, branch, inputs):
        request_id = uuid.uuid4().hex
        parameters = dict(inputs, request_id=request_id)
        self.command([
            "workflow", "run", workflow, "--repo", self.repo,
            "--ref", branch, "--json",
        ], input_data=json.dumps(parameters))
        return request_id

    def wait(self, workflow, request_id, commit, timeout=3600):
        deadline = time.monotonic() + timeout
        run_id = None
        previous_status = None
        url = f"https://github.com/{self.repo}/actions"
        print(f"Waiting for GitHub Actions. Approve the dwab environment if required: {url}", flush=True)
        while time.monotonic() < deadline:
            if run_id is None:
                runs = self.json_command([
                    "run", "list", "--repo", self.repo, "--workflow", workflow,
                    "--event", "workflow_dispatch", "--limit", "100",
                    "--json", "databaseId,displayTitle,headSha,status,conclusion,url",
                ])
                matches = [run for run in runs if run.get("displayTitle") == f"Local build {request_id}"]
                if not matches:
                    time.sleep(5)
                    continue
                if len(matches) != 1:
                    raise GitHubBuildError("More than one workflow matched this request. No artifacts were downloaded.")
                run = matches[0]
                run_id = run["databaseId"]
                if not isinstance(run_id, int) or run_id <= 0:
                    raise GitHubBuildError("GitHub returned an invalid workflow run ID.")
                url = f"https://github.com/{self.repo}/actions/runs/{run_id}"
                print(f"Workflow: {url}", flush=True)
            else:
                run = self.json_command([
                    "run", "view", str(run_id), "--repo", self.repo,
                    "--json", "headSha,status,conclusion",
                ])
            if run.get("headSha") != commit:
                raise GitHubBuildError("The default branch changed before the workflow started. Retry against the new revision.")
            status = run.get("status")
            if status != previous_status:
                print(f"GitHub build status: {status}", flush=True)
                previous_status = status
            if status == "completed":
                if run.get("conclusion") != "success":
                    raise GitHubBuildError(f"The GitHub workflow did not succeed. Review {url}")
                return run_id
            time.sleep(5)
        raise GitHubBuildError(f"Timed out waiting for the workflow. It may still be running: {url}")

    def download(self, run_id, artifact, directory):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        self.command([
            "run", "download", str(run_id), "--repo", self.repo,
            "--name", artifact, "--dir", str(directory),
        ])
