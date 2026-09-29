raw_hosts = [" API-1 ", "DB-1", " CACHE-1 "]
normalized = list(map(lambda host: host.strip().lower(), raw_hosts))
database_hosts = list(filter(lambda host: host.startswith("db"), normalized))
"""print(normalized)
print(database_hosts)"""

"""----------------------------------------"""
services = ["api", "worker", "scheduler"]
ports = [8000, 8001, 8002]

service_ports = dict(zip(services, ports))
print(service_ports)

"""----------------------------------------"""
from functools import partial


def format_event(level: str, service: str, message: str) -> str:
    return f"{level} {service}: {message}"


portal_warning = partial(format_event, "WARNING", "portal")
print(portal_warning("latency is above 500 ms"))
print(portal_warning("latency is above 500 ms"))
print(portal_warning("disk usage high"))
print(portal_warning("connection retry"))

format_event("WARNING", "portal", "latency is above 500 ms")