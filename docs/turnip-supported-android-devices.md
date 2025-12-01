# Freedreno Turnip Vulkan — Supported Android Devices

This document summarizes Android devices supported by the Freedreno Turnip Vulkan driver, grouped by Qualcomm Adreno GPU family. Entries are derived from GPU definitions in the Mesa Freedreno code and include representative commercial devices for orientation. Compatibility can vary by firmware, kernel (KGSL), and vendor stacks.

## How Support Is Determined

Turnip support is keyed to Adreno GPU IDs registered in the driver. In this repository, supported GPUs are defined in `android-dependencies/mesa/src/freedreno/common/freedreno_devices.py`. Each entry maps one or more `GPUId(...)` definitions to an internal configuration.

Code references:
- A6XX devices: `android-dependencies/mesa/src/freedreno/common/freedreno_devices.py:448`, `486`, `524`, `589`, `623`, `657`, `690`, `764`, `797`, `830`, `865`, `729`
- A7XX devices: `android-dependencies/mesa/src/freedreno/common/freedreno_devices.py:1124`, `1142`, `1160`, `1225`, `1245`, `1306`, `1327`

## A7XX Flagships (Snapdragon 8 series)

- Adreno 750 (`FD750`) — Snapdragon 8 Gen 3
  - Examples: Galaxy S24 Ultra, OnePlus 12, Xiaomi 14 Ultra
  - Definition: `android-dependencies/mesa/src/freedreno/common/freedreno_devices.py:1327`
- Adreno 740 (`FD740`, `FD740v3`) — Snapdragon 8 Gen 2
  - Examples: Galaxy S23 series, OnePlus 11, Xiaomi 13/13 Pro/13 Ultra; `FD740v3`: Meta Quest 3
  - Definitions: `freedreno_devices.py:1225` (FD740), `freedreno_devices.py:1306` (FD740v3)
- Adreno 730 (`FD730`) and Adreno 725 (`FD725`) — Snapdragon 8 Gen 1 / speedbins
  - Examples: Galaxy S22 Ultra (Snapdragon variant), OnePlus 10 Pro, Xiaomi 12/12 Pro
  - Definitions: `freedreno_devices.py:1142` (FD730), `freedreno_devices.py:1124` (FD725)
- Adreno X1-45 (`FD735`) — high-performance X-series (non-phone)
  - Definition: `freedreno_devices.py:1160`
- Adreno A32 (`FDA32`) — Snapdragon G3x Gen 2 (gaming handheld)
  - Definition: `freedreno_devices.py:1245`

## A6XX Flagships and Upper Mid‑Range

- Adreno 660 — Snapdragon 888
  - Examples: Galaxy S21/S21+/S21 Ultra (Snapdragon variants), OnePlus 9/9 Pro, Xiaomi Mi 11
  - Definition: `freedreno_devices.py:764`
- Adreno 650 — Snapdragon 865/865+
  - Examples: Galaxy S20/S20+/S20 Ultra (Snapdragon variants), OnePlus 8/8 Pro/8T, Xiaomi Mi 10/Mi 10 Pro
  - Definition: `freedreno_devices.py:690`
- Adreno 640 — Snapdragon 855/855+
  - Examples: Galaxy S10/S10+, OnePlus 7/7 Pro/7T, Pixel 4/4 XL
  - Definition: `freedreno_devices.py:623`
- Adreno 630 — Snapdragon 845
  - Examples: OnePlus 6/6T, Pixel 3/3 XL, Galaxy S9/S9+
  - Definition: `freedreno_devices.py:589`
- Adreno 680 — upper A6xx tier (platform dependent)
  - Definition: `freedreno_devices.py:657`
- Adreno 690 — upper A6xx tier (platform dependent)
  - Definition: `freedreno_devices.py:830`

## A6XX Mid‑Range and Embedded

- Adreno 643 (`FD643`) — QCM6490 platform
  - Examples: Fairphone 5
  - Definition: `freedreno_devices.py:729`
- Adreno 644 (`FD644`) / Adreno 663 (`FD663`) — Snapdragon 7 Gen 1 family
  - Examples: Xiaomi 13 Lite, Honor 90, Xiaomi Civi 2, Oppo Reno 8 Pro (China variant), Samsung Galaxy M55/F55 (regional), ZTE Nubia Flip 5G (regional)
  - Definition: `freedreno_devices.py:797`
