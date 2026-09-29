def format_retry_message(name: str, number: int, max_number = 3):
    return f"Retrying {name}: attempt {number} of {max_number}"

name = input()
number = int(input())
print(format_retry_message(name, number))
