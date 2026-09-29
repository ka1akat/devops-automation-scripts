def add_serv(serv: list[str], s_serv: list[str]) -> None:
    serv.extend(s_serv)
serv = ["Apple", "Huawei"]
s_serv = add_serv(serv, ["Redmi"])
print(serv)