import os
from fastapi import FastAPI
from mcstatus import JavaServer

app = FastAPI()

MC_HOST = os.getenv("MC_HOST", "mc")
MC_PORT = int(os.getenv("MC_PORT", "25565"))

@app.get("/api/status")
async def get_status():
    try:
        # mcstatus will resolve mc:25565 using the docker compose internal dns mapping
        server = await JavaServer.async_lookup(f"{MC_HOST}:{MC_PORT}", timeout=3.0)
        status = await server.async_status()
        
        # We try to mimic the format the dashboard expected from mcsrvstat.us
        # to minimize JS updates
        return {
            "online": True,
            "version": status.version.name,
            "players": {
                "online": status.players.online,
                "max": status.players.max
            },
            "motd": {
                "clean": [status.motd.to_plain()]
            }
        }
    except Exception as e:
        return {
            "online": False,
            "error": str(e)
        }
