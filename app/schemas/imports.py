from pydantic import BaseModel


class CsvRejectedRow(BaseModel):
    row_number: int
    reason: str


class CsvImportResult(BaseModel):
    inserted_rows: int
    rejected_rows: int
    errors: list[CsvRejectedRow]
