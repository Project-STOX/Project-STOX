import csv
import io
from decimal import Decimal, InvalidOperation

from fastapi import HTTPException, status

from sqlalchemy import Select, select
from sqlalchemy.orm import Session, selectinload

from app.core.security.input_sanitizer import sanitize_text
from app.models.product import Product
from app.models.stock_receipt import StockReceipt
from app.models.reorder_parameter import ReorderParameter
import math
from app.models.historical_sale import HistoricalSale
from app.models.supplier import Supplier
from app.schemas.imports import CsvImportResult, CsvRejectedRow
from app.schemas.product import ProductCreate, ProductUpdate
from app.schemas.stock_receipt import StockReceiptCreate, StockReceiptUpdate
from app.schemas.supplier import SupplierCreate, SupplierUpdate


def _product_status(current_qty: int, reorder_level: int, overstock_level: int | None = None) -> str:
    if current_qty <= reorder_level:
        return "Low Stock"
    if overstock_level is not None and current_qty >= overstock_level:
        return "High Stock"
    return "In Stock"


def _normalize_status(raw_status: str | None, current_qty: int, reorder_level: int) -> str:
    normalized = (raw_status or "").strip()
    if normalized in {"Low Stock", "In Stock", "High Stock", "Discontinued"}:
        return normalized
    return _product_status(current_qty, reorder_level)


def sanitize_csv_cell(value: str) -> str:
    sanitized = value.strip()
    if sanitized and sanitized[0] in {"=", "+", "-", "@"}:
        sanitized = sanitized[1:].strip()
    return sanitized

def _calculate_eoq(db: Session, product_id: int, ordering_cost: Decimal, holding_cost: Decimal) -> Decimal | None:
    if ordering_cost <= 0 or holding_cost <= 0:
        return None
        
    from sqlalchemy import func
    stmt = select(
        func.sum(HistoricalSale.quantity_sold),
        func.min(HistoricalSale.sale_date),
        func.max(HistoricalSale.sale_date)
    ).where(HistoricalSale.product_id == product_id)
    
    result = db.execute(stmt).first()
    if not result or not result[0] or not result[1] or not result[2]:
        return None
        
    total_qty = result[0]
    min_date = result[1]
    max_date = result[2]
    
    days_span = (max_date - min_date).days + 1
    if days_span <= 0:
        days_span = 1
        
    daily_demand = float(total_qty) / days_span
    annual_demand = daily_demand * 365
    
    if annual_demand <= 0:
        return None
        
    eoq = math.sqrt((2 * annual_demand * float(ordering_cost)) / float(holding_cost))
    return Decimal(str(round(eoq, 2)))

class SupplierService:
    @staticmethod
    def list_suppliers(
        db: Session, *, limit: int, offset: int, name: str | None, is_active: bool | None
    ) -> list[Supplier]:
        stmt: Select[tuple[Supplier]] = select(Supplier).order_by(Supplier.id.desc()).limit(limit).offset(offset)
        if name:
            stmt = stmt.where(Supplier.name.ilike(f"%{sanitize_text(name, max_length=255)}%"))
        return list(db.scalars(stmt).all())

    @staticmethod
    def get_supplier(db: Session, supplier_id: int) -> Supplier:
        supplier = db.get(Supplier, supplier_id)
        if supplier is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Supplier not found")
        return supplier

    @staticmethod
    def create_supplier(db: Session, payload: SupplierCreate, created_by: int) -> Supplier:
        data = payload.model_dump()
        contact_info = data.get("email") or data.get("phone")
        supplier = Supplier(
            name=sanitize_text(str(data["name"]), max_length=100),
            contact_info=sanitize_text(str(contact_info), max_length=150) if contact_info else None,
            address=sanitize_text(str(data.get("address") or ""), max_length=255) if data.get("address") else None,
            lead_time_days=data.get("lead_time_days") or 0,
            created_by=created_by,
        )
        db.add(supplier)
        db.commit()
        db.refresh(supplier)
        return supplier

    @staticmethod
    def update_supplier(db: Session, supplier: Supplier, payload: SupplierUpdate) -> Supplier:
        updates = payload.model_dump(exclude_none=True)
        if "name" in updates:
            supplier.name = sanitize_text(str(updates["name"]), max_length=100)
        
        email = updates.get("email")
        phone = updates.get("phone")
        if email or phone:
            contact_info = email or phone
            supplier.contact_info = sanitize_text(str(contact_info), max_length=150)
            
        if "address" in updates:
            supplier.address = sanitize_text(str(updates["address"]), max_length=255) if updates["address"] else None
        if "lead_time_days" in updates:
            supplier.lead_time_days = int(updates["lead_time_days"])
            
        db.commit()
        db.refresh(supplier)
        return supplier

    @staticmethod
    def delete_supplier(db: Session, supplier: Supplier) -> None:
        has_products = db.scalar(select(Product.id).where(Product.supplier_id == supplier.id).limit(1))
        if has_products:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot delete supplier with linked products",
            )
        db.delete(supplier)
        db.commit()


