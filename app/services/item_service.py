from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.item import Item
from app.schemas.item import ItemCreate, ItemUpdate


class ItemService:
    # get all items
    @staticmethod
    def list_items(db: Session) -> list[Item]:
        result = db.execute(select(Item).order_by(Item.id.desc()))
        return list(result.scalars().all())

    # create new item
    @staticmethod
    def create_item(db: Session, payload: ItemCreate) -> Item:
        item = Item(**payload.model_dump())
        db.add(item)
        db.commit()
        db.refresh(item)
        return item

    # get item by id
    @staticmethod
    def get_item_by_id(db: Session, item_id: int) -> Item | None:
        return db.get(Item, item_id)

    # update item
    @staticmethod
    def update_item(db: Session, item: Item, payload: ItemUpdate) -> Item:
        changes = payload.model_dump(exclude_none=True)
        for field, value in changes.items():
            setattr(item, field, value)
        db.commit()
        db.refresh(item)
        return item
