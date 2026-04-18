import qrcode
import io
import base64
import secrets
import pyotp
from typing import Tuple


class TOTPService:
    """Service for handling TOTP (Time-based One-Time Password) operations."""

    BACKUP_CODES_COUNT = 10
    BACKUP_CODE_LENGTH = 8

    @staticmethod
    def generate_secret() -> str:
        """Generate a new TOTP secret (base32 encoded random bytes)."""
        return pyotp.random_base32()

    @staticmethod
    def generate_backup_codes() -> list[str]:
        """Generate a list of backup codes for account recovery."""
        backup_codes = []
        for _ in range(TOTPService.BACKUP_CODES_COUNT):
            # Generate alphanumeric backup codes
            code = ''.join(secrets.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
                          for _ in range(TOTPService.BACKUP_CODE_LENGTH))
            backup_codes.append(code)
        return backup_codes

    @staticmethod
    def get_provisioning_uri(email: str, secret: str, app_name: str = "STOX") -> str:
        """Generate the otpauth provisioning URI for QR codes."""
        totp = pyotp.TOTP(secret)
        return totp.provisioning_uri(
            name=email,
            issuer_name=app_name
        )

    @staticmethod
    def generate_qr_code(email: str, secret: str, app_name: str = "STOX") -> str:

        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        provisioning_uri = TOTPService.get_provisioning_uri(email, secret, app_name)
        qr.add_data(provisioning_uri)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")

        # Convert to base64
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()
        return f"data:image/png;base64,{img_str}"

    @staticmethod
    def verify_totp_code(secret: str, code: str, window: int = 1) -> bool:
        """
        Verify a TOTP code against the secret.

        window: number of 30-second windows to check (1 = current, 2 = current + previous, etc.)
        """
        if not code or not secret:
            return False

        totp = pyotp.TOTP(secret)
        # Allow slight time drift (current and previous time window)
        return totp.verify(code, valid_window=window)

    @staticmethod
    def use_backup_code(backup_codes: list[str] | None, code: str) -> Tuple[bool, list[str] | None]:
        """
        Verify and consume a backup code.

        Returns: (is_valid, updated_backup_codes)
        """
        if not backup_codes or not code:
            return False, backup_codes

        code_upper = code.upper().strip()

        if code_upper in backup_codes:
            # Remove the used backup code
            updated_codes = [c for c in backup_codes if c != code_upper]
            return True, updated_codes

        return False, backup_codes
