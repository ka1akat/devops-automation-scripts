from pathlib import Path
rep_path = Path("service1.txt")

with rep_path.open("w", encoding="utf-8") as report:
    report.write("service = portal\n")
    report.write("status = healthy\n")
    report.write("ERROR\n")
    report.write("ERROR\n")
    report.write("ERROR\n")
    

def find_errors(path: Path):
    with path.open(encoding="utf-8") as l_file:
        for line_number, line in enumerate(l_file, start=1):
            if "ERROR" in line:
                yield line_number, line.rstrip("\n")

for number, message in find_errors(Path("service1.txt")):
    print(number, message)