class ProductService:
    @staticmethod
    def _validate_supplier_exists(db: Session, supplier_id: int) -> None:
        if db.get(Supplier, supplier_id) is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid supplier_id")

    @staticmethod
    def list_products(
        db: Session,
        *,
        limit: int,
        offset: int,
        supplier_id: int | None,
        status_flag: str | None,
        search: str | None,
    ) -> list[Product]:
        stmt: Select[tuple[Product]] = (
            select(Product)
            .options(selectinload(Product.reorder_params))
            .order_by(Product.id.desc())
            .limit(limit)
            .offset(offset)
        )
        if supplier_id is not None:
            stmt = stmt.where(Product.supplier_id == supplier_id)
        if status_flag:
            stmt = stmt.where(Product.status_flag == sanitize_text(status_flag.upper(), max_length=32))
        if search:
            search_value = f"%{sanitize_text(search, max_length=255)}%"
            stmt = stmt.where(Product.name.ilike(search_value) | Product.sku.ilike(search_value) | Product.product_code.ilike(search_value))
        products = list(db.scalars(stmt).all())
        for product in products:
            product.status_flag = _normalize_status(product.status_flag, product.current_qty, product.reorder_level)
        return products

    @staticmethod
    def get_product(db: Session, product_id: int) -> Product:
        product = db.scalar(
            select(Product)
            .where(Product.id == product_id)
            .options(selectinload(Product.reorder_params))
        )
        if product is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
        product.status_flag = _normalize_status(product.status_flag, product.current_qty, product.reorder_level)
        return product

    @staticmethod
    def create_product(db: Session, payload: ProductCreate, actor_id: int) -> Product:
        ProductService._validate_supplier_exists(db, payload.supplier_id)
        
        if db.scalar(select(Product.id).where(Product.product_code == payload.product_code)):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Product code must be unique")
        if db.scalar(select(Product.id).where(Product.sku == payload.sku)):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="SKU must be unique")
        status_flag = _product_status(payload.current_qty, payload.reorder_level)
        data = payload.model_dump()
        safety_stock_val = payload.overstock_level
        data.pop("overstock_level", None)
        lead_time = data.pop("lead_time_days", None)
        data["sku"] = sanitize_text(data["sku"], max_length=50)
        data["name"] = sanitize_text(data["name"], max_length=100)
        product = Product(**data, status_flag=status_flag)
        db.add(product)
        db.flush() # Get product.id
        
        param = ReorderParameter(
            product_id=product.id,
            configured_by=actor_id,
            lead_time_days=lead_time,
            safety_stock=safety_stock_val,
            eoq=_calculate_eoq(db, product.id, product.ordering_cost, product.holding_cost)
        )
        db.add(param)
            
        db.commit()
        db.refresh(product)
        return product

    @staticmethod
    def update_product(db: Session, product: Product, payload: ProductUpdate, actor_id: int) -> Product:
        updates = payload.model_dump(exclude_none=True)
        safety_stock_val = updates.pop("overstock_level", None)
        lead_time = updates.pop("lead_time_days", None)
        
        if "supplier_id" in updates:
            ProductService._validate_supplier_exists(db, int(updates["supplier_id"]))
        if "sku" in updates:
            updates["sku"] = sanitize_text(str(updates["sku"]), max_length=50)
            if db.scalar(select(Product.id).where(Product.sku == updates["sku"], Product.id != product.id)):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="SKU must be unique")
        if "product_code" in updates:
            updates["product_code"] = sanitize_text(str(updates["product_code"]), max_length=50)
            if db.scalar(select(Product.id).where(Product.product_code == updates["product_code"], Product.id != product.id)):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Product code must be unique")
        if "name" in updates:
            updates["name"] = sanitize_text(str(updates["name"]), max_length=100)
            
        for key, value in updates.items():
            setattr(product, key, value)
            
        product.status_flag = _product_status(product.current_qty, product.reorder_level)
        
        if product.reorder_params:
            if lead_time is not None:
                product.reorder_params.lead_time_days = lead_time
            if safety_stock_val is not None:
                product.reorder_params.safety_stock = safety_stock_val
            product.reorder_params.configured_by = actor_id
            product.reorder_params.eoq = _calculate_eoq(db, product.id, product.ordering_cost, product.holding_cost)
        else:
            param = ReorderParameter(
                product_id=product.id,
                configured_by=actor_id,
                lead_time_days=lead_time,
                safety_stock=safety_stock_val if safety_stock_val is not None else product.reorder_level,
                eoq=_calculate_eoq(db, product.id, product.ordering_cost, product.holding_cost)
            )
            db.add(param)
                
        db.commit()
        db.refresh(product)
        return product

    @staticmethod
    def delete_product(db: Session, product: Product) -> None:
        has_receipts = db.scalar(select(StockReceipt.id).where(StockReceipt.product_id == product.id).limit(1))
        if has_receipts:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot delete product with stock receipts",
            )
            
        has_sales = db.scalar(select(HistoricalSale.id).where(HistoricalSale.product_id == product.id).limit(1))
        if has_sales:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot delete product with historical sales records",
            )
            
        db.delete(product)
        db.commit()


