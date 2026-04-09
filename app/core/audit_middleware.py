from collections.abc import Awaitable, Callable
from urllib.parse import urlparse

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from app.core.security.jwt import decode_token
from app.db.database import SessionLocal
from app.services.audit_service import AuditService


class AuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        response = await call_next(request)

        if request.method not in {"POST", "PUT", "PATCH", "DELETE"}:
            return response
        # Use rstrip to ignore trailing slashes in path checks.
        path = request.url.path.rstrip("/")
        if path.endswith("/auth/login") or path.endswith("/auth/verify-2fa"):
            return response

        user_id = self._extract_user_id(request)
        entity_type, entity_id = self._extract_entity(request.url.path)

        # Build a more meaningful action description
        method_verbs = {
            "POST": "Created",
            "PUT": "Updated",
            "PATCH": "Modified",
            "DELETE": "Deleted"
        }
        verb = method_verbs.get(request.method, request.method)
        # Singularize and capitalize entity_type for display (e.g., 'products' -> 'Product')
        display_entity = entity_type.rstrip('s').capitalize() if entity_type != "unknown" else "Entity"
        descriptive_action = f"{verb} {display_entity}"

        db = SessionLocal()
        try:
            # Prevent ForeignKeyViolation by ensuring the user still exists in the DB
            if user_id:
                from app.models.user import User
                user_exists = db.get(User, user_id)
                if user_exists:
                    AuditService.write_log(
                        db,
                        user_id=user_id,
                        action=descriptive_action,
                        entity_type=entity_type,
                        entity_id=entity_id,
                    )
        except Exception as exc:
            db.rollback()
            # Shield the original response from logging failures.
            import traceback
            with open("middleware_error.log", "a") as f:
                f.write(f"Audit logging failed: {str(exc)}\n")
                f.write(traceback.format_exc())
                f.write("\n")
        finally:
            db.close()
        return response

    @staticmethod
    def _extract_user_id(request: Request) -> int | None:
        authorization = request.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return None
        token = authorization.split(" ", 1)[1]
        try:
            payload = decode_token(token)
        except Exception:
            return None
        if payload.get("type") != "access":
            return None
        subject = payload.get("sub")
        try:
            val = int(subject) if subject else None
            return val if val != 0 else None
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _extract_entity(path: str) -> tuple[str, int]:
        normalized = urlparse(path).path.strip("/")
        parts = normalized.split("/")
        
        # Expected path format: /api/v1/<entity_type>/<entity_id>
        # Or: /api/v1/<module>/<entity_type>/<entity_id>
        
        if len(parts) >= 3:
            # Check if it's the 4th or 5th part that's the ID
            entity_type = "unknown"
            entity_id = 0
            
            # Case 1: /api/v1/users/5
            if len(parts) >= 3:
                entity_type = parts[2]
                if len(parts) > 3:
                    try:
                        entity_id = int(parts[3])
                    except ValueError:
                        # Case 2: /api/v1/inventory/products/5
                        if len(parts) > 4:
                            entity_type = parts[3] # products
                            try:
                                entity_id = int(parts[4])
                            except ValueError:
                                pass
            
            return entity_type, entity_id
        return "unknown", 0
