"""
export_service.py
-----------------
Generates in-memory CSVs for each selected backup category and
bundles them into a ZIP byte-stream ready to send to the client.
No files are written to disk on the server side.
"""
from __future__ import annotations

import csv
import io
import zipfile
from datetime import datetime, date
from decimal import Decimal
from typing import Any

from sqlalchemy.orm import Session


 
# Category keys — must match the string values sent from the Flutter client
 
CATEGORY_USERS = "users"
CATEGORY_ROLES = "roles_permissions"
CATEGORY_PRODUCTS = "products"
CATEGORY_SUPPLIERS = "suppliers"
CATEGORY_STOCK_RECEIPTS = "stock_receipts"
CATEGORY_HISTORICAL_SALES = "historical_sales"
CATEGORY_DEMAND_FORECASTS = "demand_forecasts"
CATEGORY_AUDIT_LOG = "audit_log"
CATEGORY_NOTIFICATIONS = "notifications"

ALL_CATEGORIES = [
    CATEGORY_USERS,
    CATEGORY_ROLES,
    CATEGORY_PRODUCTS,
    CATEGORY_SUPPLIERS,
    CATEGORY_STOCK_RECEIPTS,
    CATEGORY_HISTORICAL_SALES,
    CATEGORY_DEMAND_FORECASTS,
    CATEGORY_AUDIT_LOG,
    CATEGORY_NOTIFICATIONS,
]


import tempfile
import os

# Stream rows to a CSV file inside a ZIP archive
def _stream_to_zip(zf: zipfile.ZipFile, filename: str, rows_iter, fieldnames: list[str] = None):
    """Helper to stream rows to a CSV file inside the ZIP archive."""
    with zf.open(filename, "w") as byte_writer:
        with io.TextIOWrapper(byte_writer, encoding="utf-8-sig", newline="") as text_writer:
            if not rows_iter:
                text_writer.write("No data available.\n")
                return

            try:
                # Handle lists or generators uniformly:
                if isinstance(rows_iter, list):
                    rows_iter = iter(rows_iter)
                peek = next(rows_iter)
            except StopIteration:
                text_writer.write("No data available.\n")
                return

            if fieldnames is None:
                fieldnames = list(peek.keys())
            
            writer = csv.DictWriter(text_writer, fieldnames=fieldnames, lineterminator="\n")
            writer.writeheader()
            writer.writerow(peek)
            
            for row in rows_iter:
                writer.writerow(row)

import json
# Stream rows to a JSON file inside a ZIP archive
def _stream_to_zip_json(zf: zipfile.ZipFile, filename: str, rows_iter):
    """Helper to stream rows to a JSON file inside the ZIP archive."""
    with zf.open(filename, "w") as byte_writer:
        with io.TextIOWrapper(byte_writer, encoding="utf-8", newline="") as text_writer:
            if not rows_iter:
                text_writer.write("[]")
                return

            try:
                if isinstance(rows_iter, list):
                    rows_iter = iter(rows_iter)
                peek = next(rows_iter)
            except StopIteration:
                text_writer.write("[]")
                return
            
            # Start JSON array
            text_writer.write("[\\n  ")
            
            # Datetime & Decimal serializer helper
            # Convert datetime and Decimal objects to JSON-serializable formats
            def _json_serial(obj):
                if isinstance(obj, (datetime, date)):
                    return obj.isoformat()
                if isinstance(obj, Decimal):
                    return float(obj)
                raise TypeError(f"Type {type(obj)} not serializable")

            # Write first row
            text_writer.write(json.dumps(peek, default=_json_serial))
            
            # Write remainder
            for row in rows_iter:
                text_writer.write(",\\n  ")
                text_writer.write(json.dumps(row, default=_json_serial))
                
            text_writer.write("\\n]\\n")