class StockReceiptService:
    @staticmethod
    def list_receipts(
        db: Session,
        *,
        limit: int,
        offset: int,
        product_id: int | None,
        supplier_id: int | None,
        reference_no: str | None,
    ) -> list[StockReceipt]:
        stmt: Select[tuple[StockReceipt]] = (
            select(StockReceipt)
            .options(selectinload(StockReceipt.user))
            .order_by(StockReceipt.id.desc())
            .limit(limit)
            .offset(offset)
        )
        if product_id is not None:
            stmt = stmt.where(StockReceipt.product_id == product_id)
        if supplier_id is not None:
            stmt = stmt.where(StockReceipt.supplier_id == supplier_id)
        if reference_no:
            stmt = stmt.where(StockReceipt.reference_no.ilike(f"%{sanitize_text(reference_no, max_length=100)}%"))
        return list(db.scalars(stmt).all())

    @staticmethod
    def get_receipt(db: Session, receipt_id: int) -> StockReceipt:
        receipt = db.scalar(select(StockReceipt).where(StockReceipt.id == receipt_id).options(selectinload(StockReceipt.user)))
        if receipt is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Stock receipt not found")
        return receipt

    @staticmethod
    def create_receipt(db: Session, payload: StockReceiptCreate, recorded_by: int) -> StockReceipt:
        product = db.get(Product, payload.product_id)
        if product is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid product_id")
        supplier = db.get(Supplier, payload.supplier_id)
        if supplier is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid supplier_id")

        data = payload.model_dump()
        if data.get("reference_no") is not None:
            data["reference_no"] = sanitize_text(str(data["reference_no"]), max_length=100)
        data.pop("unit_cost", None)
        
        # Ensure quantity_damaged is extracted
        quantity_damaged = data.get("quantity_damaged", 0)
        
        received_at = data.get("received_at")
        if received_at is None:
            data.pop("received_at", None)
            
        receipt = StockReceipt(**data, recorded_by=recorded_by)
        
        # REVERTED: Now adds full quantity regardless of damage
        product.current_qty += payload.quantity
        product.status_flag = _product_status(product.current_qty, product.reorder_level)
        db.add(receipt)
        db.commit()
        db.refresh(receipt)
        return receipt

    @staticmethod
    def update_receipt(db: Session, receipt: StockReceipt, payload: StockReceiptUpdate, updated_by: int) -> StockReceipt:
        updates = payload.model_dump(exclude_none=True)

        next_product_id = int(updates.get("product_id", receipt.product_id))
        next_supplier_id = int(updates.get("supplier_id", receipt.supplier_id))
        next_quantity = int(updates.get("quantity", receipt.quantity))
        next_damaged = int(updates.get("quantity_damaged", receipt.quantity_damaged))
        next_reference_no = updates.get("reference_no", receipt.reference_no)

        next_product = db.get(Product, next_product_id)
        if next_product is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid product_id")
        if db.get(Supplier, next_supplier_id) is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid supplier_id")

        old_product = db.get(Product, receipt.product_id)
        if old_product is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Linked product does not exist")

        # REVERTED: Now uses full quantity regardless of damage
        old_val = receipt.quantity
        next_val = next_quantity

        if receipt.product_id == next_product_id:
            adjusted_qty = old_product.current_qty - old_val + next_val
            if adjusted_qty < 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Stock receipt update would make product quantity negative",
                )
            old_product.current_qty = adjusted_qty
            old_product.status_flag = _product_status(old_product.current_qty, old_product.reorder_level)
        else:
            source_adjusted = old_product.current_qty - old_val
            if source_adjusted < 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Stock receipt update would make source product quantity negative",
                )
            old_product.current_qty = source_adjusted
            old_product.status_flag = _product_status(old_product.current_qty, old_product.reorder_level)
            next_product.current_qty += next_val
            next_product.status_flag = _product_status(next_product.current_qty, next_product.reorder_level)

        receipt.product_id = next_product_id
        receipt.supplier_id = next_supplier_id
        receipt.quantity = next_quantity
        receipt.quantity_damaged = next_damaged
        receipt.recorded_by = updated_by
        receipt.reference_no = (
            sanitize_text(str(next_reference_no), max_length=100) if next_reference_no is not None else None
        )
        if "received_at" in updates and updates["received_at"] is not None:
            receipt.received_at = updates["received_at"]

        db.commit()
        db.refresh(receipt)
        return receipt

    @staticmethod
    def delete_receipt(db: Session, receipt: StockReceipt) -> None:
        product = db.get(Product, receipt.product_id)
        if product is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Linked product does not exist")
        next_qty = product.current_qty - receipt.quantity
        if next_qty < 0:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Stock receipt deletion would make product quantity negative",
            )
        product.current_qty = next_qty
        product.status_flag = _product_status(product.current_qty, product.reorder_level)
        db.delete(receipt)
        db.commit()


