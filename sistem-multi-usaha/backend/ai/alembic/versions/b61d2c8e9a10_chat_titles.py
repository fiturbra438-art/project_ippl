from alembic import op
import sqlalchemy as sa

revision = "b61d2c8e9a10"
down_revision = "900cc2f22a4a"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("chat_sessions", sa.Column("title", sa.Text(), nullable=False, server_default="Percakapan"))


def downgrade():
    op.drop_column("chat_sessions", "title")
