import inngest

from .client import inngest_client


@inngest_client.create_function(
    fn_id="generate-embeddings",
    trigger=inngest.TriggerEvent(event="Crear version_vector - Ukuvi"),
)

async def generate_embeddings(ctx: inngest.Context) -> str:
    return "Hello world!"


functions = [generate_embeddings]

__all__ = ["functions", "generate_embeddings"]