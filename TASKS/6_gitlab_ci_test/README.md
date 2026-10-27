# Task 6 — добавить этап test

## Задание
Расширить `.gitlab-ci.yml` из Task 5: добавить второй этап `test`
и задачу `test_job`. Сделать push и убедиться, что оба этапа (build и test) прошли.

## Файл
```yaml
stages:
  - build
  - test

build_job:
  stage: build
  script:
    - echo "Building the project..."
    - echo "This is a basic build job."

test_job:
  stage: test
  script:
    - echo "Running tests..."
    - echo "All tests passed!"
```

## Что изменилось по сравнению с Task 5
- В `stages` добавила `- test` **после** `- build`. Порядок в списке = порядок выполнения.
- `build_job` не трогала: пайплайн растёт, старое не удаляется.
- Внизу добавила новую задачу `test_job` со `stage: test`.

## Как работают два этапа
- Сначала выполняется этап `build` (задача `build_job`).
- Только если `build` прошёл успешно, начинается этап `test` (задача `test_job`).
- Если `build_job` упадёт, `test_job` **не запустится**: тестировать то, что не собралось, бессмысленно.
- Каждая задача выполняется в **своём** чистом контейнере. Файлы из `build_job` в `test_job` не видны (передать их можно через `artifacts` — это Task 7).

## Что видно в GitLab
- **Build → Pipelines**: у пайплайна два кружка в колонке Stages — `build` и `test`.
- Внутри пайплайна два столбца, по одной задаче в каждом.

## Шаблон «добавить этап»
1. Дописать имя этапа в `stages` в нужное место по порядку.
2. Добавить задачу с `stage: ИМЯ_ЭТАПА` и своим `script`.

## Результат
Пайплайн с коммитом `Task 6: simple build test pipeline` — Passed ✅, 2 этапа.