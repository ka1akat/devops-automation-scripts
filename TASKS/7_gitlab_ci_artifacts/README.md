# Task 7 — передача артефактов между этапами

## Задание
`build_job` создаёт файл, `test_job` должен его прочитать.
Проверить, что файл передаётся с этапа build на этап test.

## Файл
```yaml
stages:
  - build
  - test

build_job:
  stage: build
  script:
    - echo "Build complete" > build_output.txt
  artifacts:
    paths:
      - build_output.txt

test_job:
  stage: test
  script:
    - cat build_output.txt
```

## Зачем нужны artifacts
- Каждый job работает в своём чистом контейнере, после работы контейнер удаляется вместе с файлами.
- Без `artifacts` файл `build_output.txt` пропал бы, и `test_job` упал бы с ошибкой `No such file or directory`.
- `artifacts: paths:` говорит GitLab: сохрани эти файлы после job'а и отдай их следующим этапам.
- В `test_job` ничего писать не нужно: job'ы следующих этапов получают артефакты сами.

## Новое
- `echo "..." > файл` — записать текст в файл (`>` из bash).
- `artifacts:` — на одном уровне со `script:`, внутри job'а.
- `cat файл` — показать содержимое файла.

## Результат
В логе `test_job` напечаталось `Build complete` — артефакт передался ✅
Артефакт можно скачать на странице job'а (кнопка Download справа).