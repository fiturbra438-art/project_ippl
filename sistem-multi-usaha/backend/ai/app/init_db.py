from pathlib import Path
import re
from sqlalchemy import text

from app.database import engine


def main() -> None:
    schema_path = Path("/schema/schema_database.sql")
    if not schema_path.exists():
        raise RuntimeError("schema_database.sql tidak ditemukan")
    
    sql_content = schema_path.read_text(encoding="utf-8")
    with engine.begin() as connection:
        connection.execute(text(sql_content))


if __name__ == "__main__":
    main()

