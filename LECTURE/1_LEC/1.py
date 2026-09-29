from datetime import datetime

def get_seconds() -> int:
    return datetime.now().second

curr = get_seconds()
print(curr)