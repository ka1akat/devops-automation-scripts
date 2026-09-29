with open("service.log", encoding="utf-8") as log_file:
    first_read = log_file.read()
    end_position = log_file.tell()
    log_file.seek(0)
    second_read = log_file.read()

print("Первое чтение:", first_read)
print("Позиция в конце файла:", end_position)
print("Второе чтение:", second_read)
print("Совпадают ли?", first_read == second_read)