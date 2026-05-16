from app.routes.auth_routes import router as auth_router
from app.routes.dashboard_routes import router as dashboard_router
from app.routes.admin_routes import router as admin_router
from app.routes.forecast_routes import router as forecast_router
from app.routes.inventory_routes import router as inventory_router
from app.routes.report_routes import router as report_router
from app.routes.notification_routes import router as notification_router
from app.routes.item_routes import router as item_router
from app.routes.protected_routes import router as protected_router
from app.routes.backup_routes import router as backup_router
from app.routes.export_routes import router as export_router

__all__ = [
    "item_router",
    "auth_router",
    "protected_router",
    "admin_router",
    "inventory_router",
    "report_router",
    "notification_router",
    "forecast_router",
    "dashboard_router",
    "backup_router",
    "export_router",
]
