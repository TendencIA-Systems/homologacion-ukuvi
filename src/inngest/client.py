import inngest
import structlog

logger = structlog.get_logger()

inngest_client = inngest.Inngest(app_id="Ukuvi_Embeddings", logger=logger)