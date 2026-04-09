from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security.rbac import require_any_permissions, require_permissions
from app.db.database import get_db
from app.models.user import User
from app.schemas.item import ItemCreate, ItemRead, ItemUpdate
from app.services.item_service import ItemService

router = APIRouter(prefix="/items", tags=["items"])


@router.get("/", response_model=list[ItemRead])
def list_items(
    db: Session = Depends(get_db),
    _: User = Depends(require_any_permissions("Manage products", "Manage suppliers", "Manage stock")),
) -> list[ItemRead]:
    return ItemService.list_items(db)


@router.post("/", response_model=ItemRead, status_code=status.HTTP_201_CREATED)
def create_item(
    payload: ItemCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage products")),
) -> ItemRead:
    return ItemService.create_item(db, payload)


@router.patch("/{item_id}", response_model=ItemRead)
def update_item(
    item_id: int,
    payload: ItemUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_permissions("Manage products")),
) -> ItemRead:
    item = ItemService.get_item_by_id(db, item_id)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return ItemService.update_item(db, item, payload)
