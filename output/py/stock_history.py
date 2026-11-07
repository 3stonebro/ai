#!/usr/bin/env python3
"""Download historical daily stock prices from Yahoo Finance to a CSV file."""

import argparse
import csv
from datetime import date, datetime, time, timedelta, timezone
import json
from pathlib import Path
import re
import sys
from urllib.error import URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
PERIODS = ("1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "ytd", "max")
INTERVALS = ("1d", "1wk", "1mo")
CSV_COLUMNS = ("Date", "Open", "High", "Low", "Close", "Adj Close", "Volume")


def _request_url(
    ticker: str,
    period: str,
    interval: str,
    start: str | None,
    end: str | None,
) -> str:
    ticker = ticker.strip().upper()
    if not re.fullmatch(r"[A-Z0-9.^=_-]+", ticker):
        raise ValueError("Ticker must contain only letters, numbers, '.', '^', '=', '_' or '-'.")
    if interval not in INTERVALS:
        raise ValueError(f"Unsupported interval: {interval}")

    params: dict[str, str | int] = {"interval": interval, "events": "history"}
    if start is not None or end is not None:
        if start is None or end is None:
            raise ValueError("Both --start and --end are required for a date range.")
        try:
            start_date = date.fromisoformat(start)
            end_date = date.fromisoformat(end)
        except ValueError as exc:
            raise ValueError("Dates must use YYYY-MM-DD format.") from exc
        if end_date < start_date:
            raise ValueError("--end must be on or after --start.")
        params["period1"] = int(
            datetime.combine(start_date, time.min, timezone.utc).timestamp()
        )
        params["period2"] = int(
            datetime.combine(end_date + timedelta(days=1), time.min, timezone.utc).timestamp()
        )
    else:
        if period not in PERIODS:
            raise ValueError(f"Unsupported period: {period}")
        params["range"] = period

    return f"{BASE_URL}{quote(ticker, safe='')}?{urlencode(params)}"


def fetch_history(
    ticker: str,
    period: str = "max",
    interval: str = "1d",
    start: str | None = None,
    end: str | None = None,
) -> list[dict[str, str]]:
    """Fetch bars and return CSV-ready rows for a ticker."""
    url = _request_url(ticker, period, interval, start, end)
    request = Request(url, headers={"User-Agent": "stock-history-csv/1.0"})
    with urlopen(request, timeout=30) as response:
        payload = json.loads(response.read())

    chart = payload.get("chart", {})
    if chart.get("error"):
        error = chart["error"]
        message = error.get("description") or error.get("code") or "Unknown provider error"
        raise ValueError(f"Yahoo Finance error: {message}")

    results = chart.get("result")
    if not results:
        raise ValueError("No historical data returned. Check the ticker and date range.")
    result = results[0]
    timestamps = result.get("timestamp") or []
    indicators = result.get("indicators", {})
    quotes = indicators.get("quote") or []
    if not timestamps or not quotes:
        raise ValueError("The response did not contain historical price data.")

    timezone_name = result.get("meta", {}).get("exchangeTimezoneName", "UTC")
    try:
        market_timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown exchange time zone: {timezone_name}") from exc

    quote_data = quotes[0]
    adjusted = indicators.get("adjclose") or [{}]
    adjusted_closes = adjusted[0].get("adjclose") or []

    def value_at(values: list, index: int) -> str:
        if index >= len(values) or values[index] is None:
            return ""
        return str(values[index])

    rows = []
    for index, timestamp in enumerate(timestamps):
        if timestamp is None:
            continue
        row = {
            "Date": datetime.fromtimestamp(timestamp, market_timezone).date().isoformat(),
            "Open": value_at(quote_data.get("open", []), index),
            "High": value_at(quote_data.get("high", []), index),
            "Low": value_at(quote_data.get("low", []), index),
            "Close": value_at(quote_data.get("close", []), index),
            "Adj Close": value_at(adjusted_closes, index),
            "Volume": value_at(quote_data.get("volume", []), index),
        }
        rows.append(row)

    if not rows:
        raise ValueError("No historical data returned. Check the ticker and date range.")
    return rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Download historical stock prices and save them as a CSV file."
    )
    parser.add_argument("ticker", help="Stock symbol, for example AAPL or MSFT")
    output_options = parser.add_mutually_exclusive_group()
    output_options.add_argument(
        "-o", "--output", type=Path, help="output CSV path (default: TICKER.csv)"
    )
    output_options.add_argument(
        "--output-dir",
        type=Path,
        help="folder for TICKER.csv (created if needed; default: current directory)",
    )
    parser.add_argument(
        "--period",
        choices=PERIODS,
        default="max",
        help="history window when --start/--end are not used (default: max)",
    )
    parser.add_argument(
        "--interval", choices=INTERVALS, default="1d", help="bar interval (default: 1d)"
    )
    parser.add_argument("--start", help="inclusive start date (YYYY-MM-DD)")
    parser.add_argument("--end", help="inclusive end date (YYYY-MM-DD)")
    args = parser.parse_args(argv)

    try:
        rows = fetch_history(
            args.ticker,
            period=args.period,
            interval=args.interval,
            start=args.start,
            end=args.end,
        )
        output_dir = args.output_dir or Path(".")
        output_path = args.output or output_dir / f"{args.ticker.strip().upper()}.csv"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        write_csv(output_path, rows)
    except (OSError, URLError, TimeoutError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(f"Saved {len(rows)} rows to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
