def pairs_out(**pair: str) -> None:
    for i,j in pair.items():
        print(f"{i} - {j}") 

d1 = {
    "fruit" : "apple",
    "vegatable" : "carrot"
}
pairs_out(**d1)