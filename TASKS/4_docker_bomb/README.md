# Task 4 — "Is it a bomb?" Investigate and fix a Docker image

## Task

```bash
docker pull svroman0502/kbtu-devops-bomb:1.0.0
```

- **4.1** Is it a bomb or not? Run the image.
- **4.2** Fix the image and push it to Docker Hub.

## 4.1 Investigation

An unknown image was inspected **before** running it.

**1. Image history (the build recipe):**

```bash
docker history --no-trunc svroman0502/kbtu-devops-bomb:1.0.0
```

```
CMD ["cat" "/hello.txt"]
COPY hello.txt /hello.txt
WORKDIR /app
```

There is no base OS layer — the image is built `FROM scratch` (an empty image).

**2. File content, extracted without running the image:**

```bash
docker create --name bomb-check svroman0502/kbtu-devops-bomb:1.0.0
docker cp bomb-check:/hello.txt ./hello.txt
docker rm bomb-check
wc -c hello.txt    # 13 bytes
file hello.txt     # ASCII text
cat hello.txt      # Hello, World!
```

**3. Run with resource limits** (protection in case it really is a bomb):

```bash
docker run --rm --memory=100m --cpus=0.5 --pids-limit=50 svroman0502/kbtu-devops-bomb:1.0.0
```

```
exec: "cat": executable file not found in $PATH
```

**Answer: it is not a bomb, it is a broken image.** It contains only `hello.txt`. Because the image is built from `scratch`, there is no `cat` binary (no `/bin` at all), so the `CMD` cannot run and the container fails to start.

## 4.2 Fix

[`Dockerfile`](Dockerfile) — the same recipe, with a base image that contains `cat`:

```dockerfile
FROM busybox:1.36            # fix: a minimal base image (~2 MB) with cat
WORKDIR /app
COPY hello.txt /hello.txt
CMD ["cat", "/hello.txt"]
```

Build, test, push:

```bash
docker build -t kbtu-devops-bomb-fixed:1.0.0 .
docker run --rm kbtu-devops-bomb-fixed:1.0.0          # Hello, World!

docker login
docker tag kbtu-devops-bomb-fixed:1.0.0 ka1akat/kbtu-devops-bomb:1.0.1
docker push ka1akat/kbtu-devops-bomb:1.0.1
```

Version `1.0.1` — a patch (bug-fix) version of `1.0.0`.

## Result

Fixed image on Docker Hub: [`ka1akat/kbtu-devops-bomb:1.0.1`](https://hub.docker.com/r/ka1akat/kbtu-devops-bomb)

```bash
docker run --rm ka1akat/kbtu-devops-bomb:1.0.1
# Hello, World!
```

| | Original | Fixed |
|---|---|---|
| Base image | `scratch` (empty) | `busybox:1.36` |
| `cat` available | no | yes |
| `docker run` | `"cat": executable file not found` | `Hello, World!` |