# Stock history CSV

`stock_history.py` downloads historical OHLCV data from Yahoo Finance and saves it as CSV. It uses only the Python standard library.

## Web app

Start the local web app from this directory (do not open `index.html` directly or use a static file preview):

```sh
.venv/bin/python app.py
```

Open `http://127.0.0.1:8000`, enter a stock ticker and inclusive start/end dates, and select **Get history**. The daily closing-price graph and full results table appear, with a link to download the CSV. CSV files are saved under `output/` (for example, `output/AAPL.csv`); a later lookup of the same ticker replaces that ticker's previous file. The server binds to localhost by default. Use `--port` to choose a different port. A static preview server cannot handle the app's data request; use the URL printed by `app.py`.

## Command-line downloader

```sh
.venv/bin/python stock_history.py AAPL
```

By default, the program downloads the maximum available daily history and writes `AAPL.csv` in the current directory. Choose a different output path or interval with:

```sh
.venv/bin/python stock_history.py MSFT --output data/msft.csv --interval 1wk
```

To save the ticker-named CSV in a folder (created if it does not exist), use `--output-dir`:

```sh
.venv/bin/python stock_history.py AAPL --output-dir ./output
```

Use either `--output` for a complete CSV file path or `--output-dir` for a folder, not both.

To request a date range, specify both inclusive dates:

```sh
.venv/bin/python stock_history.py AAPL --start 2024-01-01 --end 2024-12-31
```

Use `--period` instead of dates to select a preset window such as `1y`, `5y`, or `max`. The CSV contains Date, Open, High, Low, Close, Adjusted Close, and Volume. This tool uses Yahoo Finance's chart endpoint; availability, historical coverage, and rate limits are controlled by the provider.

## macOS certificate setup

If Python reports `CERTIFICATE_VERIFY_FAILED` on macOS and you installed Python from python.org, run the matching `Install Certificates.command` from `/Applications/Python <version>/`, then retry with `.venv/bin/python`. This installs the trusted CA bundle for that Python installation; do not disable HTTPS certificate verification.

Run the tests with:

```sh
.venv/bin/python -m unittest discover -s tests
```
