"""GhostPin relay: runs on the Mac, controls the USB/Wi-Fi-paired iPhone, and
exposes a token-protected HTTP API + mobile web UI reachable over the internet
through a tunnel (see run.sh)."""
from __future__ import annotations

import asyncio
import math
import os
import secrets
import time
from pathlib import Path
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from device import Device

CFG = Path.home() / ".ghostpin"
CFG.mkdir(exist_ok=True)
TOKEN_FILE = CFG / "token"
if not TOKEN_FILE.exists():
    TOKEN_FILE.write_text(secrets.token_urlsafe(24))
    TOKEN_FILE.chmod(0o600)
TOKEN = os.environ.get("GHOSTPIN_TOKEN") or TOKEN_FILE.read_text().strip()

app = FastAPI(title="GhostPin")
device = Device()
state = {"mode": "idle", "lat": None, "lng": None, "task": None, "progress": 0.0}


def auth(x_token: Optional[str] = Header(None), t: Optional[str] = Query(None)):
    given = x_token or t or ""
    if not secrets.compare_digest(given, TOKEN):
        raise HTTPException(401, "bad token")


class Point(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class Route(BaseModel):
    points: List[Point]
    speed_mps: float = Field(1.4, gt=0, le=350)
    loop: bool = False


def haversine(a: Point, b: Point) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a.lat), math.radians(b.lat)
    dp, dl = p2 - p1, math.radians(b.lng - a.lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


async def _cancel():
    t = state.get("task")
    if t and not t.done():
        t.cancel()
        try:
            await t
        except (asyncio.CancelledError, Exception):
            pass
    state["task"] = None


async def _apply(lat: float, lng: float):
    await device.set(lat, lng)
    state["lat"], state["lng"] = lat, lng


async def _walk(route: Route):
    pts = route.points
    tick = 1.0
    while True:
        total = sum(haversine(pts[i], pts[i + 1]) for i in range(len(pts) - 1)) or 1
        done = 0.0
        for a, b in zip(pts, pts[1:]):
            d = haversine(a, b)
            steps = max(1, int(d / (route.speed_mps * tick)))
            for s in range(1, steps + 1):
                f = s / steps
                await _apply(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f)
                state["progress"] = min(1.0, (done + d * f) / total)
                await asyncio.sleep(tick)
            done += d
        if not route.loop:
            break
    state["mode"] = "idle"


@app.get("/api/status", dependencies=[Depends(auth)])
async def status():
    return {"connected": device.connected, "device": device.name, "mock": device.mock,
            "mode": state["mode"], "lat": state["lat"], "lng": state["lng"],
            "progress": state["progress"]}


@app.post("/api/connect", dependencies=[Depends(auth)])
async def connect():
    try:
        return {"device": await device.connect()}
    except Exception as e:
        raise HTTPException(503, str(e))


@app.post("/api/teleport", dependencies=[Depends(auth)])
async def teleport(p: Point):
    await _cancel()
    try:
        await _apply(p.lat, p.lng)
    except Exception as e:
        raise HTTPException(503, str(e))
    state["mode"] = "teleport"
    return {"ok": True}


@app.post("/api/route", dependencies=[Depends(auth)])
async def route(r: Route):
    if len(r.points) < 2:
        raise HTTPException(400, "need at least 2 points")
    await _cancel()
    state["mode"], state["progress"] = "route", 0.0
    state["task"] = asyncio.create_task(_walk(r))
    return {"ok": True}


@app.post("/api/stop", dependencies=[Depends(auth)])
async def stop():
    await _cancel()
    state["mode"] = "idle"
    return {"ok": True}


@app.post("/api/clear", dependencies=[Depends(auth)])
async def clear():
    await _cancel()
    await device.clear()
    state.update(mode="idle", lat=None, lng=None)
    return {"ok": True}


@app.get("/")
async def index():
    return FileResponse(Path(__file__).parent / "static" / "index.html")
