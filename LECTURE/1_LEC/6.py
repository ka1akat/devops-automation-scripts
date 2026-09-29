def append_event(
        event: str,
        events: list[str] = []

) -> list[str]:
    events.append(event)
    return events

print(append_event("started"))
print(append_event("completed"))
    