def event_app(
        event: str,
        events: list[str] | None = None
) -> list[str]:
    if events == None:
        events = []

    events.append(event)
    return events
    
print(event_app("started"))
print(event_app("completed"))
