# Armbian для NanoPi R76S с vendor-ядром 6.1.172

Сборка образа **Armbian** для **FriendlyElec NanoPi R76S** (RK3576) через GitHub Actions. Источник — только официальный [`armbian/build`](https://github.com/armbian/build). Своих патчей ядра и U-Boot здесь нет.

- Плата: NanoPi R76S **rev.2**, 3 ГБ ОЗУ, **без eMMC**, загрузка с SD-карты.
- Образ: минимальный CLI, Debian 13 **trixie** (можно выбрать bookworm), ветка ядра `vendor`.
- Результат: GitHub Release с `.img.xz` и контрольными суммами.

## Чем эта сборка отличается от официальных образов

| | Официально (03.10.2026) | Эта сборка |
|---|---|---|
| Образ | Armbian 26.8.1 stable (11.08.2026), nightly в `armbian/os` | своя сборка из текущего `main` `armbian/build` |
| Ядро `vendor` | **6.1.115** (stable-репозиторий 26.8.3 — тоже 6.1.115) | **6.1.172** (`armbian/linux-rockchip`, ветка `rk-6.1-rkr7.2`) |
| U-Boot | mainline v2026.04 | тот же mainline v2026.04 (с исправлением загрузки с SD из PR #9908) |

Ядро 6.1.172 (Rockchip SDK rkr7.2) содержит исправления MPP/RGA/Mali. Для аппаратного транскодирования Jellyfin (`rkmpp`) его рекомендовал nyanmisaka в [jellyfin/jellyfin-ffmpeg#781](https://github.com/jellyfin/jellyfin-ffmpeg/issues/781). Ядра `current`/`edge` (mainline) не подходят: в них нет полноценного `rkmpp`.

### Альтернатива без своей сборки

Можно записать стабильный образ Armbian 26.8.1 и поставить ядро из **beta-репозитория**: там с 03.10.2026 лежит `linux-image-vendor-rk35xx` **26.11.0-trunk.69** с ядром 6.1.172. Это быстрее, но смешивает stable и beta. Порядок примерно такой:

```bash
# на плате со стабильным Armbian
armbian-config   # System → Updates → переключиться на beta (nightly) репозиторий
# либо вручную заменить apt.armbian.com на beta.armbian.com в /etc/apt/sources.list.d/armbian.sources
apt update
apt install linux-image-vendor-rk35xx linux-dtb-vendor-rk35xx
reboot
uname -r   # ожидается 6.1.172-vendor-rk35xx
```

Название пункта меню в `armbian-config` меняется между версиями. Если его нет — правьте файл источников вручную.

## Состояние `armbian/build` на 03.10.2026 (проверено)

Проверено на коммите [`ee64d00`](https://github.com/armbian/build/commit/ee64d00c0435a46f1fd70e23d19c63b96aacf21f), `VERSION` = `26.11.0-trunk`.

- `config/boards/nanopi-r76s.conf` — как и ожидалось: `BOARDFAMILY="rk35xx"`, `KERNEL_TARGET="vendor,edge"`, `BOOT_SCENARIO="spl-blobs"`, `IMAGE_PARTITION_TABLE="gpt"`. Хук `post_family_config__nanopi_r76s_use_mainline_uboot` ставит U-Boot `tag:v2026.04` для всех веток. Порядок загрузки U-Boot: `mmc1` (SD) → `mmc0` (eMMC) → `nvme` → …
- `config/sources/families/rk35xx.conf`, ветка `vendor`: `KERNELSOURCE=https://github.com/armbian/linux-rockchip.git`, `KERNELBRANCH='branch:rk-6.1-rkr7.2'`, `KERNELPATCHDIR='rk35xx-vendor-6.1'`. В `Makefile` ветки — `6.1.172` (head `44bbd021d780`). Переход на 6.1.172 — коммит `81e8624` от 17.08.2026.
- PR [armbian/build#9908](https://github.com/armbian/build/pull/9908) влит 28.05.2026 (`0ce3fd5`). U-Boot теперь собирается через `boot_merger` с «SD boost» для BootROM — это и чинит загрузку rev.2 без eMMC. Вторая часть PR (убрать `sdmmc0_pwren` из pinctrl SD) касается только DTS mainline-ядер. В vendor-ядре этот пин в DTS платы и так не используется (`rk3576-nanopi5-common.dtsi`).
- После #9908 вышли ещё исправления для R76S: [#9929](https://github.com/armbian/build/pull/9929) (Wi-Fi SDIO SDR104, для mainline-ядер) и `40dbe23` (rk35xx: зависание `plymouth-quit-wait` на безмониторной загрузке).
- Открытых PR и issue по `nanopi-r76s` в `armbian/build` на 03.10.2026 нет.
- Официальный `action.yml` — «Rebuild Armbian», описание «Build Armbian Linux». Входы — как в задании, плюс `armbian_artifacts`, `armbian_version`, `armbian_pgp_key`/`armbian_pgp_password`, `armbian_download_base_url`, `armbian_download_repository`, `armbian_index_url`.

### Почему `./compile.sh` напрямую, а не официальный action

Я прочитал `action.yml` целиком. Он не подходит по пяти причинам:

1. Жёстко задаёт `SHARE_LOG="yes"` и `EXPERT="yes"`. Передать `SHARE_LOG=no` и `KERNEL_GIT=shallow` нельзя.
2. Подмешивает `userpatches` из `armbian/os` (настройки официальной CI). Получается уже не «чистый `armbian/build`», и сборка зависит от второго репозитория.
3. Публикует релиз сторонним `ncipollo/release-action` с `makeLatest: true`, тегом по умолчанию из версии `armbian/ci` и токеном, переданным во все шаги. Задать свой тег, описание с SHA и проверку ядра до публикации нельзя.
4. Не выводит SHA `armbian/build` и ветки ядра и не проверяет версию ядра.
5. Для очистки диска использует сторонний `descriptinc/free-disk-space`.

Поэтому workflow повторяет ту же последовательность, что и action: `sudo ./compile.sh requirements`, затем `./compile.sh` от обычного пользователя (сборка в Docker-контейнере Armbian). Но параметры, проверки и публикацию он контролирует сам. Сторонних actions нет — только `actions/checkout`, `actions/upload-artifact` и `actions/download-artifact`, закреплённые по SHA. Релиз создаётся через `gh` со стандартным `GITHUB_TOKEN`.

## Как запустить сборку

1. Откройте репозиторий на GitHub → вкладка **Actions**.
2. Слева выберите **Build Armbian NanoPi R76S (vendor 6.1)**.
3. Справа нажмите **Run workflow**, выберите ветку `main`, заполните входы (можно оставить по умолчанию) и нажмите зелёную **Run workflow**.

| Вход | По умолчанию | Значение |
|---|---|---|
| `release` | `trixie` | Debian userspace: `trixie` (13) или `bookworm` (12) |
| `armbian_ref` | `main` | ветка, тег или SHA `armbian/build`, из которого собирать |
| `expected_kernel` | `6.1.172` | ожидаемая версия ядра. При расхождении будет `::warning::`, но сборка не упадёт |
| `prerelease` | `false` | опубликовать релиз как pre-release |
| `runner` | `ubuntu-24.04-arm` | нативный arm64-раннер. `ubuntu-24.04` (x86_64, кросс-компиляция) — запасной вариант |
| `timezone` | `Europe/Moscow` | пресет первого входа. Пусто — спросить при входе |
| `locale` | `en_US.UTF-8` | пресет первого входа. Пусто — спросить при входе |
| `ssh_pubkey` | пусто | публичный SSH-ключ для `root` (одна строка `ssh-ed25519 AAAA… comment`) |

**Сколько ждать:** обычно 1,5–3 часа. Ядро компилируется ~40–90 минут, остальное — rootfs, образ, сжатие xz. Если Armbian найдёт готовый пакет ядра того же исходника в своём кэше (ghcr.io), выйдет быстрее. Лимит задачи — 6 часов.

**Раннер.** Репозиторий публичный, поэтому `ubuntu-24.04-arm` бесплатен (4 vCPU). С 29.01.2026 arm64-раннеры есть и в приватных репозиториях (2 vCPU, расходуют минуты плана). На x86_64-раннере свободно ~14 ГБ, а сборке нужно ~40–50 ГБ. Поэтому workflow удаляет предустановленные SDK. Если `/mnt` больше корня, каталог сборки монтируется оттуда.

**Где смотреть результат:**

- **Summary** запуска: SHA `armbian/build` и ветки ядра, версия ядра, U-Boot, DTB.
- **Releases**: образ и контрольные суммы.
- **Artifacts** запуска (хранятся 7 дней): `r76s-image` — копия образа на случай сбоя публикации, `r76s-build-logs` — логи Armbian. Если сборка упала, пришлите логи для разбора.

Тег релиза: `r76s-<release>-<ядро>-<YYYYMMDD>-<короткий SHA armbian/build>`, например `r76s-trixie-6.1.172-20261003-ee64d00c`. Если такой тег уже есть, добавляется `-run<N>`.

### Локальная сборка

В любом Linux с Docker:

```bash
git clone https://github.com/armbian/build.git && cd build
cp -a /путь/к/armbian-r76s/userpatches/. userpatches/
./compile.sh r76s                    # параметры из userpatches/config-r76s.conf
./compile.sh r76s RELEASE=bookworm   # любой параметр можно переопределить
```

Образ появится в `output/images/`.

## Как записать образ

> ⚠️ Пишите **на запасную SD-карту**. Текущую карту с FriendlyElec/pxvirt (ядро 6.1.141) не трогайте и перед записью выньте её из кардридера, чтобы не выбрать по ошибке.

1. Скачайте из релиза `Armbian-…_Nanopi-r76s_trixie_vendor_6.1.172_minimal.img.xz` и `….img.xz.sha256`.
2. Проверьте контрольную сумму:
   - Linux/macOS: `sha256sum -c Armbian-…img.xz.sha256`
   - Windows (PowerShell): `Get-FileHash .\Armbian-…img.xz -Algorithm SHA256` — сравните с содержимым `.sha256`.

   Файл `.sha` — родной формат Armbian (хеш и имя через один пробел), его удобнее сверять вручную.
3. Запишите образ:
   - **balenaEtcher** (Windows/macOS/Linux): Flash from file → выберите `.img.xz` (распаковывать не нужно) → Select target — **запасная SD** → Flash.
   - **Rufus** (Windows): сначала распакуйте `.img.xz` до `.img` (7-Zip), затем Устройство — **запасная SD**, «Выбрать» → `.img`, Старт. На вопрос о режиме выберите DD.
4. Выключите плату, вставьте новую SD и включите питание. На R76S без eMMC загрузка идёт только с SD.

## Первый запуск

- Подключите Ethernet к роутеру с DHCP. Первая загрузка с расширением раздела занимает 1–3 минуты.
- **Как найти IP:**
  - в веб-интерфейсе роутера, в списке DHCP-клиентов: имя хоста `nanopi-r76s`;
  - `nmap -sn 192.168.1.0/24` (подставьте свою подсеть);
  - через HDMI или UART-консоль (1 500 000 бод): IP показан на экране входа.
- Вход: `ssh root@<IP>`, пароль **`1234`**. Если при сборке задан `ssh_pubkey`, войдёте по ключу.
- Мастер `armbian-firstlogin` сразу потребует задать **новый пароль root** и **создать обычного пользователя**. Если в сборке есть пресет, часовой пояс (`Europe/Moscow`) и локаль (`en_US.UTF-8`) он не спросит.

### Пресет первого входа

Используется штатный механизм Armbian: `userpatches/firstboot.conf` при сборке копируется в образ как `/root/.not_logged_in_yet`, а `armbian-firstlogin` читает переменные `PRESET_*`. Workflow пишет туда только `PRESET_TIMEZONE`, `PRESET_LOCALE` и `SET_LANG_BASED_ON_LOCATION="n"`. **Паролей в репозитории нет**, пароль root и пользователь создаются вручную.

SSH-ключ отличается от задания. Штатный `PRESET_ROOT_KEY` принимает **URL** и срабатывает **только вместе с `PRESET_ROOT_PASSWORD`**, то есть с паролем в образе. Поэтому ключ из `ssh_pubkey` кладётся напрямую в `/root/.ssh/authorized_keys` скриптом `userpatches/customize-image.sh`. Публичный ключ не секрет: он попадает в образ и в лог сборки.

Если нужен статический IP или Wi-Fi, после первого входа используйте `armbian-config` или netplan (`/etc/netplan/`). Можно и добавить в `firstboot.conf` переменные `PRESET_NET_*` (см. `/usr/lib/armbian/armbian-firstlogin`), но пароль Wi-Fi тогда окажется в образе.

## Проверки после загрузки

```bash
uname -r                              # ожидается 6.1.172-vendor-rk35xx
cat /etc/armbian-release              # BRANCH=vendor, VERSION=26.11.0-trunk…
ls -l /dev/mpp_service /dev/rga /dev/dri
dmesg | grep -iE "mpp|rga|mali"
```

Что должно быть:

- `/dev/mpp_service` и `/dev/rga` существуют;
- в `/dev/dri` есть `card*` и `renderD*`;
- в `dmesg` есть инициализация `mpp_*`/`rkvdec`/`rkvenc`, `rga` и `mali` без ошибок probe.

**Тёплая перезагрузка.** Выполните `reboot` несколько раз (3–5) и убедитесь, что плата каждый раз загружается и доступна по SSH. Подробности — ниже.

## Известные проблемы

### Warm-reboot: U-Boot 2026.04 теряет MMC

Тема форума: [NanoPi R76S: U-Boot 2026.04 warm-reboot mmc failure — OpenWrt PR #23520 workaround does not work on Armbian vendor kernel](https://forum.armbian.com/topic/60938-nanopi-r76s-u-boot-202604-warm-reboot-mmc-failure-%E2%80%94-openwrt-pr-23520-workaround-does-not-work-on-armbian-vendor-kernel/) (10.07.2026).

- **Статус на 03.10.2026: не исправлено.** Ответов мейнтейнеров в теме нет. Соответствующих коммитов, PR или issue в `armbian/build` нет. U-Boot по-прежнему `v2026.04`, патч платы — только `add-nanopi-r76s-support.patch`.
- Симптом: примерно в половине тёплых перезагрузок первый `ext4load` ядра падает с `fs_devread read error`, затем `No partition table - mmc 0`. `mmc rescan` не помогает.
- В теме речь об **eMMC** (`mmc 0`, плата с 64 ГБ eMMC Hynix). Похожая проблема у OpenWrt: [openwrt/openwrt#23491](https://github.com/openwrt/openwrt/issues/23491) — нестабильный драйвер eMMC в U-Boot. На плате **без eMMC** с загрузкой с SD (`mmc1`) этот путь не задействован, поэтому проблема, вероятно, вас **не затронет**. Но эту комбинацию никто публично не проверял — проверьте `reboot` сами.
- **Обходной путь:** если после `reboot` плата не поднялась — **холодный старт**: отключить питание на 5–10 секунд и включить снова. Для штатных перезагрузок используйте `poweroff` и включение питания, если плата управляется умной розеткой. Заплатку OpenWrt (PR #23520, ограничение частоты eMMC) в Armbian автор темы применить не смог: ядро зависало после `Starting kernel...`.

### Ссылки

- PR [armbian/build#9908](https://github.com/armbian/build/pull/9908) — исправление загрузки с SD на платах без eMMC (влит 28.05.2026).
- Тема [NanoPi R76s rev.2 unbootable](https://forum.armbian.com/topic/59113-nanopi-r76s-rev2-unbootable/) — исходная проблема rev.2 3 ГБ/без eMMC, решена #9908.
- PR [armbian/build#9869](https://github.com/armbian/build/pull/9869) — переход на mainline U-Boot v2026.04.
- PR [armbian/build#9929](https://github.com/armbian/build/pull/9929) — Wi-Fi SDIO SDR104 (mainline-ядра).
- [Форум Armbian: NanoPi R76S](https://forum.armbian.com/forum/280-nanopi-r76s/).
- [jellyfin/jellyfin-ffmpeg#781](https://github.com/jellyfin/jellyfin-ffmpeg/issues/781) — почему нужно ядро 6.1.172.

## Как собрать новую версию позже

Когда в `armbian/build` обновят ядро (например, до 6.1.17x) или исправят U-Boot, просто снова запустите workflow (**Actions → Run workflow**). Сборка всегда идёт из текущего `armbian_ref` (по умолчанию `main`). Если новое ядро отличается от `expected_kernel`, в Summary появится предупреждение — поправьте вход и перезапустите при желании. Для воспроизведения старой сборки укажите в `armbian_ref` SHA из описания её релиза. Ветку ядра workflow берёт из актуального `rk35xx.conf`, но репозиторий ядра по SHA не закрепляется: ветка `rk-6.1-rkr7.2` может сдвинуться.

## Состав репозитория

- `.github/workflows/build-r76s.yml` — workflow сборки и публикации.
- `userpatches/config-r76s.conf` — параметры сборки (`./compile.sh r76s`).
- `userpatches/firstboot.conf` — пресет первого входа для локальной сборки. В CI перезаписывается из входов.
- `userpatches/customize-image.sh` — установка необязательного SSH-ключа root.
- `armbian-r76s-cloud-prompt.md` — исходное задание.
