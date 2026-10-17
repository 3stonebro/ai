import csv
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
import unittest
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from unittest.mock import patch

import app
import stock_history


class StockHistoryWebAppTests(unittest.TestCase):
    def setUp(self):
        self.output_directory = TemporaryDirectory()
        self.output_patch = patch.object(app, "OUTPUT_DIR", Path(self.output_directory.name))
        self.output_patch.start()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), app.StockHistoryHandler)
        self.server_thread = Thread(target=self.server.serve_forever, daemon=True)
        self.server_thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.server_thread.join()
        self.output_patch.stop()
        self.output_directory.cleanup()

    def test_page_is_served(self):
        with urlopen(self.base_url) as response:
            page = response.read().decode("utf-8")
        self.assertIn('id="ticker"', page)
        self.assertIn('id="start"', page)
        self.assertIn('id="end"', page)
        self.assertIn("/api/history", page)
        self.assertIn("This page is being served by a static file server", page)
        self.assertIn('id="chart-container"', page)
        self.assertIn("function showChart(rows, ticker)", page)

    def test_lookup_displays_data_and_saves_downloadable_csv(self):
        rows = [
            {
                "Date": "2024-01-02",
                "Open": "185.0",
                "High": "186.0",
                "Low": "183.0",
                "Close": "185.5",
                "Adj Close": "185.5",
                "Volume": "1000",
            }
        ]
        with patch("app.fetch_history", return_value=rows) as fetch:
            request = Request(
                f"{self.base_url}/api/history",
                data=json.dumps(
                    {"ticker": "aapl", "start": "2024-01-01", "end": "2024-01-31"}
                ).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urlopen(request) as response:
                result = json.loads(response.read())

        fetch.assert_called_once_with("AAPL", start="2024-01-01", end="2024-01-31")
        self.assertEqual(result["ticker"], "AAPL")
        self.assertEqual(result["rows"], rows)
        self.assertEqual(result["filename"], "AAPL.csv")

        saved_file = Path(self.output_directory.name) / "AAPL.csv"
        with saved_file.open(newline="", encoding="utf-8") as csv_file:
            self.assertEqual(list(csv.DictReader(csv_file)), rows)

        with urlopen(f"{self.base_url}/download/AAPL.csv") as response:
            self.assertEqual(response.headers["Content-Type"], "text/csv; charset=utf-8")
            self.assertEqual(
                response.read().decode().splitlines()[0],
                ",".join(stock_history.CSV_COLUMNS),
            )

    def test_invalid_request_returns_helpful_error(self):
        request = Request(
            f"{self.base_url}/api/history",
            data=json.dumps(
                {"ticker": "AAPL", "start": "2024-02-01", "end": "2024-01-01"}
            ).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(HTTPError) as raised:
            urlopen(request)
        self.assertEqual(raised.exception.code, 400)
        with raised.exception:
            error = json.loads(raised.exception.read())
        self.assertIn("on or after", error["error"])

    def test_market_data_failure_returns_json_error(self):
        request = Request(
            f"{self.base_url}/api/history",
            data=json.dumps(
                {"ticker": "AAPL", "start": "2024-01-01", "end": "2024-01-31"}
            ).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with patch("app.fetch_history", side_effect=URLError("network unavailable")):
            with self.assertRaises(HTTPError) as raised:
                urlopen(request)
        with raised.exception:
            self.assertEqual(raised.exception.code, 502)
            error = json.loads(raised.exception.read())
        self.assertIn("network unavailable", error["error"])


if __name__ == "__main__":
    unittest.main()
