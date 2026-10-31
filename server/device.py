"""Device layer: wraps pymobiledevice3's DVT LocationSimulation (iOS 17+).

If pymobiledevice3 is missing or no iPhone is reachable, falls back to a mock
so the API and web UI can still be exercised.
"""
from __future__ import annotations

import logging
from typing import Optional

log = logging.getLogger("ghostpin.device")

try:
    from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
    from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
    from pymobiledevice3.tunneld.api import get_tunneld_devices
    HAVE_PMD = True
except Exception as e:  # pragma: no cover
    log.warning("pymobiledevice3 unavailable (%s); using mock device", e)
    HAVE_PMD = False


class Device:
    def __init__(self) -> None:
        self.rsd = None
        self.dvt = None
        self.sim = None
        self.name: Optional[str] = None
        self.mock = not HAVE_PMD
        self.last: Optional[tuple[float, float]] = None

    @property
    def connected(self) -> bool:
        return self.mock or self.sim is not None

    async def connect(self) -> str:
        if not HAVE_PMD:
            self.name = "Mock iPhone"
            return self.name
        await self.close()
        devices = await get_tunneld_devices()
        if not devices:
            raise RuntimeError(
                "No iPhone found via tunneld. Plug in the phone, enable Developer Mode, "
                "and run: sudo python3 -m pymobiledevice3 remote tunneld")
        self.rsd = devices[0]
        self.dvt = DvtProvider(self.rsd)
        await self.dvt.__aenter__()
        self.sim = LocationSimulation(self.dvt)
        await self.sim.__aenter__()
        self.name = getattr(self.rsd, "udid", "iPhone")
        return self.name

    async def set(self, lat: float, lng: float) -> None:
        if not self.connected:
            await self.connect()
        self.last = (lat, lng)
        if self.mock:
            log.info("[mock] set %.6f,%.6f", lat, lng)
            return
        await self.sim.set(lat, lng)

    async def clear(self) -> None:
        self.last = None
        if self.mock:
            return
        if self.sim:
            await self.sim.clear()

    async def close(self) -> None:
        try:
            if self.sim:
                await self.sim.__aexit__(None, None, None)
            if self.dvt:
                await self.dvt.__aexit__(None, None, None)
            if self.rsd:
                await self.rsd.close()
        except Exception:
            pass
        self.rsd = self.dvt = self.sim = None