# Stream rows to a SQL INSERT statements file inside a ZIP archive
def _stream_to_zip_sql(zf: zipfile.ZipFile, filename: str, table_name: str, rows_iter):
    """Helper to stream rows to a SQL file inside the ZIP archive."""
    with zf.open(filename, "w") as byte_writer:
        with io.TextIOWrapper(byte_writer, encoding="utf-8", newline="") as text_writer:
            if not rows_iter:
                return

            try:
                if isinstance(rows_iter, list):
                    rows_iter = iter(rows_iter)
                peek = next(rows_iter)
            except StopIteration:
                return
            
            columns = list(peek.keys())
            cols_str = ", ".join([f'"{c}"' for c in columns])

            # Format a database value for SQL INSERT statement
            def _format_val(val):
                if val is None:
                    return "NULL"
                if isinstance(val, (int, float)):
                    return str(val)
                if isinstance(val, bool):
                    return "TRUE" if val else "FALSE"
                if isinstance(val, datetime):
                    val_str = val.isoformat().replace("T", " ")
                    return f"'{val_str}'"
                val_str = str(val).replace("'", "''")
                return f"'{val_str}'"
            
            # Write a single row as a SQL INSERT statement
            def write_row(row):
                vals_str = ", ".join([_format_val(row[c]) for c in columns])
                text_writer.write(f"INSERT INTO {table_name} ({cols_str}) VALUES ({vals_str});\n")
            
            # Add header comment
            text_writer.write(f"-- STOX SQL Data Export: {table_name}\n")
            text_writer.write(f"-- Generated: {datetime.now().isoformat()}\n")
            text_writer.write("-- NOTE: This file contains INSERT statements only. It assumes the table structure already exists.\n\n")

            write_row(peek)
            for row in rows_iter:
                write_row(row)

 
# Individual category fetchers
 

# Fetch all users with their role assignments
def _fetch_users(db: Session) -> list[dict[str, Any]]:
    from app.models.user import User
    from app.models.role import Role
    from sqlalchemy import select
    stmt = (
        select(
            User.id.label("user_id"),
            User.full_name.label("username"),
            User.email,
            User.is_active,
            User.tfa_active,
            Role.role_name,
        )
        .join(Role, User.role_id == Role.id, isouter=True)
        .order_by(User.id)
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch roles, permissions, and their associations
def _fetch_roles_permissions(db: Session) -> dict[str, list[dict[str, Any]]]:
    """Returns multiple named CSVs: roles, permissions, role_permissions."""
    from app.models.role import Role
    from app.models.permission import Permission
    from app.models.role_permission import RolePermission
    from sqlalchemy import select

    roles = ({"role_id": r.id, "role_name": r.role_name, "description": r.description}
             for r in db.execute(select(Role).order_by(Role.id).execution_options(yield_per=2000)).scalars())
    permissions = ({"perm_id": p.id, "permission_name": p.action_name}
                   for p in db.execute(select(Permission).order_by(Permission.id).execution_options(yield_per=2000)).scalars())

    stmt = (
        select(
            RolePermission.role_id,
            Role.role_name,
            RolePermission.permission_id,
            Permission.action_name.label("permission_name"),
        )
        .join(Role, RolePermission.role_id == Role.id)
        .join(Permission, RolePermission.permission_id == Permission.id)
        .order_by(RolePermission.role_id, RolePermission.permission_id)
    )
    role_perms = (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))
    return {"roles": roles, "permissions": permissions, "role_permissions": role_perms}


# Fetch products with their reorder parameters
def _fetch_products(db: Session) -> dict[str, list[dict[str, Any]]]:
    """Products + reorder parameters (recursive include)."""
    from app.models.product import Product
    from app.models.supplier import Supplier
    from app.models.reorder_parameter import ReorderParameter
    from sqlalchemy import select

    stmt = (
        select(
            Product.id.label("product_id"),
            Product.product_code,
            Product.sku,
            Product.name.label("product_name"),
            Product.current_qty,
            Product.reorder_level,
            Product.unit_cost,
            Product.status_flag,
            Product.holding_cost,
            Product.ordering_cost,
            Supplier.name.label("supplier_name"),
        )
        .join(Supplier, Product.supplier_id == Supplier.id, isouter=True)
        .order_by(Product.id)
    )
    products = (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))

    rop_stmt = (
        select(
            ReorderParameter.id.label("param_id"),
            ReorderParameter.product_id,
            Product.product_code,
            ReorderParameter.safety_stock,
            ReorderParameter.eoq,
            ReorderParameter.lead_time_days,
        )
        .join(Product, ReorderParameter.product_id == Product.id)
        .order_by(ReorderParameter.product_id)
    )
    reorder_params = (dict(row._mapping) for row in db.execute(rop_stmt.execution_options(yield_per=2000)))
    return {"products": products, "reorder_parameters": reorder_params}


