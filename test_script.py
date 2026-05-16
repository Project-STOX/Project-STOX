def sanitize_csv_cell(value: str) -> str:
    sanitized = value.strip()
    if sanitized and sanitized[0] in {"=", "+", "-", "@"}:
        sanitized = sanitized[1:].strip()
    return sanitized

def test_csv_row():
    headers = ["product code", "product name", "supplier id", "sku", "unit cost", "serial number", " holding cost", " ordering cost"]
    row_values = ["P100", "Prod", "1", "S100", "5.00", "987654321", "2.00", "1.00"]
    raw_row = dict(zip(headers, row_values))

    normalized_row = {
        sanitize_csv_cell(str(key)).lower().replace(" ", "_"): value for key, value in raw_row.items() if key is not None
    }

    print("Normalized keys:", normalized_row.keys())

    serial_no_raw = ""
    for k, v in normalized_row.items():
        if "serial" in k or k == "sn":
            serial_no_raw = str(v)
            break
            
    print("serial_no_raw:", serial_no_raw)
test_csv_row()
