# Задание: сборка образа Armbian для NanoPi R76S через GitHub Actions

## Цель

Подготовь в этом репозитории всё для сборки образа **Armbian для FriendlyElec NanoPi R76S** с vendor-ядром **6.1.172** (Rockchip SDK rkr7.2) через **GitHub Actions**. Готовый образ должен публиковаться как GitHub Release. Полную сборку в своей песочнице не запускай: она идёт на раннерах GitHub. Твоя задача — workflow, конфигурация, документация и запуск первой сборки.

Отвечай и пиши документацию на русском. Названия, команды и код — как есть.

## Железо и контекст

- **Плата:** NanoPi R76S **rev.2**, SoC RK3576, **3 ГБ ОЗУ, без eMMC**. Загрузка **только с SD-карты**.
- **Зачем:** ядро 6.1.172 с исправлениями MPP/RGA/Mali. Это посоветовал разработчик Jellyfin (nyanmisaka, issue jellyfin/jellyfin-ffmpeg#781) для аппаратного транскодирования (`rkmpp`). Ядро `edge`/mainline не подходит: там нет полноценного `rkmpp`.
- **Сейчас на плате:** образ FriendlyElec (Proxmox/pxvirt) с ядром 6.1.141. Его не трогаем. Новый образ запишут на **запасную SD-карту** для проверки.
- **Дальше на этом образе планируется:** Docker + Portainer или pxvirt. В образе ничего из этого не нужно — только чистая минимальная система.

## Что уже известно (по состоянию на 3 октября 2026 — перепроверь в текущем `armbian/build`)

- `config/boards/nanopi-r76s.conf`: `BOARDFAMILY="rk35xx"`, `KERNEL_TARGET="vendor,edge"`, `BOOT_SCENARIO="spl-blobs"`, GPT. Есть хук `post_family_config__nanopi_r76s_use_mainline_uboot`: mainline U-Boot `tag:v2026.04`.
- `config/sources/families/rk35xx.conf`, ветка `vendor`: `KERNELBRANCH='branch:rk-6.1-rkr7.2'`, `KERNELPATCHDIR='rk35xx-vendor-6.1'`. Это и есть 6.1.172.
- **PR armbian/build#9908** («nanopi-r76s: fix SD boot and storage stability on eMMC-less units») влит 28.05.2026. Это исправление загрузки rev.2 с SD, оно должно попасть в сборку.
- **Известная проблема:** тема на форуме Armbian «NanoPi R76S: U-Boot 2026.04 warm-reboot mmc failure — OpenWrt PR 23520 workaround does not work on Armbian vendor kernel». После `reboot` (тёплой перезагрузки) U-Boot может не найти SD-карту. Проверь текущий статус: тему, открытые issue/PR в `armbian/build` по `nanopi-r76s`. Опиши в README, исправлено ли это и как обходить (например, холодное выключение питания).
- Стабильный образ Armbian 26.8.1 (11.08.2026) и стабильный репозиторий (пакеты 26.8.3) — с ядром **6.1.115**. Ночные образы R76S в `armbian/os` тоже на 6.1.115. Поэтому и нужна своя сборка из текущего `main`.
- В **beta-репозитории** (`beta.armbian.com`, trixie) 03.10.2026 уже есть пакет `linux-image-vendor-rk35xx` 26.11.0-trunk.69 с ядром **6.1.172**. Это подтверждает, что текущий `main` собирает именно 6.1.172. Альтернатива для пользователя: стабильный образ + это ядро из beta. Упомяни её в README.
- В корне `armbian/build` есть **официальный GitHub Action** (`action.yml`, «Build Armbian Linux»). Входы на момент проверки: `armbian_token`, `armbian_runner_clean`, `armbian_target`, `armbian_branch`, `armbian_kernel_branch`, `armbian_release`, `armbian_board`, `armbian_ui`, `armbian_compress`, `armbian_extensions`, `armbian_release_tag`, `armbian_release_title`, `armbian_release_body`, `armbian_release_prerelease` и другие. Прочитай актуальный `action.yml` целиком и реши, использовать его или вызывать `./compile.sh` напрямую. Выбор объясни в README.

## Параметры сборки

| Параметр | Значение по умолчанию |
|---|---|
| `BOARD` | `nanopi-r76s` |
| `BRANCH` | `vendor` |
| `RELEASE` | `trixie` (Debian 13); вход workflow, допускается `bookworm` |
| Тип образа | минимальный CLI: `BUILD_MINIMAL=yes`, `BUILD_DESKTOP=no`, `KERNEL_CONFIGURE=no` |
| Сжатие | `COMPRESS_OUTPUTIMAGE=sha,img,xz` (или эквивалент через action) |
| Прочее | `SHARE_LOG=no`; неинтерактивно; `KERNEL_GIT=shallow`, если поддерживается, для экономии места |

## Требования к workflow (`.github/workflows/build-r76s.yml`)

1. **Запуск:** `workflow_dispatch` с входами:
   - `release` (`trixie` / `bookworm`);
   - `armbian_ref` — ветка, тег или SHA `armbian/build`, по умолчанию `main`;
   - `expected_kernel` — по умолчанию `6.1.172`;
   - `prerelease` — boolean.

   Сборку на каждый push не запускай: она долгая и тратит минуты.
2. **Раннер:**
   - Лучше нативный arm64 (`ubuntu-24.04-arm`): сборка быстрее, без кросс-компиляции. Проверь, доступен ли он для этого репозитория: для публичных репозиториев бесплатен, для приватных — уточни по документации GitHub.
   - Если нет — `ubuntu-24.04` (x86_64) с обязательной очисткой диска: `armbian_runner_clean` или аналог. Ядро + rootfs требуют ~40–50 ГБ, а на стандартном раннере свободно ~14 ГБ.
   - `timeout-minutes` с запасом, но ≤ 360.
3. **Воспроизводимость:**
   - Зафиксируй и выведи в лог и в описание релиза точный SHA `armbian/build`, из которого собрано.
   - Зафиксируй SHA ветки ядра `armbian/linux-rockchip` `rk-6.1-rkr7.2`, если его можно получить.
4. **Проверка ядра после сборки:**
   - Найди в `output/debs` пакет `linux-image-vendor-rk35xx*`.
   - Извлеки версию ядра и выведи её в `$GITHUB_STEP_SUMMARY`.
   - Если она не совпадает с `expected_kernel`, сделай громкое предупреждение (`::warning::`), но не проваливай сборку: ядро могли поднять до 6.1.17x.
   - Также выведи версию U-Boot и имя DTB.
5. **Публикация:**
   - GitHub Release с тегом вида `r76s-<release>-<kernel>-<YYYYMMDD>-<короткий SHA armbian>`.
   - Файлы: `.img.xz` и `.sha` / `sha256`.
   - В описании: SHA `armbian/build`, версия ядра, версия U-Boot, параметры сборки и ссылка на README с инструкцией по записи.
   - Дополнительно выложи `.img.xz` как artifact workflow на 7 дней — на случай сбоя публикации релиза.
6. **Безопасность:**
   - Никаких секретов, кроме стандартного `GITHUB_TOKEN`.
   - Минимальные `permissions` (`contents: write` только для шага релиза).
   - Сторонние actions — с закреплённой версией (лучше SHA).
7. **Проверка:** перед коммитом прогони `actionlint`, если доступен, или хотя бы проверку YAML.

## Необязательно (сделай, если просто)

- **Пресет первого запуска** Armbian (механизм `armbian_first_run` / preset-файл `/root/.not_logged_in_yet`), управляемый входами workflow:
  - часовой пояс `Europe/Moscow`, локаль `en_US.UTF-8`;
  - **без паролей в репозитории**;
  - если задан необязательный вход `ssh_pubkey`, добавить ключ root'у.

  Если механизм пресета в текущем Armbian работает иначе, не делай и опиши в README, как настроить вручную.
- Каталог `userpatches/` с `config-r76s.conf`, чтобы те же параметры можно было собрать локально: `./compile.sh r76s` — в любом Linux с Docker.

## README.md (на русском)

- Что это за сборка и чем отличается от официальных образов: ядро 6.1.172 вместо 6.1.115.
- Как запустить сборку: Actions → Build → Run workflow, что значат входы, сколько примерно ждать.
- Как записать образ: balenaEtcher или Rufus, **на запасную SD-карту**, текущую карту не трогать.
- Первый запуск:
  - вход по SSH `root` / `1234` или через консоль, обязательная смена пароля и создание пользователя;
  - как найти IP платы.
- Проверки после загрузки:
  - `uname -r`;
  - `ls /dev/mpp_service /dev/rga /dev/dri`;
  - `dmesg | grep -iE "mpp|rga|mali"`;
  - что тёплая перезагрузка (`reboot`) проходит — см. известную проблему.
- Известные проблемы и ссылки: темы форума Armbian, PR #9908, состояние warm-reboot.
- Как собрать новую версию позже, когда в `armbian/build` поднимут ядро: просто перезапустить workflow.

## Порядок работы

1. Изучи актуальные `armbian/build` (`action.yml`, `config/boards/nanopi-r76s.conf`, `config/sources/families/rk35xx.conf`, документацию по параметрам сборки) и статус проблем R76S. Кратко отчитайся, что изменилось относительно раздела «Что уже известно».
2. Создай workflow, README и (опционально) `userpatches/`. Закоммить и запушь в ветку по умолчанию — с понятным сообщением коммита.
3. Если есть `gh` с правами — запусти workflow (`gh workflow run`) и сообщи ссылку на запуск. Не опрашивай статус в цикле: скажи пользователю, где смотреть.
4. Если запустить не можешь — напиши пошагово, где нажать **Run workflow** в интерфейсе GitHub.
5. Если первая сборка упадёт и пользователь пришлёт лог — разберись и исправь.

## Ограничения

- Не меняй ничего за пределами этого репозитория. Ни в какой форк `armbian/build` не пушь.
- Не используй неофициальные сборки ядра или U-Boot — только `armbian/build` и его официальные источники.
- Если что-то из этого задания расходится с текущим состоянием `armbian/build` (переименован параметр, изменилась ветка ядра, у action другие входы), следуй актуальному коду и явно напиши, что и почему сделал иначе.
