from collections.abc import Callable
from functools import wraps


def retry(max_attempts: int):
    def decorator(function: Callable[..., bool]):
        @wraps(function)
        def wrapper(*args, **kwargs) -> bool:
            for attempt in range(1, max_attempts + 1):
                if function(*args, **kwargs):
                    return True
                print(f"attempt {attempt} failed")
            return False

        return wrapper

    return decorator


@retry(max_attempts=3)
def health_check(service: str) -> bool:
    return service == "portal"


print(health_check("api"))
print("---")
print(health_check("portal"))