class CsvImportService:
    REQUIRED_PRODUCT_HEADERS = {
        "product_code",
        "sku",
        "product_name",
        "supplier_id",
        "unit_cost",
    }

    REQUIRED_RECEIPT_HEADERS = {
        "product_code",
        "supplier_id",
        "quantity_received",
    }

    @staticmethod
    def _parse_positive_int(raw: str, field: str) -> int:
        try:
            value = int(float(raw))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"{field} must be an integer") from exc
        if value < 0:
            raise ValueError(f"{field} cannot be negative")
        return value

    @staticmethod
    def _parse_optional_int(raw: str, field: str) -> int | None:
        if not raw or raw.strip().lower() == "n/a" or raw.strip() == "":
            return None
        return CsvImportService._parse_positive_int(raw, field)

    @staticmethod
    def _parse_decimal(raw: str, field: str) -> Decimal:
        try:
            value = Decimal(raw)
        except (InvalidOperation, TypeError) as exc:
            raise ValueError(f"{field} must be a decimal number") from exc
        if value < 0:
            raise ValueError(f"{field} cannot be negative")
        return value

    @staticmethod
    def import_products_csv(db: Session, csv_content: bytes, actor_id: int) -> CsvImportResult:
        try:
            decoded = csv_content.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV must be UTF-8 encoded") from exc

        reader = csv.DictReader(io.StringIO(decoded))
        if not reader.fieldnames:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV has no header row")

        headers = {sanitize_csv_cell(h).lower().replace(" ", "_") for h in reader.fieldnames if h}
        # Check if all required headers are present (subset check allowed?)
        # Let's be strict as before but allow serial_no
        if not CsvImportService.REQUIRED_PRODUCT_HEADERS.issubset(headers):
            missing = CsvImportService.REQUIRED_PRODUCT_HEADERS - headers
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid CSV. Missing headers: {', '.join(missing)}",
            )

        inserted_rows = 0
        errors: list[CsvRejectedRow] = []

        for index, row in enumerate(reader, start=2):
            try:
                normalized_row = {
                    sanitize_csv_cell(str(key)).lower().replace(" ", "_"): value for key, value in row.items() if key is not None
                }

                product_code = sanitize_csv_cell(str(normalized_row.get("product_code", "")))
                sku = sanitize_csv_cell(str(normalized_row.get("sku", "")))
                name = sanitize_csv_cell(str(normalized_row.get("product_name", normalized_row.get("name", ""))))
                if not product_code:
                    raise ValueError("product_code is required")
                if not sku:
                    raise ValueError("sku is required")
                if not name:
                    raise ValueError("product_name is required")

                supplier_id = CsvImportService._parse_positive_int(
                    str(normalized_row.get("supplier_id", "")),
                    "supplier_id",
                )
                
                current_qty_raw = str(normalized_row.get("current_qty", "")).strip()
                current_qty = CsvImportService._parse_positive_int(current_qty_raw, "current_qty") if current_qty_raw else 0
                
                reorder_level_raw = str(normalized_row.get("reorder_level", "")).strip()
                reorder_level = CsvImportService._parse_positive_int(reorder_level_raw, "reorder_level") if reorder_level_raw else 10
                
                overstock_level_raw = str(normalized_row.get("overstock_level", "")).strip()
                overstock_level = CsvImportService._parse_positive_int(overstock_level_raw, "overstock_level") if overstock_level_raw else 500

                unit_cost = CsvImportService._parse_decimal(str(normalized_row.get("unit_cost", "")), "unit_cost")
                
                holding_cost_raw = str(normalized_row.get("holding_cost", "")).strip()
                holding_cost = CsvImportService._parse_decimal(holding_cost_raw, "holding_cost") if holding_cost_raw else Decimal("0.00")
                
                ordering_cost_raw = str(normalized_row.get("ordering_cost", "")).strip()
                ordering_cost = CsvImportService._parse_decimal(ordering_cost_raw, "ordering_cost") if ordering_cost_raw else Decimal("0.00")

                # Robust search for serial number in case of extra spaces
                serial_no_raw = ""
                for k, v in normalized_row.items():
                    if "serial" in k or k == "sn":
                        serial_no_raw = str(v)
                        break
                        
                serial_no = CsvImportService._parse_optional_int(serial_no_raw, "serial_no")

                if overstock_level < reorder_level:
                    raise ValueError("overstock_level must be greater than or equal to reorder_level")

                ProductService._validate_supplier_exists(db, supplier_id)

                payload = ProductCreate(
                    product_code=product_code,
                    sku=sku,
                    name=name,
                    supplier_id=supplier_id,
                    current_qty=current_qty,
                    reorder_level=reorder_level,
                    overstock_level=overstock_level,
                    unit_cost=unit_cost,
                    serial_no=serial_no,
                    holding_cost=holding_cost,
                    ordering_cost=ordering_cost,
                )
                ProductService.create_product(db, payload, actor_id=actor_id)
                inserted_rows += 1
            except HTTPException as exc:
                errors.append(CsvRejectedRow(row_number=index, reason=str(exc.detail)))
            except Exception as exc:
                errors.append(CsvRejectedRow(row_number=index, reason=f"Invalid row format: {str(exc)}"))

        return CsvImportResult(
            inserted_rows=inserted_rows,
            rejected_rows=len(errors),
            errors=errors,
        )

    @staticmethod
    def import_receipts_csv(db: Session, csv_content: bytes, actor_id: int) -> CsvImportResult:
        try:
            decoded = csv_content.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV must be UTF-8 encoded") from exc

        reader = csv.DictReader(io.StringIO(decoded))
        if not reader.fieldnames:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV has no header row")

        headers = {sanitize_csv_cell(h).lower().replace(" ", "_") for h in reader.fieldnames if h}
        if not CsvImportService.REQUIRED_RECEIPT_HEADERS.issubset(headers):
            missing = CsvImportService.REQUIRED_RECEIPT_HEADERS - headers
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid CSV. Missing headers: {', '.join(missing)}",
            )

        inserted_rows = 0
        errors: list[CsvRejectedRow] = []

        for index, row in enumerate(reader, start=2):
            try:
                normalized_row = {
                    sanitize_csv_cell(str(key)).lower().replace(" ", "_"): value for key, value in row.items() if key is not None
                }

                product_code = sanitize_csv_cell(str(normalized_row.get("product_code", "")))
                if not product_code:
                    raise ValueError("product_code is required")

                product = db.scalar(select(Product).where(Product.product_code == product_code))
                if product is None:
                    raise ValueError(f"Product code {product_code} not found")

                supplier_id = CsvImportService._parse_positive_int(
                    str(normalized_row.get("supplier_id", "")),
                    "supplier_id",
                )
                ProductService._validate_supplier_exists(db, supplier_id)

                quantity = CsvImportService._parse_positive_int(
                    str(normalized_row.get("quantity_received", "")),
                    "quantity_received",
                )
                quantity_damaged = CsvImportService._parse_optional_int(
                    str(normalized_row.get("quantitiy_damage", "")),
                    "quantitiy_damage",
                ) or 0
                
                reference_no = sanitize_csv_cell(str(normalized_row.get("remarks", "") or normalized_row.get("reference_no", "")))
                received_at_raw = normalized_row.get("receipt_date") or normalized_row.get("received_at")

                payload = StockReceiptCreate(
                    product_id=product.id,
                    supplier_id=supplier_id,
                    quantity=quantity,
                    quantity_damaged=quantity_damaged,
                    reference_no=reference_no or None,
                    received_at=received_at_raw, 
                    unit_cost=Decimal("0.00"), # Default for import
                )

                StockReceiptService.create_receipt(db, payload, recorded_by=actor_id)
                inserted_rows += 1
            except HTTPException as exc:
                errors.append(CsvRejectedRow(row_number=index, reason=str(exc.detail)))
            except Exception as exc:
                errors.append(CsvRejectedRow(row_number=index, reason=f"Invalid row format: {str(exc)}"))

        return CsvImportResult(
            inserted_rows=inserted_rows,
            rejected_rows=len(errors),
            errors=errors,
        )
