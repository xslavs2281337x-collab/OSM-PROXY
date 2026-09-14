# OSM-PROXY
Кеширующий reverse-proxy для тайлов OpenStreetMap. Разворачивается в Docker Compose, отдаёт тайлы корпоративной ГИС из локального кеша.

## Зачем

ГИС тянула карты напрямую с `tile.openstreetmap.org` — медленно и с зависимостью от внешнего канала. Этот сервис ставит nginx между ГИС и OSM: первый запрос тайла качается из интернета и сохраняется на диск, все последующие отдаются из локального кеша. При недоступности OSM уже просмотренные районы продолжают работать.

```
ГИС ──> nginx (кеш + TLS) ──> tile.openstreetmap.org
```

## Стек
- nginx `1.27-alpine` (reverse proxy + `proxy_cache`)
- Docker Compose
- TLS: wildcard-сертификат `*.loesk.ru` (GlobalSign)

## Структура

```
OSM-PROXY/
├── docker-compose.yaml
├── web/
│   └── nginx.conf              # конфиг кеша (proxy_cache_path, upstream, server)
└── ssl/
    ├── tiles.loesk.ru.fullchain.crt   # серт + промежуточная CA (цепочка!)
    └── tiles.loesk.ru.key             # приватный ключ
```

Кеш хранится в именованном volume `Cache`, монтируемом в `/var/cache/nginx/osm`.

## Запуск

```bash
docker compose config          # проверить валидность compose-файла
docker compose up -d           # поднять в фоне
docker compose ps              # статус (ожидается Up)
docker compose logs -f nginx   # логи (следить за стартом)
```

## Проверка

```bash
# кеш работает: дважды один тайл → MISS, потом HIT
curl -skI -H "Host: tiles.loesk.ru" https://127.0.0.1/10/595/294.png | grep -i x-cache-status

# цепочка сертификата (без -k, verify должен пройти)
curl -sI --resolve tiles.loesk.ru:443:127.0.0.1 https://tiles.loesk.ru/10/595/294.png | head -1
```

Статусы в заголовке `X-Cache-Status`: `MISS` (скачал), `HIT` (из кеша), `STALE` (отдал из кеша, OSM недоступен).

## Использование в ГИС

Источник тайлов:

```
https://tiles.loesk.ru/{z}/{x}/{y}.png
```

`{z}/{x}/{y}` — плейсхолдеры зума и координат, ГИС подставляет их сама.

## Обслуживание

```bash
# размер кеша и число тайлов
docker compose exec nginx du -sh /var/cache/nginx/osm
docker compose exec nginx find /var/cache/nginx/osm -type f | wc -l

# применить изменения конфига без пересоздания контейнера
docker compose exec nginx nginx -t      # проверить синтаксис
docker compose exec nginx nginx -s reload

# офлайн-тест (карта должна работать при недоступности OSM)
OSM_IP=$(dig +short tile.openstreetmap.org | head -1)
sudo iptables -I OUTPUT -p tcp --dport 443 -d $OSM_IP -j DROP
curl -skI -H "Host: tiles.loesk.ru" https://127.0.0.1/10/595/294.png | grep -i x-cache-status
sudo iptables -D OUTPUT -p tcp --dport 443 -d $OSM_IP -j DROP
```

## Особенности и грабли

- **Кеш ленивый** — наполняется только запрошенными тайлами. Массовое предзаполнение недопустимо (OSM банит за bulk-скачивание по своей [tile usage policy](https://operations.osmfoundation.org/policies/tiles/)). Офлайн работает только для уже просмотренных районов.
- **User-Agent обязателен** — OSM блокирует анонимные/дефолтные UA. Задаётся в `nginx.conf` через `proxy_set_header User-Agent`.
- **Сертификат нужен с цепочкой** — листовой серт склеен с промежуточным GlobalSign в `fullchain.crt`. Без промежуточного Linux-клиенты падают с `unable to get local issuer certificate` (Windows докачивает цепочку сам и не жалуется — баг легко пропустить).
- **Дефолтный конфиг образа** (`/etc/nginx/conf.d/default.conf`) затирается монтированием `/dev/null`, иначе welcome-страница nginx перехватывает часть запросов.

## Настраиваемые параметры (`web/nginx.conf`)

| Параметр | Назначение |
|---|---|
| `max_size` | потолок кеша на диске (вытеснение LRU при достижении) |
| `inactive` | удаление тайлов без обращений за указанный срок |
| `proxy_cache_valid 200` | срок свежести успешного ответа |
| `keepalive` | размер пула тёплых соединений к OSM |
