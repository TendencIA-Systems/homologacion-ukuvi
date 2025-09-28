import asyncio

from inngest.connect import connect

from src.inngest.client import inngest_client
from src.inngest.functions import functions


async def main() -> None:
	await connect(apps=[(inngest_client, functions)]).start()


if __name__ == "__main__":
	asyncio.run(main())