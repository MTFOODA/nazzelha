"""
Python backend service for Nazzelha video downloader.
Communicates with Flutter via JSON messages on stdin/stdout.

Message protocol:
- Flutter sends JSON commands to stdin
- Backend sends JSON responses to stdout
"""

import json
import sys
import os
from pathlib import Path
from typing import Dict, Any

from downloader import VideoDownloader, validate_url


def send_progress_event(progress: Dict[str, Any]) -> None:
    """Send a progress event on stdout so Flutter can render live updates."""
    try:
        print(json.dumps(progress))
        sys.stdout.flush()
    except Exception as exc:
        print(json.dumps({
            "event": "progress_error",
            "error": str(exc),
        }))
        sys.stdout.flush()


def send_response(response: Dict[str, Any]) -> None:
    """
    Send a JSON response to stdout.

    Args:
        response: Dictionary to send as JSON
    """
    try:
        print(json.dumps(response))
        sys.stdout.flush()
    except Exception as e:
        error_response = {
            "success": False,
            "error": f"Failed to send response: {str(e)}"
        }
        print(json.dumps(error_response))
        sys.stdout.flush()


def handle_get_qualities(command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle GET_QUALITIES command.

    Args:
        command: Command dictionary with 'url' and 'platform'

    Returns:
        Response dictionary with available qualities or error
    """
    url = command.get("url", "").strip()
    platform = command.get("platform", "youtube").lower()

    if not url:
        return {
            "success": False,
            "error": "No video URL provided."
        }

    if not validate_url(url, platform):
        return {
            "success": False,
            "error": f"Invalid {platform} URL. Please check the URL and try again."
        }

    downloader = VideoDownloader()
    return downloader.get_available_qualities(url, platform)


def handle_download(command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle DOWNLOAD command.

    Args:
        command: Command dictionary with url, platform, quality, output_path

    Returns:
        Response dictionary with file path or error
    """
    url = command.get("url", "").strip()
    platform = command.get("platform", "youtube").lower()
    quality = command.get("quality", 720)
    output_path = command.get("output_path")
    mode = command.get("mode", "video")

    if not output_path:
        output_path = VideoDownloader.get_downloads_directory()

    if not url:
        return {
            "success": False,
            "error": "No video URL provided."
        }

    if not isinstance(quality, int) or quality <= 0:
        return {
            "success": False,
            "error": "Invalid quality specified."
        }

    # Create output directory if it doesn't exist
    try:
        Path(output_path).mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return {
            "success": False,
            "error": f"Cannot create output directory: {str(e)}"
        }

    downloader = VideoDownloader(progress_callback=send_progress_event)
    return downloader.download_video(url, platform, quality, output_path, mode=mode)


def handle_get_download_dir(command: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle GET_DOWNLOAD_DIR command.

    Returns:
        Default downloads directory path
    """
    return {
        "success": True,
        "download_dir": VideoDownloader.get_downloads_directory()
    }


COMMAND_HANDLERS = {
    "get_qualities": handle_get_qualities,
    "download": handle_download,
    "get_download_dir": handle_get_download_dir,
}


def process_command(line: str) -> None:
    """
    Process a single JSON command from stdin.

    Args:
        line: JSON string containing the command
    """
    try:
        command = json.loads(line)
    except json.JSONDecodeError as e:
        send_response({
            "success": False,
            "error": f"Invalid JSON: {str(e)}"
        })
        return

    action = command.get("action", "").lower()

    if action not in COMMAND_HANDLERS:
        send_response({
            "success": False,
            "error": f"Unknown action: {action}"
        })
        return

    try:
        handler = COMMAND_HANDLERS[action]
        response = handler(command)
        send_response(response)
    except Exception as e:
        send_response({
            "success": False,
            "error": f"Command processing error: {str(e)}"
        })


def main():
    """Main service loop - read commands from stdin and process them."""
    try:
        # Send ready signal
        send_response({"ready": True})

        # Process commands from stdin
        for line in sys.stdin:
            line = line.strip()
            if line:
                process_command(line)

    except KeyboardInterrupt:
        pass
    except Exception as e:
        send_response({
            "success": False,
            "error": f"Service error: {str(e)}"
        })
    finally:
        sys.exit(0)


if __name__ == "__main__":
    main()
