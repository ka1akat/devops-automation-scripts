# Сначала создаём и записываем файл
with open("service.log", mode="w", encoding="utf-8") as file:
    file.write("Service started\n")
    file.write("ERROR: connection timeout\n")
    file.write("Service stopped\n")

# Теперь читаем то, что записали
file = open("service.log", mode="r", encoding="utf-8")
content = file.read()
file.close()
print(content)