- Adreno 620 — Snapdragon 765G
  - Examples: Pixel 5, Pixel 4a 5G, OnePlus Nord
  - Definition: `freedreno_devices.py:524`
- Adreno 615/616/618/619 — Snapdragon 67x/72x/73x family (2019 era mid‑range)
  - Definition: `freedreno_devices.py:486`
- Adreno 605/608/610/612 — early A6xx (entry devices)
  - Definition: `freedreno_devices.py:448`
- Adreno 702 (`FD702`) — QRB2210 RB1 reference board (embedded; not phone)
  - Definition: `freedreno_devices.py:865`

## Notes and Caveats

- Representative device lists help identify practical coverage but are not exhaustive.
- Actual Turnip compatibility depends on device firmware, kernel driver (KGSL), SELinux policies, and vendor graphics stack.
- For an unlisted device, identify its SoC/Adreno GPU and compare against the families above.

## External References

- Adreno 750 (Snapdragon 8 Gen 3) — NotebookCheck overview: https://www.notebookcheck.net/Qualcomm-Adreno-750-GPU-Benchmarks-and-Specs.762136.0.html
- Adreno 740 (Snapdragon 8 Gen 2) — NotebookCheck overview: https://www.notebookcheck.net/Qualcomm-Adreno-740-GPU-Benchmarks-and-Specs.669947.0.html
- Snapdragon 8 Gen 3 phones — The Shortcut list: https://www.theshortcut.com/p/snapdragon-8-gen-3-phones
- Adreno 730 (Snapdragon 8 Gen 1) — NotebookCheck overview: https://www.notebookcheck.net/Qualcomm-Adreno-730-GPU-Benchmarks-and-Specs.583409.0.html
- Snapdragon 888 phones (Adreno 660) — TechWalls: https://www.techwalls.com/snapdragon-888-smartphone-list/
- Snapdragon 865 phones (Adreno 650) — TechWalls: https://www.techwalls.com/qualcomm-snapdragon-865-smartphones/
- Snapdragon 765G (Adreno 620) — NanoReview: https://nanoreview.net/en/soc/qualcomm-snapdragon-765g

## Comprehensive Device Catalog

Below are broader make/model lists organized by Adreno GPU. Regional SoC variability applies (many Samsung and some OEM models ship Snapdragon or Exynos/MediaTek depending on market).

### Adreno 750 — Snapdragon 8 Gen 3
- Samsung: Galaxy S24, Galaxy S24+, Galaxy S24 Ultra; Galaxy Z Fold6; Galaxy Z Flip6 (US/China Snapdragon)
- OnePlus: 12
- ASUS: ROG Phone 8, ROG Phone 8 Pro
- Xiaomi: 14, 14 Ultra
- Oppo: Find X7 Ultra
- Honor: Magic 6, Magic 6 Pro
- Vivo: iQOO 12, iQOO 12 Pro
- ZTE/Nubia: Red Magic 9 Pro, Red Magic 9 Pro+, Nubia Z60 Ultra
- Realme: GT 5 Pro
- Sony: Xperia 1 VI

