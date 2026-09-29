from collections.abc import Callable


def run_check(check: Callable[[str], bool], service: str) -> bool:
    return check(service)

def has_valid_name(service: str) -> bool:
    return bool(service.strip())

def is_running(status: str) -> bool:
    return status == "running"



print(run_check(has_valid_name, "portal"))
print(run_check(is_running, "running"))         
print(run_check(has_valid_name, "   "))      