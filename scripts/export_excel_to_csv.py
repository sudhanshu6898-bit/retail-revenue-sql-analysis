"""
Step 0 - Export the raw Excel workbooks to CSV so they can be loaded into PostgreSQL.

Usage (from the repo root):
    python scripts/export_excel_to_csv.py

Writes UTF-8 CSVs into data/csv/. No values are changed here - all cleaning
is done in SQL (see sql/04_clean_transform.sql) so it is transparent and repeatable.
"""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW, OUT = ROOT / "data" / "raw", ROOT / "data" / "csv"
OUT.mkdir(parents=True, exist_ok=True)

sales = RAW / "retail_sales_dataset.xlsx"
complaints = RAW / "customer_complaints_dataset.xlsx"

exports = {
    "sales_weekly.csv": pd.read_excel(sales, sheet_name="Assessment Dataset"),
    "shopper_profile_appeal.csv": pd.read_excel(sales, sheet_name="Shopper Profile Appeal"),
    "variable_definitions.csv": pd.read_excel(sales, sheet_name="Variable definitions"),
    "customer_complaints.csv": pd.read_excel(complaints, sheet_name="Customer_Complaints"),
}

for name, df in exports.items():
    if "Week_Start" in df.columns:
        df["Week_Start"] = pd.to_datetime(df["Week_Start"]).dt.strftime("%Y-%m-%d")
    df.to_csv(OUT / name, index=False)
    print(f"{name:30s} {df.shape[0]:>5} rows x {df.shape[1]} cols")
