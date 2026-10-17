#!/usr/bin/env python3
"""Serve a local web app for looking up and saving stock history."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import sys
from urllib.error import URLError
from urllib.parse import unquote, urlsplit

from stock_history import _request_url, fetch_history, write_csv


APP_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = APP_DIR / "output"
INDEX_PATH = APP_DIR / "index.html"
MAX_REQUEST_BYTES = 16_384
TICKER_PATTERN = re.compile(r"[A-Z0-9.^=_-]+")


def fetch_and_save(ticker: str, start: str, end: str) -> dict:
    """Fetch the selected date range, save its CSV, and return the result."""
    normalized_ticker = ticker.strip().upper()
    _request_url(normalized_ticker, "max", "1d", start, end)
    rows = fetch_history(normalized_ticker, start=start, end=end)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    filename = f"{normalized_ticker}.csv"
    write_csv(OUTPUT_DIR / filename, rows)
    return {
        "ticker": normalized_ticker,
        "rows": rows,
        "count": len(rows),
        "filename": filename,
    }


class StockHistoryHandler(BaseHTTPRequestHandler):
    server_version = "StockHistory/1.0"

    def do_GET(self) -> None:
        path = urlsplit(self.path).path
        if path == "/":
            self._send_file(INDEX_PATH, "text/html; charset=utf-8")
        elif path.startswith("/download/"):
            self._download(path.removeprefix("/download/"))
        else:
            self._send_json(404, {"error": "Not found."})

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/api/history":
            self._send_json(404, {"error": "Not found."})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": "Invalid request length."})
            return
        if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
            self._send_json(400, {"error": "Request must contain valid JSON under 16 KB."})
            return

        try:
            request_data = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_json(400, {"error": "Request body must be valid JSON."})
            return

        if not isinstance(request_data, dict):
            self._send_json(400, {"error": "Request body must be a JSON object."})
            return
        ticker = request_data.get("ticker")
        start = request_data.get("start")
        end = request_data.get("end")
        if not all(isinstance(value, str) for value in (ticker, start, end)):
            self._send_json(400, {"error": "Ticker, start date, and end date are required."})
            return

        try:
            result = fetch_and_save(ticker, start, end)
        except ValueError as exc:
            self._send_json(400, {"error": str(exc)})
        except (URLError, TimeoutError) as exc:
            self._send_json(502, {"error": f"Could not fetch market data: {exc}"})
        except OSError as exc:
            self._send_json(500, {"error": f"Could not save the CSV file: {exc}"})
        else:
            self._send_json(200, result)

    def _download(self, filename: str) -> None:
        filename = unquote(filename)
        if not filename.endswith(".csv"):
            self._send_json(404, {"error": "CSV file not found."})
            return
        ticker = filename[:-4]
        if not TICKER_PATTERN.fullmatch(ticker) or filename != f"{ticker}.csv":
            self._send_json(404, {"error": "CSV file not found."})
            return

        path = OUTPUT_DIR / filename
        try:
            content = path.read_bytes()
        except FileNotFoundError:
            self._send_json(404, {"error": "CSV file not found."})
            return
        except OSError as exc:
            self._send_json(500, {"error": f"Could not read the CSV file: {exc}"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/csv; charset=utf-8")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_file(self, path: Path, content_type: str) -> None:
        try:
            content = path.read_bytes()
        except OSError as exc:
            self._send_json(500, {"error": f"Could not read the web page: {exc}"})
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_json(self, status: int, data: dict) -> None:
        content = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.address_string()} - {format % args}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the stock history web app.")
    parser.add_argument("--host", default="127.0.0.1", help="interface to bind (default: localhost)")
    parser.add_argument("--port", type=int, default=8000, help="port to listen on (default: 8000)")
    args = parser.parse_args(argv)
    if not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535.")

    try:
        server = ThreadingHTTPServer((args.host, args.port), StockHistoryHandler)
    except OSError as exc:
        print(f"Error: could not start server: {exc}", file=sys.stderr)
        return 1

    host, port = server.server_address[:2]
    print(f"Open http://{host}:{port} in your browser. Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping web app.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