# Fetch all suppliers with creator information
def _fetch_suppliers(db: Session) -> list[dict[str, Any]]:
    from app.models.supplier import Supplier
    from app.models.user import User
    from sqlalchemy import select
    stmt = (
        select(
            Supplier.id.label("supplier_id"),
            Supplier.name.label("supplier_name"),
            Supplier.contact_info,
            Supplier.lead_time_days,
            Supplier.address,
            User.full_name.label("created_by_username"),
        )
        .join(User, Supplier.created_by == User.id, isouter=True)
        .order_by(Supplier.id)
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch all stock receipt records with product and supplier details
def _fetch_stock_receipts(db: Session) -> list[dict[str, Any]]:
    from app.models.stock_receipt import StockReceipt
    from app.models.product import Product
    from app.models.supplier import Supplier
    from app.models.user import User
    from sqlalchemy import select
    stmt = (
        select(
            StockReceipt.id.label("receipt_id"),
            Product.product_code,
            Product.name.label("product_name"),
            Supplier.name.label("supplier_name"),
            StockReceipt.quantity,
            StockReceipt.quantity_damaged,
            StockReceipt.received_at.label("receipt_date"),
            StockReceipt.reference_no.label("notes"),
            User.full_name.label("recorded_by"),
        )
        .join(Product, StockReceipt.product_id == Product.id, isouter=True)
        .join(Supplier, StockReceipt.supplier_id == Supplier.id, isouter=True)
        .join(User, StockReceipt.recorded_by == User.id, isouter=True)
        .order_by(StockReceipt.received_at.desc())
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch historical sales records with product information
def _fetch_historical_sales(db: Session) -> list[dict[str, Any]]:
    from app.models.historical_sale import HistoricalSale
    from app.models.product import Product
    from sqlalchemy import select
    stmt = (
        select(
            HistoricalSale.id.label("sale_id"),
            Product.product_code,
            Product.name.label("product_name"),
            HistoricalSale.sale_date,
            HistoricalSale.quantity_sold,
            HistoricalSale.revenue,
        )
        .join(Product, HistoricalSale.product_id == Product.id, isouter=True)
        .order_by(HistoricalSale.sale_date.desc())
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch demand forecast records with product and model information
def _fetch_demand_forecasts(db: Session) -> list[dict[str, Any]]:
    from app.models.demand_forecast import DemandForecast
    from app.models.product import Product
    from sqlalchemy import select
    stmt = (
        select(
            DemandForecast.id.label("forecast_id"),
            Product.product_code,
            Product.name.label("product_name"),
            DemandForecast.method.label("model"),
            DemandForecast.window_days.label("forecast_window"),
            DemandForecast.predicted_qty,
            DemandForecast.reorder_suggestion,
            DemandForecast.generated_at,
        )
        .join(Product, DemandForecast.product_id == Product.id, isouter=True)
        .order_by(DemandForecast.generated_at.desc())
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch audit log records with user information
def _fetch_audit_log(db: Session) -> list[dict[str, Any]]:
    from app.models.audit_log import AuditLog
    from app.models.user import User
    from sqlalchemy import select
    stmt = (
        select(
            AuditLog.id.label("log_id"),
            AuditLog.action,
            AuditLog.entity_type,
            AuditLog.entity_id,
            AuditLog.timestamp,
            User.full_name.label("performed_by"),
        )
        .join(User, AuditLog.user_id == User.id, isouter=True)
        .order_by(AuditLog.timestamp.desc())
    )
    return (dict(row._mapping) for row in db.execute(stmt.execution_options(yield_per=2000)))


# Fetch notification records with sender and recipient information
def _fetch_notifications(db: Session) -> list[dict[str, Any]]:
    from app.models.notification import Notification
    from app.models.user import User as UserModel
    from sqlalchemy import select, String
    from sqlalchemy.orm import aliased

    # We use aliased tables for the two user joins (sender / recipient)
    sender_alias = aliased(UserModel, flat=True)
    recipient_alias = aliased(UserModel, flat=True)

    # Cast `type` to String to bypass ORM enum validation.
    # The DB may contain values (e.g. 'Report') that were inserted before
    # the Python enum was defined — casting lets them come through as plain
    # strings instead of raising a LookupError.
    stmt = (
        select(
            Notification.id.label("notification_id"),
            Notification.message,
            Notification.type.cast(String).label("type"),
            Notification.sent_at,
            sender_alias.full_name.label("sender"),
            recipient_alias.full_name.label("recipient"),
        )
        .join(sender_alias, Notification.sender_id == sender_alias.id, isouter=True)
        .join(recipient_alias, Notification.recipient_id == recipient_alias.id, isouter=True)
        .order_by(Notification.sent_at.desc())
    )
    return ({"notification_id": row.notification_id, "message": row.message, "type": str(row.type) if row.type is not None else "", "sent_at": row.sent_at, "sender": row.sender, "recipient": row.recipient} for row in db.execute(stmt.execution_options(yield_per=2000)))


 
# Main ZIP builder
 

# Build a ZIP file containing exported data in specified categories and formats
def build_export_zip(db: Session, categories: list[str], formats: list[str] | None = None) -> tuple[str, str]:
    """
    Build a ZIP file containing one file per table for each
    selected category. Returns (zip_filepath, suggested_filename).
    """
    if formats is None:
        formats = ["csv"]

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    zip_filename = f"stox_backup_{timestamp}.zip"

    fd, temp_path = tempfile.mkstemp(suffix=".zip")
    os.close(fd)

    # Stream data to a specific file format in the ZIP archive
    def _stream(zf, base_name, data):
        # Convert to list so we can iterate multiple times if multiple formats are requested
        data_list = list(data) if data else []
        for fmt in formats:
            if fmt == "json":
                _stream_to_zip_json(zf, f"{base_name}.json", data_list)
            elif fmt == "sql":
                table_name = base_name.replace(" ", "_").lower()
                _stream_to_zip_sql(zf, f"{base_name}.sql", table_name, data_list)
            else:
                _stream_to_zip(zf, f"{base_name}.csv", data_list)

    with zipfile.ZipFile(temp_path, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        # README
        formats_display = ", ".join(f.upper() for f in formats)
        readme = (
            f"STOX Data Export\n"
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"Categories: {', '.join(categories)}\n"
            f"Formats: {formats_display}\n\n"
        )
        if "csv" in formats:
            readme += "All CSV files use UTF-8 encoding with BOM for direct Excel compatibility.\n"
        zf.writestr("README.txt", readme)

        if CATEGORY_USERS in categories:
            _stream(zf, "users", _fetch_users(db))

        if CATEGORY_ROLES in categories:
            data = _fetch_roles_permissions(db)
            _stream(zf, "roles", data["roles"])
            _stream(zf, "permissions", data["permissions"])
            _stream(zf, "role_permissions", data["role_permissions"])

        if CATEGORY_PRODUCTS in categories:
            data = _fetch_products(db)
            _stream(zf, "products", data["products"])
            _stream(zf, "reorder_parameters", data["reorder_parameters"])

        if CATEGORY_SUPPLIERS in categories:
            _stream(zf, "suppliers", _fetch_suppliers(db))

        if CATEGORY_STOCK_RECEIPTS in categories:
            _stream(zf, "stock_receipts", _fetch_stock_receipts(db))

        if CATEGORY_HISTORICAL_SALES in categories:
            _stream(zf, "historical_sales", _fetch_historical_sales(db))

        if CATEGORY_DEMAND_FORECASTS in categories:
            _stream(zf, "demand_forecasts", _fetch_demand_forecasts(db))

        if CATEGORY_AUDIT_LOG in categories:
            _stream(zf, "audit_log", _fetch_audit_log(db))

        if CATEGORY_NOTIFICATIONS in categories:
            _stream(zf, "notifications", _fetch_notifications(db))

    return temp_path, zip_filename
