def split_tags(tag_string: str) -> list[str]:
    """Это функция которая бла бла бла"""
    tags = []
    for i in tag_string.split(","):
        tags.append(i.strip())

    return tags
curr = split_tags("python, c++, kaspi")
print(curr)
print(split_tags.__name__)
print(split_tags.__doc__) 
