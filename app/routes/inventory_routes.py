from fastapi import APIRouter, Depends, File, HTTPException, Query, Response, UploadFile, status
from sqlalchemy.orm import Session

from app.core.security.rbac import require_any_permissions, require_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.imports import CsvImportResult
from app.schemas.product import ProductCreate, ProductRead, ProductUpdate
from app.schemas.stock_receipt import StockReceiptCreate, StockReceiptRead, StockReceiptUpdate
from app.schemas.supplier import SupplierCreate, SupplierRead, SupplierUpdate
from app.services.inventory_service import CsvImportService, ProductService, StockReceiptService, SupplierService

router = APIRouter(prefix="/inventory", tags=["inventory"])


@router.get("/suppliers", response_model=list[SupplierRead])
def list_suppliers(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    name: str | None = Query(default=None),
    is_active: bool | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage suppliers", "Manage products", "Manage stock", "View forecasts")),
) -> list[SupplierRead]:
    return SupplierService.list_suppliers(db, limit=limit, offset=offset, name=name, is_active=is_active)


@router.post("/suppliers", response_model=SupplierRead, status_code=status.HTTP_201_CREATED)
def create_supplier(
    payload: SupplierCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage suppliers")),
) -> SupplierRead:
    return SupplierService.create_supplier(db, payload, created_by=current_user.id)


@router.get("/suppliers/{supplier_id}", response_model=SupplierRead)
def get_supplier(
    supplier_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage suppliers", "Manage products", "Manage stock", "View forecasts")),
) -> SupplierRead:
    return SupplierService.get_supplier(db, supplier_id)


@router.put("/suppliers/{supplier_id}", response_model=SupplierRead)
def update_supplier(
    supplier_id: int,
    payload: SupplierUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage suppliers")),
) -> SupplierRead:
    supplier = SupplierService.get_supplier(db, supplier_id)
    return SupplierService.update_supplier(db, supplier, payload)


@router.delete("/suppliers/{supplier_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_supplier(
    supplier_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage suppliers")),
) -> Response:
    supplier = SupplierService.get_supplier(db, supplier_id)
    SupplierService.delete_supplier(db, supplier)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/products", response_model=list[ProductRead])
def list_products(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    supplier_id: int | None = Query(default=None, ge=1),
    status_flag: str | None = Query(default=None),
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage stock", "Manage suppliers", "View forecasts")),
) -> list[ProductRead]:
    return ProductService.list_products(
        db,
        limit=limit,
        offset=offset,
        supplier_id=supplier_id,
        status_flag=status_flag,
        search=search,
    )


@router.post("/products", response_model=ProductRead, status_code=status.HTTP_201_CREATED)
def create_product(
    payload: ProductCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage products")),
) -> ProductRead:
    return ProductService.create_product(db, payload, actor_id=current_user.id)


@router.get("/products/{product_id}", response_model=ProductRead)
def get_product(
    product_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage stock", "Manage suppliers", "View forecasts")),
) -> ProductRead:
    return ProductService.get_product(db, product_id)


@router.put("/products/{product_id}", response_model=ProductRead)
def update_product(
    product_id: int,
    payload: ProductUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage products")),
) -> ProductRead:
    product = ProductService.get_product(db, product_id)
    return ProductService.update_product(db, product, payload, actor_id=current_user.id)


@router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(
    product_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage products")),
) -> Response:
    product = ProductService.get_product(db, product_id)
    ProductService.delete_product(db, product)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/stock-receipts", response_model=list[StockReceiptRead])
def list_stock_receipts(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    product_id: int | None = Query(default=None, ge=1),
    supplier_id: int | None = Query(default=None, ge=1),
    reference_no: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage stock", "Manage products", "Manage suppliers", "View forecasts")),
) -> list[StockReceiptRead]:
    return StockReceiptService.list_receipts(
        db,
        limit=limit,
        offset=offset,
        product_id=product_id,
        supplier_id=supplier_id,
        reference_no=reference_no,
    )


@router.post("/stock-receipts", response_model=StockReceiptRead, status_code=status.HTTP_201_CREATED)
def create_stock_receipt(
    payload: StockReceiptCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage stock")),
) -> StockReceiptRead:
    return StockReceiptService.create_receipt(db, payload, recorded_by=current_user.id)


@router.get("/stock-receipts/{receipt_id}", response_model=StockReceiptRead)
def get_stock_receipt(
    receipt_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage stock", "Manage products", "Manage suppliers", "View forecasts")),
) -> StockReceiptRead:
    return StockReceiptService.get_receipt(db, receipt_id)


@router.put("/stock-receipts/{receipt_id}", response_model=StockReceiptRead)
def update_stock_receipt(
    receipt_id: int,
    payload: StockReceiptUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage stock")),
) -> StockReceiptRead:
    receipt = StockReceiptService.get_receipt(db, receipt_id)
    return StockReceiptService.update_receipt(db, receipt, payload, updated_by=current_user.id)


@router.delete("/stock-receipts/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_stock_receipt(
    receipt_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage stock")),
) -> Response:
    receipt = StockReceiptService.get_receipt(db, receipt_id)
    StockReceiptService.delete_receipt(db, receipt)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/products/import-csv", response_model=CsvImportResult)
async def import_products_csv(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage products")),
) -> CsvImportResult:
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only CSV files are allowed")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded CSV is empty")
    return CsvImportService.import_products_csv(db, content, actor_id=current_user.id)


@router.post("/stock-receipts/import-csv", response_model=CsvImportResult)
async def import_stock_receipts_csv(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permissions("Manage stock")),
) -> CsvImportResult:
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only CSV files are allowed")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded CSV is empty")
    return CsvImportService.import_receipts_csv(db, content, actor_id=current_user.id)

