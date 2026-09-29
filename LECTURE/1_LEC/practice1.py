def is_healthy(status:str) -> bool:
    if status == "running":
        return True
    else:
        return False

a = input()
print(is_healthy(a))