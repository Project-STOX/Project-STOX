def sanitize_text(value: str, *, max_length: int | None = None) -> str:
    cleaned = " ".join(value.strip().split())
    if max_length is not None:
        cleaned = cleaned[:max_length]
    return cleaned
