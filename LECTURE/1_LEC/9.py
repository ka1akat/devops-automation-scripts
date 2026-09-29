def print_items(**meta: str) -> None:
    print(type(meta))
    for i,j in meta.items():
        print(f"{i} - {j}")

print_items(service="portal", fruit = "apple")
d1 = {
    "service" : "portal",
    "fruit" : "apple"
}
print_items(**d1)