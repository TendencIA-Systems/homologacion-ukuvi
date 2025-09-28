import asyncio

from inngest.connect import connect
from src.inngest.client import inngest_client
from src.inngest.functions import generate_embeddings

asyncio.run(connect([(inngest_client, [generate_embeddings])]).start())