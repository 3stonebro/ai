import csv
from datetime import datetime, timezone
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import stock_history


class StockHistoryTests(unittest.TestCase):
    def test_fetches_and_writes_csv(self):
        timestamps = [
            int(datetime(2024, 1, 2, 5, tzinfo=timezone.utc).timestamp()),
            int(datetime(2024, 1, 3, 5, tzinfo=timezone.utc).timestamp()),
        ]
        payload = {
            "chart": {
                "result": [
                    {
                        "meta": {"exchangeTimezoneName": "America/New_York"},
                        "timestamp": timestamps,
                        "indicators": {
                            "quote": [
                                {
                                    "open": [185.0, 184.0],
                                    "high": [186.0, 187.0],
                                    "low": [183.0, 182.0],
                                    "close": [185.5, 186.5],
                                    "volume": [1000, 1200],
                                }
                            ],
                            "adjclose": [{"adjclose": [185.5, 186.5]}],
                        },
                    }
                ]
            }
        }
        response = io.BytesIO(json.dumps(payload).encode())

        with patch("stock_history.urlopen", return_value=response) as open_url:
            rows = stock_history.fetch_history("aapl")

        query = parse_qs(urlparse(open_url.call_args.args[0].full_url).query)
        self.assertEqual(query["range"], ["max"])
        self.assertEqual(query["interval"], ["1d"])
        self.assertEqual(rows[0]["Date"], "2024-01-02")
        self.assertEqual(rows[1]["Adj Close"], "186.5")

        with TemporaryDirectory() as directory:
            path = Path(directory) / "prices.csv"
            stock_history.write_csv(path, rows)
            with path.open(newline="", encoding="utf-8") as saved:
                csv_rows = list(csv.DictReader(saved))
        self.assertEqual(csv_rows, rows)
        self.assertEqual(
            list(csv_rows[0]),
            ["Date", "Open", "High", "Low", "Close", "Adj Close", "Volume"],
        )

    def test_date_range_is_inclusive_and_validated(self):
        url = stock_history._request_url("BRK-B", "max", "1d", "2024-01-01", "2024-01-02")
        query = parse_qs(urlparse(url).query)
        self.assertEqual(query["period1"], ["1704067200"])
        self.assertEqual(query["period2"], ["1704240000"])
        self.assertNotIn("range", query)

        with self.assertRaisesRegex(ValueError, "Both --start and --end"):
            stock_history._request_url("AAPL", "max", "1d", "2024-01-01", None)
        with self.assertRaisesRegex(ValueError, "on or after"):
            stock_history._request_url("AAPL", "max", "1d", "2024-02-01", "2024-01-01")

    def test_provider_errors_are_reported(self):
        response = io.BytesIO(
            json.dumps({"chart": {"error": {"description": "Invalid symbol"}}}).encode()
        )
        with patch("stock_history.urlopen", return_value=response):
            with self.assertRaisesRegex(ValueError, "Invalid symbol"):
                stock_history.fetch_history("NOTREAL")

    def test_main_writes_to_output_directory(self):
        rows = [{"Date": "2024-01-02", "Open": "1"}]
        with TemporaryDirectory() as directory:
            output_dir = Path(directory) / "nested" / "prices"
            with patch("stock_history.fetch_history", return_value=rows):
                result = stock_history.main(
                    ["aapl", "--output-dir", str(output_dir)]
                )

            output_path = output_dir / "AAPL.csv"
            self.assertEqual(result, 0)
            self.assertTrue(output_path.is_file())
            with output_path.open(newline="", encoding="utf-8") as saved:
                saved_rows = list(csv.DictReader(saved))
            self.assertEqual(len(saved_rows), 1)
            self.assertEqual(saved_rows[0]["Date"], "2024-01-02")
            self.assertEqual(saved_rows[0]["Open"], "1")


if __name__ == "__main__":
    unittest.main()
