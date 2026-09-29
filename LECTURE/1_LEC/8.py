def print_items(*items: str) -> None:
    print(type(items))

    for item in items:
        print(item)


print_items("api", "worker", "schedule r")
    