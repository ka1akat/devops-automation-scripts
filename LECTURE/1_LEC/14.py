from collections.abc import Callable

def minimum_latency(limit_ms: int) -> Callable[[int], bool]:
    def is_acceptable(actual_ms: int) -> bool:
        return actual_ms <= limit_ms
    
    return is_acceptable

login_latency_ok = minimum_latency(500)
print(login_latency_ok(420))