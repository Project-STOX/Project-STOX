from sqlalchemy import create_engine, select, func
from sqlalchemy.orm import Session
from app.core.config import get_settings
from app.models.permission import Permission
from app.models.role import Role
from app.models.role_permission import RolePermission
from app.models.user import User

settings = get_settings()
engine = create_engine(settings.database_url)

with Session(engine) as session:
    print("--- Permissions ---")
    perms = session.scalars(select(Permission)).all()
    for p in perms:
        print(f"ID: {p.id}, Name: '{p.action_name}'")

    print("\n--- Roles ---")
    roles = session.scalars(select(Role)).all()
    for r in roles:
        print(f"ID: {r.id}, Name: '{r.role_name}'")

    print("\n--- Role-Permission Mappings ---")
    mappings = session.query(RolePermission, Role, Permission).join(Role).join(Permission).all()
    for mp, r, p in mappings:
        print(f"Role: {r.role_name} (ID: {r.id}) -> Permission: {p.action_name} (ID: {p.id})")

    print("\n--- Users ---")
    users = session.scalars(select(User)).all()
    for u in users:
        print(f"User: {u.full_name}, Role ID: {u.role_id}")
