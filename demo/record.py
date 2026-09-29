"""Record the README demo into demo/nurl-demo.mp4 and demo/nurl-demo.webm:

    python3 demo/record.py

It plays demo.tape with VHS (https://github.com/charmbracelet/vhs) in a Neovim
isolated from yours: its own data, state and config directories, and plugins
downloaded to demo/.deps on the first run. Requests go to a mock API that a
curlrc points api.example.com and dev.api.example.com at, so the demo shows
real requests without a real API.

Needs nvim, vhs, ttyd, ffmpeg, jq, curl and git, and the JetBrainsMono Nerd
Font.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from server import serve

DEMO = Path(__file__).resolve().parent

DEPENDENCIES = {
    "snacks.nvim": "https://github.com/folke/snacks.nvim",
    "rose-pine": "https://github.com/rose-pine/neovim",
}


def user_nvim_site():
    """The site directory of the user's Neovim, where its parsers are."""
    result = subprocess.run(
        [
            "nvim",
            "--headless",
            "-u",
            "NONE",
            "-c",
            'lua io.stdout:write(vim.fn.stdpath("data"))',
            "-c",
            "qa!",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return str(Path(result.stdout.strip()) / "site")


def main():
    tools = ["nvim", "vhs", "ttyd", "ffmpeg", "jq", "curl", "git"]
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        sys.exit("Missing in PATH: " + ", ".join(missing))

    for name, url in DEPENDENCIES.items():
        path = DEMO / ".deps" / name
        if not path.exists():
            print("Downloading " + name, flush=True)
            subprocess.run(
                ["git", "clone", "--depth", "1", url, str(path)], check=True
            )

    site = user_nvim_site()
    server = serve()
    port = server.server_address[1]

    # Everything the recorded Neovim writes goes here, and is deleted after.
    with tempfile.TemporaryDirectory() as root:
        curl_home = Path(root) / "curl"
        curl_home.mkdir()
        (curl_home / ".curlrc").write_text(
            "connect-to = api.example.com:80:127.0.0.1:%d\n"
            "connect-to = dev.api.example.com:80:127.0.0.1:%d\n" % (port, port)
        )

        env = os.environ | {
            "XDG_DATA_HOME": str(Path(root) / "data"),
            "XDG_STATE_HOME": str(Path(root) / "state"),
            "XDG_CACHE_HOME": str(Path(root) / "cache"),
            "XDG_CONFIG_HOME": str(Path(root) / "config"),
            "CURL_HOME": str(curl_home),
            "NURL_DEMO_SITE": site,
        }

        print("Recording demo.tape", flush=True)
        result = subprocess.run(["vhs", "demo.tape"], cwd=DEMO, env=env)

    server.shutdown()

    if result.returncode != 0:
        sys.exit("Recording failed")

    print("Recorded demo/nurl-demo.mp4 and demo/nurl-demo.webm")


if __name__ == "__main__":
    main()