Sources: The Shortcut list of Snapdragon 8 Gen 3 phones (https://www.theshortcut.com/p/snapdragon-8-gen-3-phones), NotebookCheck Adreno 750 (https://www.notebookcheck.net/Qualcomm-Adreno-750-GPU-Benchmarks-and-Specs.762136.0.html).

### Adreno 740 — Snapdragon 8 Gen 2
- Samsung: Galaxy S23, Galaxy S23+, Galaxy S23 Ultra (global Snapdragon), some S23 FE variants differ
- OnePlus: 11
- ASUS: ROG Phone 7, ROG Phone 7 Ultimate
- Xiaomi: 13, 13 Pro, 13 Ultra
- Sony: Xperia 1 V
- Motorola: Edge 40 Pro
- Nubia/ZTE: Red Magic 8 Pro, Red Magic 8 Pro+, Nubia Z50

Sources: NotebookCheck Adreno 740 (https://www.notebookcheck.net/Qualcomm-Adreno-740-GPU-Benchmarks-and-Specs.669947.0.html), Android Authority overview (https://www.androidauthority.com/best-snapdragon-8-gen-2-phones-3270609/).

### Adreno 730 — Snapdragon 8 Gen 1 / 8+ Gen 1
- Snapdragon 8 Gen 1: Samsung Galaxy S22, S22+, S22 Ultra (US/China Snapdragon); OnePlus 10 Pro; Xiaomi 12, 12 Pro; Motorola Edge 30 Pro; Realme GT 2 Pro; iQOO 9, iQOO 9 Pro; Sony Xperia 5 IV
- Snapdragon 8+ Gen 1: OnePlus 10T; ASUS ROG Phone 6/6 Pro; ASUS Zenfone 9; Xiaomi 12T Pro; Samsung Galaxy Z Fold4, Galaxy Z Flip4; Xiaomi 12S Ultra

Sources: NotebookCheck Adreno 730 (https://www.notebookcheck.net/Qualcomm-Adreno-730-GPU-Benchmarks-and-Specs.583409.0.html), Specsera 8 Gen 1 list (https://www.specsera.com/specs/snapdragon-8-gen-1-mobile-phones/).

### Adreno 660 — Snapdragon 888
- Samsung: Galaxy S21, S21+, S21 Ultra (US/China Snapdragon)
- OnePlus: 9, 9 Pro
- Xiaomi: Mi 11, Mi 11 Ultra
- Sony: Xperia 1 III, Xperia 5 III
- Oppo: Find X3 Pro
- ASUS: ROG Phone 5, ROG Phone 5s

Sources: TechWalls SD888 list (https://www.techwalls.com/snapdragon-888-smartphone-list/), Smartprix overview (https://www.smartprix.com/bytes/phones-with-qualcomm-snapdragon-888/).

### Adreno 650 — Snapdragon 865 / 865+
- Samsung: Galaxy S20, S20+, S20 Ultra (US/China Snapdragon); Galaxy Note 20 Ultra (US Snapdragon 865+)
- OnePlus: 8, 8 Pro, 8T
- Xiaomi: Mi 10, Mi 10 Pro, Mi 10T, Mi 10T Pro
- Sony: Xperia 1 II, Xperia 5 II
- Poco: F2 Pro
- LG: V60 ThinQ
- ASUS: ROG Phone 3 (865+)

Sources: TechWalls SD865 list (https://www.techwalls.com/qualcomm-snapdragon-865-smartphones/).

### Adreno 640 — Snapdragon 855 / 855+
- Samsung: Galaxy S10, S10+, S10e; Galaxy Fold (1st gen Snapdragon)
- OnePlus: 7, 7 Pro, 7T, 7T Pro
- Google: Pixel 4, Pixel 4 XL
- Xiaomi: Mi 9
- Sony: Xperia 1, Xperia 5
- LG: G8 ThinQ, V50 ThinQ
- ASUS: ROG Phone II

Sources: NotebookCheck Adreno 640 (https://www.notebookcheck.net/Qualcomm-Adreno-640-Graphics-Card.374761.0.html), TechWalls SD855 list (https://www.techwalls.com/qualcomm-snapdragon-855-smartphones/).

### Adreno 630 — Snapdragon 845
- Samsung: Galaxy S9, S9+; Galaxy Note 9 (US/China Snapdragon)
- OnePlus: 6, 6T
- Google: Pixel 3, Pixel 3 XL
- Sony: Xperia XZ2, XZ2 Compact, XZ3
- LG: G7 ThinQ, V40 ThinQ
- Xiaomi: Poco F1, Mi 8

Sources: NotebookCheck Adreno 630 (https://www.notebookcheck.net/Qualcomm-Adreno-630-GPU.299832.0.html), TechWalls SD845 list (https://www.techwalls.com/qualcomm-snapdragon-845-smartphones/).

### Adreno 620 — Snapdragon 765G (Mid‑Range)
- Google: Pixel 5, Pixel 4a 5G
- OnePlus: Nord
- LG: Velvet
- Motorola: Edge (2020)
- Nokia: 8.3 5G
- Xiaomi: Mi 10 Lite 5G

Sources: DeviceSpecifications for OnePlus Nord (https://www.devicespecifications.com/en/model/da0653f3), NanoReview SD765G (https://nanoreview.net/en/soc/qualcomm-snapdragon-765g), Android Authority 765G comparison (https://www.androidauthority.com/snapdragon-765g-vs-snapdragon-865-1112843/).

### Adreno 618 — Snapdragon 730 / 730G (Mid‑Range)
- Google: Pixel 4a (730G)
- Poco: X2 (730G)
- Realme: X2 (730G)
- Samsung: Galaxy A80 (730)
- Xiaomi: Mi 9T (730)

### Adreno 662 — Snapdragon 7 Gen 1 (Mid‑Range)
- Xiaomi: 13 Lite; Civi 2 / Civi 2 NE (China)
- Honor: 90
- Oppo: Reno 8 Pro (China Snapdragon 7 Gen 1 variant)
- Samsung: Galaxy M55, Galaxy F55 (regional Snapdragon 7 Gen 1 variants)
- ZTE/Nubia: Nubia Flip 5G

Sources: Adimorah blog device round‑up (https://adimorahblog.com/snapdragon-7-gen-1-phones/), NanoReview SD 7 Gen 1 (https://nanoreview.net/en/soc/qualcomm-snapdragon-7-gen-1), BajajFinserv overview (https://www.bajajfinserv.in/snapdragon-7-gen-1-mobile-list-in-india).

### FD643 — QCM6490 Platform
- Fairphone: 5 (explicit in driver mapping)

### FD740v3 — Adreno 740 (Quest)
- Meta: Quest 3 (explicit in driver mapping)

Notes:
- Regional SKU differences are common; verify the Snapdragon/Adreno variant for your exact model.
- The above lists are extensive but not exhaustive; niche or regional models may also be covered if they share the same SoC/GPU family.

## Devices Grouped by Chipset

This section groups devices by Qualcomm Snapdragon chipset. For each chipset, the paired Adreno GPU is noted. Regional variants may use different SoCs.

### Snapdragon 8 Gen 3 — Adreno 750
- Samsung: Galaxy S24, Galaxy S24+, Galaxy S24 Ultra; Galaxy Z Fold6; Galaxy Z Flip6 (US/China Snapdragon)
- OnePlus: 12
- ASUS: ROG Phone 8, ROG Phone 8 Pro
- Xiaomi: 14, 14 Ultra
- Oppo: Find X7 Ultra
- Honor: Magic 6, Magic 6 Pro
- Vivo: iQOO 12, iQOO 12 Pro
- ZTE/Nubia: Red Magic 9 Pro, Red Magic 9 Pro+; Nubia Z60 Ultra
- Realme: GT 5 Pro
- Sony: Xperia 1 VI

### Snapdragon 8 Gen 2 — Adreno 740
- Samsung: Galaxy S23, S23+, S23 Ultra (global Snapdragon)
- OnePlus: 11
- ASUS: ROG Phone 7, ROG Phone 7 Ultimate
- Xiaomi: 13, 13 Pro, 13 Ultra
- Sony: Xperia 1 V
- Motorola: Edge 40 Pro
- ZTE/Nubia: Red Magic 8 Pro, Red Magic 8 Pro+

### Snapdragon 8 Gen 1 — Adreno 730
- Samsung: Galaxy S22, S22+, S22 Ultra (US/China Snapdragon)
- OnePlus: 10 Pro
- Xiaomi: 12, 12 Pro
- Motorola: Edge 30 Pro
- Realme: GT 2 Pro
- Vivo: iQOO 9, iQOO 9 Pro
- Sony: Xperia 5 IV

### Snapdragon 8+ Gen 1 — Adreno 730
- OnePlus: 10T
- ASUS: ROG Phone 6, ROG Phone 6 Pro; Zenfone 9
- Samsung: Galaxy Z Fold4; Galaxy Z Flip4
- Xiaomi: 12T Pro; 12S Ultra

### Snapdragon 888 — Adreno 660
- Samsung: Galaxy S21, S21+, S21 Ultra (US/China Snapdragon)
- OnePlus: 9, 9 Pro
- Xiaomi: Mi 11, Mi 11 Ultra
- Sony: Xperia 1 III, Xperia 5 III
- Oppo: Find X3 Pro
- ASUS: ROG Phone 5, ROG Phone 5s

### Snapdragon 865 / 865+ — Adreno 650
- Samsung: Galaxy S20, S20+, S20 Ultra (US/China Snapdragon); Galaxy Note 20 Ultra (US Snapdragon 865+)
- OnePlus: 8, 8 Pro, 8T
- Xiaomi: Mi 10, Mi 10 Pro, Mi 10T, Mi 10T Pro
- Sony: Xperia 1 II, Xperia 5 II
- Poco: F2 Pro
- LG: V60 ThinQ
- ASUS: ROG Phone 3 (865+)

### Snapdragon 855 / 855+ — Adreno 640
- Samsung: Galaxy S10, S10+, S10e; Galaxy Fold (1st gen)
- OnePlus: 7, 7 Pro, 7T, 7T Pro
- Google: Pixel 4, Pixel 4 XL
- Xiaomi: Mi 9
- Sony: Xperia 1, Xperia 5
- LG: G8 ThinQ, V50 ThinQ
- ASUS: ROG Phone II

### Snapdragon 845 — Adreno 630
- Samsung: Galaxy S9, S9+; Galaxy Note 9 (US/China Snapdragon)
- OnePlus: 6, 6T
- Google: Pixel 3, Pixel 3 XL
- Sony: Xperia XZ2, XZ2 Compact, XZ3
- LG: G7 ThinQ, V40 ThinQ
- Xiaomi: Poco F1, Mi 8

### Snapdragon 835 — Adreno 540
- Samsung: Galaxy S8, S8+; Galaxy Note 8 (US/China Snapdragon)
- Google: Pixel 2, Pixel 2 XL
- OnePlus: 5, 5T
- LG: V30/V30S/V35 ThinQ
- Xiaomi: Mi 6; Mi MIX 2S
- Sony: Xperia XZ1, XZ Premium
- HTC: U11, U11+

### Snapdragon 820 / 821 — Adreno 530
- Samsung: Galaxy S7, S7 Active (US Snapdragon)
- Google: Pixel (2016), Pixel XL (2016)
- OnePlus: 3, 3T
- LG: G5; G6 (regional Snapdragon 821 variant)
- Sony: Xperia XZ
- Xiaomi: Mi 5
- ZTE: Axon 7
- BlackBerry: DTEK60

### Snapdragon 7+ Gen 2 — Adreno 725
- Xiaomi/Poco: Poco F5 (Redmi Note 12 Turbo)
- Realme: GT Neo 5 SE

### Snapdragon 7 Gen 1 — Adreno 662 / Adreno 644/663 (driver IDs FD644/FD663)
- Xiaomi: 13 Lite; Civi 2 / Civi 2 NE
- Honor: 90
- Oppo: Reno 8 Pro (China variant)
- Samsung: Galaxy M55; Galaxy F55 (regional)
- ZTE/Nubia: Nubia Flip 5G
- Motorola: Edge 50 5G

### Snapdragon 778G / 782G — Adreno 642L (mapped via A6xx FD621/Adreno 623 family)
- Samsung: Galaxy A52s 5G
- Xiaomi: 11 Lite 5G NE
- Realme: GT Master Edition
- Motorola: Edge 20
- Honor: 50

### Snapdragon 765G — Adreno 620
- Google: Pixel 5, Pixel 4a 5G
- OnePlus: Nord
- LG: Velvet
- Motorola: Edge (2020)
- Nokia: 8.3 5G
- Xiaomi: Mi 10 Lite 5G

### Snapdragon 730 / 730G — Adreno 618
- Google: Pixel 4a (730G)
- Poco: X2 (730G)
- Realme: X2 (730G)
- Samsung: Galaxy A80 (730)
- Xiaomi: Mi 9T (730)

### XR / Gaming Platforms
- Snapdragon G3x Gen 2 — Adreno A32: gaming handhelds (developer kits, regional products)
- Snapdragon 8 Gen 2 (Adreno 740v3) — Meta Quest 3
